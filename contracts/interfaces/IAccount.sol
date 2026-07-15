// SPDX-License-Identifier: MIT
// Vendored from OpenZeppelin's draft-IERC4337.sol (April 2023 snapshot for v0.7).
// `IAccount` is the marker interface every account must implement to be
// usable through EntryPoint.handleOps. Only `validateUserOp` is required
// to gate how the bundler is allowed to relay operations; `executeUserOp`
// is a wallet-private helper that `MyMultiSigV2_5` exposes for completeness.
pragma solidity ^0.8.0;

import './PackedUserOperation.sol';

interface IAccount {
  /// @notice Validate the user operation. Must revert on failure.
  /// @param userOp The parsed user-operation.
  /// @param userOpHash The hash the bundler computed (EIP-712 over the union
  ///                   of `(userOp.sender, nonce, ...)` and the EntryPoint domain).
  /// @param missingAccountFunds The pre-deposit the EntryPoint would otherwise
  ///                            refund to the account; we ignore it on purpose.
  /// @return validationData Packed: aggregator flag in the high-1-byte, plus
  ///                        `validAfter << 160 | validUntil` in the high-2-bytes.
  function validateUserOp(
    PackedUserOperation calldata userOp,
    bytes32 userOpHash,
    uint256 missingAccountFunds
  ) external returns (uint256 validationData);
}
