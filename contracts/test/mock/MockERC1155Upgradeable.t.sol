// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

/**
 * @title MockERC1155Upgradeable - Test
 */

import 'foundry-test-utility/contracts/utils/console.sol';
import { CheatCodes } from 'foundry-test-utility/contracts/utils/cheatcodes.sol';
import 'foundry-test-utility/contracts/utils/stdlib.sol';
import { Test } from 'foundry-test-utility/contracts/utils/test.sol';

import { MockERC1155Upgradeable } from '../../mocks/MockERC1155Upgradeable.sol';

contract MockERC1155UpgradeableTest is Test {
  MockERC1155Upgradeable private mockERC1155Upgradeable;

  string constant _TEST_NAME = 'MockERC1155Upgradeable';
  string constant _TEST_SYMBOL = 'MOCK';
  string constant _TEST_URI = 'https://google.com';

  function setUp() public {
    // Deploy contracts
    mockERC1155Upgradeable = new MockERC1155Upgradeable();
    mockERC1155Upgradeable.initialize(_TEST_NAME, _TEST_SYMBOL, _TEST_URI);
  }

  function test_MockERC1155Upgradeable_name() public {
    assertEq(mockERC1155Upgradeable.name(), _TEST_NAME);
  }

  function test_MockERC1155Upgradeable_symbol() public {
    assertEq(mockERC1155Upgradeable.symbol(), _TEST_SYMBOL);
  }

  // function test_MockERC1155Upgradeable_mint(address to_, uint256 tokenId_, uint256 amount_) public {
  //   vm.assume(to_ != address(0));
  //   vm.assume(tokenId_ > 0);
  //   vm.assume(amount_ > 0);

  //   assertEq(mockERC1155Upgradeable.balanceOf(to_, tokenId_), 0);

  //   mockERC1155Upgradeable.mint(to_, tokenId_, amount_);

  //   assertEq(mockERC1155Upgradeable.balanceOf(to_, tokenId_), amount_);
  // }

  // function test_MockERC1155Upgradeable_burn(address to_, uint256 tokenId_, uint256 amount_) public {
  //   vm.assume(to_ != address(0));
  //   vm.assume(tokenId_ > 0);
  //   vm.assume(amount_ > 0);

  //   assertEq(mockERC1155Upgradeable.balanceOf(to_, tokenId_), 0);

  //   mockERC1155Upgradeable.mint(to_, tokenId_, amount_);

  //   assertEq(mockERC1155Upgradeable.balanceOf(to_, tokenId_), amount_);

  //   vm.prank(to_);

  //   mockERC1155Upgradeable.burn(tokenId_, amount_);

  //   assertEq(mockERC1155Upgradeable.balanceOf(to_, tokenId_), 0);
  // }
}
