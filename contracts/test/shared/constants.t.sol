// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Errors } from './errors.t.sol';

contract Constants is Errors {
  // Constants value specific to the contracts we are testing.
  string constant CONTRACT_FACTORY_NAME = 'MyMultiSigFactory';
  string constant CONTRACT_FACTORY_VERSION = '0.0.2';
  string constant CONTRACT_NAME = 'MyMultiSig';
  string constant CONTRACT_VERSION = '0.0.2';

  uint16 constant DEFAULT_THRESHOLD = 2;
  uint256 constant DEFAULT_GAS = 30000;

  uint256 public constant OWNERS_COUNT = 5;
  uint256[] public OWNERS_PK;
  address[] public OWNERS;

  uint256 public constant NOT_OWNERS_COUNT = 5;
  uint256[] public NOT_OWNERS_PK;
  address[] public NOT_OWNERS;

  address ADMIN = address(42_000);

  constructor() {
    for (uint256 i = 1; i < OWNERS_COUNT; i++) {
      OWNERS_PK.push(i);
      OWNERS.push(vm.addr(i));
    }
    for (uint256 i = 1; i < NOT_OWNERS_COUNT; i++) {
      NOT_OWNERS_PK.push(i + 100);
      NOT_OWNERS.push(vm.addr(i + 100));
    }
  }
}
