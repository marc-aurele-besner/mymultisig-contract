// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import '../MyMultiSigExtended.sol';

/// @title MockReentrantModule
/// @notice Test fixture: a hostile module whose inner call tries to reenter
///         `execTransactionFromModule` while the wallet is already executing
///         a module transaction, so tests can assert the wallet's
///         reentrancy guard blocks the nested call.
contract MockReentrantModule {
  MyMultiSigExtended public immutable wallet;

  constructor(MyMultiSigExtended wallet_) {
    wallet = wallet_;
  }

  /// @notice Asks the wallet to CALL back into `reenter()` below. The outer
  ///         `execTransactionFromModule` holds the wallet's reentrancy
  ///         guard, so the nested attempt inside `reenter()` must revert —
  ///         and the wallet bubbles that revert payload back out.
  function attack() external {
    wallet.execTransactionFromModule(address(this), 0, abi.encodeCall(this.reenter, ()), 0);
  }

  /// @notice Inner call executed by the wallet: attempts the nested
  ///         `execTransactionFromModule`.
  function reenter() external {
    wallet.execTransactionFromModule(address(0xdead), 0, '', 0);
  }

  receive() external payable {}
}
