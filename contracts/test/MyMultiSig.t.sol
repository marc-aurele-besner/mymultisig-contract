// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import { MyMultiSig } from '../MyMultiSig.sol';

contract TestMyMultiSig {
  MyMultiSig myMultiSig;

  function setUp() public {
    myMultiSig = new MyMultiSig();
  }

  function testMyMultiSig() public {
    assertTrue(true);
  }
}
