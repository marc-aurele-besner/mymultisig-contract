// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IEntryPoint } from '../../../interfaces/IEntryPoint.sol';
import { PackedUserOperation } from '../../../interfaces/PackedUserOperation.sol';

/// @title MockEntryPoint
/// @notice Minimal EntryPoint stub for Foundry tests of
///         `MyMultiSigExtended` v0.5.0 `validateUserOp` /
///         `executeUserOp`. Tracks deposits, dispatches a single
///         UserOp via `handleOps`, and lets Foundry assertions reach
///         into the call data without decoding.
contract MockEntryPoint is IEntryPoint {
  mapping(address => uint256) private _deposits;

  // Echoes the last user-op the test suite called `handleOps(...)`
  // with. Lets Foundry assertions reach into the call data without
  // decoding.
  bytes public lastCallData;

  event UserOpHandled(address indexed sender, bytes callData);

  function handleOps(
    PackedUserOperation[] calldata ops,
    address payable /* beneficiary */
  ) external override {
    require(ops.length == 1, 'MockEntryPoint: exactly one op');
    lastCallData = ops[0].callData;
    // Forward to the wallet's executeUserOp so the wallet-side flow
    // runs end-to-end during a test.
    (bool success, bytes memory ret) = ops[0].sender.call(
      abi.encodeWithSelector(this.forwardExecuteUserOp.selector, ops[0])
    );
    if (!success) {
      assembly {
        revert(add(ret, 0x20), mload(ret))
      }
    }
    emit UserOpHandled(ops[0].sender, ops[0].callData);
  }

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
