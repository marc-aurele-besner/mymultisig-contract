// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

/**
 * @title MockERC1155Upgradeable - Test
 */

import 'foundry-test-utility/contracts/utils/console.sol';
import { Helper } from '../shared/helper.t.sol';
import { Errors } from '../shared/errors.t.sol';

import { MockERC1155Upgradeable } from '../../mocks/MockERC1155Upgradeable.sol';

contract MockERC1155UpgradeableTest is Helper {
  MockERC1155Upgradeable private mockERC1155Upgradeable;

  string constant _TEST_NAME = 'MockERC1155Upgradeable';
  string constant _TEST_SYMBOL = 'MOCK';
  string constant _TEST_URI = 'https://google.com';

  function setUp() public {
    initialize_helper(LOG_LEVEL, TestType.TestWithoutFactory);

    // Deploy contracts
    mockERC1155Upgradeable = new MockERC1155Upgradeable();
    mockERC1155Upgradeable.initialize(_TEST_NAME, _TEST_SYMBOL, _TEST_URI);
  }

  function build_mint(address to_, uint256 tokenId_, uint256 amount_) internal pure returns (bytes memory) {
    return
      abi.encodePacked(
        bytes4(keccak256('mint(address,uint256,uint256)')),
        abi.encodePacked(bytes32(uint256(uint160(to_))), bytes32(tokenId_), bytes32(amount_))
      );
  }

  function build_burnFrom(address from_, uint256 tokenId_, uint256 amount_) internal pure returns (bytes memory) {
    return
      abi.encodePacked(
        bytes4(keccak256('burnFrom(address,uint256,uint256)')),
        abi.encodePacked(bytes32(uint256(uint160(from_))), bytes32(tokenId_), bytes32(amount_))
      );
  }

  function test_MockERC1155Upgradeable_name() public {
    assertEq(mockERC1155Upgradeable.name(), _TEST_NAME);
  }

  function test_MockERC1155Upgradeable_symbol() public {
    assertEq(mockERC1155Upgradeable.symbol(), _TEST_SYMBOL);
  }

  function test_MockERC1155Upgradeable_mint(address to_, uint256 tokenId_, uint256 amount_) public {
    vm.assume(to_ != address(0) && to_.code.length == 0);
    vm.assume(tokenId_ > 0);
    vm.assume(amount_ > 0);

    assertEq(mockERC1155Upgradeable.balanceOf(to_, tokenId_), 0);

    bytes memory data = build_mint(to_, tokenId_, amount_);
    help_execTransaction(
      myMultiSig,
      OWNERS[0],
      address(mockERC1155Upgradeable),
      0,
      data,
      DEFAULT_GAS * 2,
      build_signatures(myMultiSig, OWNERS_PK, address(mockERC1155Upgradeable), 0, data, DEFAULT_GAS * 2)
    );

    assertEq(mockERC1155Upgradeable.balanceOf(to_, tokenId_), amount_);
  }

  function test_MockERC1155Upgradeable_burnFrom(address to_, uint256 tokenId_, uint256 amount_) public {
    vm.assume(to_ != address(0) && to_.code.length == 0);
    vm.assume(to_ != address(0));
    vm.assume(tokenId_ > 0);
    vm.assume(amount_ > 0);

    assertEq(mockERC1155Upgradeable.balanceOf(to_, tokenId_), 0);

    bytes memory data = build_mint(to_, tokenId_, amount_);
    help_execTransaction(
      myMultiSig,
      OWNERS[0],
      address(mockERC1155Upgradeable),
      0,
      data,
      DEFAULT_GAS * 2,
      build_signatures(myMultiSig, OWNERS_PK, address(mockERC1155Upgradeable), 0, data, DEFAULT_GAS * 2)
    );

    assertEq(mockERC1155Upgradeable.balanceOf(to_, tokenId_), amount_);

    data = build_burnFrom(to_, tokenId_, amount_);
    help_execTransaction(
      myMultiSig,
      OWNERS[0],
      address(mockERC1155Upgradeable),
      0,
      data,
      DEFAULT_GAS * 2,
      build_signatures(myMultiSig, OWNERS_PK, address(mockERC1155Upgradeable), 0, data, DEFAULT_GAS * 2)
    );

    assertEq(mockERC1155Upgradeable.balanceOf(to_, tokenId_), 0);
  }
}
