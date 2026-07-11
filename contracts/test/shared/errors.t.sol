// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Test } from 'forge-std/Test.sol';

/// @title Errors
/// @notice Maps a `RevertStatus` enum to the exact revert message emitted by
///         `MyMultiSig`, then exposes a `verify_revertCall` helper that
///         stages the expected `vm.expectRevert` on the next call.
/// @dev    Previously inherited from `DSTest` (re-exported by the now-removed
///         `foundry-test-utility`). Switched to `forge-std/Test` so the suite
///         no longer depends on a private npm package.
contract Errors is Test {
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

  mapping(RevertStatus => string) private _errors;

  // Associate each revert status with the exact revert message produced by MyMultiSig.
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

  function _verify_revertCall(RevertStatus revertType_) internal view returns (string storage) {
    return _errors[revertType_];
  }

  /// @notice Stages a `vm.expectRevert` with the message associated to
  ///         `revertType_`. `Success` and `SkipValidation` do not stage a revert.
  function verify_revertCall(RevertStatus revertType_) public {
    if (revertType_ != RevertStatus.Success && revertType_ != RevertStatus.SkipValidation)
      vm.expectRevert(bytes(_verify_revertCall(revertType_)));
  }
}