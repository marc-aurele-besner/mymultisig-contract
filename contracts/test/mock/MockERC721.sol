// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

/**
 * @title MockERC721 - Test
 */

import 'foundry-test-utility/contracts/utils/console.sol';
import { Helper } from '../shared/helper.t.sol';
import { Errors } from '../shared/errors.t.sol';

import { MockERC721 } from '../../mocks/MockERC721.sol';

contract MockERC721Test is Helper {
  MockERC721 private mockERC721;

  string constant _TEST_NAME = 'MockERC721';
  string constant _TEST_SYMBOL = 'MOCK';

  function setUp() public {
    initialize_helper(LOG_LEVEL, TestType.TestWithoutFactory);

    // Deploy contracts
    mockERC721 = new MockERC721();
  }

  function build_mint(address to_, uint256 tokenId_) internal pure returns (bytes memory) {
    return
      abi.encodePacked(
        bytes4(keccak256('mint(address,uint256)')),
        abi.encodePacked(bytes32(uint256(uint160(to_))), bytes32(tokenId_))
      );
  }

  function build_burn(uint256 tokenId_) internal pure returns (bytes memory) {
    return abi.encodePacked(bytes4(keccak256('burn(uint256)')), abi.encodePacked(bytes32(tokenId_)));
  }

  function test_MockERC721_name() public {
    assertEq(mockERC721.name(), _TEST_NAME);
  }

  function test_MockERC721_symbol() public {
    assertEq(mockERC721.symbol(), _TEST_SYMBOL);
  }

  function test_MockERC721_mint(address to_, uint256 tokenId_) public {
    vm.assume(to_ != address(0));
    vm.assume(tokenId_ > 0);

    assertEq(mockERC721.balanceOf(to_), 0);

    bytes memory data = build_mint(to_, tokenId_);
    help_execTransaction(
      myMultiSig,
      OWNERS[0],
      address(mockERC721),
      0,
      data,
      DEFAULT_GAS * 2,
      build_signatures(myMultiSig, OWNERS_PK, address(mockERC721), 0, data, DEFAULT_GAS * 2)
    );

    assertEq(mockERC721.balanceOf(to_), 1);
    assertEq(mockERC721.ownerOf(tokenId_), to_);
  }

  function test_MockERC721_burn(address to_, uint256 tokenId_) public {
    vm.assume(to_ != address(0));
    vm.assume(tokenId_ > 0);

    assertEq(mockERC721.balanceOf(to_), 0);

    bytes memory data = build_mint(to_, tokenId_);
    help_execTransaction(
      myMultiSig,
      OWNERS[0],
      address(mockERC721),
      0,
      data,
      DEFAULT_GAS * 2,
      build_signatures(myMultiSig, OWNERS_PK, address(mockERC721), 0, data, DEFAULT_GAS * 2)
    );

    assertEq(mockERC721.balanceOf(to_), 1);
    assertEq(mockERC721.ownerOf(tokenId_), to_);

    data = build_burn(tokenId_);
    help_execTransaction(
      myMultiSig,
      OWNERS[0],
      address(mockERC721),
      0,
      data,
      DEFAULT_GAS * 2,
      build_signatures(myMultiSig, OWNERS_PK, address(mockERC721), 0, data, DEFAULT_GAS * 2)
    );

    assertEq(mockERC721.balanceOf(to_), 0);
  }
}
