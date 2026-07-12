// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { TestBasic } from './shared/tests.t.sol';

contract TestMyMultiSig_extended is TestBasic {
  function setUp() public {
    initialize_helper(LOG_LEVEL, TestType.TestWithoutFactory_extended);
  }
}
