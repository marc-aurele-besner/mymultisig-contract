// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Test } from 'forge-std/Test.sol';

import { MyMultiSigExtended } from '../MyMultiSigExtended.sol';
import { MyMultiSigExtendedDeployer } from '../MyMultiSigExtendedDeployer.sol';

contract TestMyMultiSigExtendedDeployer is Test {
  string constant CONTRACT_NAME = 'MyMultiSig';
  address constant ENTRY_POINT = 0x0000000071727dE22E5e9D8Bde0DfeC0cEB6A7d7;
  uint256 constant EIP170_RUNTIME_LIMIT = 24_576;

  MyMultiSigExtendedDeployer public deployer;
  address[] public owners;

  function setUp() public {
    deployer = new MyMultiSigExtendedDeployer();

    owners.push(vm.addr(1));
    owners.push(vm.addr(2));
    owners.push(vm.addr(3));
  }

  function test_deployerRuntimeFitsUnderEip170() public {
    assertLe(address(deployer).code.length, EIP170_RUNTIME_LIMIT);
  }

  function test_creationCodeStoresFitUnderEip170AndAreDataOnly() public {
    (address store0, address store1) = deployer.creationCodeStores();
    assertLe(store0.code.length, EIP170_RUNTIME_LIMIT);
    assertLe(store1.code.length, EIP170_RUNTIME_LIMIT);
    // Each store starts with a STOP byte so its data can never be executed.
    assertEq(store0.code[0], bytes1(0x00));
    assertEq(store1.code[0], bytes1(0x00));
  }

  function test_storedCreationCodeMatchesCompilerOutput() public {
    (address store0, address store1) = deployer.creationCodeStores();
    bytes memory reassembled = bytes.concat(_storeData(store0), _storeData(store1));
    assertEq(keccak256(reassembled), keccak256(type(MyMultiSigExtended).creationCode));
  }

  function test_deployedWalletIsFullyConfigured() public {
    address deployed = deployer.deployMyMultiSigExtended(CONTRACT_NAME, owners, 2, true, ENTRY_POINT);
    MyMultiSigExtended wallet = MyMultiSigExtended(payable(deployed));

    assertGt(deployed.code.length, 0);
    assertEq(wallet.name(), CONTRACT_NAME);
    assertEq(wallet.threshold(), 2);
    assertEq(wallet.ownerCount(), 3);
    assertTrue(wallet.isOwner(owners[0]));
    assertTrue(wallet.isOwner(owners[1]));
    assertTrue(wallet.isOwner(owners[2]));
    assertEq(address(wallet.ENTRY_POINT()), ENTRY_POINT);
  }

  function test_deployBubblesWalletConstructorRevert() public {
    // Threshold above the owner count makes the wallet constructor revert;
    // the deployer must surface that revert instead of returning address(0).
    vm.expectRevert();
    deployer.deployMyMultiSigExtended(CONTRACT_NAME, owners, 4, true, ENTRY_POINT);
  }

  /// @dev Reads a store's runtime code minus its leading STOP byte.
  function _storeData(address store_) private view returns (bytes memory data) {
    uint256 size = store_.code.length - 1;
    data = new bytes(size);
    assembly {
      extcodecopy(store_, add(data, 32), 1, size)
    }
  }
}
