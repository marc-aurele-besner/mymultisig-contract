// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import '@openzeppelin/contracts/utils/Create2.sol';

import './MyMultiSigExtended.sol';
import './interfaces/IMyMultiSigExtendedDeployer.sol';

/// @title MyMultiSigExtendedDeployer
/// @notice Thin wrapper that performs `new MyMultiSigExtended(...)` so
///         the factory doesn't have to embed the wallet's creation
///         bytecode (which is even larger than MyMultiSig's because of
///         the extra delegation / 4337 / operation-byte logic).
/// @dev    Forwards every argument — including `entryPoint_` — straight
///         through to the wallet's constructor.
///
///         Two deploy paths exist: `deployMyMultiSigExtended` uses plain
///         CREATE, and `deployMyMultiSigExtendedDeterministic` uses CREATE2
///         so the wallet address is a pure function of this deployer's
///         address, the caller, the salt and the constructor arguments.
///         `predictMyMultiSigExtendedAddress` computes that address without
///         deploying.
contract MyMultiSigExtendedDeployer is IMyMultiSigExtendedDeployer {
  function deployMyMultiSigExtended(
    string memory contractName_,
    address[] memory owners_,
    uint16 threshold_,
    bool isOnlyOwnerRequest_,
    address entryPoint_
  ) external override returns (address contractAddress) {
    contractAddress = address(
      new MyMultiSigExtended(contractName_, owners_, threshold_, isOnlyOwnerRequest_, entryPoint_)
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
    contractAddress = address(
      new MyMultiSigExtended{ salt: _callerSalt(salt_) }(
        contractName_,
        owners_,
        threshold_,
        isOnlyOwnerRequest_,
        entryPoint_
      )
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
      keccak256(
        abi.encodePacked(
          type(MyMultiSigExtended).creationCode,
          abi.encode(contractName_, owners_, threshold_, isOnlyOwnerRequest_, entryPoint_)
        )
      )
    );
  }

  /// @dev Namespaces a caller-chosen salt by `msg.sender`.
  function _callerSalt(bytes32 salt_) private view returns (bytes32) {
    return keccak256(abi.encode(msg.sender, salt_));
  }
}
