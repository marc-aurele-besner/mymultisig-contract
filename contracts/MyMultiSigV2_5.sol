// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import '@openzeppelin/contracts/security/ReentrancyGuard.sol';

import './MyMultiSig.sol';
import './interfaces/IAccount.sol';
import './interfaces/IEntryPoint.sol';
import './interfaces/PackedUserOperation.sol';

/// @title MyMultiSigV2_5 (v0.5.0)
/// @notice Adds three forward-looking features on top of the v0.4.0 base
///         wallet without changing the v0.4.0 EIP-712 domain:
///         1. An `operation` byte on the owner-signed `execTransaction`
///            (0 = CALL, 1 = DELEGATECALL gated to `to == address(this)`).
///         2. ERC-4337 v0.7 account abstraction (`IAccount.validateUserOp`
///            and an `executeUserOp` that only the pinned EntryPoint can
///            invoke).
///         3. A CREATE2-stable `version()` value (`'0.5.0'`) so callers can
///            tell at a glance whether a given wallet supports these paths.
/// @dev    V2_5 wallets only inherit `MyMultiSig` (the v0.4.0 base); they
///         do NOT inherit `MyMultiSigExtended` so the bytecode stays
///         minimal. The new EIP-712 typehash binds `uint8 operation` to
///         every signature, so old v0.4.0 signatures cannot validate here
///         (different `_domainSeparatorV4()` already handles that on top
///         of the differing typehash). `MultiRequest` and
///         `multiRequestStrict` remain CALL-only — the inner calls go via
///         `onlyThis`, so the wallet still gates them properly.
contract MyMultiSigV2_5 is MyMultiSig, IAccount {
  /// @notice EIP-712 typehash for the v0.5.0 owner-signed payload. Includes
  ///         `operation` so that `DELEGATECALL` is bound into the signature;
  ///         the same `(to, value, data, gas, nonce, validUntil)` payload
  ///         with a different `operation` produces a different hash and
  ///         will not validate.
  bytes32 private constant _TRANSACTION_TYPEHASH_V2_5 =
    keccak256(
      'Transaction(address to,uint256 value,bytes data,uint256 gas,uint96 nonce,uint256 validUntil,uint8 operation)'
    );

  /// @notice ERC-4337 v0.7 `validationData` magic value for "always valid".
  uint256 private constant _SIG_VALIDATION_SUCCESS = 0;

  /// @notice ERC-4337 v0.7 `validationData` magic value for failure.
  uint256 private constant _SIG_VALIDATION_FAILED = 1;

  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  IEntryPoint public immutable ENTRY_POINT;

  // ---------- v0.5.0 custom errors ----------

  /// @notice Thrown when `operation` is something other than 0 or 1, or
  ///         when `operation == 1` and `to != address(this)`.
  error InvalidOperation(uint8 operation);

  /// @notice Thrown when a function reserved for the pinned EntryPoint is
  ///         called by anyone else.
  error NotEntryPoint();

  /// @notice Thrown when the user operation's nonce does not match the
  ///         wallet's `_txnNonce`. Avoids replays via stale bundler state.
  error InvalidNonce(uint256 expected, uint256 got);

  /// @notice Thrown when callers hit one of the v0.4.0-inherited
  ///         `execTransaction` overloads. V2_5 uses the new
  ///         `operation`-byte overloads exclusively.
  error V2_5RequiresOperationByte();

  // ---------- v0.5.0 events ----------

  event TransactionExecutedV2_5(
    address indexed sender,
    address indexed to,
    uint256 indexed value,
    bytes data,
    uint256 txnGas,
    uint256 txnNonce,
    uint8 operation
  );
  event TxFailureV2_5(
    address indexed sender,
    address indexed to,
    uint256 indexed value,
    bytes data,
    uint256 txnGas,
    uint256 txnNonce,
    uint8 operation,
    bytes reason
  );
  event UserOpExecuted(bytes32 indexed userOpHash, uint256 indexed nonce);

  // ---------- constructor ----------

  /// @custom:oz-upgrades-unsafe-allow constructor
  /// @dev    Calls only `MyMultiSig(...)` as the base; the base in turn
  ///         calls `EIP712(name_, version())` itself. We DON'T list
  ///         `EIP712(...)` here because that would be a duplicate base
  ///         initializer (the base already forwards to EIP712).
  ///         The EIP-712 name string resolves through `name()` which the
  ///         base exposes. The string `'0.5.0'` from `version()` is read
  ///         inside MyMultiSig's constructor initializer list.
  constructor(
    string memory name_,
    address[] memory owners_,
    uint16 threshold_,
    address entryPoint_
  ) MyMultiSig(name_, owners_, threshold_) {
    if (entryPoint_ == address(0)) revert InvalidOperation(0);
    ENTRY_POINT = IEntryPoint(entryPoint_);
  }

  // ---------- view override ----------

  /// @notice Wallet version. `'0.5.0'` for v0.5.0 features and is part of
  ///         the EIP-712 domain separator — old v0.4.0 signatures are
  ///         therefore invalid here even if payload fields match.
  function version() public pure virtual override returns (string memory) {
    return '0.5.0';
  }

  // ---------- execTransaction with operation byte ----------

  /// @notice Executes a CALL or DELEGATECALL (`operation == 1`) transaction
  ///         with `validUntil = 0`. Pin the nonce to the wallet's current
  ///         nonce. Mirrors the base's 5-arg overload (`MyMultiSig.sol:282-291`)
  ///         but the new payload includes `operation`.
  /// @param operation 0 = CALL, 1 = DELEGATECALL gated to `to == address(this)`.
  function execTransaction(
    address to,
    uint256 value,
    bytes memory data,
    uint256 txnGas,
    uint8 operation,
    bytes memory signatures
  ) public payable virtual nonReentrant returns (bool success) {
    success = _execV2_5(to, value, data, txnGas, nonce(), 0, operation, signatures);
    if (nonce() > uint96(2 ** 96 - 1000)) emit ContractEndOfLife(2 ** 96 - nonce() - 1);
  }

  /// @notice Same as above with an explicit `validUntil` deadline.
  function execTransaction(
    address to,
    uint256 value,
    bytes memory data,
    uint256 txnGas,
    uint256 validUntil,
    uint8 operation,
    bytes memory signatures
  ) public payable virtual nonReentrant returns (bool success) {
    success = _execV2_5(to, value, data, txnGas, nonce(), validUntil, operation, signatures);
    if (nonce() > uint96(2 ** 96 - 1000)) emit ContractEndOfLife(2 ** 96 - nonce() - 1);
  }

  // ---------- back-compat scaffolds (must NOT be used on V2_5) ----------

  /// @notice Disabled overload — V2_5 requires the `operation` byte.
  /// @dev Reverts with `V2_5RequiresOperationByte()` so back-end tooling
  ///      that still calls the 5-arg signature gets a clear signal to
  ///      migrate. Override satisfies the same shape as the base's
  ///      `payable` virtual execTransaction.
  function execTransaction(
    address /* to */,
    uint256 /* value */,
    bytes memory /* data */,
    uint256 /* txnGas */,
    bytes memory /* signatures */
  ) public payable virtual override returns (bool /* success */) {
    revert V2_5RequiresOperationByte();
  }

  /// @notice Disabled overload — V2_5 requires the `operation` byte.
  function execTransaction(
    address /* to */,
    uint256 /* value */,
    bytes memory /* data */,
    uint256 /* txnGas */,
    uint256 /* validUntil */,
    bytes memory /* signatures */
  ) public payable virtual override returns (bool /* success */) {
    revert V2_5RequiresOperationByte();
  }

  // ---------- internal exec orchestrator ----------

  /// @notice Internal V2_5 exec path. Mirrors `MyMultiSig._execTransaction`
  ///         (lines 326-361) but:
  ///         - rejects `operation` outside `0..1`,
  ///         - rejects DELEGATECALL unless `to == address(this)`,
  ///         - dispatches via assembly `call` or `delegatecall`,
  ///         - emits the V2_5-specific events with `operation` indexed.
  /// @dev    The assembly blocks are split into per-operation helpers
  ///         (`_lowLevelCallV2_5` / `_lowLevelDelegateCallV2_5`) to keep
  ///         the orchestrator's local-variable count below the EVM stack
  ///         limit (Solidity >= 0.8 makes "stack too deep" a hard error
  ///         unless `viaIR` is on). Same trade-off used by
  ///         `MyMultiSigExtended._doLowLevelCall` at lines 553-571.
  function _execV2_5(
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

    bytes32 txHash = generateHashV2_5(to, value, data, txnGas, txnNonce, validUntil, operation);
    if (!_validateSignatureV2_5(txHash, txnNonce, validUntil, signatures)) revert InvalidSignatures();

    // Bump the base's `_txnNonce` via the public virtual `incrementNonce`.
    // The inner call is from `this` so `onlyThis` is satisfied.
    incrementNonce();

    uint256 gasBefore = gasleft();
    bytes memory returnData;
    if (operation == 0) {
      (success, returnData) = _lowLevelCallV2_5(txnGas, to, value, data);
    } else {
      // operation == 1 — DELEGATECALL. `to` MUST equal address(this) by the
      // gate above; the assembly runs the code at `to` in this wallet's
      // storage context.
      (success, returnData) = _lowLevelDelegateCallV2_5(gasBefore, to, data);
    }
    if (gasBefore - gasleft() >= txnGas) revert NotEnoughGas();
    if (success) {
      emit TransactionExecuted(msg.sender, to, value, data, txnGas, txnNonce);
      emit TransactionExecutedV2_5(msg.sender, to, value, data, txnGas, txnNonce, operation);
    } else if (returnData.length > 0) {
      assembly {
        revert(add(returnData, 0x20), mload(returnData))
      }
    } else {
      emit TxFailure(msg.sender, to, value, data, txnGas, txnNonce, returnData);
      emit TxFailureV2_5(msg.sender, to, value, data, txnGas, txnNonce, operation, returnData);
    }
  }

  /// @notice Thin assembly `call` wrapper. Mirrors the inline assembly
  ///         block at `MyMultiSig.sol:340` for parity.
  function _lowLevelCallV2_5(
    uint256 gasBudget,
    address to,
    uint256 value,
    bytes memory data
  ) internal virtual returns (bool success, bytes memory returnData) {
    assembly {
      success := call(gasBudget, to, value, add(data, 0x20), mload(data), 0, 0)
      let size := returndatasize()
      returnData := mload(0x40)
      mstore(returnData, size)
      returndatacopy(add(returnData, 0x20), 0, size)
      mstore(0x40, add(add(returnData, 0x20), and(add(size, 0x1f), not(0x1f))))
    }
  }

  /// @notice Thin assembly `delegatecall` wrapper. Mirrors
  ///         `MyMultiSigExtended.sol:682` (`execTransactionFromModule`)
  ///         but invoked from the owner-signed path. The `to` argument
  ///         is verified to equal `address(this)` by the calling
  ///         `_execV2_5` so the code at `to` runs in the wallet's
  ///         storage context — i.e. this is the wallet DELEGATECALL'ing
  ///         into itself with caller-supplied calldata.
  function _lowLevelDelegateCallV2_5(
    uint256 gasBudget,
    address to,
    bytes memory data
  ) internal virtual returns (bool success, bytes memory returnData) {
    assembly {
      success := delegatecall(gasBudget, to, add(data, 0x20), mload(data), 0, 0)
      let size := returndatasize()
      returnData := mload(0x40)
      mstore(returnData, size)
      returndatacopy(add(returnData, 0x20), 0, size)
      mstore(0x40, add(add(returnData, 0x20), and(add(size, 0x1f), not(0x1f))))
    }
  }

  // ---------- EIP-712 hash and view-side signature helpers ----------

  /// @notice EIP-712 typed-data hash for V2_5 wallets. The 7-field hash
  ///         binds `operation` so signatures against the v0.4.0 6-field
  ///         hash do NOT validate here.
  function generateHashV2_5(
    address to,
    uint256 value,
    bytes memory data,
    uint256 txnGas,
    uint256 txnNonce,
    uint256 validUntil,
    uint8 operation
  ) public view virtual returns (bytes32) {
    return
      _hashTypedDataV4(
        keccak256(
          abi.encode(
            _TRANSACTION_TYPEHASH_V2_5,
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

  /// @notice 7-arg view `isValidSignature` overload that includes
  ///         `operation` in the bound hash. Mirrors `MyMultiSig.sol:525-536`.
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
    bytes32 txHash = generateHashV2_5(to, value, data, txnGas, txnNonce, validUntil, operation);
    return _checkSignaturesV2_5(txHash, txnNonce, signatures);
  }

  /// @notice View-side signature check. Same semantics as the base's
  ///         `_checkSignatures` (`MyMultiSig.sol:546-571`) but reads state
  ///         through public accessors because the base's storage vars
  ///         (`_threshold`, `_owners`, `_approvedOwners`) are `private`.
  function _checkSignaturesV2_5(
    bytes32 txHash,
    uint256 /* txnNonce */,
    bytes memory signatures
  ) internal view returns (bool valid) {
    uint16 threshold_ = threshold();
    address[] memory approved = getApprovedOwners(txHash);
    uint256 counted;
    for (uint256 i; i < approved.length; ) {
      unchecked {
        if (!isOwner(approved[i])) return false;
        ++counted;
        ++i;
      }
    }
    if (counted >= threshold_) return true;
    (address[] memory owners, bytes[] memory sigs) = _decodeVotes(signatures);
    for (uint256 i = 0; i < owners.length; ) {
      unchecked {
        if (counted >= threshold_) break;
        if (_validateVote(txHash, owners[i], sigs[i])) ++counted;
        ++i;
      }
    }
    return counted >= threshold_;
  }

  /// @notice Mutating-side validator that records the per-`(nonce, owner)`
  ///         slot consumed (mirrors `_validateSignature` at
  ///         `MyMultiSig.sol:656-692`). Used by `_execV2_5`. Reuses the
  ///         base's `_recordVote` and `_validateVote` accessors; both are
  ///         `internal virtual`.
  function _validateSignatureV2_5(
    bytes32 txHash,
    uint256 txnNonce,
    uint256 validUntil,
    bytes memory signatures
  ) internal returns (bool valid) {
    if (validUntil != 0 && block.timestamp > validUntil) revert SignatureExpired();
    uint16 threshold_ = threshold();
    uint256 counted;
    address[] memory approved = getApprovedOwners(txHash);
    for (uint256 i; i < approved.length; ) {
      unchecked {
        address approvedOwner = approved[i];
        if (!isOwner(approvedOwner)) return false;
        if (!_recordVote(txHash, txnNonce, approvedOwner)) return false;
        ++counted;
        ++i;
      }
    }
    if (counted >= threshold_) return true;
    (address[] memory owners, bytes[] memory sigs) = _decodeVotes(signatures);
    for (uint256 i = 0; i < owners.length; ) {
      unchecked {
        if (counted >= threshold_) break;
        if (_validateVote(txHash, owners[i], sigs[i]) && _recordVote(txHash, txnNonce, owners[i])) ++counted;
        ++i;
      }
    }
    return counted >= threshold_;
  }

  // ---------- ERC-4337 v0.7 ----------

  /// @notice IAccount.validateUserOp (v0.7). Called by the EntryPoint (via
  ///         a bundler) BEFORE the operation is added to a batch. Pure
  ///         validation only — does NOT execute or advance `_txnNonce`.
  /// @dev    Bundler call flow: EntryPoint.handleOps → wallet.validateUserOp
  ///         (validation). We require:
  ///         - msg.sender == ENTRY_POINT,
  ///         - userOp.sender == address(this),
  ///         - userOp.callData decodes to (to, value, data, gas, validUntil, operation),
  ///         - operation == 0 (DELEGATECALL from a 4337 flow would touch wallet
  ///           storage in ways the bundler cannot anticipate; gate behind CALL).
  ///         - userOp.nonce == current `_txnNonce`,
  ///         - threshold reached via `_checkSignaturesV2_5`.
  function validateUserOp(
    PackedUserOperation calldata userOp,
    bytes32 /* userOpHash */,
    uint256 /* missingAccountFunds */
  ) external view override returns (uint256 validationData) {
    if (msg.sender != address(ENTRY_POINT)) revert NotEntryPoint();
    if (userOp.sender != address(this)) revert InvalidNonce(uint256(uint160(address(this))), uint256(uint160(userOp.sender)));

    (address to, uint256 value, bytes memory data, uint256 txnGas, uint256 validUntil, uint8 operation) =
      _decodeUserOpCallData(userOp.callData);

    if (operation != 0) revert InvalidOperation(operation);
    uint256 expectedNonce = nonce();
    if (userOp.nonce != expectedNonce) revert InvalidNonce(expectedNonce, userOp.nonce);
    bytes32 txHash = generateHashV2_5(to, value, data, txnGas, expectedNonce, validUntil, operation);
    if (!_checkSignaturesV2_5(txHash, expectedNonce, userOp.signature)) {
      return _SIG_VALIDATION_FAILED;
    }
    return _SIG_VALIDATION_SUCCESS;
  }

  /// @notice EntryPoint-only execution path for `UserOp`s. Reconstructs the
  ///         same payload, calls `_execV2_5`, and bumps `_txnNonce` like the
  ///         owner-signed flow.
  /// @dev    On inner-call failure with no return data, reverts with
  ///         `TxFailureV2_5` semantics (the `_execV2_5` path already
  ///         bubbles the inner revert when return data is non-empty, so
  ///         this function only really fires for the zero-return-data
  ///         silent-revert path — which is unusual for a real user op).
  function executeUserOp(PackedUserOperation calldata userOp) external payable {
    if (msg.sender != address(ENTRY_POINT)) revert NotEntryPoint();

    bytes32 userOpHash = keccak256(userOp.callData);
    (address to, uint256 value, bytes memory data, uint256 txnGas, uint256 validUntil, uint8 operation) =
      _decodeUserOpCallData(userOp.callData);

    _execV2_5(to, value, data, txnGas, nonce(), validUntil, operation, userOp.signature);
    // If _execV2_5 returned without reverting, the operation succeeded.
    // The nonReentrant lock on execTransaction is preserved by the
    // inherited `nonReentrant` modifier on the wrapper; for `executeUserOp`
    // we still hold the same lock because we're inside the wallet.
    emit UserOpExecuted(userOpHash, nonce());
  }

  // ---------- ERC-4337 helpers ----------

  /// @notice Canonical encoding for the inner call of a user operation. The
  ///         bundler MUST ABI-encode this tuple into `userOp.callData`:
  ///         `abi.encode(address to, uint256 value, bytes data, uint256 txnGas,
  ///         uint256 validUntil, uint8 operation)`.
  function _decodeUserOpCallData(
    bytes calldata callData
  ) internal pure virtual returns (address to, uint256 value, bytes memory data, uint256 gas, uint256 validUntil, uint8 operation) {
    return abi.decode(callData, (address, uint256, bytes, uint256, uint256, uint8));
  }
}
