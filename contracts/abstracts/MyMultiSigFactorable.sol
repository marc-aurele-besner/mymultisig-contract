// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import '../MyMultiSigExtended.sol';
import '../libs/MyMultiSigFactorableModels.sol';

contract MyMultiSigFactorable {
  uint256 private _multiSigCount;

  mapping(uint256 => MyMultiSig) private _multiSigs;
  mapping(address => uint256) private _multiSigIndex;
  mapping(address => uint256) private _multiSigCreatorCount;
  mapping(address => mapping(uint256 => uint256)) private _multiSigIndexByCreator;
  mapping(uint256 => MyMultiSigFactorableModels.CreationType) private _multiSigCreationType;

  event MyMultiSigCreated(
    address indexed creator,
    address indexed contractAddress,
    uint256 indexed contractIndex,
    string contractName,
    address[] originalOwners
  );

  /// @notice Retrieves the contract name
  /// @return The name as a string memory.
  function name() public pure returns (string memory) {
    return 'MyMultiSigFactory';
  }

  /// @notice Retrieves the contract version
  /// @return The version as a string memory.
  function version() public pure returns (string memory) {
    return '0.0.10';
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

  /// @notice Retrieves the amount of multisig contract created via this Factory contract by a specific creator
  /// @param creator The creator of the multisig contract
  /// @return The current amount value as a uint256.
  function multiSigCreatorCount(address creator) public view returns (uint256) {
    return _multiSigCreatorCount[creator];
  }

  /// @notice Retrieves a multisig created by a specific creator by it's index
  /// @param creator The creator of the multisig contract
  /// @param index The index of the multisig
  /// @return The current amount value as a uint256.
  function multiSigByCreator(address creator, uint256 index) public view returns (address) {
    return address(_multiSigs[_multiSigIndexByCreator[creator][index]]);
  }

  /// @notice Retrieves the type of multisig contract created via this Factory contract
  /// @param index The index of the multisig
  /// @return The type of multisig contract as a MyMultiSigFactorableModels.CreationType.
  function creationType(uint256 index) public view returns (MyMultiSigFactorableModels.CreationType) {
    return _multiSigCreationType[index];
  }

  /// @notice Creates a new multisig contract
  /// @param contractName The name of your multisig contract
  /// @param owners The owners list
  /// @param threshold The amount of owners signature require to execute transactions
  function createMultiSig(
    string memory contractName,
    address[] memory owners,
    uint16 threshold
  ) public payable returns (address contractAddress) {
    MyMultiSig myMultiSig = new MyMultiSig(contractName, owners, threshold);
    return
      _saveCreateMyMultiSig(
        MyMultiSigFactorableModels.CreationType.SIMPLE,
        myMultiSig,
        contractName,
        owners,
        threshold
      );
  }

  /// @notice Creates a new multisig contract with extended features
  /// @param contractName The name of your multisig contract
  /// @param owners The owners list
  /// @param threshold The amount of owners signature require to execute transactions
  function createMyMultiSigExtended(
    string memory contractName,
    address[] memory owners,
    uint16 threshold,
    bool isOnlyOwnerRequest
  ) public payable returns (address contractAddress) {
    MyMultiSigExtended myMultiSig = new MyMultiSigExtended(contractName, owners, threshold, isOnlyOwnerRequest);
    return
      _saveCreateMyMultiSig(
        MyMultiSigFactorableModels.CreationType.EXTENDED,
        MyMultiSig(myMultiSig),
        contractName,
        owners,
        threshold
      );
  }

  /// @notice Creates a new multisig contract (internal)
  /// @param creationType The type of creation
  /// @param myMultiSig Contract deployed (casted as MyMultiSig if extended)
  /// @param contractName The name of your multisig contract
  /// @param owners The owners list
  /// @param threshold The amount of owners signature require to execute transactions
  function _saveCreateMyMultiSig(
    MyMultiSigFactorableModels.CreationType creationType,
    MyMultiSig myMultiSig,
    string memory contractName,
    address[] memory owners,
    uint16 threshold
  ) internal returns (address contractAddress) {
    contractAddress = address(myMultiSig);

    _multiSigs[_multiSigCount] = myMultiSig;
    _multiSigIndex[contractAddress] = _multiSigCount;
    _multiSigIndexByCreator[msg.sender][_multiSigCreatorCount[msg.sender]] = _multiSigCount;
    _multiSigCreatorCount[msg.sender]++;
    _multiSigCreationType[_multiSigCount] = creationType;
    _multiSigCount++;

    emit MyMultiSigCreated(msg.sender, contractAddress, _multiSigCount, contractName, owners);
  }
}
