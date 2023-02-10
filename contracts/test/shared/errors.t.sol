// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Vm } from 'foundry-test-utility/contracts/utils/vm.sol';
import { DSTest } from 'foundry-test-utility/contracts/utils/test.sol';

contract Errors is DSTest {
  Vm public constant vm = Vm(address(uint160(uint256(keccak256('hevm cheat code')))));

  mapping(RevertStatus => string) private _errors;

  // Add a revert error to the enum of errors.
  enum RevertStatus {
    Success,
    SkipValidation,
    OnlyThisContract,
    TooManyOwners,
    InvalidSignatures,
    InvalidOwners,
    OwnerAlreadySigned,
    CannotRemoveOwnerBelowThreshold,
    ThresholdMustBeGreaterThanZero,
    ThresholdMustBeLessOrEqualThanNumberOfOwners,
    OldOwnerMustBeOwner,
    NewOwnerMustNotBeOwner,
    NewOwnerMustNotBeZero
  }

  // Associate your error with a revert message and add it to the mapping.
  constructor() {
    _errors[RevertStatus.OnlyThisContract] = 'MyMultiSig: only this contract can call this function';
    _errors[RevertStatus.TooManyOwners] = 'MyMultiSig: cannot add owner above 2^16 - 1';
    _errors[RevertStatus.InvalidSignatures] = 'MyMultiSig: invalid signatures';
    _errors[RevertStatus.InvalidOwners] = 'MyMultiSig: invalid owner';
    _errors[RevertStatus.OwnerAlreadySigned] = 'MyMultiSig: owner already signed';
    _errors[RevertStatus.CannotRemoveOwnerBelowThreshold] = 'MyMultiSig: cannot remove owner below threshold';
    _errors[RevertStatus.ThresholdMustBeGreaterThanZero] = 'MyMultiSig: threshold must be greater than 0';
    _errors[
      RevertStatus.ThresholdMustBeLessOrEqualThanNumberOfOwners
    ] = 'MyMultiSig: threshold must be less than or equal to owner count';
    _errors[RevertStatus.OldOwnerMustBeOwner] = 'MyMultiSig: old owner must be an owner';
    _errors[RevertStatus.NewOwnerMustNotBeOwner] = 'MyMultiSig: new owner must not be an owner';
    _errors[RevertStatus.NewOwnerMustNotBeZero] = 'MyMultiSig: new owner must not be the zero address';
  }

  // Return the error message associated with the error.
  function _verify_revertCall(RevertStatus revertType_) internal view returns (string storage) {
    return _errors[revertType_];
  }

  // Expect a revert error if the revert type is not success.
  function verify_revertCall(RevertStatus revertType_) public {
    if (revertType_ != RevertStatus.Success && revertType_ != RevertStatus.SkipValidation)
      vm.expectRevert(bytes(_verify_revertCall(revertType_)));
  }
}
