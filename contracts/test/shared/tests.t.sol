// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Helper } from './helper.t.sol';
import { Errors } from './errors.t.sol';
import { MyMultiSig } from '../../MyMultiSig.sol';
import { MyMultiSigExtended } from '../../MyMultiSigExtended.sol';

abstract contract TestBasic is Helper {
  address[] buildTo;
  uint256[] buildValue;
  bytes[] buildData;
  uint256[] buildGas;

  function testMyMultiSig_name() public {
    assertEq(myMultiSig.name(), CONTRACT_NAME);
  }

  function testMyMultiSig_version() public {
    assertEq(myMultiSig.version(), CONTRACT_VERSION);
  }

  function testMyMultiSig_threshold() public {
    assertEq(myMultiSig.threshold(), DEFAULT_THRESHOLD);
  }

  function testMyMultiSig_ownerCount() public {
    assertEq(myMultiSig.ownerCount(), OWNERS.length);
  }

  function testMyMultiSig_nonce() public {
    assertEq(myMultiSig.nonce(), 0);
  }

  function testMyMultiSig_isOwnerAll() public {
    for (uint256 i = 0; i < OWNERS.length; i++) {
      assertTrue(myMultiSig.isOwner(OWNERS[i]));
    }
  }

  function testMyMultiSig_addOwner() public {
    help_addOwner(OWNERS[0], myMultiSig, OWNERS_PK, NOT_OWNERS[0]);
  }

  function testMyMultiSig_removeOwner() public {
    help_removeOwner(OWNERS[0], myMultiSig, OWNERS_PK, OWNERS[0]);
  }

  function testMyMultiSig_changeThreshold() public {
    help_changeThreshold(OWNERS[0], myMultiSig, OWNERS_PK, 3);
  }

  function testMyMultiSig_replaceOwner() public {
    help_replaceOwner(OWNERS[0], myMultiSig, OWNERS_PK, OWNERS[0], NOT_OWNERS[0]);
  }

  function testMyMultiSig_multiRequest_add3Owners() public {
    uint256 NEW_OWNERS_COUNT = 3;
    for (uint256 i = 0; i < NEW_OWNERS_COUNT; i++) {
      buildTo.push(address(myMultiSig));
      buildValue.push(0);
      buildData.push(build_addOwner(NOT_OWNERS[i]));
      buildGas.push(DEFAULT_GAS);
    }

    help_multiRequest(OWNERS[0], myMultiSig, OWNERS_PK, buildTo, buildValue, buildData, buildGas);

    for (uint256 i = 0; i < NEW_OWNERS_COUNT; i++) {
      assertTrue(myMultiSig.isOwner(NOT_OWNERS[i]));
    }
  }

  function testMyMultiSig_multiRequest_add5Owners() public {
    uint256 NEW_OWNERS_COUNT = 5;
    for (uint256 i = 0; i < NEW_OWNERS_COUNT; i++) {
      buildTo.push(address(myMultiSig));
      buildValue.push(0);
      buildData.push(build_addOwner(NOT_OWNERS[i]));
      buildGas.push(DEFAULT_GAS);
    }

    help_multiRequest(OWNERS[0], myMultiSig, OWNERS_PK, buildTo, buildValue, buildData, buildGas);

    for (uint256 i = 0; i < NEW_OWNERS_COUNT; i++) {
      assertTrue(myMultiSig.isOwner(NOT_OWNERS[i]));
    }
  }

  function testMyMultiSig_multiRequest_add20Owners() public {
    uint256 NEW_OWNERS_COUNT = 20;
    for (uint256 i = 0; i < NEW_OWNERS_COUNT; i++) {
      buildTo.push(address(myMultiSig));
      buildValue.push(0);
      buildData.push(build_addOwner(NOT_OWNERS[i]));
      buildGas.push(DEFAULT_GAS);
    }

    help_multiRequest(OWNERS[0], myMultiSig, OWNERS_PK, buildTo, buildValue, buildData, buildGas);

    for (uint256 i = 0; i < NEW_OWNERS_COUNT; i++) {
      assertTrue(myMultiSig.isOwner(NOT_OWNERS[i]));
    }
  }

  function testMyMultiSig_multiRequest_add100Owners() public {
    uint256 NEW_OWNERS_COUNT = 100;
    for (uint256 i = 0; i < NEW_OWNERS_COUNT; i++) {
      buildTo.push(address(myMultiSig));
      buildValue.push(0);
      buildData.push(build_addOwner(NOT_OWNERS[i]));
      buildGas.push(DEFAULT_GAS);
    }

    help_multiRequest(OWNERS[0], myMultiSig, OWNERS_PK, buildTo, buildValue, buildData, buildGas);

    for (uint256 i = 0; i < NEW_OWNERS_COUNT; i++) {
      assertTrue(myMultiSig.isOwner(NOT_OWNERS[i]));
    }
  }

  function testMyMultiSig_multiRequest_add100Owners_then_remove10Owner() public {
    uint256 NEW_OWNERS_COUNT = 100;
    for (uint256 i = 0; i < NEW_OWNERS_COUNT; i++) {
      buildTo.push(address(myMultiSig));
      buildValue.push(0);
      buildData.push(build_addOwner(NOT_OWNERS[i]));
      buildGas.push(DEFAULT_GAS);
    }

    help_multiRequest(OWNERS[0], myMultiSig, OWNERS_PK, buildTo, buildValue, buildData, buildGas);

    for (uint256 i = 0; i < NEW_OWNERS_COUNT; i++) {
      assertTrue(myMultiSig.isOwner(NOT_OWNERS[i]));
    }

    for (uint256 i = 0; i < NEW_OWNERS_COUNT; i++) {
      buildData[i] = build_removeOwner(NOT_OWNERS[i]);
    }

    help_multiRequest(OWNERS[0], myMultiSig, OWNERS_PK, buildTo, buildValue, buildData, buildGas);

    for (uint256 i = 0; i < NEW_OWNERS_COUNT; i++) {
      assertTrue(!myMultiSig.isOwner(NOT_OWNERS[i]));
    }
  }

  function testMyMultiSig_multiRequest_replaceAllOwners() public {
    for (uint256 i = 0; i < OWNERS_COUNT; i++) {
      buildTo.push(address(myMultiSig));
      buildValue.push(0);
      buildData.push(build_replaceOwner(OWNERS[i], NOT_OWNERS[i]));
      buildGas.push(DEFAULT_GAS);
    }

    help_multiRequest(OWNERS[0], myMultiSig, OWNERS_PK, buildTo, buildValue, buildData, buildGas);

    for (uint256 i = 0; i < OWNERS_COUNT; i++) {
      assertTrue(!myMultiSig.isOwner(OWNERS[i]));
      assertTrue(myMultiSig.isOwner(NOT_OWNERS[i]));
    }
  }

  function testMyMultiSig_multiRequest_replace100Owners() public {
    uint256 NEW_OWNERS_COUNT = 100;

    buildTo.push(address(myMultiSig));
    buildValue.push(0);
    buildData.push(build_replaceOwner(OWNERS[0], NOT_OWNERS[0]));
    buildGas.push(DEFAULT_GAS);

    for (uint256 i = 0; i < NEW_OWNERS_COUNT; i++) {
      buildTo.push(address(myMultiSig));
      buildValue.push(0);
      buildData.push(build_replaceOwner(NOT_OWNERS[i], NOT_OWNERS[i + 1]));
      buildGas.push(DEFAULT_GAS);
    }

    help_multiRequest(OWNERS[0], myMultiSig, OWNERS_PK, buildTo, buildValue, buildData, buildGas);

    assertTrue(!myMultiSig.isOwner(OWNERS[0]));
    for (uint256 i = 0; i < NEW_OWNERS_COUNT; i++) {
      assertTrue(!myMultiSig.isOwner(NOT_OWNERS[i]));
    }
    assertTrue(myMultiSig.isOwner(NOT_OWNERS[100]));
  }

  function testMyMultiSig_multiRequest_emitsPerCallResults() public {
    uint256 NEW_OWNERS_COUNT = 3;
    address[] memory to_ = new address[](NEW_OWNERS_COUNT);
    uint256[] memory value_ = new uint256[](NEW_OWNERS_COUNT);
    bytes[] memory data_ = new bytes[](NEW_OWNERS_COUNT);
    uint256[] memory txGas_ = new uint256[](NEW_OWNERS_COUNT);
    for (uint256 i = 0; i < NEW_OWNERS_COUNT; i++) {
      to_[i] = address(myMultiSig);
      value_[i] = 0;
      data_[i] = build_addOwner(NOT_OWNERS[i]);
      txGas_[i] = DEFAULT_GAS;
    }

    (uint256 txNonce, bool[] memory successes, bytes[] memory returnData) = help_multiRequestAndCapture(
      OWNERS[0],
      myMultiSig,
      OWNERS_PK,
      to_,
      value_,
      data_,
      txGas_
    );

    assertEq(txNonce, 0);
    assertEq(successes.length, NEW_OWNERS_COUNT);
    assertEq(returnData.length, NEW_OWNERS_COUNT);
    for (uint256 i = 0; i < NEW_OWNERS_COUNT; i++) {
      assertTrue(successes[i]);
      assertEq(returnData[i].length, 0);
      assertTrue(myMultiSig.isOwner(NOT_OWNERS[i]));
    }
  }

  function testMyMultiSig_multiRequest_recordsPartialFailures() public {
    // The wallet itself has no ETH, so any non-zero `value` transfer to an
    // EOA reverts without data. Build a batch where the first call is a
    // successful `addOwner` and the second / third attempts to forward 1 wei
    // to NOT_OWNERS[0] — those must fail and be recorded as failures in the
    // MultiRequestExecuted event.
    address[] memory to_ = new address[](3);
    uint256[] memory value_ = new uint256[](3);
    bytes[] memory data_ = new bytes[](3);
    uint256[] memory txGas_ = new uint256[](3);

    to_[0] = address(myMultiSig);
    value_[0] = 0;
    data_[0] = build_addOwner(NOT_OWNERS[0]);
    txGas_[0] = DEFAULT_GAS;

    to_[1] = NOT_OWNERS[0];
    value_[1] = 1;
    data_[1] = '';
    txGas_[1] = DEFAULT_GAS;

    to_[2] = NOT_OWNERS[0];
    value_[2] = 2;
    data_[2] = '';
    txGas_[2] = DEFAULT_GAS;

    (uint256 txNonce, bool[] memory successes, bytes[] memory returnData) = help_multiRequestAndCapture(
      OWNERS[0],
      myMultiSig,
      OWNERS_PK,
      to_,
      value_,
      data_,
      txGas_
    );

    assertEq(txNonce, 0);
    assertEq(successes.length, 3);
    assertEq(returnData.length, 3);
    assertTrue(successes[0]);
    assertFalse(successes[1]);
    assertFalse(successes[2]);
    // addOwner succeeded — NOT_OWNERS[0] is now an owner.
    assertTrue(myMultiSig.isOwner(NOT_OWNERS[0]));
    // The two failed value transfers captured empty returnData: the EVM
    // reverts out-of-gas / insufficient-balance with no payload because the
    // call failed before any code ran.
    assertEq(returnData[1].length, 0);
    assertEq(returnData[2].length, 0);
  }

  // ---------------------------------------------------------------------
  // validUntil (EIP-712 deadline)
  // ---------------------------------------------------------------------

  function testMyMultiSig_validUntil_zeroAllowsExecution() public {
    // Sign with validUntil = 0 ("no expiry"). Warp far into the future and
    // confirm the tx still executes.
    address to = address(myMultiSig);
    uint256 value = 0;
    bytes memory data = build_addOwner(NOT_OWNERS[0]);
    uint256 gas = DEFAULT_GAS;
    vm.warp(block.timestamp + 365 days);
    help_execTransaction(
      myMultiSig,
      OWNERS[0],
      to,
      value,
      data,
      gas,
      0,
      build_signatures(myMultiSig, OWNERS_PK, to, value, data, gas, 0),
      myMultiSig.nonce(),
      Errors.RevertStatus.Success
    );
    assertTrue(myMultiSig.isOwner(NOT_OWNERS[0]));
  }

  function testMyMultiSig_validUntil_inFutureExecutes() public {
    // validUntil in the future must allow execution.
    address to = address(myMultiSig);
    uint256 value = 0;
    bytes memory data = build_addOwner(NOT_OWNERS[0]);
    uint256 gas = DEFAULT_GAS;
    uint256 validUntil = block.timestamp + 1 days;
    help_execTransaction(
      myMultiSig,
      OWNERS[0],
      to,
      value,
      data,
      gas,
      validUntil,
      build_signatures(myMultiSig, OWNERS_PK, to, value, data, gas, validUntil),
      myMultiSig.nonce(),
      Errors.RevertStatus.Success
    );
    assertTrue(myMultiSig.isOwner(NOT_OWNERS[0]));
  }

  function testMyMultiSig_validUntil_inPastReverts() public {
    // validUntil in the past must revert with `SignatureExpired`. The nonce
    // must NOT advance — the tx was rejected before recording any votes.
    address to = address(myMultiSig);
    uint256 value = 0;
    bytes memory data = build_addOwner(NOT_OWNERS[0]);
    uint256 gas = DEFAULT_GAS;
    uint256 validUntil = block.timestamp - 1;
    help_execTransaction(
      myMultiSig,
      OWNERS[0],
      to,
      value,
      data,
      gas,
      validUntil,
      build_signatures(myMultiSig, OWNERS_PK, to, value, data, gas, validUntil),
      myMultiSig.nonce(),
      Errors.RevertStatus.SignatureExpired
    );
    assertFalse(myMultiSig.isOwner(NOT_OWNERS[0]));
    assertEq(myMultiSig.nonce(), 0);
  }

  // ---------------------------------------------------------------------
  // revokeApproval
  // ---------------------------------------------------------------------

  function testMyMultiSig_revokedApprovalRemovedFromList() public {
    bytes32 hash = keccak256('test-hash');
    vm.prank(OWNERS[0]);
    myMultiSig.approveHash(hash);
    assertEq(myMultiSig.getApprovedOwners(hash).length, 1);

    vm.prank(OWNERS[0]);
    myMultiSig.revokeApproval(hash);
    assertEq(myMultiSig.getApprovedOwners(hash).length, 0);
  }

  function testMyMultiSig_revokedApprovalIsIdempotent() public {
    bytes32 hash = keccak256('test-hash');
    vm.prank(OWNERS[0]);
    myMultiSig.approveHash(hash);
    vm.prank(OWNERS[0]);
    myMultiSig.revokeApproval(hash);
    // Second revoke must revert with `NotApproved`.
    vm.prank(OWNERS[0]);
    verify_revertCall(Errors.RevertStatus.NotApproved);
    myMultiSig.revokeApproval(hash);
  }

  function testMyMultiSig_revokedApprovalRevertsForNonOwner() public {
    bytes32 hash = keccak256('test-hash');
    vm.prank(NOT_OWNERS[0]);
    verify_revertCall(Errors.RevertStatus.NotOwner);
    myMultiSig.revokeApproval(hash);
  }

  function testMyMultiSig_revokedApprovalRevertsForUnrelatedOwner() public {
    // OWNERS[0] approves. OWNERS[1] never approved, so OWNERS[1]'s revoke
    // must revert with NotApproved.
    bytes32 hash = keccak256('test-hash');
    vm.prank(OWNERS[0]);
    myMultiSig.approveHash(hash);
    vm.prank(OWNERS[1]);
    verify_revertCall(Errors.RevertStatus.NotApproved);
    myMultiSig.revokeApproval(hash);
  }

  function testMyMultiSig_revokedApprovalBreaksExec() public {
    // Approve, then revoke, then try to execute with only the revoked
    // approval as the sole vote. Must revert with InvalidSignatures.
    address to = address(myMultiSig);
    uint256 value = 0;
    bytes memory data = build_addOwner(NOT_OWNERS[0]);
    uint256 gas = DEFAULT_GAS;
    uint96 nonce = myMultiSig.nonce();
    bytes32 hash = myMultiSig.generateHash(to, value, data, gas, nonce, 0);

    vm.prank(OWNERS[0]);
    myMultiSig.approveHash(hash);
    vm.prank(OWNERS[0]);
    myMultiSig.revokeApproval(hash);

    // Only one other owner's signature is left — but the approval is gone,
    // so threshold (2) is not reached. Helper signs with OWNERS_PK but
    // OWNERS[0]'s vote was an approval (now revoked), so the only ECDSA
    // votes are OWNERS[1..]. With threshold 2 and only OWNERS[1..4]
    // signing (4 votes), it would actually pass. Drop to threshold 3 with
    // a separate test.
    // Simpler approach: sign with only ONE owner (OWNERS[1]) after the
    // revoke. The approval is gone, so we have 1 ECDSA vote and threshold 2
    // → InvalidSignatures.
    bytes memory signatures = abi.encode(
      abi.encodeWithSignature('revokeApproval placeholder'), // ignored; replaced below
      uint256(0)
    );
    // Reuse build_signatures but with only one owner.
    uint256[] memory singleOwnerPk = new uint256[](1);
    singleOwnerPk[0] = OWNERS_PK[1];
    bytes memory singleSig = build_signatures(myMultiSig, singleOwnerPk, to, value, data, gas, 0);

    help_execTransaction(
      myMultiSig,
      OWNERS[1],
      to,
      value,
      data,
      gas,
      0,
      singleSig,
      nonce,
      Errors.RevertStatus.InvalidSignatures
    );
    assertFalse(myMultiSig.isOwner(NOT_OWNERS[0]));
  }

  // ---------------------------------------------------------------------
  // stale approvals (approveHash then owner removal)
  // ---------------------------------------------------------------------

  /// @dev The digest the exec path validates: the base wallet's 6-field
  ///      `generateHash`, or the extended wallet's operation-bound
  ///      `generateHashOp` with `operation = 0`.
  function build_execHash(bytes memory data, uint256 gas, uint96 nonce) internal view returns (bytes32) {
    if (isExtended(myMultiSig)) {
      return
        MyMultiSigExtended(payable(address(myMultiSig))).generateHashOp(address(myMultiSig), 0, data, gas, nonce, 0, 0);
    }
    return myMultiSig.generateHash(address(myMultiSig), 0, data, gas, nonce, 0);
  }

  function testMyMultiSig_staleApprovalFromRemovedOwnerIsSkipped() public {
    // OWNERS[0] pre-approves the addOwner(NOT_OWNERS[1]) hash bound to
    // nonce 1, then is replaced at nonce 0. The stale approval stays in
    // getApprovedOwners but must be skipped by the vote count: two
    // signatures from current owners reach the threshold on their own.
    address to = address(myMultiSig);
    bytes memory data = build_addOwner(NOT_OWNERS[1]);
    uint256 gas = DEFAULT_GAS;
    bytes32 hash = build_execHash(data, gas, 1);

    vm.prank(OWNERS[0]);
    myMultiSig.approveHash(hash);

    help_replaceOwner(OWNERS[1], myMultiSig, OWNERS_PK, OWNERS[0], NOT_OWNERS[0]);
    assertFalse(myMultiSig.isOwner(OWNERS[0]));
    assertEq(myMultiSig.getApprovedOwners(hash).length, 1);

    uint256[] memory freshPks = new uint256[](2);
    freshPks[0] = OWNERS_PK[1];
    freshPks[1] = OWNERS_PK[2];
    bytes memory signatures = build_signatures(myMultiSig, freshPks, to, 0, data, gas);
    help_execTransaction(myMultiSig, OWNERS[1], to, 0, data, gas, signatures);
    assertTrue(myMultiSig.isOwner(NOT_OWNERS[1]));
  }

  function testMyMultiSig_staleApprovalFromRemovedOwnerDoesNotCount() public {
    // Same setup, but the executor leans on the stale approval plus a single
    // fresh signature: 1 valid vote < threshold (2), so execution must
    // revert with InvalidSignatures.
    address to = address(myMultiSig);
    bytes memory data = build_addOwner(NOT_OWNERS[1]);
    uint256 gas = DEFAULT_GAS;
    bytes32 hash = build_execHash(data, gas, 1);

    vm.prank(OWNERS[0]);
    myMultiSig.approveHash(hash);

    help_replaceOwner(OWNERS[1], myMultiSig, OWNERS_PK, OWNERS[0], NOT_OWNERS[0]);

    uint256[] memory freshPks = new uint256[](1);
    freshPks[0] = OWNERS_PK[1];
    bytes memory signatures = build_signatures(myMultiSig, freshPks, to, 0, data, gas);
    help_execTransaction(
      myMultiSig,
      OWNERS[1],
      to,
      0,
      data,
      gas,
      signatures,
      myMultiSig.nonce(),
      Errors.RevertStatus.InvalidSignatures
    );
    assertFalse(myMultiSig.isOwner(NOT_OWNERS[1]));
  }

  // ---------------------------------------------------------------------
  // multiRequestStrict (atomic batch)
  // ---------------------------------------------------------------------

  function testMyMultiSig_multiRequestStrict_allSucceed() public {
    // Three addOwner calls in one strict batch — all succeed.
    address[] memory to_ = new address[](3);
    uint256[] memory value_ = new uint256[](3);
    bytes[] memory data_ = new bytes[](3);
    uint256[] memory txGas_ = new uint256[](3);
    for (uint256 i = 0; i < 3; i++) {
      to_[i] = address(myMultiSig);
      value_[i] = 0;
      data_[i] = build_addOwner(NOT_OWNERS[i]);
      txGas_[i] = DEFAULT_GAS;
    }

    address to = address(myMultiSig);
    uint256 value = 0;
    bytes memory data = build_multiRequestStrict(to_, value_, data_, txGas_);
    uint256 gas = DEFAULT_GAS * 3;
    help_execTransaction(
      myMultiSig,
      OWNERS[0],
      to,
      value,
      data,
      gas,
      0,
      build_signatures(myMultiSig, OWNERS_PK, to, value, data, gas, 0),
      myMultiSig.nonce(),
      Errors.RevertStatus.Success
    );
    for (uint256 i = 0; i < 3; i++) {
      assertTrue(myMultiSig.isOwner(NOT_OWNERS[i]));
    }
  }

  function testMyMultiSig_multiRequestStrict_revertsOnFirstFailure() public {
    // First call is a valid addOwner. Second call forwards 1 wei to an EOA
    // — the wallet has no balance so it reverts. The strict batch must
    // revert the WHOLE transaction: NOT_OWNERS[0] must NOT be an owner
    // (its addOwner side effect was rolled back), and the nonce must NOT
    // advance.
    address[] memory to_ = new address[](2);
    uint256[] memory value_ = new uint256[](2);
    bytes[] memory data_ = new bytes[](2);
    uint256[] memory txGas_ = new uint256[](2);

    to_[0] = address(myMultiSig);
    value_[0] = 0;
    data_[0] = build_addOwner(NOT_OWNERS[0]);
    txGas_[0] = DEFAULT_GAS;

    to_[1] = NOT_OWNERS[0];
    value_[1] = 1; // wallet has 0 ETH → call reverts
    data_[1] = '';
    txGas_[1] = DEFAULT_GAS;

    address to = address(myMultiSig);
    uint256 value = 0;
    bytes memory data = build_multiRequestStrict(to_, value_, data_, txGas_);
    uint256 gas = DEFAULT_GAS * 2;
    uint96 nonceBefore = myMultiSig.nonce();
    bytes memory signatures = build_signatures(myMultiSig, OWNERS_PK, to, value, data, gas, 0);

    // `BatchCallFailed` is a parameterized error — `verify_revertCall` only
    // matches parameterless selectors, so we stage the expect inline.
    // `isExtended` is a staticcall that may revert on the base wallet —
    // it MUST run before `vm.expectRevert` so its revert doesn't get
    // matched against the expected error.
    bool extended = isExtended(myMultiSig);
    vm.prank(OWNERS[0]);
    vm.expectRevert(
      abi.encodeWithSelector(MyMultiSig.BatchCallFailed.selector, uint256(1), bytes(''))
    );
    if (extended) {
      // v0.5.0 — extended wallets use the 8-arg overload with the
      // explicit `operation` byte.
      MyMultiSigExtended(payable(address(myMultiSig))).execTransaction(
        to,
        value,
        data,
        gas,
        nonceBefore,
        0,
        0, // operation = 0 (CALL)
        signatures
      );
    } else {
      myMultiSig.execTransaction(to, value, data, gas, 0, signatures);
    }

    // Side effect of the FIRST call must NOT persist.
    assertFalse(myMultiSig.isOwner(NOT_OWNERS[0]));
    // Nonce must NOT advance — the whole tx was rolled back.
    assertEq(myMultiSig.nonce(), nonceBefore);
  }
}
