// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import '../interfaces/IMyMultiSigDeployer.sol';
import '../interfaces/IMyMultiSigExtendedDeployer.sol';
import '../libs/MyMultiSigFactorableModels.sol';

/// @title MyMultiSigFactorable
/// @notice Shared factory logic: stores bookkeeping for every MyMultiSig /
///         MyMultiSigExtended instance created through the factory and emits
///         the `MyMultiSigCreated` event.
/// @dev    The actual `new MyMultiSig(...)` and `new MyMultiSigExtended(...)`
///         calls live in two tiny external deployer contracts
///         (`MyMultiSigDeployer`, `MyMultiSigExtendedDeployer`). Keeping the
///         deployment bytecode out of this contract drops its size from
///         ~23 KB to ~3 KB, well below the EIP-170 24,576-byte limit. The
///         deployer addresses are immutable so they cost nothing at runtime.
abstract contract MyMultiSigFactorable {
  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  address public immutable myMultiSigDeployer;
  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  address public immutable myMultiSigExtendedDeployer;

  uint256 private _multiSigCount;

  mapping(uint256 => address) private _multiSigs;
  mapping(address => uint256) private _multiSigCreatorCount;
  mapping(address => mapping(uint256 => uint256)) private _multiSigIndexByCreator;
  mapping(uint256 => MyMultiSigFactorableModels.CreationType) private _multiSigCreationType;

  event MyMultiSigCreated(
    address indexed creator,
    address indexed contractAddress,
    uint256 indexed contractIndex,
    string contractName,
    address[] originalOwners,
    uint16 threshold
  );

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(address myMultiSigDeployer_, address myMultiSigExtendedDeployer_) {
    myMultiSigDeployer = myMultiSigDeployer_;
    myMultiSigExtendedDeployer = myMultiSigExtendedDeployer_;
  }

  /// @notice Retrieves the contract name
  /// @return The name as a string memory.
  function name() public pure returns (string memory) {
    return 'MyMultiSigFactory';
  }

  /// @notice Retrieves the contract version
  /// @return The version as a string memory.
  function version() public pure returns (string memory) {
    return '0.1.1';
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
    return _multiSigs[index];
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
    return _multiSigs[_multiSigIndexByCreator[creator][index]];
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
    contractAddress = IMyMultiSigDeployer(myMultiSigDeployer).deployMyMultiSig(contractName, owners, threshold);

    _multiSigs[_multiSigCount] = contractAddress;
    _multiSigIndexByCreator[msg.sender][_multiSigCreatorCount[msg.sender]] = _multiSigCount;
    unchecked {
      _multiSigCreatorCount[msg.sender]++;
    }
    _multiSigCreationType[_multiSigCount] = MyMultiSigFactorableModels.CreationType.SIMPLE;
    unchecked {
      _multiSigCount++;
    }

    emit MyMultiSigCreated(msg.sender, contractAddress, _multiSigCount, contractName, owners, threshold);
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
    contractAddress = IMyMultiSigExtendedDeployer(myMultiSigExtendedDeployer).deployMyMultiSigExtended(
      contractName,
      owners,
      threshold,
      isOnlyOwnerRequest
    );

    _multiSigs[_multiSigCount] = contractAddress;
    _multiSigIndexByCreator[msg.sender][_multiSigCreatorCount[msg.sender]] = _multiSigCount;
    unchecked {
      _multiSigCreatorCount[msg.sender]++;
    }
    _multiSigCreationType[_multiSigCount] = MyMultiSigFactorableModels.CreationType.EXTENDED;
    unchecked {
      _multiSigCount++;
    }

    emit MyMultiSigCreated(msg.sender, contractAddress, _multiSigCount, contractName, owners, threshold);
  }
}
