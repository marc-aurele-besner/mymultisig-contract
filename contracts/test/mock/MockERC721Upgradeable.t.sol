// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

/**
 * @title MockERC721Upgradeable - Test
 */

import 'foundry-test-utility/contracts/utils/console.sol';
import { Helper } from '../shared/helper.t.sol';
import { Errors } from '../shared/errors.t.sol';

import { MockERC721Upgradeable } from '../../mocks/MockERC721Upgradeable.sol';

contract MockERC721UpgradeableTest is Helper {
  MockERC721Upgradeable private mockERC721Upgradeable;

  string constant _TEST_NAME = 'MockERC721Upgradeable';
  string constant _TEST_SYMBOL = 'MOCK';

  function setUp() public {
    initialize_helper(LOG_LEVEL, TestType.TestWithoutFactory);

    // Deploy contracts
    mockERC721Upgradeable = new MockERC721Upgradeable();
    mockERC721Upgradeable.initialize(_TEST_NAME, _TEST_SYMBOL);
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

  function test_MockERC721Upgradeable_name() public {
    assertEq(mockERC721Upgradeable.name(), _TEST_NAME);
  }

  function test_MockERC721Upgradeable_symbol() public {
    assertEq(mockERC721Upgradeable.symbol(), _TEST_SYMBOL);
  }

  function test_MockERC721Upgradeable_mint(address to_, uint256 tokenId_) public {
    vm.assume(to_ != address(0));
    vm.assume(tokenId_ > 0);

    assertEq(mockERC721Upgradeable.balanceOf(to_), 0);

    bytes memory data = build_mint(to_, tokenId_);
    help_execTransaction(
      myMultiSig,
      OWNERS[0],
      address(mockERC721Upgradeable),
      0,
      data,
      DEFAULT_GAS * 2,
      build_signatures(myMultiSig, OWNERS_PK, address(mockERC721Upgradeable), 0, data, DEFAULT_GAS * 2)
    );

    assertEq(mockERC721Upgradeable.balanceOf(to_), 1);
    assertEq(mockERC721Upgradeable.ownerOf(tokenId_), to_);
  }

  function test_MockERC721Upgradeable_burn(address to_, uint256 tokenId_) public {
    vm.assume(to_ != address(0));
    vm.assume(tokenId_ > 0);

    assertEq(mockERC721Upgradeable.balanceOf(to_), 0);

    bytes memory data = build_mint(to_, tokenId_);
    help_execTransaction(
      myMultiSig,
      OWNERS[0],
      address(mockERC721Upgradeable),
      0,
      data,
      DEFAULT_GAS * 2,
      build_signatures(myMultiSig, OWNERS_PK, address(mockERC721Upgradeable), 0, data, DEFAULT_GAS * 2)
    );

    assertEq(mockERC721Upgradeable.balanceOf(to_), 1);
    assertEq(mockERC721Upgradeable.ownerOf(tokenId_), to_);

    data = build_burn(tokenId_);
    help_execTransaction(
      myMultiSig,
      OWNERS[0],
      address(mockERC721Upgradeable),
      0,
      data,
      DEFAULT_GAS * 2,
      build_signatures(myMultiSig, OWNERS_PK, address(mockERC721Upgradeable), 0, data, DEFAULT_GAS * 2)
    );

    assertEq(mockERC721Upgradeable.balanceOf(to_), 0);
  }
}
