// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import './MyMultiSigExtended.sol';
import './interfaces/IMyMultiSigExtendedDeployer.sol';

/// @title MyMultiSigExtendedDeployer
/// @notice Thin wrapper that performs `new MyMultiSigExtended(...)` so the
///         factory contract doesn't have to embed MyMultiSigExtended's
///         creation bytecode (which is even larger than MyMultiSig's because
///         of the extra delegation logic).
/// @dev    Same pattern as `MyMultiSigDeployer` — the factory stores this
///         contract's address and calls into it.
contract MyMultiSigExtendedDeployer is IMyMultiSigExtendedDeployer {
  function deployMyMultiSigExtended(
    string memory contractName_,
    address[] memory owners_,
    uint16 threshold_,
    bool isOnlyOwnerRequest_
  ) external override returns (address contractAddress) {
    contractAddress = address(new MyMultiSigExtended(contractName_, owners_, threshold_, isOnlyOwnerRequest_));
  }
}
