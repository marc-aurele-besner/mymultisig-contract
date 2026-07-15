// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IEntryPoint } from '../../../interfaces/IEntryPoint.sol';
import { PackedUserOperation } from '../../../interfaces/PackedUserOperation.sol';

/// @title MockEntryPoint
/// @notice Minimal EntryPoint stub for Foundry tests of
///         `MyMultiSigV2_5.validateUserOp` / `executeUserOp`. Does NOT
///         emulate real bundler economics (no stake, no deposit tracking)
///         because v0.5.0 only requires the wallet-side surface to
///         interact correctly.
/// @dev    Lives under `contracts/test/shared/mocks/` so the production
///         contract tree stays minimal. `handleOps(...)` is intentionally
///         a low-fidelity no-op that emits the call so Foundry tests can
///         assert it was invoked.
contract MockEntryPoint is IEntryPoint {
  // Mirrors the production deposit accounting surface enough to exercise
  // the user-op helpers' balance reads; deposits are stored per account
  // in a mapping so `balanceOf` returns the tracked value.
  mapping(address => uint256) private _deposits;

  // Echoes the last user-op the test suite called `handleOps(...)` with.
  // Lets Foundry assertions reach into the call data without decoding.
  bytes public lastCallData;

  event UserOpHandled(address indexed sender, bytes callData);

  /// @notice Real EntryPoint routes ops through inner static + dynamic
  ///         calls — the mock just logs the calldata so a Foundry test
  ///         can assert `MyMultiSigV2_5.executeUserOp` was reached via
  ///         `executeUserOp(userOp)` from this contract's perspective.
  function handleOps(
    PackedUserOperation[] calldata ops,
    address payable /* beneficiary */
  ) external override {
    require(ops.length == 1, 'MockEntryPoint: exactly one op');
    lastCallData = ops[0].callData;
    // Forward to the wallet's executeUserOp so the wallet-side flow
    // runs end-to-end during a test. The forward is a direct call;
    // a real bundler would route through EntryPoint's reputation /
    // stake machinery — out of scope for the mock.
    (bool success, bytes memory ret) = ops[0].sender.call(
      abi.encodeWithSelector(this.forwardExecuteUserOp.selector, ops[0])
    );
    if (!success) {
      // Bubble the inner revert so the test sees the actual failure.
      assembly {
        revert(add(ret, 0x20), mload(ret))
      }
    }
    emit UserOpHandled(ops[0].sender, ops[0].callData);
  }

  /// @notice External forwarder so the bundler-call surface stays the
  ///         same shape as a real EntryPoint.
  function forwardExecuteUserOp(PackedUserOperation calldata op) external {
    require(msg.sender == address(this), 'MockEntryPoint: only self');
    (bool success, bytes memory ret) = op.sender.call(
      abi.encodeWithSignature('executeUserOp((address,uint256,bytes,bytes32,uint256,bytes32,bytes,bytes,bytes))', op)
    );
    if (!success) {
      assembly {
        revert(add(ret, 0x20), mload(ret))
      }
    }
  }

  function depositTo(address account) external payable override {
    _deposits[account] += msg.value;
  }

  function withdrawTo(
    address payable withdrawAddress,
    uint256 withdrawAmount
  ) external override {
    _deposits[msg.sender] -= withdrawAmount;
    (bool ok, ) = withdrawAddress.call{value: withdrawAmount}('');
    require(ok, 'MockEntryPoint: withdraw failed');
  }

  function balanceOf(address account) external view override returns (uint256) {
    return _deposits[account];
  }

  receive() external payable {}
}
