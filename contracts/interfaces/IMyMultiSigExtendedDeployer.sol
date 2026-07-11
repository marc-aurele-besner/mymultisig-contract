// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface IMyMultiSigExtendedDeployer {
  function deployMyMultiSigExtended(
    string memory contractName_,
    address[] memory owners_,
    uint16 threshold_,
    bool isOnlyOwnerRequest_
  ) external returns (address contractAddress);
}
