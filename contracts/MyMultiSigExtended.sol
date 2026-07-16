// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';
import './MyMultiSig.sol';
import './interfaces/ITransactionGuard.sol';
import './interfaces/IAccount.sol';
import './interfaces/IEntryPoint.sol';
import './interfaces/PackedUserOperation.sol';

/// @title MyMultiSigExtended
/// @notice Extends `MyMultiSig` with inactivity / delegate handover,
///         opt-in features (timelock, guard, allowlist, allowance,
///         modules — all disabled by default), an `operation` byte on
///         `execTransaction` (0 = CALL, 1 = DELEGATECALL gated to
///         `to == address(this)`), and ERC-4337 v0.7 account abstraction.
/// @dev    Storage is appended at the END of each release so later
///         versions never collide with earlier storage slots.
contract MyMultiSigExtended is MyMultiSig, IAccount {
  // --- v0.3.0 state ---
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

  // --- v0.4.0 storage ---

  // Hot-path feature gates. `_guard`, `_allowedTargetsEnabled` and
  // `_timelockDelay` are all read by `_preExecChecks` on EVERY
  // `execTransaction`, so they share a single storage slot
  // (160 + 8 + 88 bits) and the gates pay one cold SLOAD per exec. The
  // uint88 delay caps at ~9.8e18 years — effectively unbounded;
  // `setTimelockDelay` enforces the cap.
  address internal _guard;
  bool internal _allowedTargetsEnabled; // flipped on by the first `setAllowedTarget(target, true)`; reset only by `disableAllowlist`
  uint88 internal _timelockDelay; // 0 = disabled

  // Timelock
  uint256 internal _sensitiveValueThreshold; // 0 = value-cap disabled
  /// @dev Tri-state override of the built-in default sensitive-selector set
  ///      (see `_isDefaultSensitiveSelector`): 0 = use the default set,
  ///      1 = forced sensitive, 2 = forced not sensitive. The default set
  ///      lives in code, not storage, so wallet deployment pays no
  ///      per-selector SSTOREs.
  mapping(bytes4 => uint8) internal _sensitiveSelectorOverride;
  mapping(bytes32 => uint256) internal _readyAt; // 0 = unscheduled, max = executed
  mapping(bytes32 => uint256) internal _scheduledValidUntil;

  // Guard / allowlist
  mapping(address => bool) internal _allowedTargets;

  // Allowance
  bool internal _dailyLimitsEnabled; // first non-zero setDailySpendingLimit flips this on
  mapping(address => uint256) internal _dailyLimitPerOwner;
  mapping(address => uint256) internal _dailySpentByOwner;
  mapping(address => uint256) internal _lastPeriodResetByOwner;

  // Modules
  address internal _modulesHead;
  mapping(address => address) internal _modulesNext;
  mapping(address => bool) internal _isModule;

  // --- v0.3.0 custom errors ---
  error NonceAlreadyUsed();
  error TransferInactiveOwnershipTooShort();
  error TransferInactiveOwnershipBelowMinimum();
  error OwnerMustBeAnOwner();
  error OwnerIsNotAnOwner();
  error DelegateeCannotBeZero();
  error DelegateeAlreadyOwnerOrDelegatee();
  error SenderNotDelegatee();
  error OwnerStillActive();

  // --- v0.4.0 custom errors ---
  // Timelock
  error TimelockNotReady(bytes32 txHash, uint256 readyAt, uint256 blockTimestamp);
  error SensitiveCallRequiresDelay(address to, bytes4 selector, uint256 value);
  error ZeroDelayForSensitive();
  /// @notice `setTimelockDelay` rejects delays above `type(uint88).max`
  ///         (~9.8e18 years) — the delay shares a packed slot with the
  ///         guard address and allowlist flag. Any real-world delay fits.
  error DelayTooLong();
  error AlreadyScheduled(bytes32 txHash);
  error NotScheduled(bytes32 txHash);
  error NotSensitive();
  error ScheduleExpired(bytes32 txHash, uint256 scheduledValidUntil);

  // Guard / allowlist
  error GuardReverted(address guard, bytes reason);
  error GuardIsZeroAddress();
  error TargetNotAllowed(address to);
  error TargetIsZeroAddress();

  // Allowance
  error DailySpendingLimitExceeded(address owner, uint256 requested, uint256 remaining);
  error AllowanceRequiresSingleSigner();
  error AllowanceLimitNotSet(address owner);

  // Modules
  error NotAModule(address caller);
  error ModuleAlreadyEnabled(address module);
  error ModuleIsZeroAddress();
  error ModulePrevMismatch(address prev, address module);
  error ModuleNotFound(address module);
  error InvalidModuleOperation(uint256 operation);

  // --- v0.5.0 custom errors ---
  error InvalidOperation(uint8 operation);
  error NotEntryPoint();
  error RequiresOperationByte();

  // --- v0.4.0 events (v0.3.0 events live in MyMultiSig.sol) ---

  event TimelockDelaySet(uint256 delay);
  event SensitiveValueThresholdSet(uint256 threshold);
  event SensitiveSelectorSet(bytes4 indexed selector, bool isSensitive);
  event TransactionScheduled(bytes32 indexed txHash, uint256 readyAt, address indexed submitter);
  event ScheduledTransactionExecuted(bytes32 indexed txHash, address indexed submitter);
  event ScheduledTransactionCancelled(bytes32 indexed txHash, address indexed canceller);

  event GuardSet(address indexed guard);
  event PostExecutionGuardFailed(address indexed guard, bytes reason);
  event AllowedTargetSet(address indexed target, bool allowed);
  event AllowlistDisabled();

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
  /// @custom:oz-upgrades-unsafe-allow constructor
  /// @dev    `entryPoint_` pins the ERC-4337 EntryPoint for the wallet's
  ///         lifetime and must be non-zero.
  constructor(
    string memory name_,
    address[] memory owners_,
    uint16 threshold_,
    bool isOnlyOwnerRequest_,
    address entryPoint_
  ) MyMultiSig(name_, owners_, threshold_) {
    _onlyOwnerRequest = isOnlyOwnerRequest_;

    // The default sensitive-selector set lives in code — see
    // `_isDefaultSensitiveSelector`. Once `_timelockDelay` is non-zero,
    // every privileged admin call there must go through
    // `scheduleTransaction`. Owners can prune the set via
    // `setSensitiveSelector(sel, false)`.

    if (entryPoint_ == address(0)) revert InvalidOperation(0);
    ENTRY_POINT = IEntryPoint(entryPoint_);
  }

  // ---------------------------------------------------------------------------
  // v0.5.0 immutable + version override
  // ---------------------------------------------------------------------------

  /// @notice Pinned EntryPoint for ERC-4337 v0.7 operations. Frozen at
  ///         deploy time; the address is part of the wallet's on-chain
  ///         identity (the wallet won't accept a UserOp from any other
  ///         EntryPoint). The canonical EntryPoint v0.7 address is
  ///         `0x0000000071727De22E5E9d8BDe0dFeC0CEB6a7d7` and is the
  ///         same on every EVM chain.
  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  IEntryPoint public immutable ENTRY_POINT;

  /// @notice Wallet version — same canonical value as the base wallet and
  ///         the factory, so the EIP-712 domain separator is shared; only
  ///         the typehash differs (a 7-field hash binds the `operation`
  ///         byte; the base wallet uses a 6-field hash).
  function version() public pure virtual override returns (string memory) {
    return '0.5.0';
  }

  // ---------------------------------------------------------------------------
  // v0.3.0 view / read functions
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

  /// @notice Disabled overload: this wallet binds the `operation` byte
  ///         into the EIP-712 payload, so `execTransaction` calls without
  ///         an `operation` argument always revert with
  ///         `RequiresOperationByte()`. Use one of the `operation`-carrying
  ///         overloads declared at the bottom of this contract.
  function execTransaction(
    address /* to */,
    uint256 /* value */,
    bytes memory /* data */,
    uint256 /* txnGas */,
    uint256 /* txnNonce */,
    uint256 /* validUntil */,
    bytes memory /* signatures */
  ) public payable virtual nonReentrant returns (bool /* success */) {
    revert RequiresOperationByte();
  }

  // ---------------------------------------------------------------------------
  // v0.3.0 overrides
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
  // v0.3.0 mutators
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
    uint8 overridden = _sensitiveSelectorOverride[sel];
    if (overridden != 0) return overridden == 1;
    return _isDefaultSensitiveSelector(sel);
  }

  /// @dev The built-in default sensitive-selector set, kept in code so the
  ///      constructor doesn't pay 10 cold SSTOREs per deployment. Every
  ///      privileged admin selector of the wallet family is listed;
  ///      `setSensitiveSelector` overrides win over this default.
  function _isDefaultSensitiveSelector(bytes4 sel) internal pure virtual returns (bool) {
    return
      sel == bytes4(keccak256('addOwner(address)')) ||
      sel == bytes4(keccak256('removeOwner(address)')) ||
      sel == bytes4(keccak256('replaceOwner(address,address)')) ||
      sel == bytes4(keccak256('changeThreshold(uint16)')) ||
      sel == bytes4(keccak256('setTransferInactiveOwnershipAfter(uint256)')) ||
      sel == bytes4(keccak256('setOwnerSettings(address,uint256,address)')) ||
      sel == bytes4(keccak256('markNonceAsUsed(uint256)')) ||
      sel == bytes4(keccak256('enableModule(address)')) ||
      sel == bytes4(keccak256('disableModule(address,address)')) ||
      sel == bytes4(keccak256('setTimelockDelay(uint256)'));
  }

  /// @notice Returns the unix timestamp a scheduled tx is ready to execute at.
  ///         `0` = not scheduled; `type(uint256).max` = already executed.
  function scheduledReadyAt(bytes32 txHash) public view virtual returns (uint256) {
    return _readyAt[txHash];
  }

  /// @notice Returns the `validUntil` recorded for a scheduled tx. Re-checked
  ///         by `executeScheduled` so the schedule window is bounded.
  function scheduledValidUntil(bytes32 txHash) public view virtual returns (uint256) {
    return _scheduledValidUntil[txHash];
  }

  // ---------------------------------------------------------------------------
  // v0.4.0 Feature 1 — Timelock: setters (`onlyThis`)
  // ---------------------------------------------------------------------------

  /// @notice Sets the per-call timelock delay. `setTimelockDelay` itself is
  ///         a sensitive selector (registered in the constructor), so
  ///         reducing the delay also goes through the slow path.
  function setTimelockDelay(uint256 delay) public virtual onlyThis {
    if (delay > type(uint88).max) revert DelayTooLong();
    _timelockDelay = uint88(delay);
    emit TimelockDelaySet(delay);
  }

  function setSensitiveValueThreshold(uint256 threshold) public virtual onlyThis {
    _sensitiveValueThreshold = threshold;
    emit SensitiveValueThresholdSet(threshold);
  }

  function setSensitiveSelector(bytes4 sel, bool isSensitive) public virtual onlyThis {
    _sensitiveSelectorOverride[sel] = isSensitive ? 1 : 2;
    emit SensitiveSelectorSet(sel, isSensitive);
  }

  // ---------------------------------------------------------------------------
  // v0.4.0 Feature 1 — Timelock: schedule / execute / cancel
  // ---------------------------------------------------------------------------

  /// @notice Schedules a sensitive transaction. Reverts if the timelock
  ///         feature is disabled, the tx is already scheduled, the bound
  ///         signatures fail to validate, or the payload isn't sensitive.
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
    // Extended wallets sign over the 7-field typehash, so the
    // timelock-ready hash must match it. operation is locked to 0 here:
    // timelock only applies to admin calls (CALL, not DELEGATECALL).
    txHash = generateHashOp(to, value, data, txnGas, txnNonce, validUntil, 0);
    if (_readyAt[txHash] != 0) revert AlreadyScheduled(txHash);
    if (validUntil != 0 && block.timestamp > validUntil) revert SignatureExpired();
    // Use the mutating validator (records per-`(nonce, owner)`
    // slot via `_recordVote`) so schedules consume the same vote slot
    // a direct `execTransaction` would, blocking replays.
    if (!_validateSignatureOp(txHash, txnNonce, validUntil, signatures)) revert InvalidSignatures();
    if (!_isSensitive(to, _selectorOf(data), value)) revert NotSensitive();
    uint256 readyAt = block.timestamp + _timelockDelay;
    // `_readyAt == 0` is the "not scheduled" sentinel — bump to `1` to avoid it.
    if (readyAt == 0) readyAt = 1;
    _readyAt[txHash] = readyAt;
    _scheduledValidUntil[txHash] = validUntil;
    emit TransactionScheduled(txHash, readyAt, msg.sender);
  }

  /// @notice Executes a previously-scheduled sensitive transaction. Reverts
  ///         if the tx was never scheduled, the delay window hasn't elapsed,
  ///         or the original `validUntil` window has closed.
  /// @dev    Self-contained — deliberately does NOT delegate to the
  ///         orchestrator (which would re-block the sensitive call) or to
  ///         `super._execTransaction` (which would re-read the (nonce, owner)
  ///         anti-replay slots consumed at schedule time, counting zero
  ///         votes). Nonce is intentionally NOT bumped here — the base's
  ///         `incrementNonce()` is `onlyThis` and `msg.sender` is the EOA
  ///         caller. The (nonce, owner) slots consumed at schedule time
  ///         already prevent any further tx at this nonce without fresh sigs.
  function executeScheduled(
    address to,
    uint256 value,
    bytes memory data,
    uint256 txnGas,
    uint256 txnNonce,
    uint256 validUntil,
    bytes memory signatures
  ) public payable virtual nonReentrant returns (bool success) {
    bytes32 txHash = generateHashOp(to, value, data, txnGas, txnNonce, validUntil, 0);
    uint256 ready = _readyAt[txHash];
    if (ready == 0 || ready == type(uint256).max) revert NotScheduled(txHash);
    if (block.timestamp < ready) revert TimelockNotReady(txHash, ready, block.timestamp);
    uint256 scheduledUntil = _scheduledValidUntil[txHash];
    if (scheduledUntil != 0 && block.timestamp > scheduledUntil)
      revert ScheduleExpired(txHash, scheduledUntil);
    // Mark executed BEFORE the inner call so a partial revert (rolled-back
    // storage) still blocks replays.
    _readyAt[txHash] = type(uint256).max;
    _preExecChecksGuard(to, value, data);
    // Honored if `markNonceAsUsed(nonce)` was called between schedule and
    // execute (e.g., to invalidate a pending admin call).
    if (_noncesUsed[txnNonce]) revert NonceAlreadyUsed();

    success = _runLoggedCall(to, value, data, txnGas, txnNonce, validUntil);
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
    bytes32 txHash = generateHashOp(to, value, data, txnGas, txnNonce, validUntil, 0);
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
  ///         by `setAllowedTarget(target, true)` and off by `disableAllowlist`.
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
    if (allowed) _allowedTargetsEnabled = true;
    emit AllowedTargetSet(target, allowed);
  }

  /// @notice Turn off the built-in allowlist. Existing entries are preserved
  ///         so a subsequent `setAllowedTarget(target, true)` re-enables
  ///         without rebuilding the list.
  function disableAllowlist() public virtual onlyThis {
    _allowedTargetsEnabled = false;
    emit AllowlistDisabled();
  }

  // ---------------------------------------------------------------------------
  // v0.4.0 Feature 3 — Allowance: views + setters + entry point
  // ---------------------------------------------------------------------------

  function dailySpendingLimit(address owner) public view virtual returns (uint256) {
    return _dailyLimitPerOwner[owner];
  }

  /// @notice Remaining wei the owner can spend via
  ///         `execTransactionWithSpendingAllowance` before the next 24h rollover.
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
    if (limitWei > 0) _dailyLimitsEnabled = true;
    emit DailySpendingLimitSet(owner, limitWei);
  }

  /// @notice Single-signer allowance path. Accepts ONE 65-byte ECDSA sig
  ///         that must `ecrecover` to `msg.sender` — who must be a current
  ///         owner with a non-zero `_dailyLimitPerOwner`. The recovered
  ///         signer's daily cap is charged by `value`; failed inner calls
  ///         do NOT burn the cap.
  /// @dev    Re-uses the same EIP-712 typehash as `execTransaction`. Bound
  ///         to the same `(to, value, data, gas, nonce = _txnNonce,
  ///         validUntil)` fields. Bumps `_txnNonce` once the signature
  ///         validates, so each signature is single-use — even when the
  ///         inner call fails.
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
    // Extended wallets bind `operation` into the EIP-712 typehash; the
    // allowance path uses the 7-field typehash with operation = 0.
    bytes32 txHash = generateHashOp(to, value, data, txnGas, currentNonce, validUntil, 0);
    address recovered = _recoverSigner(signatures, txHash);
    if (recovered != msg.sender || !isOwner(recovered)) revert AllowanceRequiresSingleSigner();
    // The hash is bound to `currentNonce`, so bumping the nonce consumes
    // the signature. Mirrors `_execTransaction`: the bump happens right
    // after signature validation, whether or not the inner call succeeds.
    _bumpNonce();
    uint256 cap = _dailyLimitPerOwner[recovered];
    if (cap == 0) revert AllowanceLimitNotSet(recovered);
    _rolloverIfNeeded(recovered);
    uint256 remaining = cap - _dailySpentByOwner[recovered];
    if (value > remaining) revert DailySpendingLimitExceeded(recovered, value, remaining);

    _preExecChecksGuard(to, value, data);

    success = _runLoggedCall(to, value, data, txnGas, currentNonce, validUntil);
    // Commit-on-success: failed inner calls don't burn the cap.
    if (success) _dailySpentByOwner[recovered] += value;
    _emitEndOfLifeIfNear();
  }

  /// @dev Shared tail for the timelock (`executeScheduled`) and allowance
  ///      paths: run the inner call via the base `_rawCall`, bubble a
  ///      payload-carrying revert, and emit the standard success / failure
  ///      events (+ the silent post-exec guard hook on success).
  function _runLoggedCall(
    address to,
    uint256 value,
    bytes memory data,
    uint256 txnGas,
    uint256 txnNonce,
    uint256 validUntil
  ) internal returns (bool success) {
    bytes memory returnData;
    (success, returnData) = _rawCall(txnGas, to, value, data);
    if (success) {
      emit TransactionExecuted(msg.sender, to, value, data, txnGas, txnNonce);
      _postExecChecks(to, value, data, txnGas, txnNonce, validUntil);
    } else if (returnData.length > 0) {
      _revertWith(returnData);
    } else {
      emit TxFailure(msg.sender, to, value, data, txnGas, txnNonce, returnData);
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

  /// @notice Returns enabled modules in registration order (most-recent first).
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
  ///         `prevModule` to be the immediate predecessor in the chain. To
  ///         remove the head, pass `prevModule = address(0)`.
  function disableModule(address prevModule, address module) public virtual onlyThis {
    if (module == address(0)) revert ModuleIsZeroAddress();
    if (!_isModule[module]) revert ModuleNotFound(module);
    if (_modulesHead == module) {
      // Strict head removal: only `prevModule == address(0)` is accepted.
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
  ///         are operational plugins); guard + allowlist still apply.
  /// @param operation 0 = CALL, 1 = DELEGATECALL. For DELEGATECALL, `to` MUST
  ///        equal `address(this)` so the module's code runs in the wallet's
  ///        storage context.
  /// @dev    Does NOT bump `_txnNonce` — pending owner-signed transactions
  ///         remain valid after a module action.
  function execTransactionFromModule(
    address to,
    uint256 value,
    bytes memory data,
    uint256 operation
  ) public payable virtual returns (bool success) {
    if (!_isModule[msg.sender]) revert NotAModule(msg.sender);
    if (operation > 1) revert InvalidModuleOperation(operation);

    // Modules bypass the timelock reverse-route but still answer to guard + allowlist.
    _preExecChecksGuard(to, value, data);

    uint256 gasBefore = gasleft();
    bytes memory returnData;
    if (operation == 0) {
      (success, returnData) = _rawCall(gasBefore, to, value, data);
    } else {
      // DELEGATECALL — `to` MUST be address(this); the module's code runs
      // in the wallet's storage context.
      if (to != address(this)) revert InvalidModuleOperation(1);
      (success, returnData) = _rawDelegateCall(gasBefore, msg.sender, data);
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
      _revertWith(returnData);
    }

    emit ModuleTransactionExecuted(msg.sender, to, value, data, operation, success);
  }

  // ---------------------------------------------------------------------------
  // v0.4.0 — _execTransaction orchestrator + per-feature pre/post hooks
  // ---------------------------------------------------------------------------

  /// @notice Orchestrator override: pre-checks → base path → post-check (silent).
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
    // `txnNonce + 1` because the base path already bumped `_txnNonce`.
    if (success) _postExecChecks(to, value, data, txnGas, txnNonce + 1, validUntil);
  }

  /// @dev Pre-execution checks: timelock reverse-route + guard + allowlist.
  ///      Each gate fails fast (no state change) so a violation is atomic
  ///      with the EVM-level revert.
  function _preExecChecks(address to, uint256 value, bytes memory data) internal virtual {
    _preExecChecksTimelock(to, value, data);
    _preExecChecksGuard(to, value, data);
  }

  /// @dev Timelock reverse-route. Sensitive calls must go through
  ///      `scheduleTransaction` instead. Bypassed by `executeScheduled`
  ///      and `execTransactionWithSpendingAllowance`, both of which handle
  ///      their own validation.
  function _preExecChecksTimelock(address to, uint256 value, bytes memory data) internal virtual {
    if (_timelockDelay > 0 && _isSensitive(to, _selectorOf(data), value)) {
      revert SensitiveCallRequiresDelay(to, _selectorOf(data), value);
    }
  }

  /// @dev Guard + built-in allowlist. Guard reverts are wrapped as
  ///      `GuardReverted(guard, reason)`.
  function _preExecChecksGuard(address to, uint256 value, bytes memory data) internal virtual {
    address guardContract = _guard;
    if (guardContract != address(0)) {
      try ITransactionGuard(guardContract).checkTransaction(to, value, data) {} catch (bytes memory reason) {
        revert GuardReverted(guardContract, reason);
      }
    }
    if (_allowedTargetsEnabled && !_allowedTargets[to]) revert TargetNotAllowed(to);
  }

  /// @dev Silent post-execution hook (failure logged, never reverts).
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
      bytes32 txHash = generateHashOp(to, value, data, txnGas, txnNoncePostBump, validUntil, 0);
      try ITransactionGuard(guardContract).checkAfterExecution(txHash, true) {} catch (bytes memory reason) {
        emit PostExecutionGuardFailed(guardContract, reason);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // v0.4.0 — per-inner-call gate for multiRequest / multiRequestStrict
  // ---------------------------------------------------------------------------

  /// @notice Runs the pre-exec gates (timelock reverse-route, guard,
  ///         allowlist) before every inner call of the base `multiRequest` /
  ///         `multiRequestStrict` loops. The base calls this hook per item,
  ///         so the batch loops themselves live only in `MyMultiSig.sol`.
  function _beforeInnerCall(address to, uint256 value, bytes memory data) internal virtual override {
    _preExecChecks(to, value, data);
  }

  // ---------------------------------------------------------------------------
  // v0.4.0 — informational bitmask and helpers
  // ---------------------------------------------------------------------------

  /// @notice Bitmask of which advanced features are currently active
  ///         (informational):
  ///           0x01 — Timelock delay > 0
  ///           0x02 — Guard is set
  ///           0x04 — Allowlist enabled
  ///           0x08 — A daily allowance cap is set for some owner
  ///           0x10 — At least one module is enabled
  function advancedFeaturesEnabled() public view virtual returns (uint8 mask) {
    if (_timelockDelay > 0) mask |= 0x01;
    if (_guard != address(0)) mask |= 0x02;
    if (_allowedTargetsEnabled) mask |= 0x04;
    if (_dailyLimitsEnabled) mask |= 0x08;
    if (_modulesHead != address(0)) mask |= 0x10;
  }

  // ---------------------------------------------------------------------------
  // Internal helpers (Feature 1 / 3 / 4)
  // ---------------------------------------------------------------------------

    /// @dev First 4 bytes of `data`, or `bytes4(0)` for short calldata (which
  ///      can't match any sensitive selector anyway).
  function _selectorOf(bytes memory data) internal pure returns (bytes4) {
    if (data.length < 4) return bytes4(0);
    return bytes4(data);
  }

  /// @dev True iff `(to, selector, value)` matches the sensitive predicate:
  ///      either the wallet itself at a registered sensitive selector, or
  ///      the value meets the configured wei threshold.
  function _isSensitive(address to, bytes4 sel, uint256 value) internal view returns (bool) {
    if (to == address(this) && isSensitiveSelector(sel)) return true;
    if (_sensitiveValueThreshold > 0 && value >= _sensitiveValueThreshold) return true;
    return false;
  }

  /// @dev ECDSA recovery for the allowance path. Mirrors the ECDSA branch
  ///      of `_validateVote`. Returns `address(0)` on malformed input; the
  ///      caller verifies against `msg.sender` and owners.
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

  /// @dev Day rollover: if no reset yet, or last reset is older than 24h,
  ///      zero the spend and record a fresh anchor.
  function _rolloverIfNeeded(address owner) internal {
    uint256 lastReset = _lastPeriodResetByOwner[owner];
    if (lastReset == 0 || block.timestamp >= lastReset + 1 days) {
      _dailySpentByOwner[owner] = 0;
      _lastPeriodResetByOwner[owner] = block.timestamp;
    }
  }

  // ---------------------------------------------------------------------------
  // v0.5.0 — `operation` byte on execTransaction + ERC-4337 v0.7
  // ---------------------------------------------------------------------------

  /// @notice EIP-712 typehash for the 7-field payload (binds `operation`).
  bytes32 private constant _TRANSACTION_TYPEHASH_OP =
    keccak256(
      'Transaction(address to,uint256 value,bytes data,uint256 gas,uint96 nonce,uint256 validUntil,uint8 operation)'
    );

  /// @notice ERC-4337 v0.7 `validationData` magic values.
  uint256 private constant _SIG_VALIDATION_SUCCESS = 0;
  uint256 private constant _SIG_VALIDATION_FAILED = 1;

  /// @notice Operation-carrying twins of the base `TransactionExecuted` /
  ///         `TxFailure` events. The base events fire alongside these so
  ///         indexers that only know the base surface keep working; the
  ///         `operation` field lets off-chain consumers distinguish CALL
  ///         from DELEGATECALL.
  event TransactionExecutedOp(
    address indexed sender,
    address indexed to,
    uint256 indexed value,
    bytes data,
    uint256 txnGas,
    uint256 txnNonce,
    uint8 operation
  );
  event TxFailureOp(
    address indexed sender,
    address indexed to,
    uint256 indexed value,
    bytes data,
    uint256 txnGas,
    uint256 txnNonce,
    uint8 operation,
    bytes reason
  );

  // --------- execTransaction overloads with operation byte ---------

  function execTransaction(
    address to,
    uint256 value,
    bytes memory data,
    uint256 txnGas,
    uint8 operation,
    bytes memory signatures
  ) public payable virtual nonReentrant returns (bool success) {
    success = _execExtended(to, value, data, txnGas, nonce(), 0, operation, signatures);
    _emitEndOfLifeIfNear();
  }

  function execTransaction(
    address to,
    uint256 value,
    bytes memory data,
    uint256 txnGas,
    uint256 validUntil,
    uint8 operation,
    bytes memory signatures
  ) public payable virtual nonReentrant returns (bool success) {
    success = _execExtended(to, value, data, txnGas, nonce(), validUntil, operation, signatures);
    _emitEndOfLifeIfNear();
  }

  function execTransaction(
    address to,
    uint256 value,
    bytes memory data,
    uint256 txnGas,
    uint256 txnNonce,
    uint256 validUntil,
    uint8 operation,
    bytes memory signatures
  ) public payable virtual nonReentrant returns (bool success) {
    success = _execExtended(to, value, data, txnGas, txnNonce, validUntil, operation, signatures);
    _emitEndOfLifeIfNear();
  }

  // Disabled overrides — the base wallet's overloads without an
  // `operation` byte always revert on this wallet; callers must use the
  // `operation`-carrying overloads above.

  function execTransaction(
    address /* to */,
    uint256 /* value */,
    bytes memory /* data */,
    uint256 /* txnGas */,
    bytes memory /* signatures */
  ) public payable virtual override returns (bool /* success */) {
    revert RequiresOperationByte();
  }

  function execTransaction(
    address /* to */,
    uint256 /* value */,
    bytes memory /* data */,
    uint256 /* txnGas */,
    uint256 /* validUntil */,
    bytes memory /* signatures */
  ) public payable virtual override returns (bool /* success */) {
    revert RequiresOperationByte();
  }

  // --------- EIP-712 hash + signature helpers ---------

  /// @notice EIP-712 typed-data hash. 7-field, binds `operation`.
  function generateHashOp(
    address to,
    uint256 value,
    bytes memory data,
    uint256 txnGas,
    uint256 txnNonce,
    uint256 validUntil,
    uint8 operation
  ) public view returns (bytes32) {
    return
      _hashTypedDataV4(
        keccak256(
          abi.encode(
            _TRANSACTION_TYPEHASH_OP,
            to,
            value,
            keccak256(data),
            txnGas,
            txnNonce,
            validUntil,
            operation
          )
        )
      );
  }

  /// @notice 7-arg view `isValidSignature` overload.
  function isValidSignature(
    address to,
    uint256 value,
    bytes memory data,
    uint256 txnGas,
    uint256 txnNonce,
    uint256 validUntil,
    uint8 operation,
    bytes memory signatures
  ) public view returns (bool valid) {
    bytes32 txHash = generateHashOp(to, value, data, txnGas, txnNonce, validUntil, operation);
    return _checkSignaturesOp(txHash, txnNonce, validUntil, signatures);
  }

  /// @dev View-side validator for the 7-field (`operation`-bound) hash:
  ///      rejects used nonces and expired deadlines, then defers to the
  ///      base `_checkSignatures` vote-counting core (the hash already
  ///      binds `operation`, so the counting logic is identical).
  function _checkSignaturesOp(
    bytes32 txHash,
    uint256 txnNonce,
    uint256 validUntil,
    bytes memory signatures
  ) internal view returns (bool valid) {
    if (_noncesUsed[txnNonce]) return false;
    if (validUntil != 0 && block.timestamp > validUntil) return false;
    return _checkSignatures(txHash, txnNonce, signatures);
  }

  /// @dev Mutating-side validator that records each vote's
  ///      `(nonce, owner)` slot via `_recordVote`. Defers to the base
  ///      `_validateSignatureForHash` core after the nonce / expiry gates.
  function _validateSignatureOp(
    bytes32 txHash,
    uint256 txnNonce,
    uint256 validUntil,
    bytes memory signatures
  ) internal returns (bool valid) {
    if (_noncesUsed[txnNonce]) return false;
    if (validUntil != 0 && block.timestamp > validUntil) revert SignatureExpired();
    return _validateSignatureForHash(txHash, txnNonce, signatures);
  }

  // --------- Internal exec orchestrator ---------

  function _execExtended(
    address to,
    uint256 value,
    bytes memory data,
    uint256 txnGas,
    uint256 txnNonce,
    uint256 validUntil,
    uint8 operation,
    bytes memory signatures
  ) internal virtual returns (bool success) {
    if (validUntil != 0 && block.timestamp > validUntil) revert SignatureExpired();
    if (operation > 1) revert InvalidOperation(operation);
    if (operation == 1 && to != address(this)) revert InvalidOperation(operation);

    // Run the same pre-exec gates (timelock reverse-route, guard,
    // allowlist) as the `_execTransaction` override, so every exec entry
    // point hits them.
    _preExecChecks(to, value, data);

    bytes32 txHash = generateHashOp(to, value, data, txnGas, txnNonce, validUntil, operation);
    if (!_validateSignatureOp(txHash, txnNonce, validUntil, signatures)) revert InvalidSignatures();

    _bumpNonce();

    uint256 gasBefore = gasleft();
    bytes memory returnData;
    if (operation == 0) {
      (success, returnData) = _rawCall(txnGas, to, value, data);
    } else {
      (success, returnData) = _rawDelegateCall(txnGas, to, data);
    }
    if (gasBefore - gasleft() >= txnGas) revert NotEnoughGas();
    if (success) {
      emit TransactionExecuted(msg.sender, to, value, data, txnGas, txnNonce);
      emit TransactionExecutedOp(msg.sender, to, value, data, txnGas, txnNonce, operation);
    } else if (returnData.length > 0) {
      _revertWith(returnData);
    } else {
      emit TxFailure(msg.sender, to, value, data, txnGas, txnNonce, returnData);
      emit TxFailureOp(msg.sender, to, value, data, txnGas, txnNonce, operation, returnData);
    }
  }

  /// @dev Shared DELEGATECALL wrapper (the CALL twin, `_rawCall`, lives in
  ///      the base wallet). `_execExtended` targets `address(this)`; the
  ///      module path targets the calling module — both run the target's
  ///      code in this wallet's storage context.
  function _rawDelegateCall(
    uint256 gasBudget,
    address target,
    bytes memory data
  ) internal virtual returns (bool success, bytes memory returnData) {
    assembly {
      success := delegatecall(gasBudget, target, add(data, 0x20), mload(data), 0, 0)
      let size := returndatasize()
      returnData := mload(0x40)
      mstore(returnData, size)
      returndatacopy(add(returnData, 0x20), 0, size)
      mstore(0x40, add(add(returnData, 0x20), and(add(size, 0x1f), not(0x1f))))
    }
  }

  // --------- ERC-4337 v0.7 ---------

  /// @dev Gate shared by the ERC-4337 entry points: only the pinned
  ///      EntryPoint may call them.
  function _requireFromEntryPoint() internal view {
    if (msg.sender != address(ENTRY_POINT)) revert NotEntryPoint();
  }

  /// @notice The 32-byte digest the wallet's owners vote on for a UserOp:
  ///         the EIP-191 (`personal_sign`) wrap of the EntryPoint's
  ///         `userOpHash`. The `userOpHash` already binds the full op
  ///         (sender, EntryPoint nonce, callData, gas fields), the
  ///         EntryPoint address, and the chain id, so a threshold of
  ///         votes on this digest authorizes exactly one op on one chain.
  ///         Owners can vote off-chain (ECDSA / EIP-1271 blobs in
  ///         `userOp.signature`, same `(owner, sig)[]` encoding as
  ///         `execTransaction`) or on-chain via `approveHash(digest)`.
  function userOpSigningHash(bytes32 userOpHash) public pure virtual returns (bytes32) {
    return ECDSA.toEthSignedMessageHash(userOpHash);
  }

  /// @notice IAccount.validateUserOp (v0.7). Caller must be `ENTRY_POINT`.
  ///         Checks a threshold of owner votes over
  ///         `userOpSigningHash(userOpHash)` and returns 0 on success or 1
  ///         (`SIG_VALIDATION_FAILED`) on a failed signature check, then
  ///         transfers `missingAccountFunds` to the EntryPoint so the op's
  ///         gas is prefunded. Replay protection lives in the EntryPoint's
  ///         2D nonce scheme (`userOp.nonce` is validated and consumed
  ///         there and is part of `userOpHash`); the wallet's own
  ///         `_txnNonce` is neither read nor bumped on this path.
  function validateUserOp(
    PackedUserOperation calldata userOp,
    bytes32 userOpHash,
    uint256 missingAccountFunds
  ) external override returns (uint256 validationData) {
    _requireFromEntryPoint();
    validationData = _checkSignatures(userOpSigningHash(userOpHash), 0, userOp.signature)
      ? _SIG_VALIDATION_SUCCESS
      : _SIG_VALIDATION_FAILED;
    _payPrefund(missingAccountFunds);
  }

  /// @notice ERC-4337 execution entry point. `userOp.callData` must encode
  ///         a call to this function (`abi.encodeCall(this.execute, (to,
  ///         value, data))`) — the EntryPoint relays it to the account
  ///         verbatim after a successful `validateUserOp`. Runs the same
  ///         pre-exec gates as every other exec path (timelock
  ///         reverse-route, guard, allowlist) and bubbles the inner revert
  ///         on failure so the EntryPoint records the op as reverted.
  /// @param to The address the wallet calls.
  /// @param value The wei forwarded with the call.
  /// @param data The calldata forwarded with the call.
  function execute(address to, uint256 value, bytes calldata data) external virtual {
    _requireFromEntryPoint();
    _preExecChecks(to, value, data);
    (bool success, bytes memory returnData) = _rawCall(gasleft(), to, value, data);
    if (!success) _revertWith(returnData);
    address guardContract = _guard;
    if (guardContract != address(0)) {
      bytes32 txHash = keccak256(abi.encode(msg.sender, to, value, data, uint256(0), block.number));
      try ITransactionGuard(guardContract).checkAfterExecution(txHash, true) {} catch (bytes memory reason) {
        emit PostExecutionGuardFailed(guardContract, reason);
      }
    }
  }

  /// @dev Sends the EntryPoint the deposit it is missing to prefund the
  ///      current op. A failed transfer is deliberately not reverted on:
  ///      the EntryPoint re-checks the account's deposit right after and
  ///      fails the op with its own, more descriptive error.
  function _payPrefund(uint256 missingAccountFunds) internal virtual {
    if (missingAccountFunds != 0) {
      (bool success, ) = payable(msg.sender).call{ value: missingAccountFunds }('');
      (success);
    }
  }
}
