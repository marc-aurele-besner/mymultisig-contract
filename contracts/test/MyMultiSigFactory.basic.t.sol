// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import 'foundry-test-utility/contracts/utils/console.sol';
import { Scenario_Basic } from './shared/tests.t.sol';

contract TestMyMultiSigFactory_basic is Scenario_Basic {
  function setUp() public {
    initialize_helper(LOG_LEVEL, TestType.TestWithFactory);
  }
}
