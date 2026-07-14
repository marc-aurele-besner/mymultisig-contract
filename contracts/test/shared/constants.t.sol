// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Errors } from './errors.t.sol';

contract Constants is Errors {
  // Constants value specific to the contracts we are testing.
  string constant CONTRACT_FACTORY_NAME = 'MyMultiSigFactory';
  string constant CONTRACT_FACTORY_VERSION = '0.1.1';
  string constant CONTRACT_NAME = 'MyMultiSig';
  string constant CONTRACT_VERSION = '0.1.4';

  uint16 public DEFAULT_THRESHOLD = 2;
  bool public ONLY_OWNERS_REQUEST = true;
  // Inner-call gas budget passed to `execTransaction` / `multiRequest` by
  // the test helpers. Bumped from 75_000 to 200_000 so the per-call budget
  // accommodates the additional storage writes that `getOwners()` needs to
  // maintain an enumerable owner list (`_ownerList` + `_ownerIndex`) on
  // every `addOwner` / `removeOwner` / `replaceOwner`. With 75_000 a single
  // `addOwner` consumes ~73,000 gas in `MyMultiSigExtended` and the
  // `NotEnoughGas` check trips because the budget is checked with `>=`.
  uint256 public DEFAULT_GAS = 200_000;

  uint256 public OWNERS_COUNT = 5;
  uint256[] public OWNERS_PK;
  address[] public OWNERS;

  uint256 public NOT_OWNERS_COUNT = 200;
  uint256[] public NOT_OWNERS_PK;
  address[] public NOT_OWNERS;

  address public ADMIN = address(42_000);

  constructor() {
    for (uint256 i = 1; i <= OWNERS_COUNT; i++) {
      OWNERS_PK.push(i);
      OWNERS.push(vm.addr(i));
    }
    for (uint256 i = 1; i <= NOT_OWNERS_COUNT; i++) {
      NOT_OWNERS_PK.push(i + 100);
      NOT_OWNERS.push(vm.addr(i + 100));
    }
  }
}
