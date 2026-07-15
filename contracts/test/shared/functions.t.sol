// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Vm } from 'forge-std/Vm.sol';
import { Constants } from './constants.t.sol';
import { Errors } from './errors.t.sol';
import { Signatures } from './signatures.t.sol';

import { MyMultiSigFactory } from '../../MyMultiSigFactory.sol';
import { MyMultiSigFactoryWithChugSplash } from '../../MyMultiSigFactoryWithChugSplash.sol';
import { MyMultiSig } from '../../MyMultiSig.sol';
import { MyMultiSigExtended } from '../../MyMultiSigExtended.sol';
import { MyMultiSigDeployer } from '../../MyMultiSigDeployer.sol';
import { MyMultiSigExtendedDeployer } from '../../MyMultiSigExtendedDeployer.sol';
import { MyMultiSigAdvancedDeployer } from '../../MyMultiSigAdvancedDeployer.sol';

contract Functions is Constants, Signatures {
  // Canonical v0.7 EntryPoint address used by the Foundry test sandbox.
  // Production deployments ship this in `constants/extended.ts`; tests use
  // a fixed sentinel because the address is the same on every chain.
  // Wrapped in `bytes20` to bypass Solidity's strict address-literal
  // checksum check (the canonical casing
  // `0x0000000071727De22E5E9d8BDe0dFeC0CEB6a7d7` raises an error on some
  // compilers due to mixing cases).
  address internal constant ENTRY_POINT = address(bytes20(uint160(0x0571727dE22E5E9d8BDe0dfeC0cEB6A7d7)));

  uint8 LOG_LEVEL;
  uint256 DEFAULT_BLOCKS_COUNT;

  MyMultiSigFactory public myMultiSigFactory;
  MyMultiSigFactoryWithChugSplash public myMultiSigFactoryWithChugSplash;
  MyMultiSigExtended public myMultiSigExtended;
  MyMultiSig public myMultiSig;

  enum TestType {
    TestWithFactory,
    TestWithChugSplash,
    TestWithoutFactory,
    TestWithFactory_extended,
    TestWithChugSplash_extended,
    TestWithoutFactory_extended
  }

  // MyMultiSigFactory
  event MyMultiSigCreated(
    address indexed creator,
    address indexed contractAddress,
    uint256 indexed contractIndex,
    string contractName,
    address[] originalOwners
  );

  // MyMultiSig
  event OwnerAdded(address indexed owner);
  event OwnerRemoved(address indexed owner);
  event ThresholdChanged(uint256 indexed threshold);
  event TransactionExecuted(
    address indexed sender,
    address indexed to,
    uint256 indexed value,
    bytes data,
    uint256 txnGas,
    uint256 txnNonce
  );
  event TxFailure(
    address indexed sender,
    address indexed to,
    uint256 indexed value,
    bytes data,
    uint256 txnGas,
    uint256 txnNonce,
    bytes reason
  );
  event ContractEndOfLife(uint256 indexed txNonceLefts);
  event MultiRequestExecuted(uint256 indexed txNonce, bool[] successes, bytes[] returnData);

  function initialize_tests(uint8 LOG_LEVEL_, TestType testType_) public returns (MyMultiSigFactory, MyMultiSig) {
    // Set general test settings
    LOG_LEVEL = LOG_LEVEL_;
    vm.roll(1);
    vm.warp(100);
    vm.prank(ADMIN);

    if (testType_ == TestType.TestWithFactory || testType_ == TestType.TestWithFactory_extended) {
      myMultiSigFactory = new MyMultiSigFactory(
        address(new MyMultiSigDeployer()),
        address(new MyMultiSigExtendedDeployer()),
        address(new MyMultiSigAdvancedDeployer(address(new MyMultiSigExtendedDeployer())))
      );
      if (testType_ == TestType.TestWithFactory)
        (, myMultiSig) = help_createMultiSig(ADMIN, CONTRACT_NAME, OWNERS, DEFAULT_THRESHOLD);
      // else
      //   (, myMultiSig) = createMyMultiSigExtended(ADMIN, CONTRACT_NAME, OWNERS, DEFAULT_THRESHOLD, ONLY_OWNERS_REQUEST);
    } else if (testType_ == TestType.TestWithChugSplash || testType_ == TestType.TestWithChugSplash_extended) {
      // if (testType_ == TestType.TestWithChugSplash)
      // myMultiSigFactoryWithChugSplash = new MyMultiSigFactoryWithChugSplash(
      //   address(new MyMultiSigDeployer()),
      //   address(new MyMultiSigExtendedDeployer())
      // );
      // else
      // (, myMultiSig) = help_createMultiSig(ADMIN, CONTRACT_NAME, OWNERS, DEFAULT_THRESHOLD);
    } else if (testType_ == TestType.TestWithoutFactory_extended) {
      myMultiSigExtended = new MyMultiSigExtended(CONTRACT_NAME, OWNERS, DEFAULT_THRESHOLD, ONLY_OWNERS_REQUEST, ENTRY_POINT);
      myMultiSig = MyMultiSig(payable(address(myMultiSigExtended)));
    } else {
      myMultiSig = new MyMultiSig(CONTRACT_NAME, OWNERS, DEFAULT_THRESHOLD);
    }

    vm.roll(block.number + 1);
    vm.warp(block.timestamp + 100);

    return (myMultiSigFactory, myMultiSig);
  }

  // MyMultiSigFactory
  function help_createMultiSig(
    address prank_,
    string memory contractName_,
    address[] memory owners_,
    uint16 threshold_,
    Errors.RevertStatus revertType_
  ) internal returns (uint256 multiSigId, MyMultiSig multiSig) {
    vm.prank(prank_);
    verify_revertCall(revertType_);
    address newMultisigAddress = myMultiSigFactory.createMultiSig(contractName_, owners_, threshold_);

    if (revertType_ == Errors.RevertStatus.Success) {
      multiSigId = myMultiSigFactory.multiSigCount();
      multiSig = MyMultiSig(payable(myMultiSigFactory.multiSig(multiSigId - 1)));
      assertEq(multiSig.name(), contractName_);
      assertEq(multiSig.threshold(), threshold_);
      uint256 ownersLength = owners_.length;
      assertEq(multiSig.ownerCount(), ownersLength);
      for (uint256 i = 0; i < ownersLength; i++) {
        assertTrue(multiSig.isOwner(owners_[i]));
      }
    }
  }

  function help_createMultiSig(
    address prank_,
    string memory contractName_,
    address[] memory owners_,
    uint16 threshold_
  ) internal returns (uint256 multiSigId, MyMultiSig multiSig) {
    return help_createMultiSig(prank_, contractName_, owners_, threshold_, Errors.RevertStatus.Success);
  }

  // MyMultiSigFactory
  /// @notice Resolve the EIP-712 `version` field for the deployed wallet.
  ///         As of v0.5.0 every wallet class returns the same canonical
  ///         `'0.5.0'`; the helper stays generic by reading
  ///         `wallet.version()` so it never goes stale on a future bump.
  function _versionFor(MyMultiSig multiSig_) public view returns (string memory) {
    return multiSig_.version();
  }

  function build_domainSeparator(MyMultiSig multiSig_, string memory contractName_) public view returns (bytes32) {
    return
      keccak256(
        abi.encode(
          keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'),
          bytes32(keccak256(bytes(contractName_))),
          bytes32(keccak256(bytes(_versionFor(multiSig_)))),
          block.chainid,
          address(multiSig_)
        )
      );
  }

  /// @dev Mirror of `MyMultiSig.Vote` used solely so we can encode an
  ///      array-of-tuples that matches what `_decodeVotes` expects. The
  ///      on-the-wire encoding must be that of an array of
  ///      `(address owner, bytes sig)` tuples — NOT two parallel arrays.
  struct Vote {
    address owner;
    bytes sig;
  }

  /// @dev Compute the EIP-712 inner hash for either the v0.4.0 base
  ///      wallet or the v0.5.0 extended wallet. Factored into a helper
  ///      to keep `build_signatures` under the stack-depth limit.
  function build_innerHash(
    MyMultiSig multiSig_,
    address to_,
    uint256 value_,
    bytes memory data_,
    uint256 txnGas_,
    uint256 nonce_,
    uint256 validUntil_
  ) public view returns (bytes32) {
    bool extended = isExtended(multiSig_);
    bytes32 typehash = extended
      ? keccak256('Transaction(address to,uint256 value,bytes data,uint256 gas,uint96 nonce,uint256 validUntil,uint8 operation)')
      : keccak256('Transaction(address to,uint256 value,bytes data,uint256 gas,uint96 nonce,uint256 validUntil)');
    if (extended) {
      return keccak256(
        abi.encode(typehash, to_, value_, keccak256(data_), txnGas_, nonce_, validUntil_, uint8(0))
      );
    }
    return keccak256(abi.encode(typehash, to_, value_, keccak256(data_), txnGas_, nonce_, validUntil_));
  }

  function build_signatures(
    MyMultiSig multiSig_,
    uint256[] memory ownersPk_,
    address to_,
    uint256 value_,
    bytes memory data_,
    uint256 txnGas_,
    uint256 validUntil_
  ) public returns (bytes memory signatures) {
    uint256 nonce = multiSig_.nonce();
    bytes32 domainSeparator = build_domainSeparator(multiSig_, multiSig_.name());
    bytes32 innerHash = build_innerHash(multiSig_, to_, value_, data_, txnGas_, nonce, validUntil_);
    Vote[] memory votes = new Vote[](ownersPk_.length);
    for (uint256 i = 0; i < ownersPk_.length; i++) {
      votes[i] = Vote({
        owner: vm.addr(ownersPk_[i]),
        sig: signature_signHashed(ownersPk_[i], domainSeparator, innerHash)
      });
    }
    signatures = abi.encode(votes);
  }

  /// @dev Overload with `validUntil_ = 0` for callers that don't care about
  ///      expiry. Mirrors the TS helper's default param.
  function build_signatures(
    MyMultiSig multiSig_,
    uint256[] memory ownersPk_,
    address to_,
    uint256 value_,
    bytes memory data_,
    uint256 txnGas_
  ) public returns (bytes memory signatures) {
    return build_signatures(multiSig_, ownersPk_, to_, value_, data_, txnGas_, 0);
  }

  function build_multiRequest(
    address[] memory to_,
    uint256[] memory value_,
    bytes[] memory data_,
    uint256[] memory txGas_
  ) internal pure returns (bytes memory) {
    return abi.encodeWithSignature('multiRequest(address[],uint256[],bytes[],uint256[])', to_, value_, data_, txGas_);
  }

  /// @notice Encodes the calldata for the atomic-batch entry point
  ///         `multiRequestStrict(address[],uint256[],bytes[],uint256[])` —
  ///         the strict variant that reverts on first inner-call failure.
  function build_multiRequestStrict(
    address[] memory to_,
    uint256[] memory value_,
    bytes[] memory data_,
    uint256[] memory txGas_
  ) internal pure returns (bytes memory) {
    return
      abi.encodeWithSignature(
        'multiRequestStrict(address[],uint256[],bytes[],uint256[])',
        to_,
        value_,
        data_,
        txGas_
      );
  }

  function build_addOwner(address owner) internal pure returns (bytes memory) {
    return abi.encodeWithSignature('addOwner(address)', owner);
  }

  function build_removeOwner(address owner) internal pure returns (bytes memory) {
    return abi.encodeWithSignature('removeOwner(address)', owner);
  }

  function build_changeThreshold(uint16 newThreshold) internal pure returns (bytes memory) {
    return abi.encodeWithSignature('changeThreshold(uint16)', newThreshold);
  }

  function build_replaceOwner(address oldOwner, address newOwner) internal pure returns (bytes memory) {
    return abi.encodeWithSignature('replaceOwner(address,address)', oldOwner, newOwner);
  }

  function help_execTransaction(
    MyMultiSig multiSig_,
    address prank_,
    address to_,
    uint256 value_,
    bytes memory data_,
    uint256 txnGas_,
    bytes memory signatures_,
    uint256 nonce_,
    Errors.RevertStatus revertType_
  ) internal {
    vm.prank(prank_);
    verify_revertCall(revertType_);

    // Only emit the `TransactionExecuted` event expectation on success. For
    // custom-error reverts (`InvalidSignatures`, `SignatureExpired`, …) no
    // event is emitted and `vm.expectRevert` from `verify_revertCall`
    // already enforces the failure path. Asserting a `TxFailure` emit on
    // top of an `expectRevert` would leave the expect dangling when the
    // outer call reverts before reaching the inner `call`.
    if (revertType_ == Errors.RevertStatus.Success) {
      vm.expectEmit(true, true, true, false);
      emit TransactionExecuted(prank_, to_, value_, data_, txnGas_, nonce_);
    }
    // v0.5.0 — extended wallets use the 8-arg overload (txnNonce +
    // operation). Base wallets still take the 5-arg overload.
    if (isExtended(multiSig_)) {
      MyMultiSigExtended(payable(address(multiSig_))).execTransaction(
        to_,
        value_,
        data_,
        txnGas_,
        nonce_,
        0,
        0, // operation = 0 (CALL)
        signatures_
      );
    } else {
      multiSig_.execTransaction(to_, value_, data_, txnGas_, signatures_);
    }
  }

  /// @notice Overload that threads `validUntil_` through the 6-arg
  ///         `execTransaction` overload (or the 7-arg Extended overload).
  ///         Selects the right arity based on whether `multiSig_` is the
  ///         base wallet or the Extended variant.
  function help_execTransaction(
    MyMultiSig multiSig_,
    address prank_,
    address to_,
    uint256 value_,
    bytes memory data_,
    uint256 txnGas_,
    uint256 validUntil_,
    bytes memory signatures_,
    uint256 nonce_,
    Errors.RevertStatus revertType_
  ) internal {
    // `isExtended` is a staticcall — it must run BEFORE `vm.prank`,
    // otherwise the prank is consumed by the staticcall instead of the
    // real `execTransaction` below.
    bool extended = isExtended(multiSig_);
    vm.prank(prank_);
    verify_revertCall(revertType_);

    if (revertType_ == Errors.RevertStatus.Success) {
      vm.expectEmit(true, true, true, false);
      emit TransactionExecuted(prank_, to_, value_, data_, txnGas_, nonce_);
    }
    if (extended) {
      MyMultiSigExtended extended_ = MyMultiSigExtended(payable(address(multiSig_)));
      // v0.5.0 — 8-arg overload with explicit `operation` byte. The
      // disabled v0.4.0 7-arg overload reverts with
      // `RequiresOperationByte()`.
      extended_.execTransaction(to_, value_, data_, txnGas_, nonce_, validUntil_, 0, signatures_);
    } else {
      multiSig_.execTransaction(to_, value_, data_, txnGas_, validUntil_, signatures_);
    }
  }

  function help_execTransaction(
    MyMultiSig multiSig_,
    address prank_,
    address to_,
    uint256 value_,
    bytes memory data_,
    uint256 txnGas_,
    bytes memory signatures_,
    Errors.RevertStatus revertType_
  ) internal {
    help_execTransaction(multiSig_, prank_, to_, value_, data_, txnGas_, signatures_, multiSig_.nonce(), revertType_);
  }

  function help_execTransaction(
    MyMultiSig multiSig_,
    address prank_,
    address to_,
    uint256 value_,
    bytes memory data_,
    uint256 txnGas_,
    bytes memory signatures_
  ) internal {
    help_execTransaction(multiSig_, prank_, to_, value_, data_, txnGas_, signatures_, Errors.RevertStatus.Success);
  }

  /// @dev True iff `multiSig_` is a `MyMultiSigExtended` instance. We sniff
  ///      via the `allowOnlyOwnerRequest()` accessor that only Extended
  ///      exposes; this keeps the helper generic over both wallets without
  ///      a runtime type import.
  function isExtended(MyMultiSig multiSig_) internal view returns (bool) {
    (bool ok, bytes memory ret) = address(multiSig_).staticcall(
      abi.encodeWithSignature('allowOnlyOwnerRequest()')
    );
    return ok && ret.length >= 32;
  }

  function help_addOwner(
    address prank_,
    MyMultiSig multiSig_,
    uint256[] memory ownersPk_,
    address owner_,
    Errors.RevertStatus revertType_
  ) internal {
    if (revertType_ == Errors.RevertStatus.Success) assertTrue(!multiSig_.isOwner(owner_));
    vm.prank(prank_);
    address to = address(multiSig_);
    uint256 value = 0;
    bytes memory data = build_addOwner(owner_);
    uint256 gas = DEFAULT_GAS;
    help_execTransaction(
      multiSig_,
      prank_,
      to,
      value,
      data,
      gas,
      build_signatures(multiSig_, ownersPk_, to, value, data, gas)
    );
    if (revertType_ == Errors.RevertStatus.Success) assertTrue(multiSig_.isOwner(owner_));
  }

  function help_addOwner(address prank_, MyMultiSig multiSig_, uint256[] memory ownersPk_, address owner_) internal {
    help_addOwner(prank_, multiSig_, ownersPk_, owner_, Errors.RevertStatus.Success);
  }

  function help_removeOwner(
    address prank_,
    MyMultiSig multiSig_,
    uint256[] memory ownersPk_,
    address owner_,
    Errors.RevertStatus revertType_
  ) internal {
    if (revertType_ == Errors.RevertStatus.Success) assertTrue(multiSig_.isOwner(owner_));
    vm.prank(prank_);
    address to = address(multiSig_);
    uint256 value = 0;
    bytes memory data = build_removeOwner(owner_);
    uint256 gas = DEFAULT_GAS;
    help_execTransaction(
      multiSig_,
      prank_,
      to,
      value,
      data,
      gas,
      build_signatures(multiSig_, ownersPk_, to, value, data, gas)
    );
    if (revertType_ == Errors.RevertStatus.Success) assertTrue(!multiSig_.isOwner(owner_));
  }

  function help_removeOwner(address prank_, MyMultiSig multiSig_, uint256[] memory ownersPk_, address owner_) internal {
    help_removeOwner(prank_, multiSig_, ownersPk_, owner_, Errors.RevertStatus.Success);
  }

  function help_changeThreshold(
    address prank_,
    MyMultiSig multiSig_,
    uint256[] memory ownersPk_,
    uint16 newThreshold_,
    Errors.RevertStatus revertType_
  ) internal {
    vm.prank(prank_);
    address to = address(multiSig_);
    uint256 value = 0;
    bytes memory data = build_changeThreshold(newThreshold_);
    uint256 gas = DEFAULT_GAS;
    help_execTransaction(
      multiSig_,
      prank_,
      to,
      value,
      data,
      gas,
      build_signatures(multiSig_, ownersPk_, to, value, data, gas)
    );
    if (revertType_ == Errors.RevertStatus.Success) assertEq(multiSig_.threshold(), newThreshold_);
  }

  function help_changeThreshold(
    address prank_,
    MyMultiSig multiSig_,
    uint256[] memory ownersPk_,
    uint16 newThreshold_
  ) internal {
    help_changeThreshold(prank_, multiSig_, ownersPk_, newThreshold_, Errors.RevertStatus.Success);
  }

  function help_replaceOwner(
    address prank_,
    MyMultiSig multiSig_,
    uint256[] memory ownersPk_,
    address oldOwner_,
    address newOwner_,
    Errors.RevertStatus revertType_
  ) internal {
    if (revertType_ == Errors.RevertStatus.Success) {
      assertTrue(multiSig_.isOwner(oldOwner_));
      assertTrue(!multiSig_.isOwner(newOwner_));
    }
    vm.prank(prank_);
    address to = address(multiSig_);
    uint256 value = 0;
    bytes memory data = build_replaceOwner(oldOwner_, newOwner_);
    uint256 gas = DEFAULT_GAS;
    bytes memory signatures = build_signatures(multiSig_, ownersPk_, to, value, data, gas);
    help_execTransaction(multiSig_, prank_, to, value, data, gas, signatures);
    if (revertType_ == Errors.RevertStatus.Success) {
      assertTrue(!multiSig_.isOwner(oldOwner_));
      assertTrue(multiSig_.isOwner(newOwner_));
    }
  }

  function help_replaceOwner(
    address prank_,
    MyMultiSig multiSig_,
    uint256[] memory ownersPk_,
    address oldOwner_,
    address newOwner_
  ) internal {
    help_replaceOwner(prank_, multiSig_, ownersPk_, oldOwner_, newOwner_, Errors.RevertStatus.Success);
  }

  function help_multiRequest(
    address prank_,
    MyMultiSig multiSig_,
    uint256[] memory ownersPk_,
    address[] memory to_,
    uint256[] memory value_,
    bytes[] memory data_,
    uint256[] memory txGas_,
    Errors.RevertStatus revertType_
  ) internal {
    vm.prank(prank_);
    address to = address(multiSig_);
    uint256 value = 0;
    bytes memory data = build_multiRequest(to_, value_, data_, txGas_);
    uint256 gas;
    for (uint256 i = 0; i < to_.length; i++) {
      gas += txGas_[i];
    }
    uint96 nonce = multiSig_.nonce();
    bytes memory signatures = build_signatures(multiSig_, ownersPk_, to, value, data, gas);
    help_execTransaction(multiSig_, prank_, to, value, data, gas, signatures, nonce, revertType_);
  }

  /// @dev Invokes `multiRequest` on the wallet and returns the parsed
  ///      `MultiRequestExecuted` event along with the per-call arrays.
  ///      Used by the partial-failure / per-call-result tests.
  function help_multiRequestAndCapture(
    address prank_,
    MyMultiSig multiSig_,
    uint256[] memory ownersPk_,
    address[] memory to_,
    uint256[] memory value_,
    bytes[] memory data_,
    uint256[] memory txGas_
  ) internal returns (uint256 txNonce, bool[] memory successes, bytes[] memory returnData) {
    vm.prank(prank_);
    address to = address(multiSig_);
    uint256 value = 0;
    bytes memory data = build_multiRequest(to_, value_, data_, txGas_);
    uint256 gas;
    for (uint256 i = 0; i < to_.length; i++) {
      gas += txGas_[i];
    }
    uint96 nonce = multiSig_.nonce();
    bytes memory signatures = build_signatures(multiSig_, ownersPk_, to, value, data, gas);

    vm.recordLogs();
    multiSig_.execTransaction(to, value, data, gas, signatures);
    Vm.Log[] memory logs = vm.getRecordedLogs();

    bool found;
    for (uint256 i = 0; i < logs.length; i++) {
      if (logs[i].topics[0] == keccak256('MultiRequestExecuted(uint256,bool[],bytes[])')) {
        // txNonce is the indexed first parameter — it lives in topics[1].
        txNonce = uint256(logs[i].topics[1]);
        (successes, returnData) = abi.decode(logs[i].data, (bool[], bytes[]));
        found = true;
        break;
      }
    }
    require(found, 'MultiRequestExecuted event not found');
    assertEq(txNonce, nonce);
  }

  function help_multiRequest(
    address prank_,
    MyMultiSig multiSig_,
    uint256[] memory ownersPk_,
    address[] memory to_,
    uint256[] memory value_,
    bytes[] memory data_,
    uint256[] memory txGas_
  ) internal {
    help_multiRequest(prank_, multiSig_, ownersPk_, to_, value_, data_, txGas_, Errors.RevertStatus.Success);
  }
}
