// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title ITransactionGuard
/// @notice Pluggable guard called by `MyMultiSigExtended` before (and
///         optionally after) every wallet-driven and module-driven call.
///         `checkTransaction` MUST revert to block; any other return is
///         treated as allowed. `checkAfterExecution` is silent — its
///         failure is logged via `PostExecutionGuardFailed` but never
///         reverts.
interface ITransactionGuard {
  /// @notice Pre-call gate. Validate `(to, value, data)` and EITHER return
  ///         silently to allow OR revert to block. The wallet wraps any
  ///         revert into `GuardReverted(guard, reason)`.
  /// @dev    The wallet forwards full remaining gas. Implementations
  ///         SHOULD gas-limit their own work. Only a revert is meaningful.
  function checkTransaction(address to, uint256 value, bytes calldata data) external;

  /// @notice Post-call audit hook. The wallet catches and ignores reverts.
  /// @dev    Useful for accounting, analytics, alerting — never enforced.
  function checkAfterExecution(bytes32 txHash, bool success) external;
}
