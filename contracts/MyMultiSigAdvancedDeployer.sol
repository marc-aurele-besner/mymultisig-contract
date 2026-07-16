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
/// @dev    Stores the extended deployer immutably and re-uses it. v0.4.0
///         Advanced wallets have bytecode-identical twins under the Extended
///         deployer; the distinction is purely in factory bookkeeping. A
///         future v0.5.x Advanced-only release can replace this contract
///         with one that DOES embed a different bytecode, without touching
///         the factory's call surface.
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
}
