export default {
  ONLY_SELF: 'MyMultiSig: only this contract can call this function',
  TOO_MANY_OWNERS: 'MyMultiSig: cannot add owner above 2^16 - 1',
  INVALID_SIGNATURES: 'MyMultiSig: invalid signatures',
  NOT_ENOUGH_GAS: 'MyMultiSig: not enough gas',
  NO_CONTRACT_SIGNATURE: 'MyMultiSig: No contract signatures support',
  OWNER_ALREADY_SIGNED: 'MyMultiSig: owner already signed',
  CANNOT_REMOVE_OWNERS_BELOW_THRESHOLD: 'MyMultiSig: cannot remove owner below threshold',

  THRESHOLD_MUST_BE_GREATER_THAN_ZERO: 'MyMultiSig: threshold must be greater than 0',
  THRESHOLD_MUST_BE_LESS_OR_EQUAL_TO_OWNERS_COUNT: 'MyMultiSig: threshold must be less than or equal to owner count',

  THRESHOLD_NOT_ACHIEVED: 'MyMultiSig: signatures did not reach threshold',
  INVALID_OWNER: 'MyMultiSig: invalid owner',

  OLD_OWNER_NOT_OWNER: 'MyMultiSig: old owner must be an owner',
  NEW_OWNER_ALREADY_OWNER: 'MyMultiSig: new owner must not be an owner',
  NEW_OWNER_IS_ZERO_ADDRESS: 'MyMultiSig: new owner must not be the zero address',

  PANIC_CODE_0x11:
    'VM Exception while processing transaction: reverted with panic code 0x11 (Arithmetic operation underflowed or overflowed outside of an unchecked block)',
}
