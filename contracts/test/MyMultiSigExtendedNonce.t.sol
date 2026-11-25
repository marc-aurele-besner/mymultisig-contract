// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Helper } from './shared/helper.t.sol';
import { MyMultiSigExtended } from '../MyMultiSigExtended.sol';
import './shared/mocks/MockEntryPoint.t.sol';

/// @title MyMultiSigExtended nonce consumption
/// @notice The 8-arg `execTransaction` overload takes an explicit nonce.
///         These tests pin down that a nonce can be executed at most once,
///         that every nonce below `nonce()` is dead, and that
///         `markNonceAsUsed` cancels a pending nonce immediately.
contract MyMultiSigExtendedNonceTest is Helper {
  MyMultiSigExtended internal wallet;
  address internal constant BOB = address(0xb0b);
  uint256 internal constant TXN_GAS = 50_000;

  function setUp() public {
    (myMultiSigFactory, myMultiSig) = initialize_tests(LOG_LEVEL, TestType.TestWithFactory);

    address[] memory owners = new address[](4);
    for (uint256 i = 0; i < 4; i++) owners[i] = OWNERS[i];

    // 2-of-4: a fully signed request carries two surplus signatures.
    wallet = new MyMultiSigExtended('NonceWallet', owners, 2, ONLY_OWNERS_REQUEST, address(new MockEntryPoint()));
    vm.deal(address(wallet), 10 ether);
  }

  /// @dev Signs the 7-field (`operation`-bound) payload for `nonce_` with
  ///      the two owners at indexes `a` and `b`.
  function _sign(
    address to,
    uint256 value,
    bytes memory data,
    uint256 nonce_,
    uint256 a,
    uint256 b
  ) internal returns (bytes memory) {
    bytes32 domainSeparator = build_domainSeparator(wallet, wallet.name());
    bytes32 typehash = keccak256(
      'Transaction(address to,uint256 value,bytes data,uint256 gas,uint96 nonce,uint256 validUntil,uint8 operation)'
    );
    bytes32 structHash = keccak256(
      abi.encode(typehash, to, value, keccak256(data), TXN_GAS, nonce_, uint256(0), uint8(0))
    );
    Vote[] memory votes = new Vote[](2);
    votes[0] = Vote({ owner: OWNERS[a], sig: signature_signHashed(OWNERS_PK[a], domainSeparator, structHash) });
    votes[1] = Vote({ owner: OWNERS[b], sig: signature_signHashed(OWNERS_PK[b], domainSeparator, structHash) });
    return abi.encode(votes);
  }

  function _exec(address to, uint256 value, bytes memory data, uint256 nonce_, bytes memory sigs) internal {
    vm.prank(OWNERS[0]);
    wallet.execTransaction(to, value, data, TXN_GAS, nonce_, 0, 0, sigs);
  }

  function test_surplusSignatures_cannotReplayExecutedNonce() public {
    bytes memory noData;
    bytes memory sigsAB = _sign(BOB, 1 ether, noData, 0, 0, 1);
    bytes memory sigsCD = _sign(BOB, 1 ether, noData, 0, 2, 3);

    _exec(BOB, 1 ether, noData, 0, sigsAB);
    assertEq(BOB.balance, 1 ether);
    assertEq(wallet.nonce(), 1);
    assertTrue(wallet.isNonceUsed(0));
    assertFalse(wallet.isValidSignature(BOB, 1 ether, noData, TXN_GAS, 0, 0, 0, sigsCD));

    vm.expectRevert(abi.encodeWithSelector(MyMultiSigExtended.NonceTooLow.selector, 0, 1));
    _exec(BOB, 1 ether, noData, 0, sigsCD);
    assertEq(BOB.balance, 1 ether);
  }

  function test_incrementNonce_killsAbandonedRequest() public {
    bytes memory noData;
    bytes memory abandoned = _sign(BOB, 1 ether, noData, 0, 2, 3);

    bytes memory bump = abi.encodeWithSignature('incrementNonce()');
    _exec(address(wallet), 0, bump, 0, _sign(address(wallet), 0, bump, 0, 0, 1));
    // The execution consumes nonce 0, then `incrementNonce` skips nonce 1.
    assertEq(wallet.nonce(), 2);

    vm.expectRevert(abi.encodeWithSelector(MyMultiSigExtended.NonceTooLow.selector, 0, 2));
    _exec(BOB, 1 ether, noData, 0, abandoned);
    assertEq(BOB.balance, 0);
  }

  function test_futureNonce_executesAndConsumesSkippedNonces() public {
    bytes memory noData;
    bytes memory skipped = _sign(BOB, 1 ether, noData, 1, 0, 1);

    _exec(BOB, 2 ether, noData, 3, _sign(BOB, 2 ether, noData, 3, 0, 1));
    assertEq(BOB.balance, 2 ether);
    assertEq(wallet.nonce(), 4);
    assertTrue(wallet.isNonceUsed(1));
    assertTrue(wallet.isNonceUsed(3));
    assertFalse(wallet.isNonceUsed(4));

    vm.expectRevert(abi.encodeWithSelector(MyMultiSigExtended.NonceTooLow.selector, 1, 4));
    _exec(BOB, 1 ether, noData, 1, skipped);
  }

  function test_markNonceAsUsed_isInstantUnderTimelock() public {
    vm.prank(address(wallet));
    wallet.setTimelockDelay(1 days);
    assertFalse(wallet.isSensitiveSelector(bytes4(keccak256('markNonceAsUsed(uint256)'))));

    bytes memory noData;
    bytes memory pending = _sign(BOB, 1 ether, noData, 1, 2, 3);

    bytes memory cancel = abi.encodeWithSignature('markNonceAsUsed(uint256)', uint256(1));
    _exec(address(wallet), 0, cancel, 0, _sign(address(wallet), 0, cancel, 0, 0, 1));
    assertTrue(wallet.isNonceUsed(1));
    assertEq(wallet.nonce(), 1);

    vm.expectRevert(MyMultiSigExtended.NonceAlreadyUsed.selector);
    _exec(BOB, 1 ether, noData, 1, pending);
    assertEq(BOB.balance, 0);
  }

  function test_nonceOutsideUint96_reverts() public {
    bytes memory noData;
    uint256 tooBig = type(uint96).max;
    bytes memory sigs = _sign(BOB, 1 ether, noData, tooBig, 0, 1);
    vm.expectRevert(abi.encodeWithSelector(MyMultiSigExtended.NonceOutOfRange.selector, tooBig));
    _exec(BOB, 1 ether, noData, tooBig, sigs);
  }
}
