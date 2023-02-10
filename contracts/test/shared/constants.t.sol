// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Constants {
  // Constants value specific to the contracts we are testing.
  string constant CONTRACT_FACTORY_NAME = 'MyMultiSigFactory';
  string constant CONTRACT_FACTORY_VERSION = '0.0.2';
  string constant CONTRACT_NAME = 'MyMultiSig';
  string constant CONTRACT_VERSION = '0.0.2';

  uint16 constant DEFAULT_THRESHOLD = 2;
  uint256 constant DEFAULT_GAS = 30000;

  address[] public OWNERS;

  address ADMIN = address(42_000);

  constructor() {
    OWNERS.push(address(1));
    OWNERS.push(address(2));
    OWNERS.push(address(3));
  }
}
