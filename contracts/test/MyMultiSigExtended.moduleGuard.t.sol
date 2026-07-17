// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Helper } from './shared/helper.t.sol';
import { MyMultiSigExtended } from '../MyMultiSigExtended.sol';
import { MockModule } from '../mocks/MockModule.sol';
import { MockReentrantModule } from '../mocks/MockReentrantModule.sol';

/// @title Module entry-point hardening tests
/// @notice Wallet-side protections of `execTransactionFromModule`: the
///         reentrancy guard, the `requireTxSuccess()` failure policy, and
///         the sensitive-selector registration of `setRequireTxSuccess`.
contract MyMultiSigExtendedModuleGuardTest is Helper {
  MockModule internal module;
  MockReentrantModule internal reentrantModule;

  /// @dev Gas forwarded to the inner call of wallet-driven execs — admin
  ///      setters write cold storage slots, so this needs more than the
  ///      suite-wide `DEFAULT_GAS`.
  uint256 internal constant EXEC_GAS = 300_000;

  event ModuleTransactionExecuted(
    address indexed module,
    address indexed to,
    uint256 indexed value,
    bytes data,
    uint256 operation,
    bool success
  );

  function setUp() public {
    initialize_helper(LOG_LEVEL, TestType.TestWithoutFactory_extended);
    module = new MockModule(myMultiSigExtended);
    reentrantModule = new MockReentrantModule(myMultiSigExtended);
    _execFromWallet(abi.encodeWithSignature('enableModule(address)', address(module)));
    _execFromWallet(abi.encodeWithSignature('enableModule(address)', address(reentrantModule)));
    assertTrue(myMultiSigExtended.isModule(address(module)));
    assertTrue(myMultiSigExtended.isModule(address(reentrantModule)));
  }

  function _ownersPk() internal view returns (uint256[] memory pks) {
    pks = new uint256[](2);
    pks[0] = OWNERS_PK[0];
    pks[1] = OWNERS_PK[1];
  }

  /// @dev Threshold-signed `execTransaction` from the wallet to itself.
  function _execFromWallet(bytes memory data_) internal {
    address to_ = address(myMultiSig);
    help_execTransaction(
      myMultiSig,
      OWNERS[0],
      to_,
      0,
      data_,
      EXEC_GAS,
      build_signatures(myMultiSig, _ownersPk(), to_, 0, data_, EXEC_GAS)
    );
  }

  // ---------- reentrancy ----------

  function test_module_reentrancy_is_blocked() public {
    // The nested `execTransactionFromModule` inside `reenter()` hits the
    // wallet's reentrancy guard; the guard's revert payload bubbles back
    // out through the outer module call.
    vm.expectRevert('ReentrancyGuard: reentrant call');
    reentrantModule.attack();
  }

  // ---------- requireTxSuccess on the module path ----------

  function test_module_silent_failure_returns_false_by_default() public {
    // Sending more than the wallet's balance fails without returndata →
    // soft failure: the module call completes and reports success = false.
    uint256 value = address(myMultiSig).balance + 1;
    vm.expectEmit(true, true, true, true);
    emit ModuleTransactionExecuted(address(module), NOT_OWNERS[0], value, '', 0, false);
    module.execCall(NOT_OWNERS[0], value, '');
  }

  function test_module_silent_failure_reverts_when_requireTxSuccess_on() public {
    _execFromWallet(abi.encodeWithSignature('setRequireTxSuccess(bool)', true));
    assertTrue(myMultiSig.requireTxSuccess());
    uint256 value = address(myMultiSig).balance + 1;
    vm.expectRevert(abi.encodeWithSignature('TxSuccessRequired()'));
    module.execCall(NOT_OWNERS[0], value, '');
  }

  // ---------- setRequireTxSuccess is timelock-sensitive ----------

  function test_setRequireTxSuccess_is_default_sensitive() public {
    assertTrue(myMultiSigExtended.isSensitiveSelector(bytes4(keccak256('setRequireTxSuccess(bool)'))));
  }

  function test_setRequireTxSuccess_requires_timelock_when_enabled() public {
    _execFromWallet(abi.encodeWithSignature('setTimelockDelay(uint256)', uint256(60)));
    assertEq(myMultiSigExtended.timelockDelay(), 60);

    bytes memory data = abi.encodeWithSignature('setRequireTxSuccess(bool)', true);
    bytes memory signatures = build_signatures(myMultiSig, _ownersPk(), address(myMultiSig), 0, data, EXEC_GAS);
    uint96 nonceBefore = myMultiSig.nonce();
    vm.prank(OWNERS[0]);
    vm.expectRevert(
      abi.encodeWithSelector(
        MyMultiSigExtended.SensitiveCallRequiresDelay.selector,
        address(myMultiSig),
        bytes4(keccak256('setRequireTxSuccess(bool)')),
        uint256(0)
      )
    );
    myMultiSigExtended.execTransaction(address(myMultiSig), 0, data, EXEC_GAS, nonceBefore, 0, 0, signatures);
    assertFalse(myMultiSig.requireTxSuccess());
  }
}
