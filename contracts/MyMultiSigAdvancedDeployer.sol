// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import './interfaces/IMyMultiSigAdvancedDeployer.sol';
import './interfaces/IMyMultiSigExtendedDeployer.sol';

/// @title MyMultiSigAdvancedDeployer
/// @notice Thin wrapper that defers to the existing `MyMultiSigExtendedDeployer`
///         so the factory can distinguish "Advanced" creation in its bookkeeping
///         without paying for a second copy of the wallet's creation bytecode
///         (which already pushes past the EIP-170 24,576-byte limit on the
///         extended deployer itself).
/// @dev    Stores the extended deployer immutably and re-uses it. Advanced
///         wallets are bytecode-identical twins of Extended ones; the
///         distinction lives purely in factory bookkeeping. An Advanced-only
///         release can later replace this contract with one that embeds
///         different bytecode without touching the factory's call surface.
///
///         The CREATE2 path routes through the extended deployer too. Since
///         the extended deployer namespaces salts by its direct caller, the
///         wallets deployed here live in this contract's namespace —
///         an Advanced deploy can never collide with an Extended deploy that
///         used the same salt and constructor arguments.
contract MyMultiSigAdvancedDeployer is IMyMultiSigAdvancedDeployer {
  /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
  address public immutable extendedDeployer;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(address extendedDeployer_) {
    extendedDeployer = extendedDeployer_;
  }

  function deployMyMultiSigAdvanced(
    string memory contractName_,
    address[] memory owners_,
    uint16 threshold_,
    bool isOnlyOwnerRequest_,
    address entryPoint_
  ) external override returns (address contractAddress) {
    contractAddress = IMyMultiSigExtendedDeployer(extendedDeployer).deployMyMultiSigExtended(
      contractName_,
      owners_,
      threshold_,
      isOnlyOwnerRequest_,
      entryPoint_
    );
  }

  /// @notice Deploys an Advanced wallet via CREATE2 (routed through the
  ///         extended deployer, in this contract's salt namespace).
  /// @dev    Reverts if a contract already exists at the target address
  ///         (same caller, salt and constructor arguments).
  /// @param salt_ Caller-chosen salt.
  /// @return contractAddress The deployed wallet address.
  function deployMyMultiSigAdvancedDeterministic(
    bytes32 salt_,
    string memory contractName_,
    address[] memory owners_,
    uint16 threshold_,
    bool isOnlyOwnerRequest_,
    address entryPoint_
  ) external override returns (address contractAddress) {
    contractAddress = IMyMultiSigExtendedDeployer(extendedDeployer).deployMyMultiSigExtendedDeterministic(
      _callerSalt(salt_),
      contractName_,
      owners_,
      threshold_,
      isOnlyOwnerRequest_,
      entryPoint_
    );
  }

  /// @notice Predicts the address `deployMyMultiSigAdvancedDeterministic`
  ///         would deploy to for the same caller, salt and constructor
  ///         arguments.
  /// @dev    Must be called by the same account that will perform the deploy
  ///         (the salt is namespaced by `msg.sender`).
  function predictMyMultiSigAdvancedAddress(
    bytes32 salt_,
    string memory contractName_,
    address[] memory owners_,
    uint16 threshold_,
    bool isOnlyOwnerRequest_,
    address entryPoint_
  ) external view override returns (address contractAddress) {
    contractAddress = IMyMultiSigExtendedDeployer(extendedDeployer).predictMyMultiSigExtendedAddress(
      _callerSalt(salt_),
      contractName_,
      owners_,
      threshold_,
      isOnlyOwnerRequest_,
      entryPoint_
    );
  }

  /// @dev Namespaces a caller-chosen salt by `msg.sender`, mirroring the
  ///      extended deployer's own namespacing so direct callers of this
  ///      contract each get their own address space too.
  function _callerSalt(bytes32 salt_) private view returns (bytes32) {
    return keccak256(abi.encode(msg.sender, salt_));
  }
}
