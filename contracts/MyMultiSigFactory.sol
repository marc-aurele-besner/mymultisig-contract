// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';

import './abstracts/MyMultiSigFactorable.sol';

/// @title MyMultiSigFactory
/// @notice The upgradeable factory proxy implementation. Bundles:
///         - the factory bookkeeping (`MyMultiSigFactorable`),
///         - an `Initializable` proxy setup so the contract can sit
///           behind a TransparentUpgradeableProxy and be upgraded in
///           place.
///
/// @dev    All three wallet deployers are stored as immutables on
///         `MyMultiSigFactorable`; the factory itself holds no wallet
///         creation bytecode.
contract MyMultiSigFactory is MyMultiSigFactorable, Initializable {
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(
    address myMultiSigDeployer_,
    address myMultiSigExtendedDeployer_,
    address myMultiSigAdvancedDeployer_
  )
    MyMultiSigFactorable(
      myMultiSigDeployer_,
      myMultiSigExtendedDeployer_,
      myMultiSigAdvancedDeployer_
    )
  {}

  /// @notice Bootstrap initializer for first-time proxy deployments.
  ///         Implemented as `external initializer` so the deployment
  ///         passes OZ's hardhat-upgrades layout check.
  function initialize() external initializer {}
}
