// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Helper } from './shared/helper.t.sol';
import { MyMultiSigExtended } from '../MyMultiSigExtended.sol';
import { SessionKeyModule } from '../modules/SessionKeyModule.sol';

/// @dev Simple scoped target for session-key tests: accepts ETH and
///      exposes two selectors so the selector-allowlist paths can be
///      exercised.
contract MockSessionTarget {
  uint256 public pings;
  uint256 public pongs;

  function ping() external payable {
    pings++;
  }

  function pong() external payable {
    pongs++;
  }

  receive() external payable {}
}

/// @title SessionKeyModule Foundry tests
/// @notice Session keys: time-bounded, target/selector-scoped, ETH-budgeted
///         temporary signers driven through the wallet's module system.
contract SessionKeyModuleTest is Helper {
  SessionKeyModule internal module;
  MockSessionTarget internal target;
  address internal sessionKey;
  uint48 internal constant SESSION_TTL = 1 days;
  uint256 internal constant SESSION_BUDGET = 1 ether;

  function setUp() public {
    initialize_helper(LOG_LEVEL, TestType.TestWithoutFactory_extended);
    module = new SessionKeyModule();
    target = new MockSessionTarget();
    sessionKey = vm.addr(777);
    vm.deal(address(myMultiSig), 10 ether);

    _execFromWallet(address(myMultiSig), abi.encodeWithSignature('enableModule(address)', address(module)));
    assertTrue(myMultiSigExtended.isModule(address(module)));
  }

  function _ownersPk() internal view returns (uint256[] memory pks) {
    pks = new uint256[](2);
    pks[0] = OWNERS_PK[0];
    pks[1] = OWNERS_PK[1];
  }

  /// @dev Gas forwarded to the inner call of wallet-driven execs. Granting a
  ///      session key writes several cold storage slots, so it needs more
  ///      than the suite-wide `DEFAULT_GAS`.
  uint256 internal constant EXEC_GAS = 300_000;

  /// @dev Threshold-signed `execTransaction` from the wallet to `to_`.
  function _execFromWallet(address to_, bytes memory data_) internal {
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

  function _grant(address key, uint48 validAfter, uint48 validUntil, uint256 budget, address[] memory targets, bytes4[] memory selectors) internal {
    _execFromWallet(
      address(module),
      abi.encodeCall(module.grantSessionKey, (key, validAfter, validUntil, budget, targets, selectors))
    );
  }

  function _defaultGrant() internal {
    address[] memory targets = new address[](1);
    targets[0] = address(target);
    _grant(sessionKey, 0, uint48(block.timestamp) + SESSION_TTL, SESSION_BUDGET, targets, new bytes4[](0));
  }

  // ---------- grant ----------

  function test_grant_requires_wallet_threshold_path() public {
    // Granting is not gated inside the module itself — the grant is scoped
    // to `msg.sender` as the wallet. A grant recorded by a random EOA only
    // creates keys for that EOA-as-wallet, never for the multisig.
    address[] memory targets = new address[](1);
    targets[0] = address(target);
    vm.prank(NOT_OWNERS[0]);
    module.grantSessionKey(sessionKey, 0, uint48(block.timestamp) + SESSION_TTL, SESSION_BUDGET, targets, new bytes4[](0));
    assertFalse(module.isSessionKeyActive(address(myMultiSig), sessionKey));
  }

  function test_grant_records_scope_window_and_budget() public {
    _defaultGrant();
    assertTrue(module.isSessionKeyActive(address(myMultiSig), sessionKey));
    assertTrue(module.isSessionTargetAllowed(address(myMultiSig), sessionKey, address(target)));
    assertFalse(module.isSessionTargetAllowed(address(myMultiSig), sessionKey, NOT_OWNERS[0]));
    // No selector restriction: any selector is allowed.
    assertTrue(module.isSessionSelectorAllowed(address(myMultiSig), sessionKey, MockSessionTarget.ping.selector));
    assertEq(module.sessionBudgetRemaining(address(myMultiSig), sessionKey), SESSION_BUDGET);
  }

  function test_grant_rejects_wallet_as_target() public {
    address[] memory targets = new address[](1);
    targets[0] = address(myMultiSig);
    bytes memory data = abi.encodeCall(
      module.grantSessionKey,
      (sessionKey, 0, uint48(block.timestamp) + SESSION_TTL, SESSION_BUDGET, targets, new bytes4[](0))
    );
    bytes memory signatures = build_signatures(myMultiSig, _ownersPk(), address(module), 0, data, EXEC_GAS);
    uint96 nonce = myMultiSig.nonce();
    // The wallet bubbles the module's revert payload out of execTransaction.
    vm.prank(OWNERS[0]);
    vm.expectRevert(abi.encodeWithSignature('SessionKeyTargetIsWallet()'));
    myMultiSigExtended.execTransaction(address(module), 0, data, EXEC_GAS, nonce, 0, 0, signatures);
  }

  function test_grant_rejects_bad_window_and_empty_targets() public {
    address[] memory targets = new address[](1);
    targets[0] = address(target);
    vm.startPrank(NOT_OWNERS[1]);
    vm.expectRevert(
      abi.encodeWithSignature('SessionKeyInvalidWindow(uint48,uint48)', uint48(0), uint48(block.timestamp - 1))
    );
    module.grantSessionKey(sessionKey, 0, uint48(block.timestamp - 1), SESSION_BUDGET, targets, new bytes4[](0));
    vm.expectRevert(abi.encodeWithSignature('SessionKeyNoTargets()'));
    module.grantSessionKey(sessionKey, 0, uint48(block.timestamp) + SESSION_TTL, SESSION_BUDGET, new address[](0), new bytes4[](0));
    vm.stopPrank();
  }

  // ---------- execute ----------

  function test_execute_within_scope_and_budget_succeeds() public {
    _defaultGrant();
    uint96 nonceBefore = myMultiSig.nonce();
    uint256 balanceBefore = address(target).balance;

    vm.prank(sessionKey);
    bool success = module.executeWithSessionKey(
      address(myMultiSig),
      address(target),
      0.4 ether,
      abi.encodeCall(MockSessionTarget.ping, ())
    );

    assertTrue(success);
    assertEq(target.pings(), 1);
    assertEq(address(target).balance - balanceBefore, 0.4 ether);
    assertEq(module.sessionBudgetRemaining(address(myMultiSig), sessionKey), SESSION_BUDGET - 0.4 ether);
    // Module-driven execution must not bump the wallet nonce — pending
    // owner-signed transactions stay valid.
    assertEq(myMultiSig.nonce(), nonceBefore);
  }

  function test_execute_over_budget_reverts() public {
    _defaultGrant();
    vm.startPrank(sessionKey);
    module.executeWithSessionKey(address(myMultiSig), address(target), 0.7 ether, bytes(''));
    vm.expectRevert(
      abi.encodeWithSignature('SessionKeyBudgetExceeded(uint256,uint256)', 0.7 ether, 0.3 ether)
    );
    module.executeWithSessionKey(address(myMultiSig), address(target), 0.7 ether, bytes(''));
    vm.stopPrank();
  }

  function test_execute_outside_time_window_reverts() public {
    address[] memory targets = new address[](1);
    targets[0] = address(target);
    uint48 startsAt = uint48(block.timestamp) + 1 hours;
    _grant(sessionKey, startsAt, startsAt + SESSION_TTL, SESSION_BUDGET, targets, new bytes4[](0));

    // Too early.
    vm.prank(sessionKey);
    vm.expectRevert(
      abi.encodeWithSignature('SessionKeyNotActive(address,address)', address(myMultiSig), sessionKey)
    );
    module.executeWithSessionKey(address(myMultiSig), address(target), 0, bytes(''));

    // Inside the window.
    vm.warp(startsAt);
    vm.prank(sessionKey);
    assertTrue(module.executeWithSessionKey(address(myMultiSig), address(target), 0, bytes('')));

    // Expired.
    vm.warp(startsAt + SESSION_TTL + 1);
    vm.prank(sessionKey);
    vm.expectRevert(
      abi.encodeWithSignature('SessionKeyNotActive(address,address)', address(myMultiSig), sessionKey)
    );
    module.executeWithSessionKey(address(myMultiSig), address(target), 0, bytes(''));
  }

  function test_execute_unscoped_target_reverts() public {
    _defaultGrant();
    vm.prank(sessionKey);
    vm.expectRevert(abi.encodeWithSignature('SessionKeyTargetNotAllowed(address)', NOT_OWNERS[0]));
    module.executeWithSessionKey(address(myMultiSig), NOT_OWNERS[0], 0.1 ether, bytes(''));
  }

  function test_execute_wallet_as_target_reverts() public {
    _defaultGrant();
    vm.prank(sessionKey);
    vm.expectRevert(abi.encodeWithSignature('SessionKeyCannotCallWallet()'));
    module.executeWithSessionKey(
      address(myMultiSig),
      address(myMultiSig),
      0,
      abi.encodeWithSignature('addOwner(address)', sessionKey)
    );
  }

  function test_selector_restriction_enforced() public {
    address[] memory targets = new address[](1);
    targets[0] = address(target);
    bytes4[] memory selectors = new bytes4[](1);
    selectors[0] = MockSessionTarget.ping.selector;
    _grant(sessionKey, 0, uint48(block.timestamp) + SESSION_TTL, SESSION_BUDGET, targets, selectors);

    vm.startPrank(sessionKey);
    assertTrue(
      module.executeWithSessionKey(address(myMultiSig), address(target), 0, abi.encodeCall(MockSessionTarget.ping, ()))
    );
    vm.expectRevert(
      abi.encodeWithSignature('SessionKeySelectorNotAllowed(bytes4)', MockSessionTarget.pong.selector)
    );
    module.executeWithSessionKey(address(myMultiSig), address(target), 0, abi.encodeCall(MockSessionTarget.pong, ()));
    // Plain ETH transfer matches the bytes4(0) sentinel, which this grant
    // does not allow.
    vm.expectRevert(abi.encodeWithSignature('SessionKeySelectorNotAllowed(bytes4)', bytes4(0)));
    module.executeWithSessionKey(address(myMultiSig), address(target), 0.1 ether, bytes(''));
    vm.stopPrank();
  }

  function test_unknown_key_cannot_execute() public {
    _defaultGrant();
    vm.prank(NOT_OWNERS[5]);
    vm.expectRevert(
      abi.encodeWithSignature('SessionKeyNotActive(address,address)', address(myMultiSig), NOT_OWNERS[5])
    );
    module.executeWithSessionKey(address(myMultiSig), address(target), 0, bytes(''));
  }

  // ---------- revoke ----------

  function test_single_owner_can_revoke_immediately() public {
    _defaultGrant();
    vm.prank(OWNERS[1]);
    module.revokeSessionKey(address(myMultiSig), sessionKey);
    assertFalse(module.isSessionKeyActive(address(myMultiSig), sessionKey));
    assertFalse(module.isSessionTargetAllowed(address(myMultiSig), sessionKey, address(target)));

    vm.prank(sessionKey);
    vm.expectRevert(
      abi.encodeWithSignature('SessionKeyNotActive(address,address)', address(myMultiSig), sessionKey)
    );
    module.executeWithSessionKey(address(myMultiSig), address(target), 0, bytes(''));
  }

  function test_non_owner_cannot_revoke() public {
    _defaultGrant();
    vm.prank(NOT_OWNERS[0]);
    vm.expectRevert(abi.encodeWithSignature('NotWalletOrOwner(address)', NOT_OWNERS[0]));
    module.revokeSessionKey(address(myMultiSig), sessionKey);
  }

  function test_regrant_resets_budget_and_scope() public {
    _defaultGrant();
    vm.prank(sessionKey);
    module.executeWithSessionKey(address(myMultiSig), address(target), 0.9 ether, bytes(''));
    assertEq(module.sessionBudgetRemaining(address(myMultiSig), sessionKey), 0.1 ether);

    // Re-grant with a different scope: budget resets, old target drops out.
    MockSessionTarget newTarget = new MockSessionTarget();
    address[] memory targets = new address[](1);
    targets[0] = address(newTarget);
    _grant(sessionKey, 0, uint48(block.timestamp) + SESSION_TTL, SESSION_BUDGET, targets, new bytes4[](0));

    assertEq(module.sessionBudgetRemaining(address(myMultiSig), sessionKey), SESSION_BUDGET);
    assertFalse(module.isSessionTargetAllowed(address(myMultiSig), sessionKey, address(target)));
    assertTrue(module.isSessionTargetAllowed(address(myMultiSig), sessionKey, address(newTarget)));

    vm.prank(sessionKey);
    vm.expectRevert(abi.encodeWithSignature('SessionKeyTargetNotAllowed(address)', address(target)));
    module.executeWithSessionKey(address(myMultiSig), address(target), 0, bytes(''));
  }
}
