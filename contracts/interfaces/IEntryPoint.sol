// SPDX-License-Identifier: MIT
// Vendored from OpenZeppelin's draft-IERC4337.sol (April 2023 snapshot for v0.7).
// Shape matches the canonical EntryPoint v0.7 surface; only the methods
// `MyMultiSigV2_5` actually calls are declared.
pragma solidity ^0.8.0;

import './PackedUserOperation.sol';

interface IEntryPoint {
  /// @notice Execute a batch of UserOperations.
  /// @param ops The operations to execute.
  /// @param beneficiary The address to receive the gas refund.
  function handleOps(
    PackedUserOperation[] calldata ops,
    address payable beneficiary
  ) external;

  /// @notice Deposit more funds for the account.
  function depositTo(address account) external payable;

  /// @notice Withdraw funds from the account.
  function withdrawTo(
    address payable withdrawAddress,
    uint256 withdrawAmount
  ) external;

  /// @notice Return the current deposit of the account.
  function balanceOf(address account) external view returns (uint256);
}
