// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import 'foundry-test-utility/contracts/utils/console.sol';
import { Helper } from './shared/helper.t.sol';
import { Errors } from './shared/errors.t.sol';

contract TestMyMultiSigFactory is Helper {
  function setUp() public {
    initialize_helper(LOG_LEVEL, TestType.TestWithFactory);
  }

  function testMyMultiSigFactory_name() public {
    assertEq(myMultiSigFactory.name(), CONTRACT_FACTORY_NAME);
  }

  function testMyMultiSigFactory_version() public {
    assertEq(myMultiSigFactory.version(), CONTRACT_FACTORY_VERSION);
  }

  function testMyMultiSigFactory_multiSigCount() public {
    assertEq(myMultiSigFactory.multiSigCount(), 1);
  }

  function testMyMultiSigFactory_multiSig() public {
    assertEq(myMultiSigFactory.multiSig(0), address(myMultiSig));
  }

  function testMyMultiSig_createMultiSig() public {
    help_createMultiSig(ADMIN, CONTRACT_NAME, OWNERS, DEFAULT_THRESHOLD, Errors.RevertStatus.Success);
  }

  function testMyMultiSig_name() public {
    assertEq(myMultiSig.name(), CONTRACT_NAME);
  }

  function testMyMultiSig_version() public {
    assertEq(myMultiSig.version(), CONTRACT_VERSION);
  }

  function testMyMultiSig_threshold() public {
    assertEq(myMultiSig.threshold(), DEFAULT_THRESHOLD);
  }

  function testMyMultiSig_ownerCount() public {
    assertEq(myMultiSig.ownerCount(), OWNERS.length);
  }

  function testMyMultiSig_nonce() public {
    assertEq(myMultiSig.nonce(), 0);
  }

  function testMyMultiSig_isOwnerAll() public {
    for (uint256 i = 0; i < OWNERS.length; i++) {
      assertTrue(myMultiSig.isOwner(OWNERS[i]));
    }
  }
}
