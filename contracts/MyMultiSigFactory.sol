// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';

import './abstracts/MyMultiSigFactorable.sol';

/// @title MyMultiSigFactory
/// @notice The upgradeable factory proxy implementation. Bundles:
///         - the v0.4.0 / v0.5.0 factory bookkeeping
///           (`MyMultiSigFactorable`),
///         - an `Initializable` proxy setup so the contract can sit
///           behind a TransparentUpgradeableProxy and be upgraded in
///           place.
///
/// @dev    v0.5.0 simplified the factory back to the v0.4.0 constructor
///         shape — there is no separate `MyMultiSigV2_5` deployer /
///         implementation slot. `MyMultiSigExtended` is now the
///         v0.5.0 wallet; the same `MyMultiSigExtendedDeployer` deploys
///         it (now taking an `entryPoint_` argument). The factory
///         already stores that deployer as an immutable; nothing
///         changes on the factory's storage side beyond the wallet
///         class itself gaining the new constructor arg.
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

  /// @notice Bootstrap initializer for chains that have not yet shipped
  ///         the v0.4.0 factory. Implemented as `external initializer`
  ///         so the proxy upgrade passes OZ's hardhat-upgrades layout
  ///         check on first deploy.
  function initialize() external initializer {}
}
