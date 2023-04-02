// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import './MyMultiSig.sol';

contract MyMultiSigExtended is MyMultiSig {
  bool private _onlyOwnerRequest;
  uint256 private _minimumTransferInactiveOwnershipAfter;

  struct OwnerSettings {
    uint256 lastAction;
    uint256 transferInactiveOwnershipAfter;
    address delegate;
  }
  mapping(address => OwnerSettings) private _ownerSettings;
  mapping(address => bool) private _ownersOrDelegates;
  mapping(uint256 => bool) private _noncesUsed;

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

  /// @notice Retrieves the minimum amount of time after which the other owners can transfer the ownership to a new owner
  /// @return a uint256 representing the minimum amount of time after which the other owners can transfer the ownership to a new owner
  function minimumTransferInactiveOwnershipAfter() public view virtual returns (uint256) {
    return _minimumTransferInactiveOwnershipAfter;
  }

  /// @notice Retrieves owner settings
  /// @return a OwnerSettings struct
  function ownerSettings(address owner) public view virtual returns (OwnerSettings memory) {
    return _ownerSettings[owner];
  }

  /// @notice Set if the contract only accepts owner requests (use for UI and other integrations)
  /// @param isOnlyOwnerRequest The true if the contract only accepts owner requests, false otherwise.
  /// @dev This function can only be called inside a multisig transaction.
  function setOnlyOwnerRequest(bool isOnlyOwnerRequest) public virtual onlyThis {
    _onlyOwnerRequest = isOnlyOwnerRequest;
  }

  /// @notice Executes a transaction
  /// @param to The address to which the transaction is made.
  /// @param value The amount of Ether to be transferred.
  /// @param data The data to be passed along with the transaction.
  /// @param txnGas The gas limit for the transaction.
  /// @param signatures The signatures to be used for the transaction.
  function execTransaction(
    address to,
    uint256 value,
    bytes memory data,
    uint256 txnGas,
    uint256 txnNonce,
    bytes memory signatures
  ) public payable virtual nonReentrant returns (bool success) {
    success = _execTransaction(to, value, data, txnGas, txnNonce, signatures);
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

  /// @notice Adds an owner
  /// @param owner The address to be added as an owner.
  /// @dev This function can only be called inside a multisig transaction.
  function _addOwner(address owner) internal virtual override {
    _ownersOrDelegates[owner] = true;
    super._addOwner(owner);
  }

  /// @notice Set an amount of time after which the other owners can transfer the ownership to a new owner
  /// @param transferInactiveOwnershipAfter The amount of time after which the other owners can transfer the ownership to a new owner.
  /// @dev This function can only be called inside a multisig transaction.
  function setTransferInactiveOwnershipAfter(uint256 transferInactiveOwnershipAfter) public virtual onlyThis {
    require(
      transferInactiveOwnershipAfter >= 7 days,
      'MyMultiSigExtended: transferInactiveOwnershipAfter must be greater than 7 days'
    );
    _minimumTransferInactiveOwnershipAfter = transferInactiveOwnershipAfter;
  }

  /// @notice Owner can delegate the ownership to another address and set an amount of time after which the delegatee can take the ownership
  /// @param transferInactiveOwnershipAfter The amount of time after which the delegatee can take the ownership.
  /// @param delegatee The address that will be able to take the ownership after the transferInactiveOwnershipAfter time.
  /// @dev This function can only be called inside a multisig transaction.
  function setOwnerSettings(uint256 transferInactiveOwnershipAfter, address delegatee) public virtual {
    require(
      transferInactiveOwnershipAfter > _minimumTransferInactiveOwnershipAfter,
      'MyMultiSigExtended: transferInactiveOwnershipAfter must be greater than _minimumtransferInactiveOwnershipAfter'
    );
    require(delegatee != address(0), 'MyMultiSigExtended: delegatee cannot be the zero address');
    require(!_ownersOrDelegates[delegatee], 'MyMultiSigExtended: delegatee is already an owner or delegatee');
    _ownerSettings[msg.sender] = OwnerSettings(block.timestamp, transferInactiveOwnershipAfter, delegatee);
    _ownersOrDelegates[delegatee] = true;
  }

  /// @notice Delegatee can take the ownership after the transferInactiveOwnershipAfter time
  /// @param owner The owner address.
  function takeOverOwnership(address owner) external virtual {
    OwnerSettings memory ownerSettings = _ownerSettings[owner];
    require(ownerSettings.delegate == msg.sender, 'MyMultiSigExtended: msg.sender is not the delegatee');
    require(
      ownerSettings.lastAction + ownerSettings.transferInactiveOwnershipAfter < block.timestamp,
      'MyMultiSigExtended: owner is still active'
    );
    _ownersOrDelegates[owner] = false;
    _ownersOrDelegates[msg.sender] = true;
    _ownerSettings[msg.sender] = OwnerSettings(
      block.timestamp,
      ownerSettings.transferInactiveOwnershipAfter,
      address(0)
    );
    _replaceOwner(owner, msg.sender);
  }

  function markNonceAsUsed(uint256 nonce) public virtual onlyThis {
    _noncesUsed[nonce] = true;
  }
}
