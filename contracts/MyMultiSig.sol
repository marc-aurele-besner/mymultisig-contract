// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '@openzeppelin/contracts/utils/cryptography/EIP712.sol';

contract MyMultiSig is ReentrancyGuard, EIP712 {
  string private _name;
  uint16 private _treshold;
  uint16 private _ownerCount;
  uint256 private _txnNonce;

  mapping(address => bool) private _owners;
  mapping(uint256 => bool) private _ownerNonceSigned;
  mapping(uint256 => bytes32) private _nonceTxHash;

  bytes32 private constant _TRANSACTION_TYPEHASH =
    keccak256('Transaction(address to,uint256 value,bytes data,uint256 txnGas,uint256 txnNonce)');

  event OwnerAdded(address indexed owner);
  event OwnerRemoved(address indexed owner);
  event TresholdChanged(uint256 indexed treshold);
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

  constructor(string memory name_, address[] memory owners_, uint16 treshold_) EIP712(name_, version()) {
    require(owners_.length <= 2 ** 16 - 1, 'MyMultiSig: cannot add owner above 2^16 - 1');
    _name = name_;
    for (uint256 i = 0; i < owners_.length; ) {
      _owners[owners_[i]] = true;
      unchecked {
        ++i;
      }
    }
    _ownerCount = uint16(owners_.length);
    changeTreshold(treshold_);
  }

  /// @notice Retrieves the contract version
  /// @return The version as a string memory.
  function version() public pure returns (string memory) {
    return '0.0.1';
  }

  /// @notice Retrieves the contract name
  /// @return The name as a string memory.
  function name() public view returns (string memory) {
    return _name;
  }

  /// @notice Retrieves the current threshold value
  /// @return The current threshold value as a uint16.
  function treshold() public view returns (uint16) {
    return _treshold;
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
  ) public payable nonReentrant returns (bool success) {
    (bool isValid, bytes32 txHash) = _validateSignature(to, value, data, txnGas, signatures);
    require(isValid, 'MyMultiSig: invalid signatures');
    _nonceTxHash[_txnNonce] = txHash;
    _txnNonce++;
    assembly {
      success := call(txnGas, to, value, add(data, 0x20), mload(data), 0, 0)
    }
    require(txnGas >= gasleft(), 'MyMultiSig: not enough gas');
    if (success) emit TransactionExecuted(msg.sender, to, value, data, txnGas, _txnNonce);
    else emit TransactionFailed(msg.sender, to, value, data, txnGas, _txnNonce);
    if (_txnNonce > 2 ** 96 - 1000) emit ContractEndOfLife(2 ** 96 - _txnNonce - 1);
    return success;
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
      if (v == 0) {
        revert('MyMultiSig: No contract signatures support');
      } else if (v == 1) {
        currentOwner = address(uint160(uint256(r)));
      } else if (v > 30) {
        currentOwner = ecrecover(keccak256(abi.encodePacked('\x19Ethereum Signed Message:\n32', txHash)), v - 4, r, s);
      } else {
        currentOwner = ecrecover(txHash, v, r, s);
      }
    }
  }

  /// @notice Determines if the signature is valid
  /// @param to The address to which the transaction is made.
  /// @param value The amount of Ether to be transferred.
  /// @param data The data to be passed along with the transaction.
  /// @param txnGas The gas limit for the transaction.
  /// @param signatures The signatures to be used for the transaction.
  /// @return valid True if the signature is valid, false otherwise.
  /// @return txHash The transaction hash.
  function isValidSignature(
    address to,
    uint256 value,
    bytes memory data,
    uint256 txnGas,
    bytes memory signatures
  ) public view returns (bool valid, bytes32 txHash) {
    uint16 threshold_ = _treshold;
    if (signatures.length <= 65 * threshold_) return (false, txHash);
    txHash = _hashTypedDataV4(
      keccak256(abi.encode(_TRANSACTION_TYPEHASH, to, value, keccak256(data), txnGas, _txnNonce))
    );
    address currentOwner;
    for (uint16 i; i < threshold_; ) {
      unchecked {
        currentOwner = _getCurrentOwner(txHash, signatures, i);
        require(_owners[currentOwner], 'MyMultiSig: invalid owner');
        ++i;
      }
    }
    return (true, txHash);
  }

  /// @notice Determines if the signature is valid
  /// @param to The address to which the transaction is made.
  /// @param value The amount of Ether to be transferred.
  /// @param data The data to be passed along with the transaction.
  /// @param txnGas The gas limit for the transaction.
  /// @param signatures The signatures to be used for the transaction.
  /// @return valid True if the signature is valid, false otherwise.
  /// @return txHash The transaction hash.
  function _validateSignature(
    address to,
    uint256 value,
    bytes memory data,
    uint256 txnGas,
    bytes memory signatures
  ) private view returns (bool valid, bytes32 txHash) {
    uint16 threshold_ = _treshold;
    if (signatures.length <= 65 * threshold_) return (false, txHash);
    txHash = _hashTypedDataV4(
      keccak256(abi.encode(_TRANSACTION_TYPEHASH, to, value, keccak256(data), txnGas, _txnNonce))
    );
    address currentOwner;
    uint256 currentOwnerNonce;
    for (uint16 i; i < threshold_; ) {
      unchecked {
        currentOwner = _getCurrentOwner(txHash, signatures, i);
        currentOwnerNonce = uint256(uint96(_txnNonce)) + uint256(uint160(currentOwner) << 96);
        require(_owners[currentOwner], 'MyMultiSig: invalid owner');
        require(!_ownerNonceSigned[currentOwnerNonce], 'MyMultiSig: owner already signed');
        ++i;
      }
    }
    return (true, txHash);
  }

  /// @notice Determines if the address is the owner
  /// @param owner The address to be checked.
  /// @return True if the address is the owner, false otherwise.
  function isOwner(address owner) public view returns (bool) {
    return _owners[owner];
  }

  /// @notice Adds an owner
  /// @param owner The address to be added as an owner.
  /// @dev This function can only be called inside a multisig transaction.
  function addOwner(address owner) public onlyThis {
    require(_ownerCount < 2 ** 16 - 1, 'MyMultiSig: cannot add owner above 2^16 - 1');
    _owners[owner] = true;
  }

  /// @notice Removes an owner
  /// @param owner The owner to be removed.
  /// @dev This function can only be called inside a multisig transaction.

  function removeOwner(address owner) public onlyThis {
    require(_ownerCount > _treshold, 'MyMultiSig: cannot remove owner below treshold');
    _owners[owner] = false;
  }

  /// @notice Changes the threshold
  /// @param newTreshold The new threshold.
  /// @dev This function can only be called inside a multisig transaction.
  function changeTreshold(uint16 newTreshold) public onlyThis {
    require(newTreshold > 0, 'MyMultiSig: treshold must be greater than 0');
    require(newTreshold <= _ownerCount, 'MyMultiSig: treshold must be less than or equal to owner count');
    _treshold = newTreshold;
  }

  /// @notice Replaces an owner with a new owner
  /// @param oldOwner The owner to be replaced.
  /// @param newOwner The new owner.
  /// @dev This function can only be called inside a multisig transaction.
  function replaceOwner(address oldOwner, address newOwner) public onlyThis {
    require(_owners[oldOwner], 'MyMultiSig: old owner must be an owner');
    require(!_owners[newOwner], 'MyMultiSig: new owner must not be an owner');
    require(newOwner != address(0), 'MyMultiSig: new owner must not be the zero address');
    _owners[oldOwner] = false;
    _owners[newOwner] = true;
  }
}
