// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';

import './abstracts/MyMultiSigFactorable.sol';

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

  function initialize() external initializer {}
}
