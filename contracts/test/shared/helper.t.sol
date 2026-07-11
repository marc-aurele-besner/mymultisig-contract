// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Functions } from './functions.t.sol';

/// @title Helper
/// @notice Test-level helpers (log-level tweak, block/time warps, factory init).
/// @dev    Previously pulled `stdCheats` from `foundry-test-utility/contracts/utils/stdlib.sol`
///         just to call `skip()`. Replaced with a direct `vm.warp` call —
///         equivalent semantics, zero external dependency.
contract Helper is Functions {
  function initialize_helper(uint8 LOG_LEVEL_, TestType testType_) internal {
    // Deploy contracts
    (myMultiSigFactory, myMultiSig) = initialize_tests(
      // Test Settings
      LOG_LEVEL_,
      testType_
    );
  }

  function help_changeLogLevel(uint8 newLogLevel_) internal {
    LOG_LEVEL = newLogLevel_;
  }

  function help_changeDefaultBlocksCount(uint256 newDefaultBlocksCount_) internal {
    DEFAULT_BLOCKS_COUNT = newDefaultBlocksCount_;
  }

  function help_moveBlockFoward(uint256 blockToRoll_) internal {
    vm.roll(block.number + blockToRoll_);
  }

  function help_moveTimeFoward(uint256 secondToWarp_) internal {
    vm.warp(block.timestamp + secondToWarp_);
  }

  function help_moveBlockAndTimeFoward(uint256 blockToRoll_, uint256 secondToWarp_) internal {
    help_moveBlockFoward(blockToRoll_);
    help_moveTimeFoward(secondToWarp_);
  }
}