// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Vm } from 'forge-std/Vm.sol';
import { Helper } from './shared/helper.t.sol';
import { MyMultiSigExtended } from '../MyMultiSigExtended.sol';
import { MockGuard } from '../mocks/MockGuard.sol';
import { PackedUserOperation } from '../interfaces/PackedUserOperation.sol';
import './shared/mocks/MockEntryPoint.t.sol';

/// @title MyMultiSigExtended Foundry tests
/// @notice v0.5.0 surface on the existing `MyMultiSigExtended` wallet:
///         1. `version()` returns `'0.5.0'`.
///         2. The `operation` byte on the EIP-712 payload + the
///            new execTransaction overloads.
///         3. The disabled legacy overloads revert with
///            `RequiresOperationByte()`.
///         4. ERC-4337 v0.7: `validateUserOp` / `execute` are
///            EntryPoint-gated, owners sign the EntryPoint's
///            `userOpHash`, the prefund is paid, and the EntryPoint's
///            2D nonces work independently of the wallet's own nonce.
contract MyMultiSigExtendedTest is Helper {
  MyMultiSigExtended internal wallet;
  MockEntryPoint internal mockEntryPoint;

  function setUp() public {
    (myMultiSigFactory, myMultiSig) = initialize_tests(LOG_LEVEL, TestType.TestWithFactory);

    address[] memory owners = new address[](2);
    owners[0] = OWNERS[0];
    owners[1] = OWNERS[1];

    mockEntryPoint = new MockEntryPoint();
    wallet = new MyMultiSigExtended(
      'V05Wallet',
      owners,
      2,
      ONLY_OWNERS_REQUEST,
      address(mockEntryPoint)
    );
  }

  // ---------- version ----------

  function test_version_is_v0_5() public {
    assertEq(wallet.version(), '0.5.0');
  }

  function test_entryPoint_matches() public {
    assertEq(address(wallet.ENTRY_POINT()), address(mockEntryPoint));
  }

  // ---------- disabled legacy execTransaction overloads ----------

  function test_disabled_5arg_overload_reverts() public {
    bytes memory data = abi.encodeWithSignature(
      'execTransaction(address,uint256,bytes,uint256,bytes)',
      address(0xdead),
      uint256(0),
      bytes(''),
      uint256(50000),
      bytes('')
    );
    (bool ok, bytes memory reason) = address(wallet).call(data);
    assertFalse(ok, '5-arg execTransaction must revert on v0.5.0');
    bytes memory expected = abi.encodeWithSignature('RequiresOperationByte()');
    assertEq(reason, expected, 'should bubble the v0.5.0 error');
  }

  function test_disabled_6arg_overload_reverts() public {
    bytes memory data = abi.encodeWithSignature(
      'execTransaction(address,uint256,bytes,uint256,uint256,bytes)',
      address(0xdead),
      uint256(0),
      bytes(''),
      uint256(50000),
      uint256(0), // validUntil
      bytes('')
    );
    (bool ok, ) = address(wallet).call(data);
    assertFalse(ok, '6-arg execTransaction must revert on v0.5.0');
  }

  function test_disabled_7arg_overload_reverts() public {
    // (to, value, data, gas, txnNonce, validUntil, signatures)
    bytes memory data = abi.encodeWithSignature(
      'execTransaction(address,uint256,bytes,uint256,uint256,uint256,bytes)',
      address(0xdead),
      uint256(0),
      bytes(''),
      uint256(50000),
      uint256(0),
      uint256(0),
      bytes('')
    );
    (bool ok, ) = address(wallet).call(data);
    assertFalse(ok, '7-arg execTransaction must revert on v0.5.0');
  }

  // ---------- operation gating (new execTransaction overloads) ----------

  function test_operation_out_of_range_reverts() public {
    bytes memory data = abi.encodeWithSignature(
      'execTransaction(address,uint256,bytes,uint256,uint8,bytes)',
      address(0xdead),
      uint256(0),
      bytes(''),
      uint256(50000),
      uint8(2), // operation
      bytes('')
    );
    (bool ok, bytes memory reason) = address(wallet).call(data);
    assertFalse(ok);
    bytes memory expected = abi.encodeWithSignature('InvalidOperation(uint8)', uint8(2));
    assertEq(reason, expected);
  }

  function test_delegatecall_to_other_address_reverts() public {
    bytes memory data = abi.encodeWithSignature(
      'execTransaction(address,uint256,bytes,uint256,uint8,bytes)',
      address(0xdead), // not address(this)
      uint256(0),
      bytes(''),
      uint256(50000),
      uint8(1), // DELEGATECALL
      bytes('')
    );
    (bool ok, bytes memory reason) = address(wallet).call(data);
    assertFalse(ok);
    bytes memory expected = abi.encodeWithSignature('InvalidOperation(uint8)', uint8(1));
    assertEq(reason, expected);
  }

  // ---------- DELEGATECALL honors txnGas ----------

  function test_delegatecall_honors_txnGas() public {
    // Regression: `_execExtended` used to forward `gasleft()` to the
    // inner DELEGATECALL, so the inner call could consume far more than
    // `txnGas` (up to ~9M gas in a Foundry test). The fix forwards
    // `txnGas` instead, matching the CALL branch.
    //
    // We assert via `vm.lastCallGas()` (gas usage from the callee
    // perspective), which exposes the gas arg passed to the last call
    // — the DELEGATECALL into `approveHash`. Pre-fix it's ~gasleft();
    // post-fix it's exactly `txnGas`. The threshold sits above `txnGas`
    // with a small margin to absorb CALL overhead but well below the
    // gas limit, so any EVM version passes it as long as the fix is in.
    //
    // `approveHash(bytes32)` is the only wallet entry point that's not
    // `onlyThis` (so DELEGATECALL into `address(this)` can reach it
    // without reverting) and writes to enough storage that the inner
    // call exceeds a 50_000 gas budget and OOGs under the fix.

    bytes32 hash = keccak256('mymultisig:test:delegatecall:txnGas');
    bytes memory data = abi.encodeWithSignature('approveHash(bytes32)', hash);
    uint256 txnGas = 50_000;
    uint256 nonce = wallet.nonce();
    uint8 operation = 1; // DELEGATECALL

    bytes32 domainSeparator = build_domainSeparator(wallet, wallet.name());
    // `signature_signHashed` wraps `structHash` with EIP-712 framing; the
    // wallet's `generateHashOp` would add that framing for us, so pass the
    // raw struct hash here instead of the wallet's framed digest.
    bytes32 typehash = keccak256(
      'Transaction(address to,uint256 value,bytes data,uint256 gas,uint96 nonce,uint256 validUntil,uint8 operation)'
    );
    bytes32 structHash = keccak256(
      abi.encode(typehash, address(wallet), uint256(0), keccak256(data), txnGas, nonce, uint256(0), operation)
    );
    Vote[] memory votes = new Vote[](2);
    votes[0] = Vote({ owner: OWNERS[0], sig: signature_signHashed(OWNERS_PK[0], domainSeparator, structHash) });
    votes[1] = Vote({ owner: OWNERS[1], sig: signature_signHashed(OWNERS_PK[1], domainSeparator, structHash) });
    bytes memory signatures = abi.encode(votes);

    vm.prank(OWNERS[0]);
    // The post-call `NotEnoughGas` check fires for both bug and fix
    // (the inner call needs ~70k gas, the budget is 50k), so we expect
    // the revert and inspect the call's gas arg after.
    vm.expectRevert(abi.encodeWithSignature('NotEnoughGas()'));
    wallet.execTransaction(address(wallet), 0, data, txnGas, nonce, 0, operation, signatures);

    // The most recent call frame is the DELEGATECALL into the wallet's
    // own `approveHash`. `gasLimit` is the gas arg `_execExtended`
    // passed to `_rawDelegateCall` — must be `txnGas`, not `gasleft()`.
    Vm.Gas memory lastCall = vm.lastCallGas();
    assertLe(
      lastCall.gasLimit,
      txnGas + 1_000,
      'DELEGATECALL should be bounded by txnGas, not gasleft()'
    );
  }

  // ---------- ERC-4337 v0.7 ----------

  /// @dev Builds an op whose `callData` is the standard
  ///      `execute(address,uint256,bytes)` call the EntryPoint relays to
  ///      the account verbatim.
  function _buildUserOp(
    address to,
    uint256 value,
    bytes memory data,
    uint256 opNonce
  ) internal view returns (PackedUserOperation memory op) {
    op = PackedUserOperation({
      sender: address(wallet),
      nonce: opNonce,
      initCode: '',
      callData: abi.encodeWithSignature('execute(address,uint256,bytes)', to, value, data),
      accountGasLimits: bytes32(0),
      preVerificationGas: 0,
      gasFees: bytes32(0),
      paymasterAndData: '',
      signature: ''
    });
  }

  /// @dev Owners vote on the EIP-191 wrap of the EntryPoint's
  ///      `userOpHash` — raw `vm.sign` over the wallet's
  ///      `userOpSigningHash`, no EIP-712 wallet-domain framing.
  function _signUserOp(PackedUserOperation memory op, uint256 signerCount) internal view returns (bytes memory) {
    bytes32 digest = wallet.userOpSigningHash(mockEntryPoint.getUserOpHash(op));
    Vote[] memory votes = new Vote[](signerCount);
    for (uint256 i = 0; i < signerCount; i++) {
      (uint8 v, bytes32 r, bytes32 s) = vm.sign(OWNERS_PK[i], digest);
      votes[i] = Vote({ owner: OWNERS[i], sig: abi.encodePacked(r, s, v) });
    }
    return abi.encode(votes);
  }

  function _handleOp(PackedUserOperation memory op) internal {
    PackedUserOperation[] memory ops = new PackedUserOperation[](1);
    ops[0] = op;
    mockEntryPoint.handleOps(ops, payable(address(0xbeef)));
  }

  function test_userOp_executes_and_ignores_wallet_nonce() public {
    vm.deal(address(wallet), 2 ether);
    address recipient = address(0xa11ce);
    uint96 walletNonceBefore = wallet.nonce();

    PackedUserOperation memory op = _buildUserOp(recipient, 1 ether, '', mockEntryPoint.getNonce(address(wallet), 0));
    op.signature = _signUserOp(op, 2);
    _handleOp(op);

    assertEq(recipient.balance, 1 ether, 'userOp should have transferred the ETH');
    assertEq(wallet.nonce(), walletNonceBefore, 'wallet EIP-712 nonce must not move on the 4337 path');
    assertEq(mockEntryPoint.getNonce(address(wallet), 0), 1, 'EntryPoint sequence should advance');
    // The relayed callData is a plain `execute` call — the standard
    // `account.call(userOp.callData)` flow, no custom tuple encoding.
    assertEq(bytes4(mockEntryPoint.lastCallData()), wallet.execute.selector);
  }

  function test_userOp_2d_nonce_keys_are_independent() public {
    vm.deal(address(wallet), 2 ether);
    address recipient = address(0xa11ce);

    // Two ops on distinct keys, no dependency on each other or on the
    // wallet's internal nonce.
    PackedUserOperation memory opKey0 = _buildUserOp(recipient, 0.5 ether, '', mockEntryPoint.getNonce(address(wallet), 0));
    opKey0.signature = _signUserOp(opKey0, 2);
    PackedUserOperation memory opKey5 = _buildUserOp(recipient, 0.5 ether, '', mockEntryPoint.getNonce(address(wallet), 5));
    opKey5.signature = _signUserOp(opKey5, 2);

    _handleOp(opKey5);
    _handleOp(opKey0);
    assertEq(recipient.balance, 1 ether);

    // Replaying a consumed EntryPoint nonce fails in the EntryPoint.
    vm.expectRevert(
      abi.encodeWithSelector(MockEntryPoint.InvalidAccountNonce.selector, address(wallet), opKey0.nonce)
    );
    _handleOp(opKey0);
  }

  function test_userOp_pays_prefund() public {
    vm.deal(address(wallet), 2 ether);
    mockEntryPoint.setRequiredPrefund(0.25 ether);
    address recipient = address(0xa11ce);

    PackedUserOperation memory op = _buildUserOp(recipient, 1 ether, '', mockEntryPoint.getNonce(address(wallet), 0));
    op.signature = _signUserOp(op, 2);
    _handleOp(op);

    assertEq(recipient.balance, 1 ether);
    assertEq(
      mockEntryPoint.balanceOf(address(wallet)),
      0.25 ether,
      'validateUserOp should have topped up the EntryPoint deposit'
    );
  }

  function test_userOp_below_threshold_returns_sig_validation_failed() public {
    vm.deal(address(wallet), 2 ether);
    PackedUserOperation memory op = _buildUserOp(address(0xa11ce), 1 ether, '', mockEntryPoint.getNonce(address(wallet), 0));
    // Only 1 of 2 required owner votes.
    op.signature = _signUserOp(op, 1);
    vm.expectRevert(
      abi.encodeWithSelector(MockEntryPoint.SignatureValidationFailed.selector, address(wallet), uint256(1))
    );
    _handleOp(op);
  }

  function test_userOp_approveHash_votes_count() public {
    vm.deal(address(wallet), 2 ether);
    address recipient = address(0xa11ce);
    PackedUserOperation memory op = _buildUserOp(recipient, 1 ether, '', mockEntryPoint.getNonce(address(wallet), 0));

    // Both owners pre-approve the userOp digest on-chain; the op then
    // needs no signature blob at all.
    bytes32 digest = wallet.userOpSigningHash(mockEntryPoint.getUserOpHash(op));
    vm.prank(OWNERS[0]);
    wallet.approveHash(digest);
    vm.prank(OWNERS[1]);
    wallet.approveHash(digest);

    _handleOp(op);
    assertEq(recipient.balance, 1 ether);
  }

  function test_userOp_execute_respects_allowlist() public {
    vm.deal(address(wallet), 2 ether);
    // Enable the allowlist for some other target; the op's target is not on it.
    vm.prank(address(wallet));
    wallet.setAllowedTarget(address(0xd00d), true);

    PackedUserOperation memory op = _buildUserOp(address(0xa11ce), 1 ether, '', mockEntryPoint.getNonce(address(wallet), 0));
    op.signature = _signUserOp(op, 2);
    vm.expectRevert(abi.encodeWithSignature('TargetNotAllowed(address)', address(0xa11ce)));
    _handleOp(op);
  }

  function test_validateUserOp_rejects_non_entrypoint() public {
    PackedUserOperation memory op = _buildUserOp(address(0xa11ce), 0, '', 0);
    vm.expectRevert(abi.encodeWithSignature('NotEntryPoint()'));
    wallet.validateUserOp(op, bytes32(0), 0);
  }

  function test_execute_rejects_non_entrypoint() public {
    vm.expectRevert(abi.encodeWithSignature('NotEntryPoint()'));
    wallet.execute(address(0xa11ce), 0, '');
  }

  // ---------- post-exec guard + schedule nonce ----------

  /// @dev Signs the extended 7-field (`operation`-bound) payload with both
  ///      owners for an arbitrary nonce — `build_signatures` always signs
  ///      the wallet's CURRENT nonce, which these tests need to deviate from.
  function _signExtendedTx(
    address to,
    uint256 value,
    bytes memory data,
    uint256 txnGas,
    uint256 nonce_,
    uint8 operation
  ) internal returns (bytes memory) {
    bytes32 domainSeparator = build_domainSeparator(wallet, wallet.name());
    bytes32 typehash = keccak256(
      'Transaction(address to,uint256 value,bytes data,uint256 gas,uint96 nonce,uint256 validUntil,uint8 operation)'
    );
    bytes32 structHash = keccak256(
      abi.encode(typehash, to, value, keccak256(data), txnGas, nonce_, uint256(0), operation)
    );
    Vote[] memory votes = new Vote[](2);
    votes[0] = Vote({ owner: OWNERS[0], sig: signature_signHashed(OWNERS_PK[0], domainSeparator, structHash) });
    votes[1] = Vote({ owner: OWNERS[1], sig: signature_signHashed(OWNERS_PK[1], domainSeparator, structHash) });
    return abi.encode(votes);
  }

  function test_postExecGuard_runsOnExecPath_withSignedHash() public {
    MockGuard guard = new MockGuard();
    vm.prank(address(wallet));
    wallet.setGuard(address(guard));
    assertEq(wallet.guard(), address(guard));

    vm.deal(address(wallet), 1 ether);
    address recipient = address(0xa11ce);
    uint256 txnGas = 50_000;
    uint256 nonce_ = wallet.nonce();
    bytes memory noData;
    bytes32 signedHash = wallet.generateHashOp(recipient, 0.5 ether, noData, txnGas, nonce_, 0, 0);
    bytes memory signatures = _signExtendedTx(recipient, 0.5 ether, noData, txnGas, nonce_, 0);

    vm.prank(OWNERS[0]);
    wallet.execTransaction(recipient, 0.5 ether, noData, txnGas, nonce_, 0, 0, signatures);
    assertEq(recipient.balance, 0.5 ether);

    // The guard's post-exec hook ran on the standard exec path and received
    // the exact EIP-712 hash the owners signed, so pre/post can be
    // correlated by hash.
    assertEq(guard.checkTransactionCalls(), 1);
    assertEq(guard.checkAfterExecutionCalls(), 1);
    assertEq(guard.lastTxHash(), signedHash);
    assertTrue(guard.lastSuccess());
  }

  function test_scheduleTransaction_rejectsNonCurrentNonce() public {
    vm.prank(address(wallet));
    wallet.setTimelockDelay(60);

    bytes memory data = abi.encodeWithSignature('addOwner(address)', NOT_OWNERS[0]);
    uint256 txnGas = 75_000;
    uint256 wrongNonce = wallet.nonce() + 1;
    bytes memory signatures = _signExtendedTx(address(wallet), 0, data, txnGas, wrongNonce, 0);

    vm.prank(OWNERS[0]);
    vm.expectRevert(
      abi.encodeWithSelector(MyMultiSigExtended.ScheduleNonceNotCurrent.selector, wrongNonce, wallet.nonce())
    );
    wallet.scheduleTransaction(address(wallet), 0, data, txnGas, wrongNonce, 0, signatures);

    // Scheduling against the CURRENT nonce goes through.
    uint256 currentNonce = wallet.nonce();
    signatures = _signExtendedTx(address(wallet), 0, data, txnGas, currentNonce, 0);
    vm.prank(OWNERS[0]);
    bytes32 txHash = wallet.scheduleTransaction(address(wallet), 0, data, txnGas, currentNonce, 0, signatures);
    assertGt(wallet.scheduledReadyAt(txHash), 0);
    assertEq(wallet.nonce(), currentNonce + 1);
  }
}
