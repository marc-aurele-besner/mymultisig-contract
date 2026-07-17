// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Test } from 'forge-std/Test.sol';

import { MyMultiSig } from '../../MyMultiSig.sol';
import { MyMultiSigExtended } from '../../MyMultiSigExtended.sol';

/// @title Errors
/// @notice Maps a `RevertStatus` enum to the exact custom-error selector emitted
///         by `MyMultiSig`, then exposes a `verify_revertCall` helper that stages
///         the expected `vm.expectRevert` on the next call.
/// @dev    Previously inherited from `DSTest` (re-exported by the now-removed
///         `foundry-test-utility`). Switched to `forge-std/Test` so the suite
///         no longer depends on a private npm package. Revert reasons moved from
///         `require`-strings to custom errors, so the map stores 4-byte selectors.
contract Errors is Test {
  enum RevertStatus {
    Success,
    SkipValidation,
    OnlyThisContract,
    TooManyOwners,
    InvalidSignatures,
    SignatureExpired,
    NotApproved,
    NotOwner,
    CannotRemoveOwnerBelowThreshold,
    ThresholdMustBeGreaterThanZero,
    ThresholdMustBeLessOrEqualThanNumberOfOwners,
    OldOwnerMustBeOwner,
    NewOwnerMustNotBeOwner,
    NewOwnerMustNotBeZero,
    BatchCallFailed,
    ArrayLengthMismatch,
    TxSuccessRequired,
    OwnerToRemoveMustBeOwner,
    ScheduleNonceNotCurrent
  }

  mapping(RevertStatus => bytes4) private _errors;

  // Associate each revert status with the custom-error selector produced by MyMultiSig.
  constructor() {
    _errors[RevertStatus.OnlyThisContract] = MyMultiSig.OnlyThisContract.selector;
    _errors[RevertStatus.TooManyOwners] = MyMultiSig.TooManyOwners.selector;
    _errors[RevertStatus.InvalidSignatures] = MyMultiSig.InvalidSignatures.selector;
    _errors[RevertStatus.SignatureExpired] = MyMultiSig.SignatureExpired.selector;
    _errors[RevertStatus.NotApproved] = MyMultiSig.NotApproved.selector;
    _errors[RevertStatus.NotOwner] = MyMultiSig.NotOwner.selector;
    _errors[RevertStatus.CannotRemoveOwnerBelowThreshold] = MyMultiSig.CannotRemoveOwnerBelowThreshold.selector;
    _errors[RevertStatus.ThresholdMustBeGreaterThanZero] = MyMultiSig.ThresholdMustBeGreaterThanZero.selector;
    _errors[
      RevertStatus.ThresholdMustBeLessOrEqualThanNumberOfOwners
    ] = MyMultiSig.ThresholdMustBeLessOrEqualToOwnerCount.selector;
    _errors[RevertStatus.OldOwnerMustBeOwner] = MyMultiSig.OldOwnerMustBeOwner.selector;
    _errors[RevertStatus.NewOwnerMustNotBeOwner] = MyMultiSig.NewOwnerMustNotBeOwner.selector;
    _errors[RevertStatus.NewOwnerMustNotBeZero] = MyMultiSig.NewOwnerMustNotBeZero.selector;
    _errors[RevertStatus.BatchCallFailed] = MyMultiSig.BatchCallFailed.selector;
    _errors[RevertStatus.ArrayLengthMismatch] = MyMultiSig.ArrayLengthMismatch.selector;
    _errors[RevertStatus.TxSuccessRequired] = MyMultiSig.TxSuccessRequired.selector;
    _errors[RevertStatus.OwnerToRemoveMustBeOwner] = MyMultiSig.OwnerToRemoveMustBeOwner.selector;
    _errors[RevertStatus.ScheduleNonceNotCurrent] = MyMultiSigExtended.ScheduleNonceNotCurrent.selector;
  }

  function _verify_revertCall(RevertStatus revertType_) internal view returns (bytes4) {
    return _errors[revertType_];
  }

  /// @notice Stages a `vm.expectRevert` with the selector associated to
  ///         `revertType_`. `Success` and `SkipValidation` do not stage a revert.
  function verify_revertCall(RevertStatus revertType_) public {
    if (revertType_ != RevertStatus.Success && revertType_ != RevertStatus.SkipValidation)
      vm.expectRevert(_verify_revertCall(revertType_));
  }
}