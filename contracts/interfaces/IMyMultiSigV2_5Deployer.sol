// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface IMyMultiSigV2_5Deployer {
  function deployMyMultiSigV2_5(
    string memory contractName_,
    address[] memory owners_,
    uint16 threshold_,
    address entryPoint_
  ) external returns (address contractAddress);
}
