// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import 'foundry-test-utility/contracts/utils/console.sol';
import { TestBasic } from './shared/tests.t.sol';

contract TestMyMultiSig_basic is TestBasic {
  function setUp() public {
    initialize_helper(LOG_LEVEL, TestType.TestWithoutFactory);
  }
}
