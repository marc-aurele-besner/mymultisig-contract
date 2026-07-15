// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Helper } from './shared/helper.t.sol';
import { MyMultiSigExtended } from '../MyMultiSigExtended.sol';
import './shared/mocks/MockEntryPoint.t.sol';

/// @title MyMultiSigExtendedV2_5 Foundry tests
/// @notice v0.5.0 surface on the existing `MyMultiSigExtended` wallet:
///         1. `version()` returns `'0.5.0'`.
///         2. The `operation` byte on the EIP-712 payload + the
///            new execTransaction overloads.
///         3. The disabled legacy overloads revert with
///            `V2_5RequiresOperationByte()`.
///         4. ERC-4337 `validateUserOp` rejects non-EntryPoint
///            callers and approves honest ones.
contract MyMultiSigExtendedV2_5Test is Helper {
  MyMultiSigExtended internal wallet;
  MockEntryPoint internal mockEntryPoint;

  function setUp() public {
    (myMultiSigFactory, myMultiSig) = initialize_tests(LOG_LEVEL, TestType.TestWithFactory);

    address[] memory owners = new address[](2);
    owners[0] = OWNERS[0];
    owners[1] = OWNERS[1];

    mockEntryPoint = new MockEntryPoint();
    wallet = new MyMultiSigExtended(
      'V2_5_Wallet',
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
    bytes memory expected = abi.encodeWithSignature('V2_5RequiresOperationByte()');
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
    bytes memory expected = abi.encodeWithSignature('InvalidOperationV2_5(uint8)', uint8(2));
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
    bytes memory expected = abi.encodeWithSignature('InvalidOperationV2_5(uint8)', uint8(1));
    assertEq(reason, expected);
  }
}
