// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import '../interfaces/IMyMultiSigDeployer.sol';
import '../interfaces/IMyMultiSigExtendedDeployer.sol';
import '../interfaces/IMyMultiSigAdvancedDeployer.sol';
import '../libs/MyMultiSigFactorableModels.sol';

/// @title MyMultiSigFactorable
/// @notice Shared factory logic: stores bookkeeping for every `MyMultiSig` /
///         `MyMultiSigExtended` instance created via the factory, exposes
///         per-type counts and address-keyed type lookup, and emits the
///         `MyMultiSigCreated` event.
/// @dev    The actual `new MyMultiSig(...)` and `new MyMultiSigExtended(...)`
///         calls live in three tiny external deployer contracts
///         (`MyMultiSigDeployer`, `MyMultiSigExtendedDeployer`,
///         `MyMultiSigAdvancedDeployer`). Keeping deployment bytecode out of
///         this contract drops its size, well below the EIP-170 24,576-byte
///         limit. Deployer addresses are immutable so they cost nothing at
///         runtime.
abstract contract MyMultiSigFactorable {
  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  address public immutable myMultiSigDeployer;
  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  address public immutable myMultiSigExtendedDeployer;
  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  address public immutable myMultiSigAdvancedDeployer;

  uint256 private _multiSigCount;
  uint256 private _simpleCount;
  uint256 private _extendedCount;
  uint256 private _advancedCount;

  mapping(uint256 => address) private _multiSigs;
  mapping(address => uint256) private _multiSigCreatorCount;
  mapping(address => mapping(uint256 => uint256)) private _multiSigIndexByCreator;
  mapping(uint256 => MyMultiSigFactorableModels.CreationType) private _multiSigCreationType;
  /// @dev Reverse lookup populated alongside `_multiSigCreationType[index]`
  ///      so callers can resolve a wallet address back to its kind.
  mapping(address => MyMultiSigFactorableModels.CreationType) private _creationTypeByAddress;

  event MyMultiSigCreated(
    address indexed creator,
    address indexed contractAddress,
    uint256 indexed contractIndex,
    string contractName,
    address[] originalOwners,
    uint16 threshold
  );

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(
    address myMultiSigDeployer_,
    address myMultiSigExtendedDeployer_,
    address myMultiSigAdvancedDeployer_
  ) {
    myMultiSigDeployer = myMultiSigDeployer_;
    myMultiSigExtendedDeployer = myMultiSigExtendedDeployer_;
    myMultiSigAdvancedDeployer = myMultiSigAdvancedDeployer_;
  }

  /// @notice Retrieves the contract name
  function name() public pure returns (string memory) {
    return 'MyMultiSigFactory';
  }

  /// @notice Retrieves the contract version
  function version() public pure returns (string memory) {
    return '0.5.0';
  }

  /// @notice Total multisigs created via this factory (all types combined).
  function multiSigCount() public view returns (uint256) {
    return _multiSigCount;
  }

  /// @notice Number of base `MyMultiSig` wallets created via this factory.
  function simpleCount() public view returns (uint256) {
    return _simpleCount;
  }

  /// @notice Number of `MyMultiSigExtended` wallets created via the
  ///         Extended deployer (incl. Advanced, which subclasses Extended).
  function extendedCount() public view returns (uint256) {
    return _extendedCount;
  }

  /// @notice Number of wallets created via the Advanced deployer.
  function advancedCount() public view returns (uint256) {
    return _advancedCount;
  }

  /// @notice Count of wallets of the given creation type.
  function creationTypeCount(MyMultiSigFactorableModels.CreationType kind) public view returns (uint256) {
    if (kind == MyMultiSigFactorableModels.CreationType.SIMPLE) return _simpleCount;
    if (kind == MyMultiSigFactorableModels.CreationType.EXTENDED) return _extendedCount;
    if (kind == MyMultiSigFactorableModels.CreationType.ADVANCED) return _advancedCount;
    return 0; // unknown enum value
  }

  /// @notice Retrieves a multisig by its global index.
  function multiSig(uint256 index) public view returns (address) {
    return _multiSigs[index];
  }

  /// @notice Number of multisigs created by `creator` (any type).
  function multiSigCreatorCount(address creator) public view returns (uint256) {
    return _multiSigCreatorCount[creator];
  }

  /// @notice The address of the multisig created by `creator` at its index.
  function multiSigByCreator(address creator, uint256 index) public view returns (address) {
    return _multiSigs[_multiSigIndexByCreator[creator][index]];
  }

  /// @notice Returns the creation type at a global index.
  function creationType(uint256 index) public view returns (MyMultiSigFactorableModels.CreationType) {
    return _multiSigCreationType[index];
  }

  /// @notice Returns the creation type for a wallet address, or `SIMPLE` if
  ///         the address was never recorded by this factory.
  function creationTypeOf(address contractAddress) public view returns (MyMultiSigFactorableModels.CreationType) {
    return _creationTypeByAddress[contractAddress];
  }

  /// @notice `true` iff `contractAddress` is an Extended (or Advanced)
  ///         wallet — i.e. anything that is `MyMultiSigExtended`.
  /// @dev    Advanced subclasses `MyMultiSigExtended`, so both count as
  ///         Extended here. For finer-grained queries use `creationTypeOf`.
  function isExtended(address contractAddress) public view returns (bool) {
    MyMultiSigFactorableModels.CreationType kind = _creationTypeByAddress[contractAddress];
    return
      kind == MyMultiSigFactorableModels.CreationType.EXTENDED ||
      kind == MyMultiSigFactorableModels.CreationType.ADVANCED;
  }

  /// @notice `true` iff the multisig at `index` was created via the Advanced
  ///         deployer.
  function isAdvanced(uint256 index) public view returns (bool) {
    return _multiSigCreationType[index] == MyMultiSigFactorableModels.CreationType.ADVANCED;
  }

  /// @dev Shared post-deploy bookkeeping for the three `create*` entry
  ///      points. Reads `_multiSigCount` / `_multiSigCreatorCount` once into
  ///      locals and touches each storage slot exactly once.
  /// @return newCount The post-increment global count, emitted by the
  ///         callers as the `contractIndex` of `MyMultiSigCreated`.
  function _recordMultiSig(
    address contractAddress,
    MyMultiSigFactorableModels.CreationType kind
  ) private returns (uint256 newCount) {
    uint256 count = _multiSigCount;
    uint256 creatorCount = _multiSigCreatorCount[msg.sender];
    _multiSigs[count] = contractAddress;
    _multiSigIndexByCreator[msg.sender][creatorCount] = count;
    _multiSigCreationType[count] = kind;
    _creationTypeByAddress[contractAddress] = kind;
    unchecked {
      _multiSigCreatorCount[msg.sender] = creatorCount + 1;
      if (kind == MyMultiSigFactorableModels.CreationType.SIMPLE) _simpleCount++;
      else if (kind == MyMultiSigFactorableModels.CreationType.EXTENDED) _extendedCount++;
      else _advancedCount++;
      newCount = count + 1;
    }
    _multiSigCount = newCount;
  }

  /// @notice Creates a new base `MyMultiSig` wallet.
  /// @param contractName The wallet's name (shown in the EIP-712 domain).
  /// @param owners The owners list.
  /// @param threshold The minimum sigs required to execute a transaction.
  function createMultiSig(
    string memory contractName,
    address[] memory owners,
    uint16 threshold
  ) public payable returns (address contractAddress) {
    contractAddress = IMyMultiSigDeployer(myMultiSigDeployer).deployMyMultiSig(contractName, owners, threshold);

    uint256 newCount = _recordMultiSig(contractAddress, MyMultiSigFactorableModels.CreationType.SIMPLE);

    emit MyMultiSigCreated(msg.sender, contractAddress, newCount, contractName, owners, threshold);
  }

  /// @notice Creates a new `MyMultiSigExtended` wallet via the Extended
  ///         deployer. The caller is responsible for passing the
  ///         canonical v0.7 EntryPoint address.
  /// @param entryPoint Canonical EntryPoint v0.7 address. Required to
  ///        be non-zero so the wallet constructor's `InvalidOperation`
  ///        check passes; pass the constant
  ///        `0x0000000071727De22E5E9d8BDe0dFeC0CEB6a7d7` (same on every
  ///        chain) for the typical case.
  function createMyMultiSigExtended(
    string memory contractName,
    address[] memory owners,
    uint16 threshold,
    bool isOnlyOwnerRequest,
    address entryPoint
  ) public payable returns (address contractAddress) {
    contractAddress = IMyMultiSigExtendedDeployer(myMultiSigExtendedDeployer).deployMyMultiSigExtended(
      contractName,
      owners,
      threshold,
      isOnlyOwnerRequest,
      entryPoint
    );

    uint256 newCount = _recordMultiSig(contractAddress, MyMultiSigFactorableModels.CreationType.EXTENDED);

    emit MyMultiSigCreated(msg.sender, contractAddress, newCount, contractName, owners, threshold);
  }

  /// @notice Creates a new `MyMultiSigExtended`-class wallet via the Advanced
  ///         deployer. Currently routes to the Extended deployer (the
  ///         wallet bytecode is identical); the factory
  ///         uses a separate code path so future Advanced-only features
  ///         can ship without re-deploying the wallet. Same
  ///         `entryPoint` semantics as `createMyMultiSigExtended`.
  function createMyMultiSigAdvanced(
    string memory contractName,
    address[] memory owners,
    uint16 threshold,
    bool isOnlyOwnerRequest,
    address entryPoint
  ) public payable returns (address contractAddress) {
    contractAddress = IMyMultiSigAdvancedDeployer(myMultiSigAdvancedDeployer).deployMyMultiSigAdvanced(
      contractName,
      owners,
      threshold,
      isOnlyOwnerRequest,
      entryPoint
    );

    uint256 newCount = _recordMultiSig(contractAddress, MyMultiSigFactorableModels.CreationType.ADVANCED);

    emit MyMultiSigCreated(msg.sender, contractAddress, newCount, contractName, owners, threshold);
  }
}
