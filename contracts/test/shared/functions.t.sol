// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import 'foundry-test-utility/contracts/utils/console.sol';
import { CheatCodes } from 'foundry-test-utility/contracts/utils/cheatcodes.sol';

import { Constants } from './constants.t.sol';
import { Errors } from './errors.t.sol';

import { MyMultiSigFactory } from '../../MyMultiSigFactory.sol';
import { MyMultiSig } from '../../MyMultiSig.sol';

contract Functions is Constants, Errors {
  uint8 LOG_LEVEL;
  uint256 DEFAULT_BLOCKS_COUNT;

  MyMultiSigFactory public myMultiSigFactory;
  MyMultiSig public myMultiSig;

  enum TestType {
    TestWithFactory,
    TestWithoutFactory
  }

  function initialize_tests(uint8 LOG_LEVEL_, TestType testType_) public returns (MyMultiSigFactory, MyMultiSig) {
    // Set general test settings
    LOG_LEVEL = LOG_LEVEL_;
    vm.roll(1);
    vm.warp(100);
    vm.prank(ADMIN);

    if (testType_ == TestType.TestWithFactory) {
      myMultiSigFactory = new MyMultiSigFactory();
      (, myMultiSig) = help_createMultiSig(ADMIN, CONTRACT_NAME, OWNERS, DEFAULT_THRESHOLD);
    } else {
      myMultiSig = new MyMultiSig(CONTRACT_NAME, OWNERS, DEFAULT_THRESHOLD);
    }

    vm.roll(block.number + 1);
    vm.warp(block.timestamp + 100);

    return (myMultiSigFactory, myMultiSig);
  }

  // MyMultiSigFactory
  function help_createMultiSig(
    address prank_,
    string memory contractName_,
    address[] memory owners_,
    uint16 threshold_,
    Errors.RevertStatus revertType_
  ) internal returns (uint256 multiSigId, MyMultiSig newMultiSig) {
    vm.prank(prank_);
    verify_revertCall(revertType_);
    myMultiSigFactory.createMultiSig(contractName_, owners_, threshold_);

    if (revertType_ == Errors.RevertStatus.Success) {
      multiSigId = myMultiSigFactory.multiSigCount();
      newMultiSig = MyMultiSig(myMultiSigFactory.multiSig(multiSigId - 1));
      assertEq(newMultiSig.name(), contractName_);
      assertEq(newMultiSig.threshold(), threshold_);
      uint256 ownersLength = owners_.length;
      assertEq(newMultiSig.ownerCount(), ownersLength);
      for (uint256 i = 0; i < ownersLength; i++) {
        assertTrue(newMultiSig.isOwner(owners_[i]));
      }
    }
  }

  function help_createMultiSig(
    address prank_,
    string memory contractName_,
    address[] memory owners_,
    uint16 threshold_
  ) internal returns (uint256 multiSigId, MyMultiSig newMultiSig) {
    return help_createMultiSig(prank_, contractName_, owners_, threshold_, Errors.RevertStatus.Success);
  }

  // MyMultiSigFactory
  function help_execTransaction(
    MyMultiSig multiSig_,
    address prank_,
    address to_,
    uint256 value_,
    bytes memory data_,
    uint256 txnGas_,
    bytes memory signatures_,
    Errors.RevertStatus revertType_
  ) internal {
    vm.prank(prank_);
    verify_revertCall(revertType_);
    multiSig_.execTransaction(to_, value_, data_, txnGas_, signatures_);

    if (revertType_ == Errors.RevertStatus.Success) {}
  }

  function help_execTransaction(
    MyMultiSig multiSig_,
    address prank_,
    address to_,
    uint256 value_,
    bytes memory data_,
    uint256 txnGas_,
    bytes memory signatures_
  ) internal {
    help_execTransaction(multiSig_, prank_, to_, value_, data_, txnGas_, signatures_, Errors.RevertStatus.Success);
  }
}
