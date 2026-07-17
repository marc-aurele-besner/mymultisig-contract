// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import '@openzeppelin/contracts/utils/Create2.sol';

import './MyMultiSigExtended.sol';
import './interfaces/IMyMultiSigExtendedDeployer.sol';

/// @title MyMultiSigExtendedDeployer
/// @notice Deploys `MyMultiSigExtended` wallets so the factory doesn't have
///         to embed the wallet's creation bytecode (which is even larger
///         than MyMultiSig's because of the extra delegation / 4337 /
///         operation-byte logic).
/// @dev    The wallet's creation code is itself larger than the EIP-170
///         runtime-code limit (24,576 bytes), so it cannot live in this
///         contract's runtime code either. Instead, the constructor splits
///         `type(MyMultiSigExtended).creationCode` into two data-only store
///         contracts (each a STOP byte followed by raw bytes, so the data can
///         never be executed) and the deploy/predict functions reassemble the
///         byte-identical creation code from those stores in memory. The
///         creation code is only ever carried in this contract's *initcode*,
///         which is bounded by EIP-3860's 49,152-byte limit, keeping the
///         deployed runtime of every contract involved under EIP-170.
///
///         Two deploy paths exist: `deployMyMultiSigExtended` uses plain
///         CREATE, and `deployMyMultiSigExtendedDeterministic` uses CREATE2
///         so the wallet address is a pure function of this deployer's
///         address, the caller, the salt and the constructor arguments.
///         `predictMyMultiSigExtendedAddress` computes that address without
///         deploying.
contract MyMultiSigExtendedDeployer is IMyMultiSigExtendedDeployer {
  /// @notice Thrown when a creation-code store contract fails to deploy.
  error CreationCodeStoreDeploymentFailed();
  /// @notice Thrown when the wallet deployment fails without revert data
  ///         (e.g. a CREATE2 address collision).
  error MyMultiSigExtendedDeploymentFailed();

  address private immutable _creationCodeStore0;
  address private immutable _creationCodeStore1;
  uint256 private immutable _creationCodeSize0;
  uint256 private immutable _creationCodeSize1;

  constructor() {
    bytes memory creationCode = type(MyMultiSigExtended).creationCode;
    uint256 firstHalfSize = creationCode.length / 2;
    uint256 secondHalfSize = creationCode.length - firstHalfSize;
    _creationCodeStore0 = _deployCreationCodeStore(creationCode, 0, firstHalfSize);
    _creationCodeSize0 = firstHalfSize;
    _creationCodeStore1 = _deployCreationCodeStore(creationCode, firstHalfSize, secondHalfSize);
    _creationCodeSize1 = secondHalfSize;
  }

  function deployMyMultiSigExtended(
    string memory contractName_,
    address[] memory owners_,
    uint16 threshold_,
    bool isOnlyOwnerRequest_,
    address entryPoint_
  ) external override returns (address contractAddress) {
    contractAddress = _deployWallet(
      _walletInitCode(contractName_, owners_, threshold_, isOnlyOwnerRequest_, entryPoint_),
      0,
      false
    );
  }

  /// @notice Deploys a `MyMultiSigExtended` wallet via CREATE2.
  /// @dev    The effective salt mixes in `msg.sender`, so each caller of this
  ///         deployer gets its own address namespace: a third party calling
  ///         this function directly can never occupy an address that a
  ///         factory-mediated deploy would resolve to.
  ///         Reverts if a contract already exists at the target address
  ///         (same caller, salt and constructor arguments).
  /// @param salt_ Caller-chosen salt.
  /// @return contractAddress The deployed wallet address.
  function deployMyMultiSigExtendedDeterministic(
    bytes32 salt_,
    string memory contractName_,
    address[] memory owners_,
    uint16 threshold_,
    bool isOnlyOwnerRequest_,
    address entryPoint_
  ) external override returns (address contractAddress) {
    contractAddress = _deployWallet(
      _walletInitCode(contractName_, owners_, threshold_, isOnlyOwnerRequest_, entryPoint_),
      _callerSalt(salt_),
      true
    );
  }

  /// @notice Predicts the address `deployMyMultiSigExtendedDeterministic`
  ///         would deploy to for the same caller, salt and constructor
  ///         arguments.
  /// @dev    Must be called by the same account that will perform the deploy
  ///         (the salt is namespaced by `msg.sender`).
  function predictMyMultiSigExtendedAddress(
    bytes32 salt_,
    string memory contractName_,
    address[] memory owners_,
    uint16 threshold_,
    bool isOnlyOwnerRequest_,
    address entryPoint_
  ) external view override returns (address contractAddress) {
    contractAddress = Create2.computeAddress(
      _callerSalt(salt_),
      keccak256(_walletInitCode(contractName_, owners_, threshold_, isOnlyOwnerRequest_, entryPoint_))
    );
  }

  /// @notice The two store contracts holding the wallet's creation code.
  /// @dev    Concatenating their runtime code (minus each store's leading
  ///         STOP byte) yields `type(MyMultiSigExtended).creationCode`,
  ///         which lets anyone verify the deployed bytecode off-chain.
  function creationCodeStores() external view returns (address store0, address store1) {
    return (_creationCodeStore0, _creationCodeStore1);
  }

  /// @dev Deploys a data-only store contract whose runtime code is a STOP
  ///      byte followed by `creationCode_[offset_ : offset_ + length_]`.
  ///      The store's initcode is `PUSH2 <length_ + 1> DUP1 PUSH1 0x0a
  ///      RETURNDATASIZE CODECOPY RETURNDATASIZE RETURN` followed by the
  ///      runtime bytes it returns.
  function _deployCreationCodeStore(
    bytes memory creationCode_,
    uint256 offset_,
    uint256 length_
  ) private returns (address store) {
    bytes memory initCode = new bytes(length_ + 11);
    assembly {
      let ptr := add(initCode, 32)
      mstore8(ptr, 0x61)
      mstore8(add(ptr, 1), shr(8, add(length_, 1)))
      mstore8(add(ptr, 2), and(add(length_, 1), 0xff))
      // 80 600a 3d 39 3d f3, then the STOP guard byte of the runtime code
      mstore(add(ptr, 3), shl(192, 0x80600A3D393DF300))
      // Copy the chunk after the 11-byte prefix via the identity precompile
      // so exactly `length_` bytes are written.
      if iszero(staticcall(gas(), 4, add(add(creationCode_, 32), offset_), length_, add(ptr, 11), length_)) {
        revert(0, 0)
      }
      store := create(0, ptr, add(length_, 11))
    }
    if (store == address(0)) revert CreationCodeStoreDeploymentFailed();
  }

  /// @dev Reassembles `type(MyMultiSigExtended).creationCode` from the two
  ///      store contracts, skipping each store's leading STOP byte.
  function _walletCreationCode() private view returns (bytes memory creationCode) {
    address store0 = _creationCodeStore0;
    address store1 = _creationCodeStore1;
    uint256 size0 = _creationCodeSize0;
    uint256 size1 = _creationCodeSize1;
    creationCode = new bytes(size0 + size1);
    assembly {
      extcodecopy(store0, add(creationCode, 32), 1, size0)
      extcodecopy(store1, add(add(creationCode, 32), size0), 1, size1)
    }
  }

  /// @dev The wallet's full initcode: creation code followed by the
  ///      ABI-encoded constructor arguments.
  function _walletInitCode(
    string memory contractName_,
    address[] memory owners_,
    uint16 threshold_,
    bool isOnlyOwnerRequest_,
    address entryPoint_
  ) private view returns (bytes memory) {
    return
      bytes.concat(
        _walletCreationCode(),
        abi.encode(contractName_, owners_, threshold_, isOnlyOwnerRequest_, entryPoint_)
      );
  }

  /// @dev Runs the wallet initcode via CREATE or CREATE2. Bubbles up the
  ///      wallet constructor's revert data on failure.
  function _deployWallet(
    bytes memory initCode_,
    bytes32 salt_,
    bool deterministic_
  ) private returns (address contractAddress) {
    assembly {
      switch deterministic_
      case 0 {
        contractAddress := create(0, add(initCode_, 32), mload(initCode_))
      }
      default {
        contractAddress := create2(0, add(initCode_, 32), mload(initCode_), salt_)
      }
      if iszero(contractAddress) {
        let rds := returndatasize()
        if rds {
          returndatacopy(0, 0, rds)
          revert(0, rds)
        }
      }
    }
    if (contractAddress == address(0)) revert MyMultiSigExtendedDeploymentFailed();
  }

  /// @dev Namespaces a caller-chosen salt by `msg.sender`.
  function _callerSalt(bytes32 salt_) private view returns (bytes32) {
    return keccak256(abi.encode(msg.sender, salt_));
  }
}
