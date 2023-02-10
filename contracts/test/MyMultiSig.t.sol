// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import 'foundry-test-utility/contracts/utils/console.sol';
import { Helper } from './shared/helper.t.sol';
import { Errors } from './shared/errors.t.sol';

contract TestMyMultiSig is Helper {
  function setUp() public {
    initialize_helper(LOG_LEVEL, TestType.TestWithoutFactory);
  }

  function testMyMultiSig() public {
    assertTrue(true);
  }
}
