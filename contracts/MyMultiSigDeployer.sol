// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import './MyMultiSig.sol';
import './interfaces/IMyMultiSigDeployer.sol';

/// @title MyMultiSigDeployer
/// @notice Thin wrapper that performs `new MyMultiSig(...)` so the factory
///         contract doesn't have to embed MyMultiSig's creation bytecode.
/// @dev    The factory holds this contract's address and forwards the deploy
///         call here. The MyMultiSig creation bytecode lives in this contract,
///         not in the factory, which keeps the factory well under the
///         EIP-170 24,576-byte deployable-code limit.
contract MyMultiSigDeployer is IMyMultiSigDeployer {
  function deployMyMultiSig(
    string memory contractName_,
    address[] memory owners_,
    uint16 threshold_
  ) external override returns (address contractAddress) {
    contractAddress = address(new MyMultiSig(contractName_, owners_, threshold_));
  }
}
