// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import './abstracts/MyMultiSigFactorable.sol';

contract MyMultiSigFactoryWithChugSplash is MyMultiSigFactorable {
  constructor(
    address myMultiSigDeployer_,
    address myMultiSigExtendedDeployer_
  ) MyMultiSigFactorable(myMultiSigDeployer_, myMultiSigExtendedDeployer_) {}
}
