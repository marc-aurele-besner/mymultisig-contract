// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import './MyMultiSigExtended.sol';
import './interfaces/IMyMultiSigExtendedDeployer.sol';

/// @title MyMultiSigExtendedDeployer
/// @notice Thin wrapper that performs `new MyMultiSigExtended(...)` so
///         the factory doesn't have to embed the wallet's creation
///         bytecode (which is even larger than MyMultiSig's because of
///         the extra delegation / 4337 / operation-byte logic).
/// @dev    v0.5.0 adds an `entryPoint_` argument; the deployer forwards
///         it through to the wallet's constructor. The factory
///         `createMyMultiSigExtended(...)` is unchanged at the
///         `MyMultiSigFactorable` level — the new `entryPoint_` arg is
///         stored on the factory as a v0.5.0 surface addition.
contract MyMultiSigExtendedDeployer is IMyMultiSigExtendedDeployer {
  function deployMyMultiSigExtended(
    string memory contractName_,
    address[] memory owners_,
    uint16 threshold_,
    bool isOnlyOwnerRequest_,
    address entryPoint_
  ) external override returns (address contractAddress) {
    contractAddress = address(
      new MyMultiSigExtended(contractName_, owners_, threshold_, isOnlyOwnerRequest_, entryPoint_)
    );
  }
}
