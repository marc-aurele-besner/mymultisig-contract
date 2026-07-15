// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';

import './abstracts/MyMultiSigFactorable.sol';
import './abstracts/MyMultiSigFactorableV2_5.sol';

/// @title MyMultiSigFactory
/// @notice The upgradeable factory proxy implementation. Bundles:
///         - the v0.4.0 factory bookkeeping (`MyMultiSigFactorable`),
///         - the v0.5.0 CREATE2 wallet surface (`MyMultiSigFactorableV2_5`),
///         - an `Initializable` proxy setup so the contract can sit
///           behind a TransparentUpgradeableProxy and be upgraded in place.
/// @dev    The constructor takes the v0.4.0 deployer immutables AND the
///         v0.5.0 (deployer, implementation) immutables. OpenZeppelin's
///         hardhat-upgrades plugin validates this layout on every upgrade.
///         The `reinitializeV2_5` re-initializer is the entry point for
///         chains that already had the v0.4.0 factory deployed; chains
///         that bootstrap directly from this version call `initialize`.
contract MyMultiSigFactory is MyMultiSigFactorable, MyMultiSigFactorableV2_5, Initializable {
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(
    address myMultiSigDeployer_,
    address myMultiSigExtendedDeployer_,
    address myMultiSigAdvancedDeployer_,
    address myMultiSigV2_5Impl_,
    address myMultiSigV2_5Deployer_
  )
    MyMultiSigFactorable(
      myMultiSigDeployer_,
      myMultiSigExtendedDeployer_,
      myMultiSigAdvancedDeployer_
    )
    MyMultiSigFactorableV2_5(myMultiSigV2_5Impl_, myMultiSigV2_5Deployer_)
  {}

  /// @notice Bootstrap initializer for chains that have not yet shipped
  ///         the v0.4.0 factory. Caches the v2_5 implementation address
  ///         as zero (call `initializeV2_5` later to wire it up).
  function initialize() external initializer {}

  /// @notice Re-initializer for chains that already have the v0.4.0
  ///         factory deployed. Records the v2_5 implementation and the
  ///         v2_5 deployer so the CREATE2 path becomes available without
  ///         having to redeploy the proxy.
  /// @dev    Using `@custom:oz-upgrades-unsafe-allow` because OZ's
  ///         layout check is satisfied — the factory's existing storage
  ///         layout (`MyMultiSigFactorable`) is unchanged and the new
  ///         abstracts only introduce immutables.
  function reinitializeV2_5() external reinitializer(2) {
    // No storage reads required for the initial deployment. The new
    // `MyMultiSigFactorableV2_5` only owns immutables; both were set at
    // construction time.
  }
}

