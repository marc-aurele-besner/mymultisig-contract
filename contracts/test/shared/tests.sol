// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import 'foundry-test-utility/contracts/utils/console.sol';
import { Helper } from './helper.t.sol';
import { Errors } from './errors.t.sol';

abstract contract Scenario_Basic is Helper {
  address[] buildTo;
  uint256[] buildValue;
  bytes[] buildData;
  uint256[] buildGas;

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

  function testMyMultiSig_multiRequest_add3Owners() public {
    uint256 NEW_OWNERS_COUNT = 3;
    for (uint256 i = 0; i < NEW_OWNERS_COUNT; i++) {
      buildTo.push(address(myMultiSig));
      buildValue.push(0);
      buildData.push(build_addOwner(NOT_OWNERS[i]));
      buildGas.push(DEFAULT_GAS);
    }

    help_multiRequest(OWNERS[0], myMultiSig, OWNERS_PK, buildTo, buildValue, buildData, buildGas);

    for (uint256 i = 0; i < NEW_OWNERS_COUNT; i++) {
      assertTrue(myMultiSig.isOwner(NOT_OWNERS[i]));
    }
  }

  function testMyMultiSig_multiRequest_add5Owners() public {
    uint256 NEW_OWNERS_COUNT = 5;
    for (uint256 i = 0; i < NEW_OWNERS_COUNT; i++) {
      buildTo.push(address(myMultiSig));
      buildValue.push(0);
      buildData.push(build_addOwner(NOT_OWNERS[i]));
      buildGas.push(DEFAULT_GAS);
    }

    help_multiRequest(OWNERS[0], myMultiSig, OWNERS_PK, buildTo, buildValue, buildData, buildGas);

    for (uint256 i = 0; i < NEW_OWNERS_COUNT; i++) {
      assertTrue(myMultiSig.isOwner(NOT_OWNERS[i]));
    }
  }

  function testMyMultiSig_multiRequest_add20Owners() public {
    uint256 NEW_OWNERS_COUNT = 20;
    for (uint256 i = 0; i < NEW_OWNERS_COUNT; i++) {
      buildTo.push(address(myMultiSig));
      buildValue.push(0);
      buildData.push(build_addOwner(NOT_OWNERS[i]));
      buildGas.push(DEFAULT_GAS);
    }

    help_multiRequest(OWNERS[0], myMultiSig, OWNERS_PK, buildTo, buildValue, buildData, buildGas);

    for (uint256 i = 0; i < NEW_OWNERS_COUNT; i++) {
      assertTrue(myMultiSig.isOwner(NOT_OWNERS[i]));
    }
  }

  function testMyMultiSig_multiRequest_add100Owners() public {
    uint256 NEW_OWNERS_COUNT = 100;
    for (uint256 i = 0; i < NEW_OWNERS_COUNT; i++) {
      buildTo.push(address(myMultiSig));
      buildValue.push(0);
      buildData.push(build_addOwner(NOT_OWNERS[i]));
      buildGas.push(DEFAULT_GAS);
    }

    help_multiRequest(OWNERS[0], myMultiSig, OWNERS_PK, buildTo, buildValue, buildData, buildGas);

    for (uint256 i = 0; i < NEW_OWNERS_COUNT; i++) {
      assertTrue(myMultiSig.isOwner(NOT_OWNERS[i]));
    }
  }

  function testMyMultiSig_multiRequest_add100Owners_then_remove10Owner() public {
    uint256 NEW_OWNERS_COUNT = 100;
    for (uint256 i = 0; i < NEW_OWNERS_COUNT; i++) {
      buildTo.push(address(myMultiSig));
      buildValue.push(0);
      buildData.push(build_addOwner(NOT_OWNERS[i]));
      buildGas.push(DEFAULT_GAS);
    }

    help_multiRequest(OWNERS[0], myMultiSig, OWNERS_PK, buildTo, buildValue, buildData, buildGas);

    for (uint256 i = 0; i < NEW_OWNERS_COUNT; i++) {
      assertTrue(myMultiSig.isOwner(NOT_OWNERS[i]));
    }

    for (uint256 i = 0; i < NEW_OWNERS_COUNT; i++) {
      buildData[i] = build_removeOwner(NOT_OWNERS[i]);
    }

    help_multiRequest(OWNERS[0], myMultiSig, OWNERS_PK, buildTo, buildValue, buildData, buildGas);

    for (uint256 i = 0; i < NEW_OWNERS_COUNT; i++) {
      assertTrue(!myMultiSig.isOwner(NOT_OWNERS[i]));
    }
  }

  function testMyMultiSig_multiRequest_replaceAllOwners() public {
    for (uint256 i = 0; i < OWNERS_COUNT; i++) {
      buildTo.push(address(myMultiSig));
      buildValue.push(0);
      buildData.push(build_replaceOwner(OWNERS[i], NOT_OWNERS[i]));
      buildGas.push(DEFAULT_GAS);
    }

    help_multiRequest(OWNERS[0], myMultiSig, OWNERS_PK, buildTo, buildValue, buildData, buildGas);

    for (uint256 i = 0; i < OWNERS_COUNT; i++) {
      assertTrue(!myMultiSig.isOwner(OWNERS[i]));
      assertTrue(myMultiSig.isOwner(NOT_OWNERS[i]));
    }
  }

  function testMyMultiSig_multiRequest_replace100Owners() public {
    uint256 NEW_OWNERS_COUNT = 100;

    buildTo.push(address(myMultiSig));
    buildValue.push(0);
    buildData.push(build_replaceOwner(OWNERS[0], NOT_OWNERS[0]));
    buildGas.push(DEFAULT_GAS);

    for (uint256 i = 0; i < NEW_OWNERS_COUNT; i++) {
      buildTo.push(address(myMultiSig));
      buildValue.push(0);
      buildData.push(build_replaceOwner(NOT_OWNERS[i], NOT_OWNERS[i + 1]));
      buildGas.push(DEFAULT_GAS);
    }

    help_multiRequest(OWNERS[0], myMultiSig, OWNERS_PK, buildTo, buildValue, buildData, buildGas);

    assertTrue(!myMultiSig.isOwner(OWNERS[0]));
    for (uint256 i = 0; i < NEW_OWNERS_COUNT; i++) {
      assertTrue(!myMultiSig.isOwner(NOT_OWNERS[i]));
    }
    assertTrue(myMultiSig.isOwner(NOT_OWNERS[100]));
  }
}
