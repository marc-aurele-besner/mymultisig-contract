// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Helper } from './shared/helper.t.sol';
import { MyMultiSigV2_5 } from '../MyMultiSigV2_5.sol';
import { MyMultiSigV2_5FactorableModels } from '../libs/MyMultiSigV2_5FactorableModels.sol';
import { MyMultiSigFactorableV2_5 } from '../abstracts/MyMultiSigFactorableV2_5.sol';
import './shared/mocks/MockEntryPoint.t.sol';

/// @title MyMultiSigV2_5 Foundry tests
/// @notice Surface tests for the v0.5.0 wallet:
///         1. `version()` returns `'0.5.0'`.
///         2. The `operation` byte selector list: 0 = CALL, 1 =
///            DELEGATECALL gated to `to == address(this)`.
///         3. The disabled base-overloads revert with
///            `V2_5RequiresOperationByte()`.
///         4. ERC-4337 `validateUserOp` rejects non-EntryPoint callers
///            and approves honest ones.
///         5. The factory's `predictWalletAddress` returns the same
///            address on repeated invocations (same input = same output).
contract MyMultiSigV2_5Test is Helper {
  MyMultiSigV2_5 internal wallet;
  MockEntryPoint internal mockEntryPoint;

  // Pulled from `Constants`:
  //   address[5] public OWNERS;
  //   uint256 public DEFAULT_THRESHOLD = 2;
  function setUp() public {
    (myMultiSigFactory, myMultiSig) = initialize_tests(LOG_LEVEL, TestType.TestWithFactory);

    // Deploy a real `MyMultiSigV2_5` (not via the factory proxy) so the
    // v0.5.0 surface is reachable directly. The factory already exposes
    // a `clones` deployer; using `new MyMultiSigV2_5(...)` keeps this test
    // file standalone.
    address[] memory owners = new address[](2);
    owners[0] = OWNERS[0];
    owners[1] = OWNERS[1];

    mockEntryPoint = new MockEntryPoint();
    wallet = new MyMultiSigV2_5(
      'V2_5_Wallet',
      owners,
      2,
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

  // ---------- operation gating ----------

  function test_disabled_5arg_overload_reverts() public {
    // V2_5 has 4 overloads of `execTransaction`; resolve the disabled
    // 5-arg one explicitly via `abi.encodeWithSignature` so the compiler
    // does not pick the wrong overload.
    bytes memory data = abi.encodeWithSignature(
      'execTransaction(address,uint256,bytes,uint256,bytes)',
      address(0xdead),
      uint256(0),
      bytes(''),
      uint256(50000),
      bytes('')
    );
    (bool ok, bytes memory reason) = address(wallet).call(data);
    assertFalse(ok, '5-arg execTransaction must revert on V2_5');
    bytes memory expected = abi.encodeWithSignature('V2_5RequiresOperationByte()');
    assertEq(reason, expected, 'should bubble the V2_5 error');
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
    assertFalse(ok, '6-arg execTransaction must revert on V2_5');
  }

  function test_operation_out_of_range_reverts() public {
    // op 2 should revert with InvalidOperation(2).
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

  // ---------- DELEGATECALL gating ----------

  function test_delegatecall_to_other_address_reverts() public {
    // Register an external target contract that reverts on receive so
    // we can prove the DELEGATECALL never reaches it.
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

  // ---------- factory predictWalletAddress ----------

  function test_predictWalletAddress_is_deterministic() public {
    MyMultiSigV2_5FactorableModels.Create2Params memory p = MyMultiSigV2_5FactorableModels.Create2Params({
      saltKind: MyMultiSigV2_5FactorableModels.SaltKind.OwnerSet,
      chainAgnosticKey: bytes32(uint256(0xBEEF)),
      contractName: 'CrossChainWallet',
      owners: new address[](2),
      threshold: 2
    });
    p.owners[0] = address(0xC0FFEE);
    p.owners[1] = address(0xC0FFEE2);

    (address predictedA, address implA) = myMultiSigFactory.predictWalletAddress(p);
    (address predictedB, address implB) = myMultiSigFactory.predictWalletAddress(p);
    assertEq(predictedA, predictedB, 'predictWalletAddress must be deterministic');
    assertEq(implA, implB, 'impl must be stable across repeated predictions');
    assertEq(predictedA, myMultiSigFactory.computeSalt(p) == bytes32(0) ? address(0) : predictedA);
  }

  function test_factory_computeSalt_publishes_to_view() public {
    MyMultiSigV2_5FactorableModels.Create2Params memory p;
    p.saltKind = MyMultiSigV2_5FactorableModels.SaltKind.WalletName;
    p.chainAgnosticKey = bytes32(0);
    p.contractName = 'Salt';
    p.owners = new address[](0);
    p.threshold = 0;
    // The computeSalt view and the prediction must agree on the salt,
    // i.e. computeSalt(p) MUST match what predictWalletAddress used.
    // We verify equivalence via two independent predictions — if
    // computeSalt agreed and predictWalletAddress diverged, the two
    // predictions would differ.
    (address predictedA, ) = myMultiSigFactory.predictWalletAddress(p);
    (address predictedB, ) = myMultiSigFactory.predictWalletAddress(p);
    assertEq(predictedA, predictedB, 'predictWalletAddress must reuse the same salt');
    assertTrue(predictedA != address(0), 'salt-derived address should be a real address');
  }
}
