// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Helper } from './shared/helper.t.sol';
import { MyMultiSig } from '../MyMultiSig.sol';

/// @title signMessage / EIP-1271 off-chain-auth Foundry tests
/// @notice Covers the on-chain message-signing surface of the base wallet:
///         1. `getMessageHash` binds the message into the wallet's
///            EIP-712 domain (`MyMultiSigMessage(bytes message)`).
///         2. `signMessage` requires threshold consensus (`onlyThis`) and
///            flips the EIP-1271 empty-signature path to the magic value.
///         3. `unsignMessage` withdraws the approval.
///         4. The threshold-signature EIP-1271 path keeps working.
contract MyMultiSigSignMessageTest is Helper {
  bytes4 internal constant MAGIC = 0x1626ba7e;
  bytes4 internal constant NOT_MAGIC = 0xffffffff;

  function setUp() public {
    initialize_helper(LOG_LEVEL, TestType.TestWithoutFactory);
  }

  function _ownersPk() internal view returns (uint256[] memory pks) {
    pks = new uint256[](2);
    pks[0] = OWNERS_PK[0];
    pks[1] = OWNERS_PK[1];
  }

  /// @dev Runs `signMessage(message)` (or `unsignMessage`) through a
  ///      threshold-signed `execTransaction`.
  function _execSignMessage(bytes memory message, bool sign) internal {
    bytes memory data = sign
      ? abi.encodeWithSignature('signMessage(bytes)', message)
      : abi.encodeWithSignature('unsignMessage(bytes)', message);
    help_execTransaction(
      myMultiSig,
      OWNERS[0],
      address(myMultiSig),
      0,
      data,
      DEFAULT_GAS,
      build_signatures(myMultiSig, _ownersPk(), address(myMultiSig), 0, data, DEFAULT_GAS)
    );
  }

  function test_getMessageHash_matches_manual_eip712() public {
    bytes memory message = bytes('prove wallet control');
    bytes32 domainSeparator = build_domainSeparator(myMultiSig, CONTRACT_NAME);
    bytes32 structHash = keccak256(
      abi.encode(keccak256('MyMultiSigMessage(bytes message)'), keccak256(message))
    );
    bytes32 expected = keccak256(abi.encodePacked('\x19\x01', domainSeparator, structHash));
    assertEq(myMultiSig.getMessageHash(message), expected);
  }

  function test_signMessage_direct_call_reverts_onlyThis() public {
    vm.prank(OWNERS[0]);
    vm.expectRevert(abi.encodeWithSignature('OnlyThisContract()'));
    myMultiSig.signMessage(bytes('nope'));
  }

  function test_signMessage_enables_empty_signature_eip1271() public {
    bytes32 dataHash = keccak256('siwe:login:mymultisig.app');
    bytes memory message = abi.encode(dataHash);

    // Unsigned wallet: the empty-signature path must NOT validate.
    assertEq(myMultiSig.isValidSignature(dataHash, bytes('')), NOT_MAGIC);
    assertFalse(myMultiSig.isMessageSigned(myMultiSig.getMessageHash(message)));

    _execSignMessage(message, true);

    assertTrue(myMultiSig.isMessageSigned(myMultiSig.getMessageHash(message)));
    assertEq(myMultiSig.isValidSignature(dataHash, bytes('')), MAGIC);
  }

  function test_signMessage_is_wallet_specific() public {
    bytes32 dataHash = keccak256('shared payload');
    _execSignMessage(abi.encode(dataHash), true);
    assertEq(myMultiSig.isValidSignature(dataHash, bytes('')), MAGIC);

    // A sibling wallet with the same owners never signed the message, so
    // its empty-signature path must reject the same dataHash.
    MyMultiSig sibling = new MyMultiSig(CONTRACT_NAME, OWNERS, DEFAULT_THRESHOLD);
    assertEq(sibling.isValidSignature(dataHash, bytes('')), NOT_MAGIC);
  }

  function test_unsignMessage_withdraws_approval() public {
    bytes32 dataHash = keccak256('temporary authorization');
    bytes memory message = abi.encode(dataHash);
    _execSignMessage(message, true);
    assertEq(myMultiSig.isValidSignature(dataHash, bytes('')), MAGIC);

    _execSignMessage(message, false);
    assertFalse(myMultiSig.isMessageSigned(myMultiSig.getMessageHash(message)));
    assertEq(myMultiSig.isValidSignature(dataHash, bytes('')), NOT_MAGIC);
  }

  function test_unsignMessage_reverts_when_never_signed() public {
    vm.prank(address(myMultiSig));
    vm.expectRevert(abi.encodeWithSignature('MessageNotSigned()'));
    myMultiSig.unsignMessage(bytes('never signed'));
  }

  function test_threshold_signature_path_still_validates() public {
    // The pre-existing EIP-1271 behavior — threshold owner votes over an
    // arbitrary hash — must keep working alongside the stored-message path.
    bytes32 hash = keccak256('external protocol digest');
    Vote[] memory votes = new Vote[](2);
    for (uint256 i = 0; i < 2; i++) {
      (uint8 v, bytes32 r, bytes32 s) = vm.sign(OWNERS_PK[i], hash);
      votes[i] = Vote({ owner: OWNERS[i], sig: abi.encodePacked(r, s, v) });
    }
    assertEq(myMultiSig.isValidSignature(hash, abi.encode(votes)), MAGIC);
    assertEq(myMultiSig.isValidSignature(keccak256('other digest'), abi.encode(votes)), NOT_MAGIC);
  }
}
