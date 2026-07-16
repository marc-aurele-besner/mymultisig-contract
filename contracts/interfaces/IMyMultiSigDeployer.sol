// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface IMyMultiSigDeployer {
  function deployMyMultiSig(
    string memory contractName_,
    address[] memory owners_,
    uint16 threshold_
  ) external returns (address contractAddress);

  function deployMyMultiSigDeterministic(
    bytes32 salt_,
    string memory contractName_,
    address[] memory owners_,
    uint16 threshold_
  ) external returns (address contractAddress);

  function predictMyMultiSigAddress(
    bytes32 salt_,
    string memory contractName_,
    address[] memory owners_,
    uint16 threshold_
  ) external view returns (address contractAddress);
}
