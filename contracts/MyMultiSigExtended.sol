// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import './MyMultiSig.sol';

contract MyMultiSigExtended is MyMultiSig {
  bool private _onlyOwnerRequest;

  constructor(
    string memory name_,
    address[] memory owners_,
    uint16 threshold_,
    bool isOnlyOwnerRequest_
  ) MyMultiSig(name_, owners_, threshold_) {
    _onlyOwnerRequest = isOnlyOwnerRequest_;
  }

  /// @notice Retrieves if the contract only accepts owner requests (use for UI and other integrations)
  /// @return The true if the contract only accepts owner requests, false otherwise.
  function allowOnlyOwnerRequest() public view returns (bool) {
    return _onlyOwnerRequest;
  }

  /// @notice Set if the contract only accepts owner requests (use for UI and other integrations)
  /// @param isOnlyOwnerRequest The true if the contract only accepts owner requests, false otherwise.
  /// @dev This function can only be called inside a multisig transaction.
  function setOnlyOwnerRequest(bool isOnlyOwnerRequest) public onlyThis {
    _onlyOwnerRequest = isOnlyOwnerRequest;
  }
}
