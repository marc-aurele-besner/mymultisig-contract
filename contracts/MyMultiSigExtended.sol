// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import './MyMultiSig.sol';

contract MyMultiSigExtended is MyMultiSig {
  bool private _onlyOwnerRequest;
  uint256 private _minimumTranferInactiveOwnershipAfter;

  struct OwnerSettings {
    uint256 lastAction;
    uint256 tranferInactiveOwnershipAfter;
    address delegate;
  }
  mapping(address => OwnerSettings) private _ownerSettings;
  mapping(address => bool) private _ownersOrDelegates;

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
  function allowOnlyOwnerRequest() public view virtual returns (bool) {
    return _onlyOwnerRequest;
  }

  /// @notice Set if the contract only accepts owner requests (use for UI and other integrations)
  /// @param isOnlyOwnerRequest The true if the contract only accepts owner requests, false otherwise.
  /// @dev This function can only be called inside a multisig transaction.
  function setOnlyOwnerRequest(bool isOnlyOwnerRequest) public virtual onlyThis {
    _onlyOwnerRequest = isOnlyOwnerRequest;
  }

  /// @notice Determines if the owner is valid
  /// @param txHash The transaction hash.
  /// @param signatures The signatures to be used for the transaction.
  /// @param txnNonce The transaction nonce.
  /// @param currentOwner The current owner address.
  function _validateOwner(
    bytes32 txHash,
    bytes memory signatures,
    uint256 txnNonce,
    uint16 currentIndex
  ) internal virtual override returns (address currentOwner) {
    unchecked {
      currentOwner = super._validateOwner(txHash, signatures, txnNonce, currentIndex);
      _ownerSettings[currentOwner].lastAction = block.timestamp;
    }
  }

  /// @notice Set an amount of time after which the other owners can transfer the ownership to a new owner
  /// @param tranferInactiveOwnershipAfter The amount of time after which the other owners can transfer the ownership to a new owner.
  /// @dev This function can only be called inside a multisig transaction.
  function setTranferInactiveOwnershipAftert(uint256 tranferInactiveOwnershipAfter) public virtual onlyThis {
    require(
      tranferInactiveOwnershipAfter >= 7 days,
      'MyMultiSigExtended: tranferInactiveOwnershipAfter must be greater than 7 days'
    );
    _minimumTranferInactiveOwnershipAfter = tranferInactiveOwnershipAfter;
  }

  /// @notice Owner can delegate the ownership to another address and set an amount of time after which the delegatee can take the ownership
  /// @param tranferInactiveOwnershipAfter The amount of time after which the delegatee can take the ownership.
  /// @param delegatee The address that will be able to take the ownership after the tranferInactiveOwnershipAfter time.
  /// @dev This function can only be called inside a multisig transaction.
  function setOwnerSettings(uint256 tranferInactiveOwnershipAfter, address delegatee) public virtual onlyThis {
    require(
      tranferInactiveOwnershipAfter > _minimumTranferInactiveOwnershipAfter,
      'MyMultiSigExtended: tranferInactiveOwnershipAfter must be greater than _minimumTranferInactiveOwnershipAfter'
    );
    require(delegatee != address(0), 'MyMultiSigExtended: delegatee cannot be the zero address');
    require(!_ownersOrDelegates[delegatee], 'MyMultiSigExtended: delegatee is already an owner or delegatee');
    _ownerSettings[msg.sender] = OwnerSettings(block.timestamp, tranferInactiveOwnershipAfter, delegatee);
    _ownersOrDelegates[delegatee] = true;
  }

  /// @notice Delegatee can take the ownership after the tranferInactiveOwnershipAfter time
  /// @param owner The owner address.
  function takeOverOwnership(address owner) external virtual {
    OwnerSettings memory ownerSettings = _ownerSettings[owner];
    require(ownerSettings.delegate == msg.sender, 'MyMultiSigExtended: msg.sender is not the delegatee');
    require(
      ownerSettings.lastAction + ownerSettings.tranferInactiveOwnershipAfter < block.timestamp,
      'MyMultiSigExtended: owner is still active'
    );
    _ownersOrDelegates[owner] = false;
    _ownersOrDelegates[msg.sender] = true;
    _ownerSettings[msg.sender] = OwnerSettings(
      block.timestamp,
      ownerSettings.tranferInactiveOwnershipAfter,
      address(0)
    );
    _replaceOwner(owner, msg.sender);
  }
}
