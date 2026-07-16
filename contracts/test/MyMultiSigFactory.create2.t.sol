// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Test } from 'forge-std/Test.sol';

import { MyMultiSig } from '../MyMultiSig.sol';
import { MyMultiSigExtended } from '../MyMultiSigExtended.sol';
import { MyMultiSigFactory } from '../MyMultiSigFactory.sol';
import { MyMultiSigDeployer } from '../MyMultiSigDeployer.sol';
import { MyMultiSigExtendedDeployer } from '../MyMultiSigExtendedDeployer.sol';
import { MyMultiSigAdvancedDeployer } from '../MyMultiSigAdvancedDeployer.sol';
import { MyMultiSigFactorableModels } from '../libs/MyMultiSigFactorableModels.sol';

contract TestMyMultiSigFactory_create2 is Test {
  string constant CONTRACT_NAME = 'MyMultiSig';
  address constant ENTRY_POINT = 0x0000000071727dE22E5e9D8Bde0DfeC0cEB6A7d7;
  bytes32 constant SALT = keccak256('mymultisig.app/test-salt');

  MyMultiSigFactory public factory;
  MyMultiSigDeployer public simpleDeployer;
  MyMultiSigExtendedDeployer public extendedDeployer;
  MyMultiSigAdvancedDeployer public advancedDeployer;

  address public alice = vm.addr(1_001);
  address public bob = vm.addr(1_002);
  address[] public owners;

  event MyMultiSigCreated(
    address indexed creator,
    address indexed contractAddress,
    uint256 indexed contractIndex,
    string contractName,
    address[] originalOwners,
    uint16 threshold
  );

  function setUp() public {
    simpleDeployer = new MyMultiSigDeployer();
    extendedDeployer = new MyMultiSigExtendedDeployer();
    advancedDeployer = new MyMultiSigAdvancedDeployer(address(extendedDeployer));
    factory = new MyMultiSigFactory(address(simpleDeployer), address(extendedDeployer), address(advancedDeployer));

    owners.push(vm.addr(1));
    owners.push(vm.addr(2));
    owners.push(vm.addr(3));
  }

  function test_create2_simple_deploysAtPredictedAddress() public {
    address predicted = factory.predictMultiSigAddress(alice, CONTRACT_NAME, owners, 2, SALT);

    vm.expectEmit(true, true, true, true, address(factory));
    emit MyMultiSigCreated(alice, predicted, 1, CONTRACT_NAME, owners, 2);
    vm.prank(alice);
    address deployed = factory.createDeterministicMultiSig(CONTRACT_NAME, owners, 2, SALT);

    assertEq(deployed, predicted);
    assertGt(deployed.code.length, 0);
    assertEq(MyMultiSig(payable(deployed)).threshold(), 2);
    assertEq(factory.multiSig(0), deployed);
    assertEq(factory.multiSigCount(), 1);
    assertEq(factory.simpleCount(), 1);
    assertTrue(factory.creationTypeOf(deployed) == MyMultiSigFactorableModels.CreationType.SIMPLE);
  }

  function test_create2_extended_deploysAtPredictedAddress() public {
    address predicted = factory.predictMyMultiSigExtendedAddress(alice, CONTRACT_NAME, owners, 2, true, ENTRY_POINT, SALT);

    vm.prank(alice);
    address deployed = factory.createDeterministicMyMultiSigExtended(CONTRACT_NAME, owners, 2, true, ENTRY_POINT, SALT);

    assertEq(deployed, predicted);
    assertGt(deployed.code.length, 0);
    assertEq(address(MyMultiSigExtended(payable(deployed)).ENTRY_POINT()), ENTRY_POINT);
    assertEq(factory.extendedCount(), 1);
    assertTrue(factory.creationTypeOf(deployed) == MyMultiSigFactorableModels.CreationType.EXTENDED);
    assertTrue(factory.isExtended(deployed));
  }

  function test_create2_advanced_deploysAtPredictedAddress() public {
    address predicted = factory.predictMyMultiSigAdvancedAddress(alice, CONTRACT_NAME, owners, 2, true, ENTRY_POINT, SALT);

    vm.prank(alice);
    address deployed = factory.createDeterministicMyMultiSigAdvanced(CONTRACT_NAME, owners, 2, true, ENTRY_POINT, SALT);

    assertEq(deployed, predicted);
    assertGt(deployed.code.length, 0);
    assertEq(factory.advancedCount(), 1);
    assertTrue(factory.creationTypeOf(deployed) == MyMultiSigFactorableModels.CreationType.ADVANCED);
  }

  function test_create2_advancedAndExtended_sameSaltDoNotCollide() public {
    address predictedExtended = factory.predictMyMultiSigExtendedAddress(
      alice,
      CONTRACT_NAME,
      owners,
      2,
      true,
      ENTRY_POINT,
      SALT
    );
    address predictedAdvanced = factory.predictMyMultiSigAdvancedAddress(
      alice,
      CONTRACT_NAME,
      owners,
      2,
      true,
      ENTRY_POINT,
      SALT
    );
    assertTrue(predictedExtended != predictedAdvanced);

    vm.startPrank(alice);
    address extendedWallet = factory.createDeterministicMyMultiSigExtended(
      CONTRACT_NAME,
      owners,
      2,
      true,
      ENTRY_POINT,
      SALT
    );
    address advancedWallet = factory.createDeterministicMyMultiSigAdvanced(
      CONTRACT_NAME,
      owners,
      2,
      true,
      ENTRY_POINT,
      SALT
    );
    vm.stopPrank();

    assertEq(extendedWallet, predictedExtended);
    assertEq(advancedWallet, predictedAdvanced);
  }

  function test_create2_sameCreatorSameSaltReverts() public {
    vm.prank(alice);
    factory.createDeterministicMultiSig(CONTRACT_NAME, owners, 2, SALT);

    vm.prank(alice);
    vm.expectRevert();
    factory.createDeterministicMultiSig(CONTRACT_NAME, owners, 2, SALT);
  }

  function test_create2_differentCreatorsGetDifferentAddresses() public {
    address predictedAlice = factory.predictMultiSigAddress(alice, CONTRACT_NAME, owners, 2, SALT);
    address predictedBob = factory.predictMultiSigAddress(bob, CONTRACT_NAME, owners, 2, SALT);
    assertTrue(predictedAlice != predictedBob);

    vm.prank(alice);
    assertEq(factory.createDeterministicMultiSig(CONTRACT_NAME, owners, 2, SALT), predictedAlice);
    vm.prank(bob);
    assertEq(factory.createDeterministicMultiSig(CONTRACT_NAME, owners, 2, SALT), predictedBob);
  }

  function test_create2_directDeployerCallCannotSquatFactoryAddress() public {
    address predicted = factory.predictMultiSigAddress(alice, CONTRACT_NAME, owners, 2, SALT);

    // A third party replays the factory's derived salt directly against the
    // deployer; the deployer namespaces salts by caller, so the address it
    // deploys to differs from the factory-mediated one.
    bytes32 factorySalt = factory.computeSalt(alice, SALT);
    vm.prank(bob);
    address squatted = simpleDeployer.deployMyMultiSigDeterministic(factorySalt, CONTRACT_NAME, owners, 2);
    assertTrue(squatted != predicted);

    vm.prank(alice);
    address deployed = factory.createDeterministicMultiSig(CONTRACT_NAME, owners, 2, SALT);
    assertEq(deployed, predicted);
  }

  function test_create2_predictIsPureFunctionOfInputs() public {
    address before = factory.predictMultiSigAddress(alice, CONTRACT_NAME, owners, 2, SALT);
    vm.roll(block.number + 100);
    vm.warp(block.timestamp + 1 days);
    assertEq(factory.predictMultiSigAddress(alice, CONTRACT_NAME, owners, 2, SALT), before);
    assertTrue(factory.predictMultiSigAddress(alice, CONTRACT_NAME, owners, 2, keccak256('other-salt')) != before);
    assertTrue(factory.predictMultiSigAddress(alice, CONTRACT_NAME, owners, 3, SALT) != before);
  }
}
