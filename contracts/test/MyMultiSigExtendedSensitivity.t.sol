// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Helper } from './shared/helper.t.sol';
import { MyMultiSig } from '../MyMultiSig.sol';
import { MyMultiSigExtended } from '../MyMultiSigExtended.sol';
import { MockERC20 } from '../mocks/MockERC20.sol';
import { MockERC721 } from '../mocks/MockERC721.sol';
import { SessionKeyModule } from '../modules/SessionKeyModule.sol';
import './shared/mocks/MockEntryPoint.t.sol';
import { ERC721 } from '@openzeppelin/contracts/token/ERC721/ERC721.sol';

/// @dev ERC-721 that can mint token id `0`, which `MockERC721` rejects.
contract ZeroIdERC721 is ERC721 {
  constructor(address holder) ERC721('ZeroId', 'ZERO') {
    _mint(holder, 0);
  }
}

/// @title MyMultiSigExtended timelock sensitivity
/// @notice Pins down which calls the timelock delays: token transfers and
///         grants, module configuration, and batches holding any sensitive
///         inner call, while revocations and cancellations stay instant.
contract MyMultiSigExtendedSensitivityTest is Helper {
  MyMultiSigExtended internal wallet;
  MockERC20 internal token;
  MockERC721 internal nft;
  address internal constant BOB = address(0xb0b);
  uint256 internal constant TXN_GAS = 1_000_000;
  uint256 internal constant DELAY = 1 days;

  function setUp() public {
    (myMultiSigFactory, myMultiSig) = initialize_tests(LOG_LEVEL, TestType.TestWithFactory);

    address[] memory owners = new address[](3);
    for (uint256 i = 0; i < 3; i++) owners[i] = OWNERS[i];
    wallet = new MyMultiSigExtended('SensitivityWallet', owners, 2, ONLY_OWNERS_REQUEST, address(new MockEntryPoint()));
    vm.deal(address(wallet), 10 ether);

    token = new MockERC20();
    token.mint(address(wallet), 1_000 ether);
    nft = new MockERC721();
    nft.mint(address(wallet), 1);
  }

  // ---------------------------------------------------------------- helpers

  function _sign(address to, uint256 value, bytes memory data, uint256 nonce_) internal returns (bytes memory) {
    bytes32 domainSeparator = build_domainSeparator(wallet, wallet.name());
    bytes32 typehash = keccak256(
      'Transaction(address to,uint256 value,bytes data,uint256 gas,uint96 nonce,uint256 validUntil,uint8 operation)'
    );
    bytes32 structHash = keccak256(
      abi.encode(typehash, to, value, keccak256(data), TXN_GAS, nonce_, uint256(0), uint8(0))
    );
    Vote[] memory votes = new Vote[](2);
    votes[0] = Vote({ owner: OWNERS[0], sig: signature_signHashed(OWNERS_PK[0], domainSeparator, structHash) });
    votes[1] = Vote({ owner: OWNERS[1], sig: signature_signHashed(OWNERS_PK[1], domainSeparator, structHash) });
    return abi.encode(votes);
  }

  function _exec(address to, uint256 value, bytes memory data) internal {
    uint256 n = wallet.nonce();
    bytes memory sigs = _sign(to, value, data, n);
    vm.prank(OWNERS[0]);
    wallet.execTransaction(to, value, data, TXN_GAS, n, 0, 0, sigs);
  }

  function _expectDelayed(address to, uint256 value, bytes memory data) internal {
    uint256 n = wallet.nonce();
    bytes memory sigs = _sign(to, value, data, n);
    bytes4 sel = data.length >= 4 ? bytes4(data) : bytes4(0);
    vm.expectRevert(abi.encodeWithSelector(MyMultiSigExtended.SensitiveCallRequiresDelay.selector, to, sel, value));
    vm.prank(OWNERS[0]);
    wallet.execTransaction(to, value, data, TXN_GAS, n, 0, 0, sigs);
  }

  function _scheduleAndRun(address to, uint256 value, bytes memory data) internal {
    uint256 n = wallet.nonce();
    bytes memory sigs = _sign(to, value, data, n);
    vm.prank(OWNERS[0]);
    wallet.scheduleTransaction(to, value, data, TXN_GAS, n, 0, sigs);
    vm.warp(block.timestamp + DELAY);
    wallet.executeScheduled(to, value, data, TXN_GAS, n, 0);
  }

  function _enableTimelock() internal {
    vm.prank(address(wallet));
    wallet.setTimelockDelay(DELAY);
  }

  function _batch(
    bytes4 sel,
    address[] memory to,
    uint256[] memory value,
    bytes[] memory data
  ) internal pure returns (bytes memory) {
    uint256[] memory gas = new uint256[](to.length);
    for (uint256 i; i < to.length; i++) gas[i] = 200_000;
    return abi.encodeWithSelector(sel, to, value, data, gas);
  }

  // ------------------------------------------------------- token transfers

  function test_tokenTransfer_isInstantWithoutTimelock() public {
    _exec(address(token), 0, abi.encodeCall(token.transfer, (BOB, 1 ether)));
    assertEq(token.balanceOf(BOB), 1 ether);
  }

  function test_tokenTransfer_requiresDelay_andRunsWhenScheduled() public {
    _enableTimelock();
    bytes memory data = abi.encodeCall(token.transfer, (BOB, 1 ether));
    _expectDelayed(address(token), 0, data);
    _scheduleAndRun(address(token), 0, data);
    assertEq(token.balanceOf(BOB), 1 ether);
  }

  function test_tokenThreshold_letsSmallAmountsThrough() public {
    _enableTimelock();
    vm.prank(address(wallet));
    wallet.setTokenSensitiveThreshold(address(token), 10 ether);
    assertEq(wallet.tokenSensitiveThreshold(address(token)), 10 ether);

    _exec(address(token), 0, abi.encodeCall(token.transfer, (BOB, 9 ether)));
    assertEq(token.balanceOf(BOB), 9 ether);
    _expectDelayed(address(token), 0, abi.encodeCall(token.transfer, (BOB, 10 ether)));
    _expectDelayed(address(token), 0, abi.encodeCall(token.approve, (BOB, 10 ether)));
    _expectDelayed(address(token), 0, abi.encodeCall(token.transferFrom, (address(wallet), BOB, 10 ether)));
  }

  function test_setTokenSensitiveThreshold_isDefaultSensitive() public {
    assertTrue(wallet.isSensitiveSelector(MyMultiSigExtended.setTokenSensitiveThreshold.selector));
    _enableTimelock();
    _expectDelayed(
      address(wallet),
      0,
      abi.encodeCall(MyMultiSigExtended.setTokenSensitiveThreshold, (address(token), 1_000 ether))
    );
  }

  function test_erc20Approve_isDelayed_zeroRunsBelowThreshold() public {
    _enableTimelock();
    _expectDelayed(address(token), 0, abi.encodeCall(token.approve, (BOB, 1)));
    _expectDelayed(address(token), 0, abi.encodeCall(token.approve, (BOB, 0)));

    vm.prank(address(wallet));
    wallet.setTokenSensitiveThreshold(address(token), 1 ether);
    _exec(address(token), 0, abi.encodeCall(token.approve, (BOB, 0)));
  }

  function test_nftApproveOfTokenIdZero_isDelayed() public {
    ZeroIdERC721 zeroNft = new ZeroIdERC721(address(wallet));
    _enableTimelock();
    bytes memory data = abi.encodeCall(zeroNft.approve, (BOB, 0));
    _expectDelayed(address(zeroNft), 0, data);
    _scheduleAndRun(address(zeroNft), 0, data);
    assertEq(zeroNft.getApproved(0), BOB);
  }

  function test_nft_transfersAndOperatorGrants_areDelayed() public {
    _enableTimelock();
    _expectDelayed(address(nft), 0, abi.encodeWithSignature('safeTransferFrom(address,address,uint256)', address(wallet), BOB, 1));
    _expectDelayed(
      address(nft),
      0,
      abi.encodeWithSignature('safeTransferFrom(address,address,uint256,bytes)', address(wallet), BOB, 1, '')
    );
    _expectDelayed(address(nft), 0, abi.encodeCall(nft.transferFrom, (address(wallet), BOB, 1)));
    _expectDelayed(address(nft), 0, abi.encodeCall(nft.setApprovalForAll, (BOB, true)));
    _exec(address(nft), 0, abi.encodeCall(nft.setApprovalForAll, (BOB, false)));
  }

  function test_selectorOverride_exemptsAndForcesExternalCalls() public {
    _enableTimelock();
    vm.startPrank(address(wallet));
    wallet.setSensitiveSelector(token.transfer.selector, false);
    wallet.setSensitiveSelector(token.burn.selector, true);
    vm.stopPrank();

    _exec(address(token), 0, abi.encodeCall(token.transfer, (BOB, 1 ether)));
    assertEq(token.balanceOf(BOB), 1 ether);
    _expectDelayed(address(token), 0, abi.encodeCall(token.burn, (1 ether)));
  }

  // ------------------------------------------------------------- modules

  function test_moduleConfiguration_isDelayed_revokeIsInstant() public {
    SessionKeyModule module = new SessionKeyModule();
    vm.prank(address(wallet));
    wallet.enableModule(address(module));
    _enableTimelock();

    address[] memory targets = new address[](1);
    targets[0] = BOB;
    bytes memory grant = abi.encodeCall(
      module.grantSessionKey,
      (address(0x5e55), 0, uint48(block.timestamp + 30 days), 1 ether, targets, new bytes4[](0))
    );
    _expectDelayed(address(module), 0, grant);
    _scheduleAndRun(address(module), 0, grant);
    assertTrue(module.isSessionKeyActive(address(wallet), address(0x5e55)));

    _exec(address(module), 0, abi.encodeCall(module.revokeSessionKey, (address(wallet), address(0x5e55))));
    assertFalse(module.isSessionKeyActive(address(wallet), address(0x5e55)));
  }

  // ------------------------------------------------------------- batches

  function test_batchWithSensitiveCall_canBeScheduled() public {
    _enableTimelock();
    address[] memory to = new address[](2);
    uint256[] memory value = new uint256[](2);
    bytes[] memory data = new bytes[](2);
    to[0] = address(wallet);
    data[0] = abi.encodeWithSignature('changeThreshold(uint16)', uint16(1));
    to[1] = address(wallet);
    data[1] = abi.encodeWithSignature('removeOwner(address)', OWNERS[2]);

    for (uint256 k; k < 2; k++) {
      bytes4 sel = k == 0 ? MyMultiSig.multiRequestStrict.selector : MyMultiSig.multiRequest.selector;
      bytes memory batch = _batch(sel, to, value, data);
      _expectDelayed(address(wallet), 0, batch);
      if (k == 1) {
        _scheduleAndRun(address(wallet), 0, batch);
        assertEq(wallet.threshold(), 1);
        assertFalse(wallet.isOwner(OWNERS[2]));
      }
    }
  }

  function test_batchWithoutSensitiveCall_isNotSchedulable() public {
    _enableTimelock();
    vm.prank(address(wallet));
    wallet.setSensitiveSelector(token.transfer.selector, false);

    address[] memory to = new address[](1);
    uint256[] memory value = new uint256[](1);
    bytes[] memory data = new bytes[](1);
    to[0] = address(token);
    data[0] = abi.encodeCall(token.transfer, (BOB, 1 ether));
    bytes memory batch = _batch(MyMultiSig.multiRequestStrict.selector, to, value, data);

    uint256 n = wallet.nonce();
    bytes memory sigs = _sign(address(wallet), 0, batch, n);
    vm.expectRevert(MyMultiSigExtended.NotSensitive.selector);
    vm.prank(OWNERS[0]);
    wallet.scheduleTransaction(address(wallet), 0, batch, TXN_GAS, n, 0, sigs);

    _exec(address(wallet), 0, batch);
    assertEq(token.balanceOf(BOB), 1 ether);
  }

  function test_batchValueSum_meetsValueThreshold() public {
    _enableTimelock();
    vm.prank(address(wallet));
    wallet.setSensitiveValueThreshold(1 ether);

    address[] memory to = new address[](2);
    uint256[] memory value = new uint256[](2);
    bytes[] memory data = new bytes[](2);
    to[0] = BOB;
    to[1] = BOB;
    value[0] = 0.6 ether;
    value[1] = 0.6 ether;
    bytes memory batch = _batch(MyMultiSig.multiRequestStrict.selector, to, value, data);
    _expectDelayed(address(wallet), 0, batch);
    _scheduleAndRun(address(wallet), 0, batch);
    assertEq(BOB.balance, 1.2 ether);
  }

  // ------------------------------------------------------- cancellations

  function test_cancelScheduled_isInstantUnderTimelock() public {
    _enableTimelock();
    assertFalse(wallet.isSensitiveSelector(MyMultiSigExtended.cancelScheduled.selector));

    bytes memory data = abi.encodeCall(token.transfer, (BOB, 1 ether));
    uint256 n = wallet.nonce();
    bytes memory sigs = _sign(address(token), 0, data, n);
    vm.prank(OWNERS[0]);
    bytes32 txHash = wallet.scheduleTransaction(address(token), 0, data, TXN_GAS, n, 0, sigs);

    _exec(address(wallet), 0, abi.encodeCall(MyMultiSigExtended.cancelScheduled, (txHash)));
    assertEq(wallet.scheduledReadyAt(txHash), 0);
  }

  // -------------------------------------------------- requireTxSuccess

  function _failingBatch() internal view returns (bytes memory) {
    address[] memory to = new address[](1);
    uint256[] memory value = new uint256[](1);
    bytes[] memory data = new bytes[](1);
    to[0] = address(token);
    data[0] = abi.encodeCall(token.transfer, (BOB, 1_000_000 ether));
    return _batch(MyMultiSig.multiRequest.selector, to, value, data);
  }

  function test_multiRequest_honorsRequireTxSuccess() public {
    vm.prank(address(wallet));
    wallet.setRequireTxSuccess(true);

    bytes memory batch = _failingBatch();
    uint256 n = wallet.nonce();
    bytes memory sigs = _sign(address(wallet), 0, batch, n);
    vm.expectPartialRevert(MyMultiSig.BatchCallFailed.selector);
    vm.prank(OWNERS[0]);
    wallet.execTransaction(address(wallet), 0, batch, TXN_GAS, n, 0, 0, sigs);
    assertEq(wallet.nonce(), n);
  }

  function test_multiRequest_recordsFailureWhenRequireTxSuccessOff() public {
    vm.recordLogs();
    _exec(address(wallet), 0, _failingBatch());
    assertEq(wallet.nonce(), 1);
    assertEq(token.balanceOf(BOB), 0);
  }
}
