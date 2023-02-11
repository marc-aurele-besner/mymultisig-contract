// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import 'foundry-test-utility/contracts/utils/console.sol';
import { Helper } from './shared/helper.t.sol';
import { Errors } from './shared/errors.t.sol';

contract TestMyMultiSig is Helper {
  address[] buildTo;
  uint256[] buildValue;
  bytes[] buildData;
  uint256[] buildGas;

  function setUp() public {
    initialize_helper(LOG_LEVEL, TestType.TestWithoutFactory);
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

  function testMyMultiSig_addOwner() public {
    help_addOwner(OWNERS[0], myMultiSig, OWNERS_PK, NOT_OWNERS[0]);
  }

  function testMyMultiSig_removeOwner() public {
    help_removeOwner(OWNERS[0], myMultiSig, OWNERS_PK, OWNERS[0]);
  }

  function testMyMultiSig_changeThreshold() public {
    help_changeThreshold(OWNERS[0], myMultiSig, OWNERS_PK, 3);
  }

  function testMyMultiSig_replaceOwner() public {
    help_replaceOwner(OWNERS[0], myMultiSig, OWNERS_PK, OWNERS[0], NOT_OWNERS[0]);
  }

  // function testMyMultiSig_multiRequest() public {
  //   buildTo.push(address(myMultiSig));
  //   buildTo.push(address(myMultiSig));
  //   buildTo.push(address(myMultiSig));

  //   buildValue.push(0);
  //   buildValue.push(0);
  //   buildValue.push(0);

  //   buildData.push(build_addOwner(NOT_OWNERS[0]));
  //   buildData.push(build_addOwner(NOT_OWNERS[1]));
  //   buildData.push(build_addOwner(NOT_OWNERS[2]));

  //   buildGas.push(DEFAULT_GAS);
  //   buildGas.push(DEFAULT_GAS);
  //   buildGas.push(DEFAULT_GAS);

  //   help_multiRequest(OWNERS[0], myMultiSig, OWNERS_PK, buildTo, buildValue, buildData, buildGas);
  // }
}
