// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';

import './abstracts/MyMultiSigFactorable.sol';

contract MyMultiSigFactory is MyMultiSigFactorable, Initializable {
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(
    address myMultiSigDeployer_,
    address myMultiSigExtendedDeployer_
  ) MyMultiSigFactorable(myMultiSigDeployer_, myMultiSigExtendedDeployer_) {}

  function initialize() external initializer {}
}
