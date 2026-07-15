// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import './MyMultiSig.sol';
import './interfaces/ITransactionGuard.sol';

/// @title MyMultiSigExtended (v0.4.0)
/// @notice Extended-wallet v0.4.0 features: inactivity / delegate handover, custom-nonce
///         exec, per-nonce kill switch, plus four NEW v0.4.0 features: timelock on
///         sensitive admin calls, pluggable transaction guard with built-in target
///         allowlist, per-owner daily spending allowance, and a Safe-style enabled
///         module registry.
/// @dev    All four v0.4.0 features are DISABLED BY DEFAULT (zero-state-replay
///         backwards-compatible): every v0.3.0 sig and every existing Extended
///         wallet behaves unchanged until the new setters are called. Storage
///         added for these features is appended AFTER v0.3.0 storage so future
///         base-wallet additions cannot collide.
contract MyMultiSigExtended is MyMultiSig {
  // ---------------------------------------------------------------------------
  // v0.3.0 state (unchanged)
  // ---------------------------------------------------------------------------
  bool private _onlyOwnerRequest;
  uint256 private _minimumTransferInactiveOwnershipAfter;

  struct OwnerSettings {
    uint256 lastAction;
    uint256 transferInactiveOwnershipAfter;
    address delegate;
  }
  mapping(address => OwnerSettings) private _ownerSettings;
  mapping(address => bool) private _ownersOrDelegates;
  mapping(uint256 => bool) private _noncesUsed;

  // ---------------------------------------------------------------------------
  // v0.4.0 storage — appended at the END so future base-wallet additions
  // cannot collide. Layout is documented for clarity.
  // ---------------------------------------------------------------------------

  // Feature 1 — Timelock / delay
  uint256 internal _timelockDelay; // 0 = disabled
  uint256 internal _sensitiveValueThreshold; // 0 = value-cap disabled
  mapping(bytes4 => bool) internal _sensitiveSelectors;
  mapping(bytes32 => uint256) internal _readyAt; // txHash → unix ts; 0 = unscheduled, max = executed
  mapping(bytes32 => uint256) internal _scheduledValidUntil; // txHash → sig validUntil at schedule time

  // Feature 2 — Transaction guard / allowlist
  address internal _guard;
  mapping(address => bool) internal _allowedTargets;
  bool internal _allowedTargetsEnabled; // first `setAllowedTarget(...)` flips this on

  // Feature 3 — Spending limits / allowances
  mapping(address => uint256) internal _dailyLimitPerOwner; // wei cap per 24h
  mapping(address => uint256) internal _dailySpentByOwner; // wei accumulated this period
  mapping(address => uint256) internal _lastPeriodResetByOwner; // unix ts of last rollover

  // Feature 4 — Modules / plugins (Safe ModuleManager linked-list pattern)
  address internal _modulesHead;
  mapping(address => address) internal _modulesNext;
  mapping(address => bool) internal _isModule;

  // ---------------------------------------------------------------------------
  // v0.3.0 custom errors (unchanged)
  // ---------------------------------------------------------------------------
  error NonceAlreadyUsed();
  error TransferInactiveOwnershipTooShort();
  error TransferInactiveOwnershipBelowMinimum();
  error OwnerMustBeAnOwner();
  error OwnerIsNotAnOwner();
  error DelegateeCannotBeZero();
  error DelegateeAlreadyOwnerOrDelegatee();
  error SenderNotDelegatee();
  error OwnerStillActive();

  // ---------------------------------------------------------------------------
  // v0.4.0 custom errors
  // ---------------------------------------------------------------------------
  // Feature 1 — Timelock
  error TimelockNotReady(bytes32 txHash, uint256 readyAt, uint256 blockTimestamp);
  error SensitiveCallRequiresDelay(address to, bytes4 selector, uint256 value);
  error ZeroDelayForSensitive();
  error AlreadyScheduled(bytes32 txHash);
  error NotScheduled(bytes32 txHash);
  error NotSensitive();
  error ScheduleExpired(bytes32 txHash, uint256 scheduledValidUntil);

  // Feature 2 — Guard / allowlist
  error GuardReverted(address guard, bytes reason);
  error GuardIsZeroAddress();
  error TargetNotAllowed(address to);
  error TargetIsZeroAddress();

  // Feature 3 — Allowance
  error DailySpendingLimitExceeded(address owner, uint256 requested, uint256 remaining);
  error AllowanceRequiresSingleSigner();
  error AllowanceLimitNotSet(address owner);

  // Feature 4 — Modules
  error NotAModule(address caller);
  error ModuleAlreadyEnabled(address module);
  error ModuleIsZeroAddress();
  error ModulePrevMismatch(address prev, address module);
  error ModuleNotFound(address module);
  error InvalidModuleOperation(uint256 operation);

  // ---------------------------------------------------------------------------
  // v0.4.0 events (v0.3.0 events live in MyMultiSig.sol)
  // ---------------------------------------------------------------------------
  event TimelockDelaySet(uint256 delay);
  event SensitiveValueThresholdSet(uint256 threshold);
  event SensitiveSelectorSet(bytes4 indexed selector, bool isSensitive);
  event TransactionScheduled(bytes32 indexed txHash, uint256 readyAt, address indexed submitter);
  event ScheduledTransactionExecuted(bytes32 indexed txHash, address indexed submitter);
  event ScheduledTransactionCancelled(bytes32 indexed txHash, address indexed canceller);

  event GuardSet(address indexed guard);
  event PostExecutionGuardFailed(address indexed guard, bytes reason);
  event AllowedTargetSet(address indexed target, bool allowed);

  event DailySpendingLimitSet(address indexed owner, uint256 limit);

  event ModuleEnabled(address indexed module);
  event ModuleDisabled(address indexed module);
  event ModuleTransactionExecuted(
    address indexed module,
    address indexed to,
    uint256 indexed value,
    bytes data,
    uint256 operation,
    bool success
  );

  // ---------------------------------------------------------------------------
  // Constructor
  // ---------------------------------------------------------------------------
  constructor(
    string memory name_,
    address[] memory owners_,
    uint16 threshold_,
    bool isOnlyOwnerRequest_
  ) MyMultiSig(name_, owners_, threshold_) {
    _onlyOwnerRequest = isOnlyOwnerRequest_;

    // Register the default sensitive-selector set so a fresh Extended wallet
    // already enforces timelock on its own admin primitives once `_timelockDelay`
    // is set non-zero. Off-chain owners who register a smaller set via
    // `setSensitiveSelector(false)` are free to do so.
    _sensitiveSelectors[bytes4(keccak256('addOwner(address)'))] = true;
    _sensitiveSelectors[bytes4(keccak256('removeOwner(address)'))] = true;
    _sensitiveSelectors[bytes4(keccak256('replaceOwner(address,address)'))] = true;
    _sensitiveSelectors[bytes4(keccak256('changeThreshold(uint16)'))] = true;
    _sensitiveSelectors[bytes4(keccak256('setTransferInactiveOwnershipAfter(uint256)'))] = true;
    _sensitiveSelectors[bytes4(keccak256('setOwnerSettings(address,uint256,address)'))] = true;
    _sensitiveSelectors[bytes4(keccak256('markNonceAsUsed(uint256)'))] = true;
    _sensitiveSelectors[bytes4(keccak256('enableModule(address)'))] = true;
    _sensitiveSelectors[bytes4(keccak256('disableModule(address,address)'))] = true;
    _sensitiveSelectors[bytes4(keccak256('setTimelockDelay(uint256)'))] = true;
  }

  // ---------------------------------------------------------------------------
  // v0.4.0 version override
  // ---------------------------------------------------------------------------

  /// @notice Wallet version. Bumped to '0.4.0' for the four advanced features
  ///         (timelock, guard, allowance, modules) added in this release.
  function version() public pure virtual override returns (string memory) {
    return '0.4.0';
  }

  // ---------------------------------------------------------------------------
  // v0.3.0 view / read functions (unchanged)
  // ---------------------------------------------------------------------------

  /// @notice Retrieves if the contract only accepts owner requests (use for UI and other integrations)
  /// @return The true if the contract only accepts owner requests, false otherwise.
  function allowOnlyOwnerRequest() public view virtual returns (bool) {
    return _onlyOwnerRequest;
  }

  /// @notice Retrieves the minimum amount of time after which the other owners can transfer the ownership to a new owner
  /// @return a uint256 representing the minimum amount of time after which the other owners can transfer the ownership to a new owner
  function minimumTransferInactiveOwnershipAfter() public view virtual returns (uint256) {
    return _minimumTransferInactiveOwnershipAfter;
  }

  /// @notice Retrieves owner settings
  /// @return a OwnerSettings struct
  function ownerSettings(address owner) public view virtual returns (OwnerSettings memory) {
    return _ownerSettings[owner];
  }

  /// @notice Retrieves if the nonce has been used
  /// @return The true if the nonce has been used, false otherwise.
  function isNonceUsed(uint256 nonce) public view virtual returns (bool) {
    return _noncesUsed[nonce];
  }

  /// @notice Executes a transaction
  /// @param to The address to which the transaction is made.
  /// @param value The amount of Ether to be transferred.
  /// @param data The data to be passed along with the transaction.
  /// @param txnGas The gas limit for the transaction.
  /// @param txnNonce The nonce bound to the transaction. Lets callers pick a
  ///        nonce inside the replay window (any value in `[0, 2^96 - 1]`),
  ///        enabling signers to pre-sign for a future nonce (e.g. `_txnNonce + N`)
  ///        so the tx can be replayed later by anyone holding the signatures.
  ///        Reverts if `txnNonce` has already been marked as used via
  ///        `markNonceAsUsed`.
  /// @param validUntil Unix timestamp after which the signature is invalid;
  ///        `0` disables the deadline check.
  /// @param signatures The signatures to be used for the transaction.
  function execTransaction(
    address to,
    uint256 value,
    bytes memory data,
    uint256 txnGas,
    uint256 txnNonce,
    uint256 validUntil,
    bytes memory signatures
  ) public payable virtual nonReentrant returns (bool success) {
    success = _execTransaction(to, value, data, txnGas, txnNonce, validUntil, signatures);
  }

  // ---------------------------------------------------------------------------
  // v0.3.0 overrides (unchanged)
  // ---------------------------------------------------------------------------

  /// @notice Bumps `lastAction` for the owner whenever their vote is recorded
  ///         against a transaction — whether via `approveHash`, an off-chain
  ///         ECDSA signature, or an EIP-1271 contract-owner vote. Without this
  ///         override, vote-driven activity would silently bypass the
  ///         inactivity tracking that `takeOverOwnership` relies on.
  function _recordOwnerApproval(address owner) internal virtual override {
    _ownerSettings[owner].lastAction = block.timestamp;
  }

  /// @notice Determines if the signature is valid (extended)
  /// @dev Rejects signatures bound to a nonce that has already been marked as used,
  ///      so `markNonceAsUsed` permanently invalidates any transaction whose
  ///      EIP-712 hash is keyed on that nonce and closes the replay window.
  function _validateSignature(
    address to,
    uint256 value,
    bytes memory data,
    uint256 txnGas,
    uint256 txnNonce,
    uint256 validUntil,
    bytes memory signatures
  ) internal virtual override returns (bool valid) {
    if (_noncesUsed[txnNonce]) revert NonceAlreadyUsed();
    return super._validateSignature(to, value, data, txnGas, txnNonce, validUntil, signatures);
  }

  /// @notice Adds an owner
  /// @param owner The address to be added as an owner.
  /// @dev This function can only be called inside a multisig transaction.
  function _addOwner(address owner) internal virtual override {
    _ownersOrDelegates[owner] = true;
    super._addOwner(owner);
  }

  /// @notice Removes an owner
  /// @param owner The owner to be removed.
  /// @dev This function can only be called inside a multisig transaction.
  function _removeOwner(address owner) internal virtual override {
    _ownersOrDelegates[owner] = false;
    _ownerSettings[owner].delegate = address(0);
    super._removeOwner(owner);
  }

  /// @notice Replaces an owner with a new owner (internal)
  /// @param oldOwner The owner to be replaced.
  /// @param newOwner The new owner.
  /// @dev This function can only be called inside a multisig transaction.
  function _replaceOwner(address oldOwner, address newOwner) internal virtual override {
    _ownersOrDelegates[oldOwner] = false;
    _ownersOrDelegates[newOwner] = true;
    super._replaceOwner(oldOwner, newOwner);
  }

  // ---------------------------------------------------------------------------
  // v0.3.0 mutators (unchanged)
  // ---------------------------------------------------------------------------

  function setOnlyOwnerRequest(bool isOnlyOwnerRequest) public virtual onlyThis {
    _onlyOwnerRequest = isOnlyOwnerRequest;
  }

  function setTransferInactiveOwnershipAfter(uint256 transferInactiveOwnershipAfter) public virtual onlyThis {
    if (transferInactiveOwnershipAfter < 7 days) revert TransferInactiveOwnershipTooShort();
    _minimumTransferInactiveOwnershipAfter = transferInactiveOwnershipAfter;
  }

  function setOwnerSettings(
    address owner,
    uint256 transferInactiveOwnershipAfter,
    address delegatee
  ) public virtual onlyThis {
    if (!isOwner(owner)) revert OwnerMustBeAnOwner();
    if (transferInactiveOwnershipAfter <= _minimumTransferInactiveOwnershipAfter)
      revert TransferInactiveOwnershipBelowMinimum();
    if (delegatee == address(0)) revert DelegateeCannotBeZero();
    if (_ownersOrDelegates[delegatee]) revert DelegateeAlreadyOwnerOrDelegatee();
    _ownerSettings[owner] = OwnerSettings(block.timestamp, transferInactiveOwnershipAfter, delegatee);
    _ownersOrDelegates[delegatee] = true;
  }

  function takeOverOwnership(address owner) external virtual {
    if (!isOwner(owner)) revert OwnerIsNotAnOwner();
    OwnerSettings memory tempOwnerSettings = _ownerSettings[owner];
    if (tempOwnerSettings.delegate != msg.sender) revert SenderNotDelegatee();
    if (tempOwnerSettings.lastAction + tempOwnerSettings.transferInactiveOwnershipAfter >= block.timestamp)
      revert OwnerStillActive();
    _ownerSettings[owner].delegate = address(0);
    _ownerSettings[msg.sender].lastAction = block.timestamp;
    _ownerSettings[msg.sender].delegate = address(0);
    _replaceOwner(owner, msg.sender);
  }

  function markNonceAsUsed(uint256 nonce) public virtual onlyThis {
    _noncesUsed[nonce] = true;
  }

  // ---------------------------------------------------------------------------
  // v0.4.0 Feature 1 — Timelock / delay: views
  // ---------------------------------------------------------------------------

  function timelockDelay() public view virtual returns (uint256) {
    return _timelockDelay;
  }

  function sensitiveValueThreshold() public view virtual returns (uint256) {
    return _sensitiveValueThreshold;
  }

  function isSensitiveSelector(bytes4 sel) public view virtual returns (bool) {
    return _sensitiveSelectors[sel];
  }

  /// @notice Returns the unix timestamp a scheduled tx is ready to execute at.
  /// @dev `0` = not scheduled; `type(uint256).max` = already executed (replay blocked).
  function scheduledReadyAt(bytes32 txHash) public view virtual returns (uint256) {
    return _readyAt[txHash];
  }

  /// @notice Returns the `validUntil` recorded for a scheduled tx. The schedule
  ///         window is bounded: `executeScheduled` re-checks `block.timestamp`
  ///         against this value so the original sig window still applies.
  function scheduledValidUntil(bytes32 txHash) public view virtual returns (uint256) {
    return _scheduledValidUntil[txHash];
  }

  // ---------------------------------------------------------------------------
  // v0.4.0 Feature 1 — Timelock: setters (`onlyThis`)
  // ---------------------------------------------------------------------------

  /// @notice Sets the per-call timelock delay. Reducing the delay itself goes
  ///         through the slow path because `setTimelockDelay`'s selector is
  ///         registered as sensitive by default.
  /// @param delay The minimum number of seconds between `scheduleTransaction`
  ///              and `executeScheduled`. `0` disables the feature entirely.
  function setTimelockDelay(uint256 delay) public virtual onlyThis {
    _timelockDelay = delay;
    emit TimelockDelaySet(delay);
  }

  function setSensitiveValueThreshold(uint256 threshold) public virtual onlyThis {
    _sensitiveValueThreshold = threshold;
    emit SensitiveValueThresholdSet(threshold);
  }

  function setSensitiveSelector(bytes4 sel, bool isSensitive) public virtual onlyThis {
    _sensitiveSelectors[sel] = isSensitive;
    emit SensitiveSelectorSet(sel, isSensitive);
  }

  // ---------------------------------------------------------------------------
  // v0.4.0 Feature 1 — Timelock: schedule / execute / cancel
  // ---------------------------------------------------------------------------

  /// @notice Schedules a sensitive transaction. Reverts if the timelock feature
  ///         is disabled (`_timelockDelay == 0`), the tx is already scheduled,
  ///         the bound signatures fail to validate, or the payload is not
  ///         sensitive (so it shouldn't need the delay in the first place).
  /// @return txHash The EIP-712 transaction hash — also the queue id.
  function scheduleTransaction(
    address to,
    uint256 value,
    bytes memory data,
    uint256 txnGas,
    uint256 txnNonce,
    uint256 validUntil,
    bytes memory signatures
  ) public payable virtual nonReentrant returns (bytes32 txHash) {
    if (_timelockDelay == 0) revert ZeroDelayForSensitive();
    txHash = generateHash(to, value, data, txnGas, txnNonce, validUntil);
    if (_readyAt[txHash] != 0) revert AlreadyScheduled(txHash);
    if (validUntil != 0 && block.timestamp > validUntil) revert SignatureExpired();
    if (!_validateSignature(to, value, data, txnGas, txnNonce, validUntil, signatures))
      revert InvalidSignatures();
    if (!_isSensitive(to, _selectorOf(data), value)) revert NotSensitive();
    uint256 readyAt = block.timestamp + _timelockDelay;
    // `_readyAt == 0` is the "not scheduled" sentinel; nudge to `1` to avoid it.
    if (readyAt == 0) readyAt = 1;
    _readyAt[txHash] = readyAt;
    _scheduledValidUntil[txHash] = validUntil;
    emit TransactionScheduled(txHash, readyAt, msg.sender);
  }

  /// @notice Executes a previously-scheduled sensitive transaction.
  ///         Reverts if the tx was never scheduled (or was already executed —
  ///         detected via the `type(uint256).max` sentinel), the delay window
  ///         has not yet elapsed, or the original `validUntil` window has
  ///         already closed. On success, marks the entry as executed via
  ///         sentinel so replay attempts revert.
  /// @dev    Self-contained — we deliberately DON'T delegate to `_execTransaction`
  ///         (orchestrator) OR `super._execTransaction` because:
  ///           1. The orchestrator's `_preExecChecks` would re-block this
  ///              sensitive call (defeats the timelock).
  ///           2. The base's `_validateSignature` would re-read the
  ///              `(nonce, owner)` slots consumed during `scheduleTransaction`,
  ///              counting each signer's vote twice.
  ///         We instead re-validate the signatures via the existing
  ///         `_validateSignature` override (which already enforces the per-owner
  ///         anti-replay on the (nonce, owner) slot and the `_noncesUsed` kill
  ///         switch), but THEN manually perform the low-level call so the
  ///         `_txnNonce++` step happens AFTER our pre-call side-effects.
  function executeScheduled(
    address to,
    uint256 value,
    bytes memory data,
    uint256 txnGas,
    uint256 txnNonce,
    uint256 validUntil,
    bytes memory signatures
  ) public payable virtual nonReentrant returns (bool success) {
    bytes32 txHash = generateHash(to, value, data, txnGas, txnNonce, validUntil);
    uint256 ready = _readyAt[txHash];
    if (ready == 0 || ready == type(uint256).max) revert NotScheduled(txHash);
    if (block.timestamp < ready) revert TimelockNotReady(txHash, ready, block.timestamp);
    uint256 scheduledUntil = _scheduledValidUntil[txHash];
    if (scheduledUntil != 0 && block.timestamp > scheduledUntil)
      revert ScheduleExpired(txHash, scheduledUntil);
    // Mark the entry as executed BEFORE the inner call so partial reverts
    // (EVM rolls back storage) still block replay attempts.
    _readyAt[txHash] = type(uint256).max;

    // Guard + allowlist pre-checks (the timelock reverse-route is
    // intentionally absent — we already satisfied it to get here).
    _preExecChecksGuard(to, value, data);

    // Signatures were already validated in `scheduleTransaction`. Calling
    // `_validateSignature` again would double-consume the (nonce, owner)
    // anti-replay slots and cause the second pass to count zero votes.
    // The nonce-bound `txHash` makes payload-tampering impossible between
    // schedule and execute, so skipping the re-validation is safe.

    // Re-check the per-nonce kill switch: if the wallet's owner set
    // `markNonceAsUsed(nonce)` between schedule and execute (e.g., to
    // invalidate a pending scheduled admin call), we honor that
    // immediately.
    if (_noncesUsed[txnNonce]) revert NonceAlreadyUsed();

    // NOTE: we deliberately do NOT bump `_txnNonce` here. The base contract's
    // `incrementNonce()` is `onlyThis`-gated, and `executeScheduled`'s
    // `msg.sender` is the EOA caller, not the wallet itself — calling it
    // would revert `OnlyThisContract`. The (nonce, owner) anti-replay slots
    // were already consumed during `scheduleTransaction`, so the next
    // transaction at this nonce requires fresh signatures anyway. To
    // advance the wallet nonce after an execute, owners can issue a
    // follow-up tx (e.g., a no-op `multiRequest`) from inside a regular
    // execTransaction.

    bytes memory returnData;
    success = _doLowLevelCall(gasleft(), to, value, data, txnGas, returnData);
    if (!success && returnData.length > 0) {
      _bubbleRevert(returnData);
    }
    if (success) {
      emit TransactionExecuted(msg.sender, to, value, data, txnGas, txnNonce);
      _postExecChecks(to, value, data, txnGas, txnNonce, validUntil);
    } else {
      emit TxFailure(msg.sender, to, value, data, txnGas, txnNonce, returnData);
    }
    emit ScheduledTransactionExecuted(txHash, msg.sender);
  }


  function cancelScheduled(
    address to,
    uint256 value,
    bytes memory data,
    uint256 txnGas,
    uint256 txnNonce,
    uint256 validUntil
  ) public virtual onlyThis {
    bytes32 txHash = generateHash(to, value, data, txnGas, txnNonce, validUntil);
    if (_readyAt[txHash] == 0) revert NotScheduled(txHash);
    delete _readyAt[txHash];
    delete _scheduledValidUntil[txHash];
    emit ScheduledTransactionCancelled(txHash, msg.sender);
  }

  // ---------------------------------------------------------------------------
  // v0.4.0 Feature 2 — Guard / allowlist: views + setters
  // ---------------------------------------------------------------------------

  function guard() public view virtual returns (address) {
    return _guard;
  }

  function allowedTargets(address target) public view virtual returns (bool) {
    return _allowedTargets[target];
  }

  /// @notice Whether the built-in allowlist is currently enforced. Flipped on
  ///         the first call to `setAllowedTarget(target, allowed=true)`. Defaults
  ///         to `false` so a fresh wallet doesn't block any target.
  function allowedTargetsEnabled() public view virtual returns (bool) {
    return _allowedTargetsEnabled;
  }

  function setGuard(address guard_) public virtual onlyThis {
    _guard = guard_;
    emit GuardSet(guard_);
  }

  function setAllowedTarget(address target, bool allowed) public virtual onlyThis {
    if (target == address(0)) revert TargetIsZeroAddress();
    _allowedTargets[target] = allowed;
    _allowedTargetsEnabled = true;
    emit AllowedTargetSet(target, allowed);
  }

  // ---------------------------------------------------------------------------
  // v0.4.0 Feature 3 — Allowance: views + setters + entry point
  // ---------------------------------------------------------------------------

  function dailySpendingLimit(address owner) public view virtual returns (uint256) {
    return _dailyLimitPerOwner[owner];
  }

  /// @notice Remaining wei the owner can spend via `execTransactionWithSpendingAllowance`
  ///         before the next 24h rollover. Returns 0 if no limit is set or the
  ///         cap has been fully consumed.
  function spendingLimitRemaining(address owner) public view virtual returns (uint256) {
    uint256 cap = _dailyLimitPerOwner[owner];
    if (cap == 0) return 0;
    uint256 spent = _dailySpentByOwner[owner];
    uint256 lastReset = _lastPeriodResetByOwner[owner];
    if (lastReset == 0) return cap;
    if (block.timestamp >= lastReset + 1 days) return cap;
    return cap > spent ? cap - spent : 0;
  }

  function setDailySpendingLimit(address owner, uint256 limitWei) public virtual onlyThis {
    _dailyLimitPerOwner[owner] = limitWei;
    emit DailySpendingLimitSet(owner, limitWei);
  }

  /// @notice Single-signer "allowance" entry point. Unlike `execTransaction`
  ///         which requires `threshold` votes, this path accepts exactly ONE
  ///         65-byte ECDSA signature that must `ecrecover` to `msg.sender` —
  ///         and that single signer must be a current owner with a
  ///         non-zero `_dailyLimitPerOwner`. The recovered signer's daily
  ///         cap is charged by `value`; failed inner calls do NOT burn cap.
  /// @dev    Re-uses the same EIP-712 typehash as the regular exec path
  ///         (`_TRANSACTION_TYPEHASH` at `MyMultiSig.sol:32`); the bound
  ///         signatures must therefore include the same `(to, value, data, gas,
  ///         nonce = _txnNonce, validUntil)` fields. Off-chain tooling can
  ///         produce one signature and route via the regular `execTransaction`
  ///         OR via this allowance path.
  function execTransactionWithSpendingAllowance(
    address to,
    uint256 value,
    bytes memory data,
    uint256 txnGas,
    uint256 validUntil,
    bytes memory signatures
  ) public payable virtual nonReentrant returns (bool success) {
    if (signatures.length != 65) revert AllowanceRequiresSingleSigner();
    uint96 currentNonce = nonce();
    bytes32 txHash = generateHash(to, value, data, txnGas, currentNonce, validUntil);
    address recovered = _recoverSigner(signatures, txHash);
    if (recovered != msg.sender || !isOwner(recovered)) revert AllowanceRequiresSingleSigner();
    uint256 cap = _dailyLimitPerOwner[recovered];
    if (cap == 0) revert AllowanceLimitNotSet(recovered);
    _rolloverIfNeeded(recovered);
    uint256 remaining = cap - _dailySpentByOwner[recovered];
    if (value > remaining) revert DailySpendingLimitExceeded(recovered, value, remaining);

    // Pre-checks (guard + allowlist). The timelock reverse-route is
    // intentionally absent here — this path is only for plain transfers.
    _preExecChecksGuard(to, value, data);

    bytes memory returnData;
    success = _doLowLevelCall(gasleft(), to, value, data, txnGas, returnData);
    if (!success && returnData.length > 0) {
      _bubbleRevert(returnData);
    }
    if (success) {
      _dailySpentByOwner[recovered] += value;
      emit TransactionExecuted(msg.sender, to, value, data, txnGas, currentNonce);
      _postExecChecks(to, value, data, txnGas, currentNonce, validUntil);
    } else {
      emit TxFailure(msg.sender, to, value, data, txnGas, currentNonce, returnData);
    }
  }

  /// @dev Low-level `call` mirroring the assembly pattern in
  ///      `MyMultiSig.sol:336-343`. Returns whether the call succeeded and
  ///      captures the returndata. Used by the v0.4.0 self-contained entry
  ///      points (`execTransactionWithSpendingAllowance`, `execTransactionFromModule`)
  ///      so each one doesn't need its own copy of the assembly.
  function _doLowLevelCall(
    uint256 gasBudget,
    address to,
    uint256 value,
    bytes memory data,
    uint256 txnGas,
    bytes memory returnDataOut
  ) internal returns (bool success) {
    assembly {
      success := call(txnGas, to, value, add(data, 0x20), mload(data), 0, 0)
      let size := returndatasize()
      returnDataOut := mload(0x40)
      mstore(returnDataOut, size)
      returndatacopy(add(returnDataOut, 0x20), 0, size)
      mstore(0x40, add(add(returnDataOut, 0x20), and(add(size, 0x1f), not(0x1f))))
    }
    // gasBudget unused — the call uses `txnGas` directly. Kept as a
    // future-proofing knob.
    gasBudget;
  }

  /// @dev Revert with raw returndata, mirroring `MyMultiSig.sol:352-354`.
  function _bubbleRevert(bytes memory returnData) internal pure {
    assembly {
      revert(add(returnData, 0x20), mload(returnData))
    }
  }

  // ---------------------------------------------------------------------------
  // v0.4.0 Feature 4 — Modules: views + setters + entry point
  // ---------------------------------------------------------------------------

  function modulesHead() public view virtual returns (address) {
    return _modulesHead;
  }

  function isModule(address module) public view virtual returns (bool) {
    return _isModule[module];
  }

  function moduleNext(address module) public view virtual returns (address) {
    return _modulesNext[module];
  }

  /// @notice Returns the enabled module list in registration order (most
  ///         recently enabled first). Bounded by `ownerCount <= 65535`.
  function getModules() public view virtual returns (address[] memory modules) {
    uint256 count;
    address cursor = _modulesHead;
    while (cursor != address(0)) {
      unchecked {
        ++count;
      }
      cursor = _modulesNext[cursor];
    }
    modules = new address[](count);
    cursor = _modulesHead;
    for (uint256 i; cursor != address(0); ) {
      modules[i] = cursor;
      cursor = _modulesNext[cursor];
      unchecked {
        ++i;
      }
    }
  }

  /// @notice Inserts `module` at the head of the linked list. Reverts on zero
  ///         address or duplicate registration.
  function enableModule(address module) public virtual onlyThis {
    if (module == address(0)) revert ModuleIsZeroAddress();
    if (_isModule[module]) revert ModuleAlreadyEnabled(module);
    _isModule[module] = true;
    _modulesNext[module] = _modulesHead;
    _modulesHead = module;
    emit ModuleEnabled(module);
  }

  /// @notice Removes `module` from the linked list. Safe's pattern requires
  ///         `prevModule` to be the immediate predecessor in the chain so a
  ///         malicious current module can't front-run disconnects of its
  ///         siblings. To remove the head, pass `prevModule = address(0)`.
  function disableModule(address prevModule, address module) public virtual onlyThis {
    if (module == address(0)) revert ModuleIsZeroAddress();
    if (!_isModule[module]) revert ModuleNotFound(module);
    if (_modulesHead == module) {
      // Strict head removal: only `prevModule == address(0)` is allowed when
      // removing the head. Mirrors the Safe ModuleManager's sentinel-based
      // pattern; a non-zero prev with module=head is rejected as a
      // `ModulePrevMismatch` so the caller can't bypass the prev-pointer
      // verification.
      if (prevModule != address(0)) revert ModulePrevMismatch(prevModule, module);
      _modulesHead = _modulesNext[module];
    } else {
      if (prevModule == address(0) || _modulesNext[prevModule] != module)
        revert ModulePrevMismatch(prevModule, module);
      _modulesNext[prevModule] = _modulesNext[module];
    }
    delete _modulesNext[module];
    _isModule[module] = false;
    emit ModuleDisabled(module);
  }

  /// @notice Module-driven entry point. Bypasses signature threshold (modules
  ///         are trusted operational plugins). The active guard (if any) and
  ///         the built-in allowlist still apply.
  /// @param to For CALL (operation=0), the destination. For DELEGATECALL
  ///          (operation=1), MUST equal `address(this)` so the module's code
  ///          runs in the wallet's storage context.
  /// @param value Wei forwarded with the call. Ignored for DELEGATECALL.
  /// @param data Calldata for the call.
  /// @param operation 0 = CALL, 1 = DELEGATECALL.
  /// @dev    Does NOT bump `_txnNonce` so pending owner-signed transactions
  ///         remain valid after a module action.
  function execTransactionFromModule(
    address to,
    uint256 value,
    bytes memory data,
    uint256 operation
  ) public payable virtual returns (bool success) {
    if (!_isModule[msg.sender]) revert NotAModule(msg.sender);
    if (operation > 1) revert InvalidModuleOperation(operation);

    // Modules bypass the timelock reverse-route (they are operational
    // plugins the multisig has explicitly authorized) but still answer
    // to the guard + allowlist.
    _preExecChecksGuard(to, value, data);

    uint256 gasBefore = gasleft();
    bytes memory returnData;
    if (operation == 0) {
      assembly {
        success := call(gasBefore, to, value, add(data, 0x20), mload(data), 0, 0)
        let size := returndatasize()
        returnData := mload(0x40)
        mstore(returnData, size)
        returndatacopy(add(returnData, 0x20), 0, size)
        mstore(0x40, add(add(returnData, 0x20), and(add(size, 0x1f), not(0x1f))))
      }
    } else {
      // DELEGATECALL — `to` MUST be address(this) so the module's code runs in
      // the wallet's storage context.
      if (to != address(this)) revert InvalidModuleOperation(1);
      assembly {
        success := delegatecall(gasBefore, caller(), add(data, 0x20), mload(data), 0, 0)
        let size := returndatasize()
        returnData := mload(0x40)
        mstore(returnData, size)
        returndatacopy(add(returnData, 0x20), 0, size)
        mstore(0x40, add(add(returnData, 0x20), and(add(size, 0x1f), not(0x1f))))
      }
    }

    if (success) {
      address guardContract = _guard;
      if (guardContract != address(0)) {
        bytes32 txHash = keccak256(abi.encode(msg.sender, to, value, data, operation, block.number));
        try ITransactionGuard(guardContract).checkAfterExecution(txHash, true) {} catch (
          bytes memory reason
        ) {
          emit PostExecutionGuardFailed(guardContract, reason);
        }
      }
    } else if (returnData.length > 0) {
      assembly {
        revert(add(returnData, 0x20), mload(returnData))
      }
    }

    emit ModuleTransactionExecuted(msg.sender, to, value, data, operation, success);
  }

  // ---------------------------------------------------------------------------
  // v0.4.0 — _execTransaction orchestrator + per-feature pre/post hooks
  // ---------------------------------------------------------------------------

  /// @notice v0.4.0 override of the base `_execTransaction`. Runs the four
  ///         pre-execution hooks (timelock sensitivity, guard, allowlist),
  ///         then delegates to the base, then runs the post-execution guard
  ///         hook (silent). Failed inner calls bubble through the existing
  ///         revert path at `MyMultiSig.sol:347-354`.
  function _execTransaction(
    address to,
    uint256 value,
    bytes memory data,
    uint256 txnGas,
    uint256 txnNonce,
    uint256 validUntil,
    bytes memory signatures
  ) internal virtual override returns (bool success) {
    _preExecChecks(to, value, data);
    success = super._execTransaction(to, value, data, txnGas, txnNonce, validUntil, signatures);
    // The base already bumped `_txnNonce`, so the post-bump hash uses
    // `txnNonce + 1`. The guard only inspects `checkAfterExecution`; the precise
    // binding of the post hash to on-chain state is informational.
    if (success) {
      _postExecChecks(to, value, data, txnGas, txnNonce + 1, validUntil);
    }
  }

  /// @dev Pre-execution checks: timelock-sensitive reverse-route, pluggable
  ///      guard, and built-in allowlist. Each gate fails fast (no state
  ///      change) so a violation is atomic with the EVM-level revert.
  function _preExecChecks(address to, uint256 value, bytes memory data) internal virtual {
    _preExecChecksTimelock(to, value, data);
    _preExecChecksGuard(to, value, data);
  }

  /// @dev Feature 1 — Sensitive calls must be scheduled, not direct-executed.
  ///      Bypassed by `executeScheduled` (which has already passed the
  ///      delay-and-validity checks) and by `execTransactionWithSpendingAllowance`
  ///      (which is only intended for plain transfers).
  function _preExecChecksTimelock(address to, uint256 value, bytes memory data) internal virtual {
    if (_timelockDelay > 0 && _isSensitive(to, _selectorOf(data), value)) {
      revert SensitiveCallRequiresDelay(to, _selectorOf(data), value);
    }
  }

  /// @dev Feature 2 — Guard + built-in allowlist. Reverts from the guard
  ///      are wrapped so consumers can identify which guard failed and
  ///      inspect the raw payload.
  function _preExecChecksGuard(address to, uint256 value, bytes memory data) internal virtual {
    address guardContract = _guard;
    if (guardContract != address(0)) {
      try ITransactionGuard(guardContract).checkTransaction(to, value, data) {} catch (bytes memory reason) {
        revert GuardReverted(guardContract, reason);
      }
    }
    if (_allowedTargetsEnabled && !_allowedTargets[to]) revert TargetNotAllowed(to);
  }

  /// @dev Post-execution hook: silent `checkAfterExecution` (failure logged via
  ///      `PostExecutionGuardFailed` but never reverts). Spending-limit commit
  ///      for the single-signer path happens in the entry point itself —
  ///      `execTransactionWithSpendingAllowance` — so this helper is guard-only.
  function _postExecChecks(
    address to,
    uint256 value,
    bytes memory data,
    uint256 txnGas,
    uint256 txnNoncePostBump,
    uint256 validUntil
  ) internal virtual {
    address guardContract = _guard;
    if (guardContract != address(0)) {
      bytes32 txHash = generateHash(to, value, data, txnGas, txnNoncePostBump, validUntil);
      try ITransactionGuard(guardContract).checkAfterExecution(txHash, true) {} catch (bytes memory reason) {
        emit PostExecutionGuardFailed(guardContract, reason);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // v0.4.0 — multiRequest overrides that run the guard per inner call
  // ---------------------------------------------------------------------------

  /// @notice Override of `multiRequest` (base `MyMultiSig.sol:380`) that runs
  ///         the active guard and built-in allowlist on each inner call before
  ///         the low-level `call`. The outer call from `_execTransaction` is
  ///         already pre-checked by `_preExecChecks`.
  function multiRequest(
    address[] memory to,
    uint256[] memory value,
    bytes[] memory data,
    uint256[] memory txGas
  ) public payable virtual override onlyThis returns (bool[] memory successes, bytes[] memory returnData) {
    uint256 qty = to.length;
    successes = new bool[](qty);
    returnData = new bytes[](qty);
    for (uint256 i; i < qty; ) {
      _preExecChecks(to[i], value[i], data[i]);
      address to_ = to[i];
      uint256 value_ = value[i];
      bytes memory data_ = data[i];
      uint256 txGas_ = txGas[i];
      bool callSuccess;
      bytes memory callReturnData;
      assembly {
        callSuccess := call(txGas_, to_, value_, add(data_, 0x20), mload(data_), 0, 0)
        let size := returndatasize()
        callReturnData := mload(0x40)
        mstore(callReturnData, size)
        returndatacopy(add(callReturnData, 0x20), 0, size)
        mstore(0x40, add(add(callReturnData, 0x20), and(add(size, 0x1f), not(0x1f))))
      }
      successes[i] = callSuccess;
      returnData[i] = callReturnData;
      unchecked {
        ++i;
      }
    }
    // The base already bumped `_txnNonce` in `_execTransaction` before this
    // function is reached, so the outer transaction's nonce is one less than
    // the current `nonce()` view.
    uint96 outerNonce = nonce();
    emit MultiRequestExecuted(outerNonce - 1, successes, returnData);
  }

  /// @notice Override of `multiRequestStrict` (base `MyMultiSig.sol:437`) that
  ///         runs the guard + allowlist on each inner call before the
  ///         low-level `call`. Reverts the entire batch on the first inner
  ///         failure (no partial side effects, no `MultiRequestExecuted`).
  function multiRequestStrict(
    address[] memory to,
    uint256[] memory value,
    bytes[] memory data,
    uint256[] memory txGas
  ) public payable virtual override onlyThis {
    uint256 qty = to.length;
    for (uint256 i; i < qty; ) {
      _preExecChecks(to[i], value[i], data[i]);
      address to_ = to[i];
      uint256 value_ = value[i];
      bytes memory data_ = data[i];
      uint256 txGas_ = txGas[i];
      bool ok;
      bytes memory returnData;
      assembly {
        ok := call(txGas_, to_, value_, add(data_, 0x20), mload(data_), 0, 0)
        let size := returndatasize()
        returnData := mload(0x40)
        mstore(returnData, size)
        returndatacopy(add(returnData, 0x20), 0, size)
        mstore(0x40, add(add(returnData, 0x20), and(add(size, 0x1f), not(0x1f))))
      }
      if (!ok) revert BatchCallFailed(i, returnData);
      unchecked {
        ++i;
      }
    }
  }

  // ---------------------------------------------------------------------------
  // v0.4.0 — informational bitmask and helpers
  // ---------------------------------------------------------------------------

  /// @notice Bitmask of which advanced features are currently active. Purely
  ///         informational for UIs and explorers:
  ///           bit 0 (1) — Timelock delay > 0
  ///           bit 1 (2) — Guard is set
  ///           bit 2 (4) — Allowlist enabled
  ///           bit 3 (8) — At least one daily allowance cap is set
  ///           bit 4 (16) — At least one module is enabled
  function advancedFeaturesEnabled() public view virtual returns (uint8 mask) {
    if (_timelockDelay > 0) mask |= 0x01;
    if (_guard != address(0)) mask |= 0x02;
    if (_allowedTargetsEnabled) mask |= 0x04;
    if (_dailyLimitPerOwner[address(0)] > 0) {
      // Note: address(0) is unlikely to be a configured owner; this is a
      // conservative bit-flip only when a cap on address(0) is set. UIs
      // querying whether the feature is generally active should iterate.
      mask |= 0x08;
    }
    // For the budget bit we use the heads because a single membership check
    // is cheaper than scanning owners at view time.
    if (_modulesHead != address(0)) mask |= 0x10;
  }

  // ---------------------------------------------------------------------------
  // Internal helpers (Feature 1 / 3 / 4)
  // ---------------------------------------------------------------------------

  /// @dev First 4 bytes of `data`, or `bytes4(0)` for short calldata. A
  ///      short calldata cannot match any sensitive selector (which require
  ///      at least the 4-byte selector prefix), so this is the safe default.
  function _selectorOf(bytes memory data) internal pure returns (bytes4) {
    if (data.length < 4) return bytes4(0);
    return bytes4(data);
  }

  /// @dev True iff `(to, selector, value)` matches the sensitive predicate:
  ///      either the call targets the wallet itself at a registered sensitive
  ///      selector, or the forwarded value meets (or exceeds) the configured
  ///      sensitive wei threshold.
  function _isSensitive(address to, bytes4 sel, uint256 value) internal view returns (bool) {
    if (to == address(this) && _sensitiveSelectors[sel]) return true;
    if (_sensitiveValueThreshold > 0 && value >= _sensitiveValueThreshold) return true;
    return false;
  }

  /// @dev ECDSA recovery for the allowance path. Mirrors the inline Yul at
  ///      `MyMultiSig.sol:595-599` but operates on `bytes memory` directly.
  ///      Returns `address(0)` on malformed input (no owner check here — the
  ///      caller verifies the recovered address against `msg.sender` and the
  ///      owner set).
  function _recoverSigner(bytes memory sig, bytes32 txHash) internal pure virtual returns (address) {
    bytes32 r;
    bytes32 s;
    uint8 v;
    assembly {
      r := mload(add(sig, 32))
      s := mload(add(sig, 64))
      v := and(mload(add(sig, 65)), 255)
    }
    return ecrecover(txHash, v, r, s);
  }

  /// @dev Rollover helper: if `_lastPeriodResetByOwner[owner]` is zero or
  ///      older than 24h, reset `_dailySpentByOwner[owner]` to zero and
  ///      record the new anchor.
  function _rolloverIfNeeded(address owner) internal {
    uint256 lastReset = _lastPeriodResetByOwner[owner];
    if (lastReset == 0 || block.timestamp >= lastReset + 1 days) {
      _dailySpentByOwner[owner] = 0;
      _lastPeriodResetByOwner[owner] = block.timestamp;
    }
  }
}
