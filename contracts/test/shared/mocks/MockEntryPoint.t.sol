// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IEntryPoint } from '../../../interfaces/IEntryPoint.sol';
import { IAccount } from '../../../interfaces/IAccount.sol';
import { PackedUserOperation } from '../../../interfaces/PackedUserOperation.sol';

/// @title MockEntryPoint
/// @notice Minimal EntryPoint v0.7 stub for Foundry tests of
///         `MyMultiSigExtended`'s ERC-4337 surface. Mirrors the canonical
///         EntryPoint semantics the wallet relies on:
///         - `getUserOpHash` binds the op's fields, this EntryPoint's
///           address, and the chain id (same encoding as the reference
///           `UserOperationLib`).
///         - 2D nonces: `userOp.nonce` is `key (192 bits) | seq (64 bits)`;
///           the sequence is validated and consumed per `(sender, key)`.
///         - Validation phase: calls `validateUserOp` with the deposit the
///           account is missing, credits ETH the account sends back, and
///           rejects the op unless the prefund is covered and
///           `validationData == 0`.
///         - Execution phase: relays `userOp.callData` to the account
///           verbatim via `sender.call(callData)`. Unlike the real
///           EntryPoint (which logs a failed op and moves on), an inner
///           revert is bubbled so tests can assert on the wallet's errors.
contract MockEntryPoint is IEntryPoint {
  mapping(address => uint256) private _deposits;
  mapping(address => mapping(uint192 => uint64)) private _nonceSequence;

  /// @notice Prefund (in wei) each op must have on deposit before
  ///         execution. Tests set this to exercise the account's
  ///         `missingAccountFunds` payment path; the default of 0 mirrors
  ///         a fully-sponsored op.
  uint256 public requiredPrefund;

  // Echoes the last user-op callData relayed to an account, so Foundry
  // assertions can reach into it without decoding.
  bytes public lastCallData;

  event UserOpHandled(address indexed sender, bytes32 indexed userOpHash, bytes callData);

  error InvalidAccountNonce(address sender, uint256 nonce);
  error PrefundNotPaid(address sender, uint256 deposit, uint256 required);
  error SignatureValidationFailed(address sender, uint256 validationData);

  function setRequiredPrefund(uint256 requiredPrefund_) external {
    requiredPrefund = requiredPrefund_;
  }

  /// @notice Same hash the canonical v0.7 EntryPoint computes: the packed
  ///         op fields, wrapped with this EntryPoint's address and chain id.
  function getUserOpHash(PackedUserOperation calldata userOp) public view returns (bytes32) {
    bytes32 packed = keccak256(
      abi.encode(
        userOp.sender,
        userOp.nonce,
        keccak256(userOp.initCode),
        keccak256(userOp.callData),
        userOp.accountGasLimits,
        userOp.preVerificationGas,
        userOp.gasFees,
        keccak256(userOp.paymasterAndData)
      )
    );
    return keccak256(abi.encode(packed, address(this), block.chainid));
  }

  /// @notice Next valid `userOp.nonce` for `(sender, key)` — `key` in the
  ///         high 192 bits, the per-key sequence in the low 64 bits.
  function getNonce(address sender, uint192 key) public view returns (uint256) {
    return (uint256(key) << 64) | _nonceSequence[sender][key];
  }

  function handleOps(PackedUserOperation[] calldata ops, address payable /* beneficiary */) external override {
    for (uint256 i = 0; i < ops.length; ++i) {
      _handleOp(ops[i]);
    }
  }

  function _handleOp(PackedUserOperation calldata op) internal {
    // 2D nonce: validate and consume the sequence for the op's key.
    uint192 key = uint192(op.nonce >> 64);
    uint64 seq = uint64(op.nonce);
    if (_nonceSequence[op.sender][key] != seq) revert InvalidAccountNonce(op.sender, op.nonce);
    _nonceSequence[op.sender][key] = seq + 1;

    // Validation phase: ask the account to validate and top up its deposit.
    bytes32 userOpHash = getUserOpHash(op);
    uint256 deposit = _deposits[op.sender];
    uint256 missing = deposit >= requiredPrefund ? 0 : requiredPrefund - deposit;
    uint256 validationData = IAccount(op.sender).validateUserOp(op, userOpHash, missing);
    if (_deposits[op.sender] < requiredPrefund)
      revert PrefundNotPaid(op.sender, _deposits[op.sender], requiredPrefund);
    if (validationData != 0) revert SignatureValidationFailed(op.sender, validationData);

    // Execution phase: relay the op's callData to the account verbatim.
    lastCallData = op.callData;
    (bool success, bytes memory ret) = op.sender.call(op.callData);
    if (!success) {
      assembly {
        revert(add(ret, 0x20), mload(ret))
      }
    }
    emit UserOpHandled(op.sender, userOpHash, op.callData);
  }

  function depositTo(address account) external payable override {
    _deposits[account] += msg.value;
  }

  function withdrawTo(address payable withdrawAddress, uint256 withdrawAmount) external override {
    _deposits[msg.sender] -= withdrawAmount;
    (bool ok, ) = withdrawAddress.call{ value: withdrawAmount }('');
    require(ok, 'MockEntryPoint: withdraw failed');
  }

  function balanceOf(address account) external view override returns (uint256) {
    return _deposits[account];
  }

  /// @notice Plain ETH sent to the EntryPoint (the account's
  ///         `missingAccountFunds` payment during validation) is credited
  ///         to the sender's deposit, matching the real EntryPoint.
  receive() external payable {
    _deposits[msg.sender] += msg.value;
  }
}
