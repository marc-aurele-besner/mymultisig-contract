// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import '../MyMultiSigExtended.sol';

/// @title MockModule
/// @notice Test fixture: wraps `MyMultiSigExtended.execTransactionFromModule` so
///         the Hardhat test suite can drive a module-driven tx without a hand-
///         written ABI-encoded calldata blob. Also exposes a DELEGATECALL helper
///         that runs the supplied code in the wallet's storage context.
contract MockModule {
  MyMultiSigExtended public immutable wallet;

  constructor(MyMultiSigExtended wallet_) {
    wallet = wallet_;
  }

  /// @notice Direct CALL path. Equivalent to the wallet's
  ///         `execTransactionFromModule(to, value, data, 0)`.
  function execCall(address to, uint256 value, bytes calldata data) external {
    wallet.execTransactionFromModule(to, value, data, 0);
  }

  /// @notice DELEGATECALL path. Runs the supplied `data` in the wallet's
  ///         storage context. `to` is forced to `address(wallet)` inside the
  ///         wallet; we pass `address(wallet)` here.
  function execDelegateCall(bytes calldata data) external {
    wallet.execTransactionFromModule(address(wallet), 0, data, 1);
  }

  receive() external payable {}
}
