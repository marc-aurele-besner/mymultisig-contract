// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import '@openzeppelin/contracts/utils/Create2.sol';

import './MyMultiSig.sol';
import './interfaces/IMyMultiSigDeployer.sol';

/// @title MyMultiSigDeployer
/// @notice Thin wrapper that performs `new MyMultiSig(...)` so the factory
///         contract doesn't have to embed MyMultiSig's creation bytecode.
/// @dev    The factory holds this contract's address and forwards the deploy
///         call here. The MyMultiSig creation bytecode lives in this contract,
///         not in the factory, which keeps the factory well under the
///         EIP-170 24,576-byte deployable-code limit.
///
///         Two deploy paths exist: `deployMyMultiSig` uses plain CREATE, and
///         `deployMyMultiSigDeterministic` uses CREATE2 so the wallet address
///         is a pure function of this deployer's address, the caller, the
///         salt and the constructor arguments — the same inputs on any chain
///         where this deployer sits at the same address yield the same wallet
///         address. `predictMyMultiSigAddress` computes that address without
///         deploying.
contract MyMultiSigDeployer is IMyMultiSigDeployer {
  function deployMyMultiSig(
    string memory contractName_,
    address[] memory owners_,
    uint16 threshold_
  ) external override returns (address contractAddress) {
    contractAddress = address(new MyMultiSig(contractName_, owners_, threshold_));
  }

  /// @notice Deploys a `MyMultiSig` wallet via CREATE2.
  /// @dev    The effective salt mixes in `msg.sender`, so each caller of this
  ///         deployer gets its own address namespace: a third party calling
  ///         this function directly can never occupy an address that a
  ///         factory-mediated deploy would resolve to.
  ///         Reverts if a contract already exists at the target address
  ///         (same caller, salt and constructor arguments).
  /// @param salt_ Caller-chosen salt.
  /// @param contractName_ The wallet's name (part of the EIP-712 domain).
  /// @param owners_ The owners list.
  /// @param threshold_ The minimum sigs required to execute a transaction.
  /// @return contractAddress The deployed wallet address.
  function deployMyMultiSigDeterministic(
    bytes32 salt_,
    string memory contractName_,
    address[] memory owners_,
    uint16 threshold_
  ) external override returns (address contractAddress) {
    contractAddress = address(new MyMultiSig{ salt: _callerSalt(salt_) }(contractName_, owners_, threshold_));
  }

  /// @notice Predicts the address `deployMyMultiSigDeterministic` would
  ///         deploy to for the same caller, salt and constructor arguments.
  /// @dev    Must be called by the same account that will perform the deploy
  ///         (the salt is namespaced by `msg.sender`).
  function predictMyMultiSigAddress(
    bytes32 salt_,
    string memory contractName_,
    address[] memory owners_,
    uint16 threshold_
  ) external view override returns (address contractAddress) {
    contractAddress = Create2.computeAddress(
      _callerSalt(salt_),
      keccak256(abi.encodePacked(type(MyMultiSig).creationCode, abi.encode(contractName_, owners_, threshold_)))
    );
  }

  /// @dev Namespaces a caller-chosen salt by `msg.sender`.
  function _callerSalt(bytes32 salt_) private view returns (bytes32) {
    return keccak256(abi.encode(msg.sender, salt_));
  }
}
