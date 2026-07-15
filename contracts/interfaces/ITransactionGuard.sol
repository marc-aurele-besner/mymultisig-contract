// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title ITransactionGuard
/// @notice Pluggable transaction guard for MyMultiSigExtended v0.4.0.
/// @dev    A guard is an external contract the wallet calls before (and optionally after)
///         executing every wallet-driven transaction, including module-driven ones.
///         `checkTransaction` MUST revert if the call should not proceed; any other
///         outcome (including a silent return) is treated as "allowed" by the wallet.
///         `checkAfterExecution` is a SILENT audit hook — its failure is logged via
///         `PostExecutionGuardFailed` but never reverts the wallet's transaction. The
///         caller of `execTransaction` does not pay for failures of `checkAfterExecution`.
interface ITransactionGuard {
  /// @notice Called by the wallet BEFORE executing a wallet-driven transaction.
  ///         Implementations should validate `(to, value, data)` and EITHER return
  ///         silently to allow the call OR revert to block it. The wallet wraps
  ///         any revert into a `GuardReverted(guard, reason)` so consumers can
  ///         see the guard's raw revert payload.
  /// @dev    The wallet forwards the full remaining gas to this call. Implementations
  ///         SHOULD gas-limit their own work to avoid grief vectors. The wallet does
  ///         NOT trust the return data — only a revert is meaningful.
  /// @param to The destination of the wallet-driven transaction.
  /// @param value The wei value forwarded to `to`.
  /// @param data The calldata of the wallet-driven transaction.
  function checkTransaction(address to, uint256 value, bytes calldata data) external;

  /// @notice Called by the wallet AFTER a wallet-driven transaction has executed.
  ///         A no-op `return` is the success signal; a revert is logged but does not
  ///         cause the wallet's transaction to fail.
  /// @dev    Implementations MUST be defensive — the wallet catches and ignores all
  ///         reverts. Useful for accounting, analytics, alerting, etc.
  /// @param txHash The EIP-712 transaction hash that was executed.
  /// @param success `true` if the inner call returned successfully, `false` otherwise.
  function checkAfterExecution(bytes32 txHash, bool success) external;
}
