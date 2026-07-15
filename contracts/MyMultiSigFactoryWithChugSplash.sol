// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import './abstracts/MyMultiSigFactorable.sol';

contract MyMultiSigFactoryWithChugSplash is MyMultiSigFactorable {
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
}
