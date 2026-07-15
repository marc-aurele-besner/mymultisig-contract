// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import '../interfaces/ITransactionGuard.sol';

/// @title MockGuard
/// @notice Test fixture: behaves differently per `mode` so the Hardhat suite
///         can exercise each guard-revert path:
///           - `0` (default): pass-through.
contract MockGuard is ITransactionGuard {
  uint8 public mode; // 0 = pass, 1 = revert with a reason, 2 = revert with empty data
  address public lastTo;
  uint256 public lastValue;
  bytes public lastData;
  bytes32 public lastTxHash;
  bool public lastSuccess;
  uint256 public checkTransactionCalls;
  uint256 public checkAfterExecutionCalls;

  function setMode(uint8 mode_) external {
    mode = mode_;
  }

  function checkTransaction(address to, uint256 value, bytes calldata data) external override {
    checkTransactionCalls++;
    lastTo = to;
    lastValue = value;
    lastData = data;
    if (mode == 1) {
      revert('MockGuard: explicit reject');
    } else if (mode == 2) {
      assembly {
        revert(0, 0)
      }
    }
  }

  function checkAfterExecution(bytes32 txHash, bool success) external override {
    checkAfterExecutionCalls++;
    lastTxHash = txHash;
    lastSuccess = success;
    if (mode == 3) {
      revert('MockGuard: post-exec failure');
    }
  }
}
