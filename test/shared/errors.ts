// Custom-error names as declared on MyMultiSig / MyMultiSigExtended. Asserted
// with `revertedWithCustomError(contract, name)` (see test/shared/functions.ts).
export default {
  ONLY_SELF: 'OnlyThisContract',
  TOO_MANY_OWNERS: 'TooManyOwners',
  INVALID_SIGNATURES: 'InvalidSignatures',
  SIGNATURE_EXPIRED: 'SignatureExpired',
  NOT_ENOUGH_GAS: 'NotEnoughGas',
  NOT_APPROVED: 'NotApproved',
  BATCH_CALL_FAILED: 'BatchCallFailed',
  NONCE_ALREADY_USED: 'NonceAlreadyUsed',
  NOT_OWNER: 'NotOwner',
  CANNOT_REMOVE_OWNERS_BELOW_THRESHOLD: 'CannotRemoveOwnerBelowThreshold',

  THRESHOLD_MUST_BE_GREATER_THAN_ZERO: 'ThresholdMustBeGreaterThanZero',
  THRESHOLD_MUST_BE_LESS_OR_EQUAL_TO_OWNERS_COUNT: 'ThresholdMustBeLessOrEqualToOwnerCount',

  OLD_OWNER_NOT_OWNER: 'OldOwnerMustBeOwner',
  NEW_OWNER_ALREADY_OWNER: 'NewOwnerMustNotBeOwner',
  NEW_OWNER_IS_ZERO_ADDRESS: 'NewOwnerMustNotBeZero',

  OWNER_SETTINGS_MUST_BE_GREATER_THAN_MINIMUM: 'TransferInactiveOwnershipBelowMinimum',
  OWNER_SETTINGS_TRANSFER_INACTIVE_TOO_SHORT: 'TransferInactiveOwnershipTooShort',
  OWNER_SETTINGS_DELEGATEE_MUST_NOT_BE_OWNER: 'DelegateeAlreadyOwnerOrDelegatee',
  OWNER_SETTINGS_OWNER_MUST_BE_OWNER: 'OwnerMustBeAnOwner',
  OWNER_STILL_ACTIVE: 'OwnerStillActive',
  SENDER_NOT_DELEGATEE: 'SenderNotDelegatee',

  PANIC_CODE_0x11:
    'VM Exception while processing transaction: reverted with panic code 0x11 (Arithmetic operation underflowed or overflowed outside of an unchecked block)',
}
