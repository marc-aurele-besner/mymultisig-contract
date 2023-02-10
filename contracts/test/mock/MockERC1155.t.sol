// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

/**
 * @title MockERC1155 - Test
 */

import 'foundry-test-utility/contracts/utils/console.sol';
import { CheatCodes } from 'foundry-test-utility/contracts/utils/cheatcodes.sol';
import 'foundry-test-utility/contracts/utils/stdlib.sol';
import { Test } from 'foundry-test-utility/contracts/utils/test.sol';

import { MockERC1155 } from '../../mocks/MockERC1155.sol';

contract MockERC1155Test is Test {
  MockERC1155 private mockERC1155;

  string constant _TEST_NAME = 'MockERC1155';
  string constant _TEST_SYMBOL = 'MOCK';

  function setUp() public {
    // Deploy contracts
    mockERC1155 = new MockERC1155();
  }

  function test_MockERC1155_name() public {
    assertEq(mockERC1155.name(), _TEST_NAME);
  }

  function test_MockERC1155_symbol() public {
    assertEq(mockERC1155.symbol(), _TEST_SYMBOL);
  }

  function test_MockERC1155_mint(address to_, uint256 tokenId_, uint256 amount_) public {
    vm.assume(to_ != address(0));
    vm.assume(tokenId_ > 0);
    vm.assume(amount_ > 0);

    assertEq(mockERC1155.balanceOf(to_, tokenId_), 0);

    mockERC1155.mint(to_, tokenId_, amount_);

    assertEq(mockERC1155.balanceOf(to_, tokenId_), amount_);
  }

  function test_MockERC1155_burn(address to_, uint256 tokenId_, uint256 amount_) public {
    vm.assume(to_ != address(0));
    vm.assume(tokenId_ > 0);
    vm.assume(amount_ > 0);

    assertEq(mockERC1155.balanceOf(to_, tokenId_), 0);

    mockERC1155.mint(to_, tokenId_, amount_);

    assertEq(mockERC1155.balanceOf(to_, tokenId_), amount_);

    vm.prank(to_);

    mockERC1155.burn(tokenId_, amount_);

    assertEq(mockERC1155.balanceOf(to_, tokenId_), 0);
  }
}
