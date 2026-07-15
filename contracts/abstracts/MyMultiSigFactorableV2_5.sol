// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import '@openzeppelin/contracts/proxy/Clones.sol';

import '../interfaces/IMyMultiSigV2_5Deployer.sol';
import '../libs/MyMultiSigV2_5FactorableModels.sol';

/// @title MyMultiSigFactorableV2_5
/// @notice Adds the v0.5.0 CREATE2 wallet path on top of the v0.4.0
///         factory bookkeeping. Wallets are deployed as EIP-1167 minimal
///         proxies (`Clones.cloneDeterministic`) whose target is a single
///         `MyMultiSigV2_5` implementation contract stored as an immutable
///         on the factory.
/// @dev    The factory uses the existing `MyMultiSigFactorable` (v0.4.0)
///         for shared counts, events and reverse-lookup. We deliberately
///         do NOT mutate that abstract (its bytecode is already deployed
///         on Sepolia behind the proxy); we layer the new path on top.
abstract contract MyMultiSigFactorableV2_5 {
  // We use `enumCreationTypeV2_5` as a stable identifier for the new
  // wallet class without touching `MyMultiSigFactorableModels.CreationType`
  // (which is already frozen on Sepolia).
  enum CreationTypeV2_5 { V2_5 }

  /// @dev The single `MyMultiSigV2_5` implementation contract whose
  ///      bytecode every CREATE2-deployed wallet proxies into. Storing
  ///      as immutable keeps the factory's runtime bytecode minimal.
  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  address public immutable myMultiSigV2_5Impl;
  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  address public immutable myMultiSigV2_5Deployer;

  /// @notice Indexed CREATE2 deployments. Per-wallet metadata is recorded
  ///         against the wallet's own address so the existing
  ///         `MyMultiSigFactorable._creationTypeByAddress` lookup can be
  ///         reused — the wallet address is the natural key.
  mapping(address => bool) private _isV2_5Wallet;
  uint256 private _v2_5Count;

  event MyMultiSigV2_5Created(
    address indexed creator,
    address indexed contractAddress,
    bytes32 salt,
    string contractName,
    address[] originalOwners,
    uint16 threshold
  );

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(address myMultiSigV2_5Impl_, address myMultiSigV2_5Deployer_) {
    myMultiSigV2_5Impl = myMultiSigV2_5Impl_;
    myMultiSigV2_5Deployer = myMultiSigV2_5Deployer_;
  }

  /// @notice Total number of V2_5 wallets deployed via this factory.
  function v2_5Count() public view returns (uint256) {
    return _v2_5Count;
  }

  /// @notice Whether `wallet` was deployed as a V2_5 wallet via this factory.
  function isV2_5Wallet(address wallet) public view returns (bool) {
    return _isV2_5Wallet[wallet];
  }

  /// @notice Predict the address of a V2_5 wallet for the given parameters.
  /// @dev    Same address on every chain by construction: the salt is a
  ///         `keccak256` over user-supplied inputs, the deployer is `this`,
  ///         and the implementation address is held constant. Callers
  ///         repeat this on every chain to confirm they match.
  function predictWalletAddress(
    MyMultiSigV2_5FactorableModels.Create2Params calldata params
  ) public view returns (address wallet, address impl) {
    bytes32 salt = _computeSalt(params);
    impl = myMultiSigV2_5Impl;
    wallet = Clones.predictDeterministicAddress(impl, salt);
  }

  /// @notice Compute the salt that the factory would use for the given
  ///         parameters. Exposed publicly so off-chain tooling (the
  ///         frontend's pre-flight check, indexers) can show the same
  ///         address without having to redeploy.
  function computeSalt(
    MyMultiSigV2_5FactorableModels.Create2Params calldata params
  ) public pure returns (bytes32) {
    return _computeSalt(params);
  }

  /// @notice Deploy a V2_5 wallet via CREATE2.
  function createMyMultiSigV2_5(
    MyMultiSigV2_5FactorableModels.Create2Params calldata params,
    address entryPoint
  ) public payable returns (address contractAddress) {
    bytes32 salt = _computeSalt(params);
    // EIP-1167 minimal proxy pointing at the immutable V2_5 implementation.
    contractAddress = Clones.cloneDeterministic(myMultiSigV2_5Impl, salt);
    // The proxy has no constructor; the deployer helper forwards the
    // factory-time arguments (name, owners, threshold, entryPoint) so the
    // proxy's runtime state matches the user-supplied parameters.
    IMyMultiSigV2_5Deployer(myMultiSigV2_5Deployer).deployMyMultiSigV2_5(
      params.contractName,
      params.owners,
      params.threshold,
      entryPoint
    );
    _isV2_5Wallet[contractAddress] = true;
    unchecked {
      ++_v2_5Count;
    }
    emit MyMultiSigV2_5Created(
      msg.sender,
      contractAddress,
      salt,
      params.contractName,
      params.owners,
      params.threshold
    );
  }

  /// @dev Folds the user-supplied parameters into a single 32-byte salt.
  ///      The shape is fixed across chains so the same input parameters
  ///      always produce the same address.
  function _computeSalt(
    MyMultiSigV2_5FactorableModels.Create2Params calldata params
  ) internal pure returns (bytes32) {
    return keccak256(abi.encode(params.saltKind, params.chainAgnosticKey, params.owners, params.threshold, params.contractName));
  }
}
