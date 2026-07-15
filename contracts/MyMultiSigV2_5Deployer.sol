// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import './MyMultiSigV2_5.sol';
import './interfaces/IMyMultiSigV2_5Deployer.sol';

/// @title MyMultiSigV2_5Deployer
/// @notice Thin wrapper that performs `new MyMultiSigV2_5(...)` so the
///         factory doesn't have to embed the v0.5.0 wallet's creation
///         bytecode. Same pattern as `MyMultiSigDeployer.sol:14-21` for
///         the v0.4.0 base wallet.
/// @dev    The factory holds this contract's address as an immutable and
///         forwards the V2_5 deploy call here.
contract MyMultiSigV2_5Deployer is IMyMultiSigV2_5Deployer {
  function deployMyMultiSigV2_5(
    string memory contractName_,
    address[] memory owners_,
    uint16 threshold_,
    address entryPoint_
  ) external override returns (address contractAddress) {
    contractAddress = address(
      new MyMultiSigV2_5(contractName_, owners_, threshold_, entryPoint_)
    );
  }
}
