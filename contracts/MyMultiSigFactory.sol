// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import './MyMultiSig.sol';

contract MyMultiSigFactory {
  uint256 private _multiSigCount;

  mapping(uint256 => MyMultiSig) private _multiSigs;

  event MyMultiSigCreated(
    address indexed creator,
    address indexed contractAddress,
    uint256 indexed contractIndex,
    string contractName,
    address[] originalOwners
  );

  constructor() {}

  /// @notice Retrieves the contract name
  /// @return The name as a string memory.
  function name() public pure returns (string memory) {
    return 'MyMultiSigFactory';
  }

  /// @notice Retrieves the contract version
  /// @return The version as a string memory.
  function version() public pure returns (string memory) {
    return '0.0.2';
  }

  /// @notice Retrieves the amount of multisig contract created via this Factory contract
  /// @return The current amount value as a uint256.
  function multiSigCount() public view returns (uint256) {
    return _multiSigCount;
  }

  /// @notice Retrieves a multisig by it's index
  /// @param index The index of the multisig
  /// @return The current amount value as a uint256.
  function multiSig(uint256 index) public view returns (address) {
    return address(_multiSigs[index]);
  }

  /// @notice Executes a transaction
  /// @param contractName The name of your multisig contract
  /// @param owners The owners list
  /// @param threshold The amount of owners signature require to execute transactions
  function createMultiSig(
    string memory contractName,
    address[] memory owners,
    uint16 threshold
  ) public payable returns (bool success) {
    _multiSigs[_multiSigCount] = new MyMultiSig(contractName, owners, threshold);
    emit MyMultiSigCreated(msg.sender, address(_multiSigs[_multiSigCount]), _multiSigCount, contractName, owners);
    _multiSigCount++;
    return true;
  }
}
