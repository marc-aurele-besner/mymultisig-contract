// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

/**
 * @title MockERC20 - Test
 */

import 'foundry-test-utility/contracts/utils/console.sol';
import { Helper } from '../shared/helper.t.sol';
import { Errors } from '../shared/errors.t.sol';
import { MockERC20 } from '../../mocks/MockERC20.sol';

contract MockERC20Test is Helper {
  MockERC20 private mockERC20;

  string constant _TEST_NAME = 'MockERC20';
  string constant _TEST_SYMBOL = 'MOCK';

  function setUp() public {
    initialize_helper(LOG_LEVEL, TestType.TestWithoutFactory);

    // Deploy contracts
    mockERC20 = new MockERC20();
  }

  function build_mint(address to_, uint256 amount_) internal pure returns (bytes memory) {
    return
      abi.encodePacked(
        bytes4(keccak256('mint(address,uint256)')),
        abi.encodePacked(bytes32(uint256(uint160(to_))), bytes32(amount_))
      );
  }

  function build_burnFrom(address from_, uint256 amount_) internal pure returns (bytes memory) {
    return
      abi.encodePacked(
        bytes4(keccak256('burnFrom(address,uint256)')),
        abi.encodePacked(bytes32(uint256(uint160(from_))), bytes32(amount_))
      );
  }

  function test_MockERC20_name() public {
    assertEq(mockERC20.name(), _TEST_NAME);
  }

  function test_MockERC20_symbol() public {
    assertEq(mockERC20.symbol(), _TEST_SYMBOL);
  }

  function test_MockERC20_mint(address to_, uint256 amount_) public {
    vm.assume(to_ != address(0));
    vm.assume(amount_ > 0);

    assertEq(mockERC20.balanceOf(to_), 0);
    assertEq(mockERC20.totalSupply(), 0);

    bytes memory data = build_mint(to_, amount_);
    help_execTransaction(
      myMultiSig,
      OWNERS[0],
      address(mockERC20),
      0,
      data,
      DEFAULT_GAS * 2,
      build_signatures(myMultiSig, OWNERS_PK, address(mockERC20), 0, data, DEFAULT_GAS * 2)
    );

    assertEq(mockERC20.balanceOf(to_), amount_);
    assertEq(mockERC20.totalSupply(), amount_);
  }

  function test_MockERC20_burn(address to_, uint256 amount_) public {
    vm.assume(to_ != address(0));
    vm.assume(amount_ > 0);

    assertEq(mockERC20.balanceOf(to_), 0);
    assertEq(mockERC20.totalSupply(), 0);

    bytes memory data = build_mint(to_, amount_);
    help_execTransaction(
      myMultiSig,
      OWNERS[0],
      address(mockERC20),
      0,
      data,
      DEFAULT_GAS * 2,
      build_signatures(myMultiSig, OWNERS_PK, address(mockERC20), 0, data, DEFAULT_GAS * 2)
    );

    assertEq(mockERC20.balanceOf(to_), amount_);

    data = build_burnFrom(to_, amount_);
    help_execTransaction(
      myMultiSig,
      OWNERS[0],
      address(mockERC20),
      0,
      data,
      DEFAULT_GAS * 2,
      build_signatures(myMultiSig, OWNERS_PK, address(mockERC20), 0, data, DEFAULT_GAS * 2)
    );

    assertEq(mockERC20.balanceOf(to_), 0);
    assertEq(mockERC20.totalSupply(), 0);
  }
}
