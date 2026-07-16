// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface IMyMultiSigAdvancedDeployer {
  function deployMyMultiSigAdvanced(
    string memory contractName_,
    address[] memory owners_,
    uint16 threshold_,
    bool isOnlyOwnerRequest_,
    address entryPoint_
  ) external returns (address contractAddress);
}
