// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '@openzeppelin/contracts/utils/cryptography/EIP712.sol';
import '@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol';
import '@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol';

contract MyMultiSig is ReentrancyGuard, EIP712, ERC721Holder, ERC1155Holder {
  string private _name;
  uint96 private _txnNonce;
  uint16 private _threshold;
  uint16 private _ownerCount;

  mapping(address => bool) private _owners;
  mapping(uint256 => bool) private _ownerNonceSigned;

  bytes32 private constant _TRANSACTION_TYPEHASH =
    keccak256('Transaction(address to,uint256 value,bytes data,uint256 gas,uint96 nonce)');

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
  event TransactionFailed(
    address indexed sender,
    address indexed to,
    uint256 indexed value,
    bytes data,
    uint256 txnGas,
    uint256 txnNonce
  );
  event ContractEndOfLife(uint256 indexed txNonceLefts);

  modifier onlyThis() {
    require(msg.sender == address(this), 'MyMultiSig: only this contract can call this function');
    _;
  }

  constructor(string memory name_, address[] memory owners_, uint16 threshold_) EIP712(name_, version()) {
    _name = name_;
    uint256 length = owners_.length;
    require(length <= 2 ** 16 - 1, 'MyMultiSig: cannot add owner above 2^16 - 1');
    for (uint256 i = 0; i < length; ) {
      _addOwner(owners_[i]);
      unchecked {
        ++i;
      }
    }
    _ownerCount = uint16(owners_.length);
    _changeThreshold(threshold_);
  }

  /// @notice Retrieves the contract name
  /// @return The name as a string memory.
  function name() public view virtual returns (string memory) {
    return _name;
  }

  /// @notice Retrieves the contract version
  /// @return The version as a string memory.
  function version() public pure virtual returns (string memory) {
    return '0.1.1';
  }

  /// @notice Retrieves the current threshold value
  /// @return The current threshold value as a uint16.
  function threshold() public view virtual returns (uint16) {
    return _threshold;
  }

  /// @notice Retrieves the amount of owners
  /// @return The amount of owners value as a uint16.
  function ownerCount() public view virtual returns (uint16) {
    return _ownerCount;
  }

  /// @notice Retrieves the last txn nonce used
  /// @return The txn nonce value as a uint16.
  function nonce() public view virtual returns (uint96) {
    return _txnNonce;
  }

  /// @notice Determines if the address is the owner
  /// @param owner The address to be checked.
  /// @return True if the address is the owner, false otherwise.
  function isOwner(address owner) public view virtual returns (bool) {
    return _owners[owner];
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
    bytes memory signatures
  ) public payable virtual nonReentrant returns (bool success) {
    success = _execTransaction(to, value, data, txnGas, _txnNonce, signatures);
    if (_txnNonce > uint96(2 ** 96 - 1000)) emit ContractEndOfLife(2 ** 96 - _txnNonce - 1);
  }

  /// @notice Executes a transaction (internal)
  /// @param to The address to which the transaction is made.
  /// @param value The amount of Ether to be transferred.
  /// @param data The data to be passed along with the transaction.
  /// @param txnGas The gas limit for the transaction.
  /// @param txnNonce The nonce for the transaction.
  /// @param signatures The signatures to be used for the transaction.
  function _execTransaction(
    address to,
    uint256 value,
    bytes memory data,
    uint256 txnGas,
    uint256 txnNonce,
    bytes memory signatures
  ) internal virtual returns (bool success) {
    require(_validateSignature(to, value, data, txnGas, txnNonce, signatures), 'MyMultiSig: invalid signatures');
    _txnNonce++;
    uint256 gasBefore = gasleft();
    assembly {
      success := call(txnGas, to, value, add(data, 0x20), mload(data), 0, 0)
    }
    require(gasBefore - gasleft() < txnGas, 'MyMultiSig: not enough gas');
    if (success) emit TransactionExecuted(msg.sender, to, value, data, txnGas, txnNonce);
    else emit TransactionFailed(msg.sender, to, value, data, txnGas, txnNonce);
  }

  /// @notice Prepare multiple transactions
  /// @param to The address to which the transaction is made. (as a array)
  /// @param value The amount of Ether to be transferred. (as a array)
  /// @param data The data to be passed along with the transaction. (as a array)
  /// @param txGas The gas limit for the transaction. (as a array)
  function multiRequest(
    address[] memory to,
    uint256[] memory value,
    bytes[] memory data,
    uint256[] memory txGas
  ) public payable virtual onlyThis returns (bool success) {
    uint256 qty = to.length;
    for (uint256 i; i < qty; ) {
      address to_ = to[i];
      uint256 value_ = value[i];
      bytes memory data_ = data[i];
      uint256 txGas_ = txGas[i];
      assembly {
        success := call(txGas_, to_, value_, add(data_, 0x20), mload(data_), 0, 0)
      }
      unchecked {
        ++i;
      }
    }
  }

  /// @notice Return the current owner address from the full signature at the id position
  /// @param txHash The transaction hash.
  /// @param signatures The signatures to be used for the transaction.
  /// @param id The id of the position of the owner in the full signature.
  /// @return currentOwner The current owner address.
  function _getCurrentOwner(
    bytes32 txHash,
    bytes memory signatures,
    uint16 id
  ) private pure returns (address currentOwner) {
    unchecked {
      uint8 v;
      bytes32 r;
      bytes32 s;
      assembly {
        let signaturePos := mul(0x41, id)
        r := mload(add(signatures, add(signaturePos, 32)))
        s := mload(add(signatures, add(signaturePos, 64)))
        v := and(mload(add(signatures, add(signaturePos, 65))), 255)
      }
      currentOwner = ecrecover(txHash, v, r, s);
    }
  }

  /// @notice Determines if the signature is valid
  /// @param to The address to which the transaction is made.
  /// @param value The amount of Ether to be transferred.
  /// @param data The data to be passed along with the transaction.
  /// @param txnGas The gas limit for the transaction.
  /// @param signatures The signatures to be used for the transaction.
  /// @return valid True if the signature is valid, false otherwise.
  function isValidSignature(
    address to,
    uint256 value,
    bytes memory data,
    uint256 txnGas,
    uint256 txnNonce,
    bytes memory signatures
  ) public view returns (bool valid) {
    uint16 threshold_ = _threshold;
    if (signatures.length < 65 * threshold_) return false;
    address currentOwner;
    bytes32 txHash = generateHash(to, value, data, txnGas, _txnNonce);
    for (uint16 i; i < threshold_; ) {
      unchecked {
        currentOwner = _getCurrentOwner(txHash, signatures, i);
        if (
          !_owners[currentOwner] || _ownerNonceSigned[uint256(uint96(_txnNonce)) + uint256(uint160(currentOwner) << 96)]
        ) return false;
        ++i;
      }
    }
    return true;
  }

  /// @notice Determines if the owner is valid
  /// @param txHash The transaction hash.
  /// @param signatures The signatures to be used for the transaction.
  /// @param txnNonce The transaction nonce.
  /// @param currentIndex The current owner index.
  function _validateOwner(
    bytes32 txHash,
    bytes memory signatures,
    uint256 txnNonce,
    uint16 currentIndex
  ) internal virtual returns (address currentOwner) {
    unchecked {
      currentOwner = _getCurrentOwner(txHash, signatures, currentIndex);
      uint256 currentOwnerNonce = uint256(uint96(txnNonce)) + uint256(uint160(currentOwner) << 96);
      require(_owners[currentOwner], 'MyMultiSig: invalid owner');
      require(!_ownerNonceSigned[currentOwnerNonce], 'MyMultiSig: owner already signed');
      _ownerNonceSigned[currentOwnerNonce] = true;
    }
  }

  /// @notice Determines if the signature is valid
  /// @param to The address to which the transaction is made.
  /// @param value The amount of Ether to be transferred.
  /// @param data The data to be passed along with the transaction.
  /// @param txnGas The gas limit for the transaction.
  /// @param signatures The signatures to be used for the transaction.
  /// @return valid True if the signature is valid, false otherwise.
  function _validateSignature(
    address to,
    uint256 value,
    bytes memory data,
    uint256 txnGas,
    uint256 txnNonce,
    bytes memory signatures
  ) internal virtual returns (bool valid) {
    uint16 threshold_ = _threshold;
    if (signatures.length < 65 * threshold_) return (false);
    txnNonce = _txnNonce;
    bytes32 txHash = generateHash(to, value, data, txnGas, txnNonce);
    for (uint16 i; i < threshold_; ) {
      unchecked {
        _validateOwner(txHash, signatures, txnNonce, i);
        ++i;
      }
    }
    return true;
  }

  /// @notice Adds an owner
  /// @param owner The address to be added as an owner.
  /// @dev This function can only be called inside a multisig transaction.
  function _addOwner(address owner) internal virtual {
    require(!_owners[owner], 'MyMultiSig: owner already exists');
    _owners[owner] = true;
    ++_ownerCount;
  }

  /// @notice Adds an owner
  /// @param owner The address to be added as an owner.
  /// @dev This function can only be called inside a multisig transaction.
  function addOwner(address owner) public virtual onlyThis {
    require(_ownerCount < 2 ** 16 - 1, 'MyMultiSig: cannot add owner above 2^16 - 1');
    _addOwner(owner);
  }

  /// @notice Removes an owner
  /// @param owner The owner to be removed.
  /// @dev This function can only be called inside a multisig transaction.

  function _removeOwner(address owner) internal virtual {
    if (_ownerCount <= _threshold) revert('MyMultiSig: cannot remove owner below threshold');
    _owners[owner] = false;
    --_ownerCount;
  }

  /// @notice Removes an owner
  /// @param owner The owner to be removed.
  /// @dev This function can only be called inside a multisig transaction.

  function removeOwner(address owner) public virtual onlyThis {
    _removeOwner(owner);
  }

  /// @notice Changes the threshold
  /// @param newThreshold The new threshold.
  /// @dev This function can only be called inside a multisig transaction.
  function changeThreshold(uint16 newThreshold) public virtual onlyThis {
    _changeThreshold(newThreshold);
  }

  /// @notice Changes the threshold
  /// @param newThreshold The new threshold.
  /// @dev This function can only be called inside a multisig transaction.
  function _changeThreshold(uint16 newThreshold) private {
    require(newThreshold > 0, 'MyMultiSig: threshold must be greater than 0');
    require(newThreshold <= _ownerCount, 'MyMultiSig: threshold must be less than or equal to owner count');
    _threshold = newThreshold;
  }

  /// @notice Replaces an owner with a new owner
  /// @param oldOwner The owner to be replaced.
  /// @param newOwner The new owner.
  /// @dev This function can only be called inside a multisig transaction.
  function replaceOwner(address oldOwner, address newOwner) public virtual onlyThis {
    _replaceOwner(oldOwner, newOwner);
  }

  /// @notice Replaces an owner with a new owner (internal)
  /// @param oldOwner The owner to be replaced.
  /// @param newOwner The new owner.
  /// @dev This function can only be called inside a multisig transaction.
  function _replaceOwner(address oldOwner, address newOwner) internal virtual {
    require(_owners[oldOwner], 'MyMultiSig: old owner must be an owner');
    require(!_owners[newOwner], 'MyMultiSig: new owner must not be an owner');
    require(newOwner != address(0), 'MyMultiSig: new owner must not be the zero address');
    _owners[oldOwner] = false;
    _owners[newOwner] = true;
  }

  function generateHash(
    address to,
    uint256 value,
    bytes memory data,
    uint256 txnGas,
    uint256 txnNonce
  ) public view virtual returns (bytes32) {
    return _hashTypedDataV4(keccak256(abi.encode(_TRANSACTION_TYPEHASH, to, value, keccak256(data), txnGas, txnNonce)));
  }

  /// @notice Returns the current transaction nonce
  /// @return The current transaction nonce.
  function verifyNonce(uint256 nonce_) internal view virtual returns (bool) {
    return nonce_ == _txnNonce;
  }

  /// @notice Increments the transaction nonce, can be use to invalidate previous signatures
  /// @dev This function can only be called inside a multisig transaction.
  function incrementNonce() public virtual onlyThis {
    _txnNonce++;
  }

  /// @notice Receives Ether
  receive() external payable {}
}
