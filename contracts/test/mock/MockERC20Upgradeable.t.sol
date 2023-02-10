// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

/**
 * @title MockERC20Upgradeable - Test
 */

import 'foundry-test-utility/contracts/utils/console.sol';
import { CheatCodes } from 'foundry-test-utility/contracts/utils/cheatcodes.sol';
import 'foundry-test-utility/contracts/utils/stdlib.sol';
import { Test } from 'foundry-test-utility/contracts/utils/test.sol';

import { MockERC20Upgradeable } from '../../mocks/MockERC20Upgradeable.sol';

contract MockERC20UpgradeableTest is Test {
  MockERC20Upgradeable private mockERC20Upgradeable;

  string constant _TEST_NAME = 'MockERC20Upgradeable';
  string constant _TEST_SYMBOL = 'MOCK';

  function setUp() public {
    // Deploy contracts
    mockERC20Upgradeable = new MockERC20Upgradeable();
    mockERC20Upgradeable.initialize(_TEST_NAME, _TEST_SYMBOL);
  }

  function test_MockERC20Upgradeable_name() public {
    assertEq(mockERC20Upgradeable.name(), _TEST_NAME);
  }

  function test_MockERC20Upgradeable_symbol() public {
    assertEq(mockERC20Upgradeable.symbol(), _TEST_SYMBOL);
  }

  function test_MockERC20Upgradeable_mint(address to_, uint256 amount_) public {
    vm.assume(to_ != address(0));
    vm.assume(amount_ > 0);

    assertEq(mockERC20Upgradeable.balanceOf(to_), 0);
    assertEq(mockERC20Upgradeable.totalSupply(), 0);

    mockERC20Upgradeable.mint(to_, amount_);

    assertEq(mockERC20Upgradeable.balanceOf(to_), amount_);
    assertEq(mockERC20Upgradeable.totalSupply(), amount_);
  }

  function test_MockERC20Upgradeable_burn(address to_, uint256 amount_) public {
    vm.assume(to_ != address(0));
    vm.assume(amount_ > 0);

    assertEq(mockERC20Upgradeable.balanceOf(to_), 0);
    assertEq(mockERC20Upgradeable.totalSupply(), 0);

    mockERC20Upgradeable.mint(to_, amount_);

    assertEq(mockERC20Upgradeable.balanceOf(to_), amount_);

    vm.prank(to_);

    mockERC20Upgradeable.burn(amount_);

    assertEq(mockERC20Upgradeable.balanceOf(to_), 0);
    assertEq(mockERC20Upgradeable.totalSupply(), 0);
  }
}
