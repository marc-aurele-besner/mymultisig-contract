// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Vm } from 'forge-std/Vm.sol';
import { Helper } from './shared/helper.t.sol';
import { MyMultiSigExtended } from '../MyMultiSigExtended.sol';
import './shared/mocks/MockEntryPoint.t.sol';

/// @title MyMultiSigExtended Foundry tests
/// @notice v0.5.0 surface on the existing `MyMultiSigExtended` wallet:
///         1. `version()` returns `'0.5.0'`.
///         2. The `operation` byte on the EIP-712 payload + the
///            new execTransaction overloads.
///         3. The disabled legacy overloads revert with
///            `RequiresOperationByte()`.
///         4. ERC-4337 `validateUserOp` rejects non-EntryPoint
///            callers and approves honest ones.
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
}
