// SPDX-License-Identifier: MIT
// Vendored from OpenZeppelin's draft-IERC4337.sol (April 2023 snapshot for v0.7).
// `IAccount` is the interface every account must implement to be usable
// through EntryPoint.handleOps: the EntryPoint calls `validateUserOp`
// during the validation phase, then executes `userOp.callData` against
// the account during the execution phase.
pragma solidity ^0.8.0;

import './PackedUserOperation.sol';

interface IAccount {
  /// @notice Validate the user operation. Must revert if the caller is not
  ///         the trusted EntryPoint; signature failure is reported via the
  ///         return value (1 = SIG_VALIDATION_FAILED), not a revert.
  /// @param userOp The parsed user-operation.
  /// @param userOpHash Hash of the op computed by the EntryPoint — binds the
  ///                   op's fields, the EntryPoint address, and the chain id.
  /// @param missingAccountFunds The deposit the account still owes the
  ///                            EntryPoint to prefund this op's gas; the
  ///                            account must transfer at least this much to
  ///                            the EntryPoint before returning.
  /// @return validationData 0 on success, 1 on signature failure; accounts
  ///                        with time-bounded signatures pack
  ///                        `validAfter (48) | validUntil (48) | authorizer (160)`.
  function validateUserOp(
    PackedUserOperation calldata userOp,
    bytes32 userOpHash,
    uint256 missingAccountFunds
  ) external returns (uint256 validationData);
}
