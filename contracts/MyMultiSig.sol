// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';
import '@openzeppelin/contracts/utils/cryptography/EIP712.sol';
import '@openzeppelin/contracts/interfaces/IERC1271.sol';
import '@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol';
import '@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol';
import '@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol';

contract MyMultiSig is ReentrancyGuard, EIP712, IERC1271, ERC721Holder, ERC1155Holder {
  string private _name;
  uint96 private _txnNonce;
  uint16 private _threshold;
  uint16 private _ownerCount;

  /// @notice Owners as a sentinel-headed singly-linked list (the same
  ///         pattern as the modules list in `MyMultiSigExtended`):
  ///         `_ownersNext[_SENTINEL_OWNER]` is the most recently added owner,
  ///         each owner points to the next one, and the last owner points
  ///         back to `_SENTINEL_OWNER`. An address is an owner iff its entry
  ///         is non-zero (see `isOwner`), and the list makes the full owner
  ///         set enumerable on-chain via `getOwners`.
  mapping(address => address) private _ownersNext;
  mapping(uint256 => bool) private _ownerNonceSigned;
  /// @notice Per-hash set of owners who have pre-approved the transaction
  ///         via `approveHash`. Keyed by the 32-byte EIP-712 transaction hash.
  mapping(bytes32 => mapping(address => bool)) private _approvedHashes;
  /// @notice Per-hash list of owners who have pre-approved the transaction,
  ///         in the order they called `approveHash`. Stored as an array so
  ///         `getApprovedOwners` can return it without an extra off-chain indexer.
  mapping(bytes32 => address[]) private _approvedOwners;
  /// @notice Messages the wallet has signed on-chain via `signMessage`.
  ///         Keyed by the EIP-712 message hash (see `getMessageHash`), so a
  ///         stored entry is bound to this wallet's domain separator and
  ///         cannot be replayed against another wallet. Read by the
  ///         EIP-1271 `isValidSignature(bytes32,bytes)` empty-signature path.
  mapping(bytes32 => bool) private _signedMessages;

  /// @notice Failure-policy flag for inner calls that fail WITHOUT revert
  ///         data (e.g. an ETH transfer bouncing off an insufficient
  ///         balance). When true, such a failure reverts the whole
  ///         `execTransaction` (`TxSuccessRequired`) — the nonce is not
  ///         consumed and the collected signatures stay usable for a retry.
  ///         When false, the failure is soft: `TxFailure` is emitted and the
  ///         nonce IS consumed. Inner calls that fail WITH revert data are
  ///         not governed by this flag — their payload always bubbles up and
  ///         reverts the whole transaction (see `_execTransaction`).
  bool private _requireTxSuccess;

  /// @notice Sentinel head/tail of the owners linked list. Never a valid
  ///         owner itself; `_addOwner` rejects it like the zero address.
  address private constant _SENTINEL_OWNER = address(0x1);

  /// @notice EIP-712 typehash for the per-transaction payload. Includes a
  ///         `uint256 validUntil` deadline so signatures carry an explicit
  ///         expiry. `validUntil == 0` means "no expiry" (matches Safe's
  ///         convention).
  bytes32 private constant _TRANSACTION_TYPEHASH =
    keccak256('Transaction(address to,uint256 value,bytes data,uint256 gas,uint96 nonce,uint256 validUntil)');

  /// @notice EIP-712 typehash for off-chain-auth messages signed via
  ///         `signMessage`. Mirrors Safe's `SafeMessage(bytes message)`
  ///         pattern: the raw message bytes are hashed into the wallet's
  ///         EIP-712 domain, so the resulting hash is unique per wallet,
  ///         chain, and message.
  bytes32 private constant _MSG_TYPEHASH = keccak256('MyMultiSigMessage(bytes message)');

  /// @notice EIP-1271 magic value: `isValidSignature(bytes32,bytes)` must return
  ///         this 4-byte value when the signature is valid. Equal to
  ///         `IERC1271.isValidSignature.selector` (= `0x1626ba7e`). We cache it
  ///         for use in `_isValidERC1271` (where we compare against the
  ///         right-padded 32-byte staticcall return value).
  bytes4 private constant _ERC1271_MAGIC = IERC1271.isValidSignature.selector;

  /// @notice Gas forwarded to a contract owner's `isValidSignature` staticcall.
  ///         200k matches Safe's typical `GAS_VALIDATION` budget and is enough
  ///         for several `ecrecover` calls + storage reads + magic return
  ///         inside the nested wallet, while still capping a hostile contract
  ///         owner's grief vector. Tweak upward if integrating with on-chain
  ///         KMS validators that need more.
  uint256 private constant _ERC1271_GAS_STIPEND = 200_000;

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
  /// @notice Emitted when the signatures validated but the low-level call to
  ///         `to` failed WITHOUT revert data (e.g. a plain ETH transfer
  ///         bouncing, or the target running out of its forwarded gas) while
  ///         `requireTxSuccess()` is off. The nonce is consumed on this path.
  ///         A failed inner call that DOES return revert data never reaches
  ///         this event: its payload is bubbled up and the whole
  ///         `execTransaction` reverts, preserving the nonce — so `reason`
  ///         is empty bytes by construction whenever this event fires.
  event TxFailure(
    address indexed sender,
    address indexed to,
    uint256 indexed value,
    bytes data,
    uint256 txnGas,
    uint256 txnNonce,
    bytes reason
  );
  event ContractEndOfLife(uint256 indexed txNonceLefts);
  /// @notice Emitted when an owner pre-approves a transaction hash via
  ///         `approveHash`. The hash is the EIP-712 transaction hash; it
  ///         encodes `(to, value, data, gas, nonce)` so each approval is
  ///         bound to a single, fully-specified transaction.
  event ApproveHash(address indexed owner, bytes32 indexed hash);
  /// @notice Emitted when an owner withdraws a previous on-chain approval
  ///         via `revokeApproval`. The owner is removed from both the
  ///         per-hash approval map and the per-hash owner list, so a later
  ///         `execTransaction` for the same hash loses this owner's vote.
  event RevokeApproval(address indexed owner, bytes32 indexed hash);
  /// @notice Emitted at the end of every `multiRequest` call, once per batch,
  ///         carrying the per-call outcome arrays so off-chain consumers and
  ///         indexers can audit partial failures without replaying the inner
  ///         transactions. `successes[i]` mirrors the boolean returned by the
  ///         low-level `call` to `to[i]` (`true` for a successful return,
  ///         `false` for a silent revert). `returnData[i]` carries the raw
  ///         return data of the call — empty for a successful no-data return,
  ///         the ABI-encoded revert payload for a failed call, or the happy-
  ///         path return value when the call succeeded. `txNonce` is the
  ///         outer `execTransaction` nonce under which the batch ran.
  event MultiRequestExecuted(uint256 indexed txNonce, bool[] successes, bytes[] returnData);
  /// @notice Emitted when the wallet signs a message on-chain via
  ///         `signMessage`. `msgHash` is the EIP-712 message hash returned
  ///         by `getMessageHash(message)`.
  event MessageSigned(bytes32 indexed msgHash);
  /// @notice Emitted when a previously-signed message is withdrawn via
  ///         `unsignMessage`, so EIP-1271 verifiers stop accepting it.
  event MessageUnsigned(bytes32 indexed msgHash);
  /// @notice Emitted when `setRequireTxSuccess` toggles the must-succeed
  ///         execution mode (see `requireTxSuccess`).
  event RequireTxSuccessSet(bool required);

  error OnlyThisContract();
  error TooManyOwners();
  error InvalidSignatures();
  /// @notice The signature was bound to a `validUntil` deadline that has
  ///         already passed. Reverts from `_validateSignature` (the mutating
  ///         path) so an `execTransaction` cannot execute a stale payload
  ///         even if it still collects enough votes.
  error SignatureExpired();
  /// @notice Caller asked to revoke an approval they never recorded. Emitted
  ///         by `revokeApproval(bytes32)` when the caller is an owner but
  ///         has no entry in `_approvedHashes[hash]`.
  error NotApproved();
  /// @notice `unsignMessage` was called for a message the wallet never
  ///         signed (or already unsigned).
  error MessageNotSigned();
  /// @notice Emitted by `multiRequestStrict` when an inner call reverts.
  ///         `index` is the 0-based position of the failing call in the
  ///         batch; `reason` is the raw return data of that call so
  ///         front-ends can decode the inner revert reason. The whole
  ///         outer `execTransaction` reverts — no side effects from the
  ///         batch persist.
  error BatchCallFailed(uint256 index, bytes reason);
  /// @notice `multiRequest` / `multiRequestStrict` received arrays of
  ///         different lengths — every batch array must have one entry per
  ///         inner call.
  error ArrayLengthMismatch();
  /// @notice The inner call failed without revert data while
  ///         `requireTxSuccess()` is enabled. The whole `execTransaction`
  ///         reverts, so the nonce is not consumed and the collected
  ///         signatures stay usable. (An inner failure WITH revert data
  ///         bubbles that payload instead of this error.)
  error TxSuccessRequired();
  /// @notice `removeOwner` was called for an address that is not a current
  ///         owner.
  error OwnerToRemoveMustBeOwner();
  error NotOwner();
  error NotEnoughGas();
  error OwnerAlreadyExists();
  error CannotRemoveOwnerBelowThreshold();
  error ThresholdMustBeGreaterThanZero();
  error ThresholdMustBeLessOrEqualToOwnerCount();
  error OldOwnerMustBeOwner();
  error NewOwnerMustNotBeOwner();
  error NewOwnerMustNotBeZero();

  modifier onlyThis() {
    if (msg.sender != address(this)) revert OnlyThisContract();
    _;
  }

  constructor(string memory name_, address[] memory owners_, uint16 threshold_) EIP712(name_, version()) {
    _name = name_;
    _ownersNext[_SENTINEL_OWNER] = _SENTINEL_OWNER;
    uint256 length = owners_.length;
    if (length > 2 ** 16 - 1) revert TooManyOwners();
    for (uint256 i = 0; i < length; ) {
      _addOwner(owners_[i]);
      unchecked {
        ++i;
      }
    }
    _changeThreshold(threshold_);
  }

  /// @notice Retrieves the contract name
  /// @return The name as a string memory.
  function name() public view virtual returns (string memory) {
    return _name;
  }

  /// @notice Wallet version — the same canonical value across every wallet
  ///         class (`MyMultiSigExtended`, `MyMultiSigFactorable`, and the
  ///         factory proxy). Part of the EIP-712 domain separator, which is
  ///         fixed at deploy time.
  function version() public pure virtual returns (string memory) {
    return '0.5.0';
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
    return owner != _SENTINEL_OWNER && _ownersNext[owner] != address(0);
  }

  /// @notice Returns every current owner by walking the linked list. Order
  ///         is most-recently-added first (owners are inserted at the head,
  ///         like the modules list in `MyMultiSigExtended`); `replaceOwner`
  ///         keeps the replaced owner's position.
  /// @return owners The list of current owner addresses.
  function getOwners() public view virtual returns (address[] memory owners) {
    owners = new address[](_ownerCount);
    address cursor = _ownersNext[_SENTINEL_OWNER];
    for (uint256 i; cursor != _SENTINEL_OWNER; ) {
      owners[i] = cursor;
      cursor = _ownersNext[cursor];
      unchecked {
        ++i;
      }
    }
  }

  /// @notice Whether must-succeed execution mode is on. Failure handling of
  ///         the inner call of every exec path is:
  ///         - fails WITH revert data: the payload bubbles up and the whole
  ///           `execTransaction` reverts (nonce preserved) — regardless of
  ///           this flag;
  ///         - fails WITHOUT revert data, flag on: the whole
  ///           `execTransaction` reverts with `TxSuccessRequired` (nonce
  ///           preserved);
  ///         - fails WITHOUT revert data, flag off: `TxFailure` is emitted
  ///           and the nonce is consumed (soft failure).
  function requireTxSuccess() public view virtual returns (bool) {
    return _requireTxSuccess;
  }

  /// @notice Toggles must-succeed execution mode (see `requireTxSuccess`).
  /// @param required True to revert `execTransaction` when the inner call
  ///        fails without revert data (payload-carrying failures always
  ///        revert either way).
  /// @dev This function can only be called inside a multisig transaction.
  ///      On `MyMultiSigExtended` this selector is part of the default
  ///      sensitive set, so once a timelock delay is configured the toggle
  ///      must go through `scheduleTransaction`.
  function setRequireTxSuccess(bool required) public virtual onlyThis {
    _requireTxSuccess = required;
    emit RequireTxSuccessSet(required);
  }

  /// @notice ERC-165 introspection. Advertises EIP-1271
  ///         (`isValidSignature(bytes32,bytes)`), the ERC-721 and ERC-1155
  ///         receiver hooks, and ERC-165 itself.
  function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
    return
      interfaceId == type(IERC1271).interfaceId ||
      interfaceId == type(IERC721Receiver).interfaceId ||
      super.supportsInterface(interfaceId);
  }

  /// @notice Returns the owners who have pre-approved the given hash via
  ///         `approveHash`. Returned in the order they called `approveHash`;
  ///         each address appears at most once because the function is
  ///         idempotent per (hash, owner).
  /// @param hash The EIP-712 transaction hash.
  /// @return The list of owner addresses that approved `hash`.
  function getApprovedOwners(bytes32 hash) public view virtual returns (address[] memory) {
    return _approvedOwners[hash];
  }

  /// @notice Returns the signature threshold that `execTransaction` will check
  ///         against for `hash`. The wallet has a single contract-wide
  ///         threshold; the `hash` argument exists for Safe API parity so
  ///         off-chain clients can query the threshold using the same value
  ///         they pass to `approveHash`.
  /// @return The current threshold.
  function getThreshold(bytes32 /* hash */) public view virtual returns (uint256) {
    return _threshold;
  }

  /// @notice Pre-approves a transaction hash off the owner's own balance /
  ///         signature collection. The hash is the EIP-712 transaction hash
  ///         (see `generateHash`); the corresponding transaction may later be
  ///         executed by anyone — including a relayer — once enough
  ///         signatures and approvals have been collected for it.
  /// @dev Idempotent per (owner, hash): calling twice with the same
  ///      arguments is a no-op (does not revert, does not double-count).
  ///      The owner's vote is stored until the matching transaction is
  ///      executed, the caller withdraws it via `revokeApproval`, or the
  ///      nonce is invalidated via `markNonceAsUsed`.
  ///      Reverts with `NotOwner` if `msg.sender` is not a current owner.
  /// @param hash The EIP-712 transaction hash to approve.
  function approveHash(bytes32 hash) public virtual {
    if (!isOwner(msg.sender)) revert NotOwner();
    if (_approvedHashes[hash][msg.sender]) return;
    _approvedHashes[hash][msg.sender] = true;
    _approvedOwners[hash].push(msg.sender);
    _recordOwnerApproval(msg.sender);
    emit ApproveHash(msg.sender, hash);
  }

  /// @notice Withdraws a previous `approveHash(hash)` vote. The caller is
  ///         removed from `_approvedHashes[hash]` and `_approvedOwners[hash]`
  ///         so any subsequent `execTransaction` for that hash loses this
  ///         owner's vote. Use this to retract a vote before the matching
  ///         transaction executes — the alternative is to bump the nonce
  ///         (`incrementNonce` / `markNonceAsUsed`) which also clears every
  ///         owner's approvals.
  /// @dev    Self-only: an owner can only withdraw their OWN approval. We
  ///      deliberately do NOT expose an admin-style revoke because the
  ///      multisig has no privileged owner — every owner is equal.
  ///      Idempotency: calling `revokeApproval` for a hash you never
  ///      approved reverts with `NotApproved` (matches Safe's `disapproveHash`
  ///      semantics and prevents silent double-revoke footguns).
  ///      The owner's `lastAction` is NOT bumped — revoking is not a vote
  ///      and should not reset inactivity timers (overridden in
  ///      `MyMultiSigExtended`).
  /// @param hash The EIP-712 transaction hash to revoke.
  function revokeApproval(bytes32 hash) public virtual {
    if (!isOwner(msg.sender)) revert NotOwner();
    if (!_approvedHashes[hash][msg.sender]) revert NotApproved();
    _approvedHashes[hash][msg.sender] = false;
    _removeApprovedOwner(hash, msg.sender);
    emit RevokeApproval(msg.sender, hash);
  }

  /// @dev Removes `owner` from `_approvedOwners[hash]` using swap-and-pop —
  ///      O(n) in the array length but `n <= ownerCount <= 65535`, and we
  ///      avoid the storage-write cost of shifting every element. The
  ///      caller has already cleared `_approvedHashes[hash][owner]`, so a
  ///      no-op (owner not in the array) is impossible: the revert path in
  ///      `revokeApproval` would have caught it.
  function _removeApprovedOwner(bytes32 hash, address owner) private {
    address[] storage arr = _approvedOwners[hash];
    uint256 n = arr.length;
    for (uint256 i = 0; i < n; ) {
      unchecked {
        if (arr[i] == owner) {
          arr[i] = arr[n - 1];
          arr.pop();
          return;
        }
        ++i;
      }
    }
  }

  /// @notice Executes a transaction. Backwards-compatible entry point that
  ///         pins `txnNonce` to the wallet's current nonce and uses
  ///         `validUntil = 0` (no expiry). Callers that need a deadline
  ///         should use the 6-arg overload below.
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
    success = _execTransaction(to, value, data, txnGas, _txnNonce, 0, signatures);
    _emitEndOfLifeIfNear();
  }

  /// @notice Executes a transaction with an explicit `validUntil` deadline.
  ///         Pins `txnNonce` to the wallet's current nonce. Reverts with
  ///         `SignatureExpired` if `validUntil != 0 && block.timestamp >
  ///         validUntil` — the bound signatures must therefore include the
  ///         same `validUntil` in their typed-data payload.
  /// @param to The address to which the transaction is made.
  /// @param value The amount of Ether to be transferred.
  /// @param data The data to be passed along with the transaction.
  /// @param txnGas The gas limit for the transaction.
  /// @param validUntil Unix timestamp deadline; `0` disables the check.
  /// @param signatures The signatures to be used for the transaction.
  function execTransaction(
    address to,
    uint256 value,
    bytes memory data,
    uint256 txnGas,
    uint256 validUntil,
    bytes memory signatures
  ) public payable virtual nonReentrant returns (bool success) {
    success = _execTransaction(to, value, data, txnGas, _txnNonce, validUntil, signatures);
    _emitEndOfLifeIfNear();
  }

  /// @notice Emits `ContractEndOfLife` once the nonce enters the last ~1000
  ///         usable values. Shared by every `execTransaction` overload here
  ///         and in `MyMultiSigExtended`.
  function _emitEndOfLifeIfNear() internal virtual {
    uint96 txnNonce = _txnNonce;
    if (txnNonce > uint96(2 ** 96 - 1000)) emit ContractEndOfLife(2 ** 96 - txnNonce - 1);
  }

  /// @notice Shared low-level CALL wrapper: forwards `txnGas` to `to` with
  ///         `value` and `data`, then copies the full returndata into a fresh
  ///         memory buffer. Every raw call in the wallet family routes
  ///         through here so the assembly exists exactly once.
  function _rawCall(
    uint256 txnGas,
    address to,
    uint256 value,
    bytes memory data
  ) internal virtual returns (bool success, bytes memory returnData) {
    assembly {
      success := call(txnGas, to, value, add(data, 0x20), mload(data), 0, 0)
    }
    returnData = _collectReturnData();
  }

  /// @notice Copies the full returndata of the most recent external call
  ///         into a fresh memory buffer. Shared by the CALL and DELEGATECALL
  ///         wrappers; must run immediately after the call opcode, before
  ///         any other external call clobbers the returndata buffer.
  function _collectReturnData() internal pure returns (bytes memory returnData) {
    assembly {
      let size := returndatasize()
      returnData := mload(0x40)
      mstore(returnData, size)
      returndatacopy(add(returnData, 0x20), 0, size)
      // round size up to the next 32-byte word for the free-memory pointer
      mstore(0x40, add(add(returnData, 0x20), and(add(size, 0x1f), not(0x1f))))
    }
  }

  /// @notice Reverts with `returnData` as the raw revert payload, bubbling an
  ///         inner call's structured error to the outer caller unchanged.
  function _revertWith(bytes memory returnData) internal pure {
    assembly {
      revert(add(returnData, 0x20), mload(returnData))
    }
  }

  /// @notice Per-inner-call hook run before each `multiRequest` /
  ///         `multiRequestStrict` inner call. No-op here;
  ///         `MyMultiSigExtended` overrides it to run its timelock / guard /
  ///         allowlist gates per inner call without re-implementing the loops.
  function _beforeInnerCall(address /* to */, uint256 /* value */, bytes memory /* data */) internal virtual {}

  /// @notice Executes a transaction (internal)
  /// @dev Failure policy for the inner call, shared by every exec path of
  ///      the wallet family:
  ///      - success: `TransactionExecuted`, nonce consumed;
  ///      - failed WITH revert data: the payload bubbles up unchanged and
  ///        the whole transaction reverts — nonce preserved regardless of
  ///        `requireTxSuccess()` — so structured inner errors (e.g.
  ///        `multiRequestStrict`'s `BatchCallFailed`, `onlyThis` admin
  ///        errors) stay decodable by the caller;
  ///      - failed WITHOUT revert data: reverts `TxSuccessRequired` when
  ///        `requireTxSuccess()` is on (nonce preserved), otherwise emits
  ///        `TxFailure` and consumes the nonce.
  /// @param to The address to which the transaction is made.
  /// @param value The amount of Ether to be transferred.
  /// @param data The data to be passed along with the transaction.
  /// @param txnGas The gas limit for the transaction.
  /// @param txnNonce The nonce for the transaction.
  /// @param validUntil Unix timestamp after which the signature is no longer
  ///        valid. `0` disables the deadline check (signatures never expire).
  ///        Baked into the EIP-712 hash so the bound signatures must match.
  /// @param signatures The signatures to be used for the transaction.
  function _execTransaction(
    address to,
    uint256 value,
    bytes memory data,
    uint256 txnGas,
    uint256 txnNonce,
    uint256 validUntil,
    bytes memory signatures
  ) internal virtual returns (bool success) {
    if (!_validateSignature(to, value, data, txnGas, txnNonce, validUntil, signatures)) revert InvalidSignatures();
    _bumpNonce();
    uint256 gasBefore = gasleft();
    bytes memory returnData;
    (success, returnData) = _rawCall(txnGas, to, value, data);
    if (gasBefore - gasleft() >= txnGas) revert NotEnoughGas();
    if (success) {
      emit TransactionExecuted(msg.sender, to, value, data, txnGas, txnNonce);
    } else if (returnData.length > 0) {
      // The inner call reverted with a payload (e.g. a custom error such as
      // `multiRequestStrict`'s BatchCallFailed). Bubble the revert so the
      // caller can decode the actual reason — emitting TxFailure here would
      // hide the structured error inside an opaque bytes blob.
      _revertWith(returnData);
    } else if (_requireTxSuccess) {
      revert TxSuccessRequired();
    } else {
      emit TxFailure(msg.sender, to, value, data, txnGas, txnNonce, returnData);
    }
  }

  /// @notice Prepare multiple transactions
  /// @param to The address to which the transaction is made. (as a array)
  /// @param value The amount of Ether to be transferred. (as a array)
  /// @param data The data to be passed along with the transaction. (as a array)
  /// @param txGas The gas limit for the transaction. (as a array)
  /// @return successes One entry per inner call, in input order: `true` if the
  ///         low-level `call` returned success, `false` otherwise (silent
  ///         revert or explicit `revert()`/`require(false)`). Identical to
  ///         the `successes` array emitted in `MultiRequestExecuted`.
  /// @return returnData One entry per inner call, in input order: the raw
  ///         return data of the call — empty bytes on a successful no-data
  ///         return, the ABI-encoded revert payload on a failure, or the
  ///         happy-path return value when the call succeeded. Identical to
  ///         the `returnData` array emitted in `MultiRequestExecuted`.
  /// @dev    This function never reverts on inner-call failure: every call is
  ///         executed and its outcome recorded. A batch with any failure is
  ///         surfaced via `successes[i] == false` and the captured revert
  ///         payload in `returnData[i]`. A single `MultiRequestExecuted`
  ///         event is emitted once the full batch has run, giving callers
  ///         and indexers a complete audit trail in one log entry.
  function multiRequest(
    address[] memory to,
    uint256[] memory value,
    bytes[] memory data,
    uint256[] memory txGas
  ) public payable virtual onlyThis returns (bool[] memory successes, bytes[] memory returnData) {
    uint256 qty = to.length;
    if (value.length != qty || data.length != qty || txGas.length != qty) revert ArrayLengthMismatch();
    successes = new bool[](qty);
    returnData = new bytes[](qty);
    for (uint256 i; i < qty; ) {
      _beforeInnerCall(to[i], value[i], data[i]);
      (successes[i], returnData[i]) = _rawCall(txGas[i], to[i], value[i], data[i]);
      unchecked {
        ++i;
      }
    }
    emit MultiRequestExecuted(_txnNonce - 1, successes, returnData);
  }

  /// @notice Atomic variant of `multiRequest`: executes the batch of inner
  ///         calls in order and reverts the entire transaction on the FIRST
  ///         failure. Use this when the batch must be all-or-nothing —
  ///         typical for treasury operations where the second call depends
  ///         on the first one's side effect (e.g. approve-then-swap).
  /// @dev    Differs from `multiRequest` in three ways:
  ///         1. On any inner-call failure the outer tx reverts. No
  ///            `MultiRequestExecuted` event is emitted and no inner call's
  ///            side effects persist (the EVM rolls back the whole tx).
  ///         2. The failure path bubbles up `BatchCallFailed(index, reason)`
  ///            where `index` is the position of the failing call and
  ///            `reason` is its raw return data.
  ///         3. Does NOT return `(successes, returnData)` because the
  ///            success path is identical to a normal tx receipt.
  ///         Like `multiRequest`, callable only via the wallet itself
  ///         (the `onlyThis` modifier), so callers must route through
  ///         `execTransaction` (and gather enough signatures).
  /// @param to The address to call for each inner transaction. (array)
  /// @param value The ETH value to forward for each inner call. (array)
  /// @param data The calldata for each inner call. (array)
  /// @param txGas The gas limit for each inner call. (array)
  function multiRequestStrict(
    address[] memory to,
    uint256[] memory value,
    bytes[] memory data,
    uint256[] memory txGas
  ) public payable virtual onlyThis {
    uint256 qty = to.length;
    if (value.length != qty || data.length != qty || txGas.length != qty) revert ArrayLengthMismatch();
    for (uint256 i; i < qty; ) {
      _beforeInnerCall(to[i], value[i], data[i]);
      (bool ok, bytes memory returnData) = _rawCall(txGas[i], to[i], value[i], data[i]);
      if (!ok) revert BatchCallFailed(i, returnData);
      unchecked {
        ++i;
      }
    }
  }

  /// @notice EIP-1271 entry point. Validates `signature` (an ABI-encoded
  ///         `(address owner, bytes sig)[]` of owner votes) against `hash` and
  ///         returns the standard magic value iff the count of valid votes
  ///         reaches `threshold`. Pure: no state mutation, no nonce
  ///         bookkeeping. A single contract signature may carry many owner
  ///         votes — this is the path used when another Safe / multisig /
  ///         SIWE verifier / NFT marketplace calls `isValidSignature` on this
  ///         wallet.
  /// @dev    The supplied `hash` is treated as opaque: the caller decides what
  ///         is being signed. The wallet does NOT compute an EIP-712 hash here
  ///         — the in-wallet `_validateSignature` path does that, but the
  ///         EIP-1271 entry point is generic over the hash.
  /// @param hash The hash the caller wants validated.
  /// @param signature ABI-encoded `(address owner, bytes sig)[]` of owner
  ///        votes, or empty bytes to check for an on-chain `signMessage`
  ///        approval of `hash` (see `signMessage`).
  /// @return magicValue `bytes4(0x1626ba7e)` on success, `bytes4(0xffffffff)` otherwise.
  function isValidSignature(bytes32 hash, bytes memory signature) public view virtual returns (bytes4 magicValue) {
    if (signature.length == 0 && _signedMessages[getMessageHash(abi.encode(hash))]) return _ERC1271_MAGIC;
    return _checkSignatures(hash, 0, signature) ? _ERC1271_MAGIC : bytes4(0xffffffff);
  }

  /// @notice Builds the EIP-712 hash of an off-chain-auth message. The hash
  ///         binds the raw `message` bytes into this wallet's domain
  ///         separator (name, version, chainId, wallet address), so the
  ///         same message produces a different hash on every wallet.
  /// @param message The raw message bytes. To authorize a 32-byte digest
  ///        `dataHash` for EIP-1271 verifiers, pass `abi.encode(dataHash)`.
  /// @return The EIP-712 message hash used as the `_signedMessages` key.
  function getMessageHash(bytes memory message) public view virtual returns (bytes32) {
    return _hashTypedDataV4(keccak256(abi.encode(_MSG_TYPEHASH, keccak256(message))));
  }

  /// @notice Marks `message` as signed by the wallet, with full threshold
  ///         consensus: the call must run inside an `execTransaction`
  ///         (`onlyThis`), so it carries the same signature requirements as
  ///         any other wallet action. Once signed, EIP-1271 verifiers that
  ///         call `isValidSignature(dataHash, '')` — with an EMPTY signature
  ///         — get the magic value back for `message == abi.encode(dataHash)`.
  ///         This lets the wallet prove control off-chain (SIWE, order
  ///         pre-signing, ownership attestations) without any owner
  ///         signature present at verification time.
  /// @param message The raw message bytes (see `getMessageHash`).
  function signMessage(bytes memory message) public virtual onlyThis {
    bytes32 msgHash = getMessageHash(message);
    _signedMessages[msgHash] = true;
    emit MessageSigned(msgHash);
  }

  /// @notice Withdraws a previous `signMessage(message)` so EIP-1271
  ///         verifiers stop accepting the empty-signature proof. Requires
  ///         threshold consensus (`onlyThis`), same as `signMessage`.
  /// @param message The raw message bytes that were previously signed.
  function unsignMessage(bytes memory message) public virtual onlyThis {
    bytes32 msgHash = getMessageHash(message);
    if (!_signedMessages[msgHash]) revert MessageNotSigned();
    _signedMessages[msgHash] = false;
    emit MessageUnsigned(msgHash);
  }

  /// @notice Whether the wallet has signed the message with this EIP-712
  ///         message hash (see `getMessageHash`) via `signMessage`.
  /// @param msgHash The EIP-712 message hash.
  /// @return True if the message is currently signed.
  function isMessageSigned(bytes32 msgHash) public view virtual returns (bool) {
    return _signedMessages[msgHash];
  }

  /// @notice Determines if the signature is valid
  /// @param to The address to which the transaction is made.
  /// @param value The amount of Ether to be transferred.
  /// @param data The data to be passed along with the transaction.
  /// @param txnGas The gas limit for the transaction.
  /// @param txnNonce The nonce bound to the transaction. The 5-arg `execTransaction`
  ///        overload pins this to `_txnNonce`; the 6-arg overload in
  ///        `MyMultiSigExtended` lets callers choose a custom nonce (e.g. a future
  ///        one inside the replay window).
  /// @param validUntil Unix timestamp after which the signature is no longer
  ///        valid. `0` disables the deadline check (signatures never expire).
  ///        Baked into the EIP-712 hash so the bound signatures must match.
  /// @param signatures The signatures to be used for the transaction.
  /// @return valid True if the signature is valid, false otherwise.
  function isValidSignature(
    address to,
    uint256 value,
    bytes memory data,
    uint256 txnGas,
    uint256 txnNonce,
    uint256 validUntil,
    bytes memory signatures
  ) public view returns (bool valid) {
    bytes32 txHash = generateHash(to, value, data, txnGas, txnNonce, validUntil);
    return _checkSignatures(txHash, txnNonce, signatures);
  }

  /// @notice Validates an ABI-encoded `(address owner, bytes sig)[]` of owner
  ///         votes against `txHash` and reports whether they reach `threshold`.
  ///         Pure (no state mutation, no nonce bookkeeping). Shared between
  ///         the public EIP-1271 `isValidSignature(bytes32,bytes)` and the
  ///         6-arg view `isValidSignature(address,...,bytes)`.
  /// @dev    On-chain `approveHash` approvals count as votes for the matching
  ///         tx hash without any signature payload. An approval from an
  ///         address that is no longer an owner is skipped — it neither
  ///         counts toward the threshold nor blocks the remaining votes.
  ///         Each owner counts at most once: a vote whose owner already
  ///         approved on-chain, or already appeared at an earlier index of
  ///         the same `Vote[]`, is skipped. This mirrors the per-`(nonce,
  ///         owner)` slot bookkeeping of the mutating
  ///         `_validateSignatureForHash` path, so a payload accepted here
  ///         also reaches threshold inside `execTransaction` (build payloads
  ///         with one entry per owner — a duplicated owner never adds a
  ///         second vote on either path).
  function _checkSignatures(
    bytes32 txHash,
    uint256 txnNonce,
    bytes memory signatures
  ) internal view virtual returns (bool valid) {
    uint16 threshold_ = _threshold;
    address[] storage approved = _approvedOwners[txHash];
    uint256 approvedLength = approved.length;
    uint256 counted;
    for (uint256 i; i < approvedLength; ) {
      unchecked {
        if (isOwner(approved[i])) ++counted;
        ++i;
      }
    }
    if (counted >= threshold_) return true;
    Vote[] memory votes = _decodeVotes(signatures);
    uint256 votesLength = votes.length;
    for (uint256 i = 0; i < votesLength; ) {
      unchecked {
        if (counted >= threshold_) break;
        address voteOwner = votes[i].owner;
        bool duplicate = _approvedHashes[txHash][voteOwner];
        for (uint256 j; j < i && !duplicate; ++j) {
          if (votes[j].owner == voteOwner) duplicate = true;
        }
        if (!duplicate && _validateVote(txHash, voteOwner, votes[i].sig)) ++counted;
        ++i;
      }
    }
    return counted >= threshold_;
  }

  /// @notice Validates one `(owner, sig)` pair against `txHash` and, on success,
  ///         records the vote in `_ownerNonceSigned` and bumps the owner's
  ///         `lastAction` via `_recordOwnerApproval`. Used by the mutating
  ///         `_validateSignature` path that runs inside `execTransaction`.
  /// @dev    Two signature shapes are accepted:
  ///         - 65-byte ECDSA `r || s || v`: OZ `ECDSA.tryRecover` derives the
  ///           signer — enforcing canonical low-`s` values and `v ∈ {27, 28}`
  ///           so a malleated twin of a valid signature is rejected — and we
  ///           require `recovered == owner` AND `isOwner(recovered)`.
  ///           The recovered address is the source of truth — a malicious
  ///           signer cannot lie about identity via ECDSA.
  ///         - any other length from a contract owner: we static-call
  ///           `IERC1271.isValidSignature(txHash, sig)` on `owner` (with a
  ///           fixed gas stipend). The blob's `owner` field is authoritative
  ///           here because there is no `ecrecover` equivalent for contracts.
  ///         If neither branch succeeds, returns false.
  function _validateVote(
    bytes32 txHash,
    address owner,
    bytes memory sig
  ) internal view virtual returns (bool) {
    if (!isOwner(owner)) return false;
    if (sig.length == 65) {
      // ECDSA branch — recover and require recovered == owner.
      (address recovered, ECDSA.RecoverError err) = ECDSA.tryRecover(txHash, sig);
      if (err != ECDSA.RecoverError.NoError || recovered != owner) {
        // Fall through to EIP-1271 only if the owner has code. A bare EOA
        // with a 65-byte payload that doesn't recover to it is a hostile /
        // mis-typed vote — reject.
        if (owner.code.length == 0) return false;
        return _isValidERC1271(owner, txHash, sig);
      }
      // Recovered == owner. Note: a contract owner whose EOA operator signs
      // with a 65-byte ECDSA passes through here. That is the simplest way
      // for a contract operator to vote without implementing IERC1271.
    } else if (owner.code.length > 0) {
      // EIP-1271 branch — only contract owners can produce arbitrary-length
      // signature blobs, so reject bare-EOA entries of unexpected length.
      if (!_isValidERC1271(owner, txHash, sig)) return false;
    } else {
      // EOA owner, non-65-byte signature: not a valid vote shape.
      return false;
    }
    return true;
  }

  /// @notice Performs the bookkeeping that `_checkSignatures` skipped: marks
  ///         the (nonce, owner) slot consumed and bumps `lastAction` via
  ///         `_recordOwnerApproval`. Only called from `_validateSignature`.
  ///         Returns whether the vote was valid (mirrors `_validateVote`).
  function _recordVote(
    bytes32 /* txHash */,
    uint256 txnNonce,
    address owner
  ) internal virtual returns (bool) {
    uint256 ownerNonce = uint256(uint96(txnNonce)) + uint256(uint160(owner) << 96);
    if (_ownerNonceSigned[ownerNonce]) return false;
    _ownerNonceSigned[ownerNonce] = true;
    _recordOwnerApproval(owner);
    return true;
  }

  /// @notice Determines if the signature is valid
  /// @param to The address to which the transaction is made.
  /// @param value The amount of Ether to be transferred.
  /// @param data The data to be passed along with the transaction.
  /// @param txnGas The gas limit for the transaction.
  /// @param txnNonce The nonce bound to the transaction. The 5-arg `execTransaction`
  ///        overload pins this to `_txnNonce`; the 6-arg overload in
  ///        `MyMultiSigExtended` lets callers choose a custom nonce.
  /// @param validUntil Unix timestamp after which the signature is no longer
  ///        valid. `0` disables the deadline check (signatures never expire).
  ///        Baked into the EIP-712 hash so the bound signatures must match.
  ///        Reverts with `SignatureExpired` if `validUntil != 0` and
  ///        `block.timestamp > validUntil`.
  /// @param signatures The signatures to be used for the transaction.
  /// @return valid True if the signature is valid, false otherwise.
  function _validateSignature(
    address to,
    uint256 value,
    bytes memory data,
    uint256 txnGas,
    uint256 txnNonce,
    uint256 validUntil,
    bytes memory signatures
  ) internal virtual returns (bool valid) {
    if (validUntil != 0 && block.timestamp > validUntil) revert SignatureExpired();
    bytes32 txHash = generateHash(to, value, data, txnGas, txnNonce, validUntil);
    return _validateSignatureForHash(txHash, txnNonce, signatures);
  }

  /// @notice Mutating vote-counting core shared by `_validateSignature` and
  ///         `MyMultiSigExtended`'s 7-field (`operation`-bound) validator.
  ///         Counts on-chain approvals plus decoded signature votes against
  ///         `txHash`, consuming each vote's `(nonce, owner)` slot via
  ///         `_recordVote`. The caller is responsible for any expiry /
  ///         used-nonce pre-checks and for computing the right typed-data hash.
  function _validateSignatureForHash(
    bytes32 txHash,
    uint256 txnNonce,
    bytes memory signatures
  ) internal virtual returns (bool valid) {
    uint16 threshold_ = _threshold;
    // On-chain approvals count as votes and consume their (nonce, owner)
    // slot. An approval from an address that is no longer an owner, or whose
    // (nonce, owner) slot is already consumed, is skipped — it neither counts
    // toward the threshold nor blocks the remaining votes.
    address[] storage approved = _approvedOwners[txHash];
    uint256 approvedLength = approved.length;
    uint256 counted;
    for (uint256 i; i < approvedLength; ) {
      unchecked {
        address approvedOwner = approved[i];
        if (isOwner(approvedOwner) && _recordVote(txHash, txnNonce, approvedOwner)) ++counted;
        ++i;
      }
    }
    if (counted < threshold_) {
      Vote[] memory votes = _decodeVotes(signatures);
      uint256 votesLength = votes.length;
      for (uint256 i = 0; i < votesLength; ) {
        unchecked {
          if (counted >= threshold_) break;
          if (_validateVote(txHash, votes[i].owner, votes[i].sig) && _recordVote(txHash, txnNonce, votes[i].owner))
            ++counted;
          ++i;
        }
      }
    }
    valid = counted >= threshold_;
    // The hash is about to execute (or be scheduled): its on-chain approvals
    // are consumed, so clear them. This keeps `getApprovedOwners` accurate
    // and stops stale entries (e.g. from since-removed owners) from
    // inflating the vote-count loops of this hash forever.
    if (valid) _pruneApprovals(txHash);
  }

  /// @notice Clears every `approveHash` record for `txHash`: each owner's
  ///         `_approvedHashes` flag and the whole `_approvedOwners` list.
  ///         Called once a hash reaches threshold on the mutating
  ///         validation path — the approvals are consumed by the execution.
  function _pruneApprovals(bytes32 txHash) internal virtual {
    address[] storage approved = _approvedOwners[txHash];
    uint256 n = approved.length;
    if (n == 0) return;
    for (uint256 i; i < n; ) {
      unchecked {
        _approvedHashes[txHash][approved[i]] = false;
        ++i;
      }
    }
    delete _approvedOwners[txHash];
  }

  /// @notice Decodes an ABI-encoded `(address owner, bytes sig)[]` blob.
  ///         Centralized so the vote-counting cores (`_checkSignatures` and
  ///         `_validateSignatureForHash`) decode identically. Returns an
  ///         empty array if the input is empty.
  function _decodeVotes(bytes memory signatures) internal pure virtual returns (Vote[] memory) {
    if (signatures.length == 0) return new Vote[](0);
    return abi.decode(signatures, (Vote[]));
  }

  /// @notice Storage-free tuple used solely to decode the per-vote signature
  ///         blob. See `_decodeVotes`.
  struct Vote {
    address owner;
    bytes sig;
  }
  ///         with a fixed gas stipend and returns whether the magic value
  ///         came back. Returns false on any failure path: revert, OOG,
  ///         short returndata, or non-matching magic.
  function _isValidERC1271(
    address signer,
    bytes32 hash,
    bytes memory sig
  ) internal view virtual returns (bool) {
    (bool success, bytes memory ret) = signer.staticcall{gas: _ERC1271_GAS_STIPEND}(
      abi.encodeWithSelector(IERC1271.isValidSignature.selector, hash, sig)
    );
    return (success && ret.length >= 32 && abi.decode(ret, (bytes32)) == bytes32(_ERC1271_MAGIC));
  }

  /// @notice Hook fired each time an owner's vote is recorded against a
  ///         transaction — whether via `approveHash` or via `_recordVote`
  ///         inside `_validateSignature`. The base implementation is a no-op;
  ///         `MyMultiSigExtended` overrides this hook to bump `lastAction`
  ///         for inactivity tracking. Because every vote source flows through
  ///         this hook (on-chain approval, ECDSA vote, EIP-1271 contract-owner
  ///         vote), the inactivity tracking works uniformly across all paths.
  function _recordOwnerApproval(address /* owner */) internal virtual {}

  /// @notice Adds an owner
  /// @param owner The address to be added as an owner.
  /// @dev This function can only be called inside a multisig transaction.
  ///      Reverts with `NewOwnerMustNotBeZero` for the zero address and the
  ///      linked-list sentinel (`address(0x1)`) — neither can ever vote,
  ///      and both are reserved by the owners list encoding.
  function _addOwner(address owner) internal virtual {
    if (owner == address(0) || owner == _SENTINEL_OWNER) revert NewOwnerMustNotBeZero();
    if (_ownersNext[owner] != address(0)) revert OwnerAlreadyExists();
    _ownersNext[owner] = _ownersNext[_SENTINEL_OWNER];
    _ownersNext[_SENTINEL_OWNER] = owner;
    ++_ownerCount;
    emit OwnerAdded(owner);
  }

  /// @notice Adds an owner
  /// @param owner The address to be added as an owner.
  /// @dev This function can only be called inside a multisig transaction.
  function addOwner(address owner) public virtual onlyThis {
    if (_ownerCount >= 2 ** 16 - 1) revert TooManyOwners();
    _addOwner(owner);
  }

  /// @notice Removes an owner
  /// @param owner The owner to be removed.
  /// @dev This function can only be called inside a multisig transaction.

  function _removeOwner(address owner) internal virtual {
    if (!isOwner(owner)) revert OwnerToRemoveMustBeOwner();
    if (_ownerCount <= _threshold) revert CannotRemoveOwnerBelowThreshold();
    _ownersNext[_findPrevOwner(owner)] = _ownersNext[owner];
    delete _ownersNext[owner];
    --_ownerCount;
    emit OwnerRemoved(owner);
  }

  /// @dev Walks the owners linked list to find the entry pointing at
  ///      `owner`. The caller has already verified `owner` is a current
  ///      owner, so the walk always terminates. O(n) SLOADs, but owner
  ///      removal / replacement is a rare admin action.
  function _findPrevOwner(address owner) private view returns (address prev) {
    prev = _SENTINEL_OWNER;
    address cursor = _ownersNext[_SENTINEL_OWNER];
    while (cursor != owner) {
      prev = cursor;
      cursor = _ownersNext[cursor];
    }
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
    if (newThreshold == 0) revert ThresholdMustBeGreaterThanZero();
    if (newThreshold > _ownerCount) revert ThresholdMustBeLessOrEqualToOwnerCount();
    _threshold = newThreshold;
    emit ThresholdChanged(newThreshold);
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
    if (!isOwner(oldOwner)) revert OldOwnerMustBeOwner();
    if (isOwner(newOwner)) revert NewOwnerMustNotBeOwner();
    if (newOwner == address(0) || newOwner == _SENTINEL_OWNER) revert NewOwnerMustNotBeZero();
    // Splice the new owner into the old owner's position in the linked
    // list, so list order is preserved.
    _ownersNext[newOwner] = _ownersNext[oldOwner];
    _ownersNext[_findPrevOwner(oldOwner)] = newOwner;
    delete _ownersNext[oldOwner];
    emit OwnerRemoved(oldOwner);
    emit OwnerAdded(newOwner);
  }

  /// @notice Builds the EIP-712 transaction hash for the given payload. The
  ///         hash binds `(to, value, data, gas, nonce, validUntil)`; signers
  ///         must therefore include `validUntil` in their typed-data payload
  ///         or the resulting signature will not validate.
  /// @param to The address to which the transaction is made.
  /// @param value The amount of Ether to be transferred.
  /// @param data The data to be passed along with the transaction.
  /// @param txnGas The gas limit for the transaction.
  /// @param txnNonce The nonce bound to the transaction.
  /// @param validUntil Unix timestamp after which the signature is invalid;
  ///        `0` means "no expiry".
  function generateHash(
    address to,
    uint256 value,
    bytes memory data,
    uint256 txnGas,
    uint256 txnNonce,
    uint256 validUntil
  ) public view virtual returns (bytes32) {
    return
      _hashTypedDataV4(
        keccak256(
          abi.encode(
            _TRANSACTION_TYPEHASH,
            to,
            value,
            keccak256(data),
            txnGas,
            txnNonce,
            validUntil
          )
        )
      );
  }

  /// @notice Increments the transaction nonce, can be use to invalidate previous signatures
  /// @dev This function can only be called inside a multisig transaction.
  function incrementNonce() public virtual onlyThis {
    _txnNonce++;
  }

  /// @dev Mutation hook so internal `_execTransaction` /
  ///      `_execExtended` can bump the nonce without going through the
  ///      `onlyThis`-guarded `incrementNonce()` public entry (calling
  ///      that from inside `execTransaction` would revert because the
  ///      external caller's `msg.sender` is not `address(this)`).
  function _bumpNonce() internal virtual {
    _txnNonce++;
  }

  /// @notice Receives Ether
  receive() external payable {}
}
