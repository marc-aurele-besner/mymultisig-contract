// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import '@openzeppelin/contracts/security/ReentrancyGuard.sol';

import '../interfaces/IModuleWallet.sol';

/// @title SessionKeyModule
/// @notice Time-bounded, scope-limited session keys ("temporary signers")
///         for `MyMultiSigExtended` wallets — e.g. "this key can call
///         Uniswap for 24 hours, spending up to 1 ETH" — without touching
///         the wallet's permanent owner set or threshold.
///
///         One deployed instance serves any number of wallets. A wallet
///         opts in by enabling this module (`enableModule`, threshold-
///         gated) and then granting keys via `grantSessionKey` — also
///         threshold-gated, because the wallet itself must be the caller.
///         The key holder executes with a plain transaction from the key:
///         `executeWithSessionKey(wallet, to, value, data)`.
///
///         Every grant is bounded on three axes:
///         - time: `[validAfter, validUntil]` unix window;
///         - scope: an explicit target allowlist (mandatory) plus an
///           optional function-selector allowlist;
///         - value: a cumulative wei budget across the whole session.
///
///         A session key can NEVER call the wallet itself, so it cannot
///         reach `addOwner` / `changeThreshold` / `enableModule` or any
///         other `onlyThis` admin surface. The wallet's guard and
///         allowlist gates still run inside `execTransactionFromModule`.
///
///         Revocation is deliberately cheaper than granting: the wallet
///         (threshold) OR any single current owner can revoke a key
///         immediately — a leaked session key must not stay live while a
///         quorum is assembled.
contract SessionKeyModule is ReentrancyGuard {
  struct SessionKey {
    /// @notice Unix timestamp the key becomes usable at. `0` = immediately.
    uint48 validAfter;
    /// @notice Unix timestamp the key expires at (inclusive). `0` = no grant.
    uint48 validUntil;
    /// @notice Bumped on every grant and revoke. Target / selector scope
    ///         entries are keyed by epoch, so a re-grant or revoke
    ///         invalidates the previous scope without iterating it.
    uint64 epoch;
    /// @notice When true, only calldata whose selector is in the grant's
    ///         selector set is allowed. Plain ETH transfers (calldata
    ///         shorter than 4 bytes) match the sentinel selector
    ///         `bytes4(0)`, which must be allowed explicitly.
    bool restrictSelectors;
    /// @notice Total wei the key may spend over the session.
    uint256 ethBudget;
    /// @notice Wei spent so far. Only successful calls are charged.
    uint256 ethSpent;
  }

  /// @notice wallet => session key address => grant.
  mapping(address => mapping(address => SessionKey)) private _sessionKeys;
  /// @notice Allowed call targets, keyed by `keccak256(abi.encode(wallet,
  ///         key, epoch, target))` so stale epochs never match.
  mapping(bytes32 => bool) private _allowedTarget;
  /// @notice Allowed function selectors, keyed by `keccak256(abi.encode(
  ///         wallet, key, epoch, selector))` so stale epochs never match.
  mapping(bytes32 => bool) private _allowedSelector;

  event SessionKeyGranted(
    address indexed wallet,
    address indexed key,
    uint48 validAfter,
    uint48 validUntil,
    uint256 ethBudget,
    address[] targets,
    bytes4[] selectors
  );
  event SessionKeyRevoked(address indexed wallet, address indexed key, address revoker);
  event SessionKeyUsed(
    address indexed wallet,
    address indexed key,
    address indexed to,
    uint256 value,
    bytes data,
    bool success
  );

  error SessionKeyZeroAddress();
  error SessionKeyInvalidWindow(uint48 validAfter, uint48 validUntil);
  error SessionKeyNoTargets();
  error SessionKeyTargetIsWallet();
  error SessionKeyNotActive(address wallet, address key);
  error SessionKeyTargetNotAllowed(address to);
  error SessionKeySelectorNotAllowed(bytes4 selector);
  error SessionKeyBudgetExceeded(uint256 requested, uint256 remaining);
  error SessionKeyCannotCallWallet();
  error NotWalletOrOwner(address caller);

  // ---------------------------------------------------------------------------
  // Grant / revoke — `msg.sender` is the wallet (grant) or wallet/owner (revoke)
  // ---------------------------------------------------------------------------

  /// @notice Grants (or re-grants, overwriting scope and resetting the
  ///         spent counter) a session key for the calling wallet. Must be
  ///         invoked BY the wallet, i.e. through a threshold-signed
  ///         `execTransaction` that targets this module.
  /// @param key The temporary signer address. Must be non-zero.
  /// @param validAfter Unix timestamp the key activates at; `0` = now.
  /// @param validUntil Unix timestamp the key expires at (inclusive). Must
  ///        be in the future and after `validAfter`.
  /// @param ethBudget Total wei the key may spend over the session.
  /// @param targets Allowed call targets. Mandatory (at least one), and the
  ///        wallet itself is never allowed.
  /// @param selectors Optional allowed function selectors. Empty = any
  ///        selector on the allowed targets. Include `bytes4(0)` to allow
  ///        plain ETH transfers when restricting selectors.
  function grantSessionKey(
    address key,
    uint48 validAfter,
    uint48 validUntil,
    uint256 ethBudget,
    address[] calldata targets,
    bytes4[] calldata selectors
  ) external {
    if (key == address(0)) revert SessionKeyZeroAddress();
    if (validUntil <= block.timestamp || validAfter >= validUntil)
      revert SessionKeyInvalidWindow(validAfter, validUntil);
    if (targets.length == 0) revert SessionKeyNoTargets();

    SessionKey storage sk = _sessionKeys[msg.sender][key];
    uint64 epoch = sk.epoch + 1;
    sk.validAfter = validAfter;
    sk.validUntil = validUntil;
    sk.epoch = epoch;
    sk.restrictSelectors = selectors.length > 0;
    sk.ethBudget = ethBudget;
    sk.ethSpent = 0;

    for (uint256 i = 0; i < targets.length; ) {
      address target = targets[i];
      if (target == address(0)) revert SessionKeyZeroAddress();
      if (target == msg.sender) revert SessionKeyTargetIsWallet();
      _allowedTarget[keccak256(abi.encode(msg.sender, key, epoch, target))] = true;
      unchecked {
        ++i;
      }
    }
    for (uint256 i = 0; i < selectors.length; ) {
      _allowedSelector[keccak256(abi.encode(msg.sender, key, epoch, selectors[i]))] = true;
      unchecked {
        ++i;
      }
    }
    emit SessionKeyGranted(msg.sender, key, validAfter, validUntil, ethBudget, targets, selectors);
  }

  /// @notice Revokes a session key immediately. Callable by the wallet
  ///         itself (threshold path) or by ANY single current owner of the
  ///         wallet, so a leaked key can be killed without waiting for a
  ///         quorum.
  /// @param wallet The wallet the key was granted for.
  /// @param key The session key to revoke.
  function revokeSessionKey(address wallet, address key) external {
    if (msg.sender != wallet && !IModuleWallet(wallet).isOwner(msg.sender)) revert NotWalletOrOwner(msg.sender);
    SessionKey storage sk = _sessionKeys[wallet][key];
    if (sk.validUntil == 0) revert SessionKeyNotActive(wallet, key);
    // Bumping the epoch orphans every target / selector entry of the
    // revoked grant; zeroing `validUntil` returns the key to "no grant".
    sk.epoch += 1;
    sk.validAfter = 0;
    sk.validUntil = 0;
    sk.restrictSelectors = false;
    sk.ethBudget = 0;
    sk.ethSpent = 0;
    emit SessionKeyRevoked(wallet, key, msg.sender);
  }

  // ---------------------------------------------------------------------------
  // Execution — `msg.sender` is the session key
  // ---------------------------------------------------------------------------

  /// @notice Executes `(to, value, data)` through `wallet` as the calling
  ///         session key. The key must be inside its time window, `to`
  ///         must be in the grant's target set (and never the wallet
  ///         itself), the selector must pass the optional selector set,
  ///         and `value` must fit the remaining budget. The budget is
  ///         charged before the call and refunded if the inner call
  ///         fails, so a reentrant attempt can never overspend.
  /// @return success Whether the inner call succeeded. Reverts with a
  ///         payload are bubbled up by the wallet instead.
  function executeWithSessionKey(
    address wallet,
    address to,
    uint256 value,
    bytes calldata data
  ) external nonReentrant returns (bool success) {
    SessionKey storage sk = _sessionKeys[wallet][msg.sender];
    if (sk.validUntil == 0 || block.timestamp > sk.validUntil || block.timestamp < sk.validAfter)
      revert SessionKeyNotActive(wallet, msg.sender);
    if (to == wallet) revert SessionKeyCannotCallWallet();
    uint64 epoch = sk.epoch;
    if (!_allowedTarget[keccak256(abi.encode(wallet, msg.sender, epoch, to))]) revert SessionKeyTargetNotAllowed(to);
    if (sk.restrictSelectors) {
      bytes4 selector = data.length >= 4 ? bytes4(data[:4]) : bytes4(0);
      if (!_allowedSelector[keccak256(abi.encode(wallet, msg.sender, epoch, selector))])
        revert SessionKeySelectorNotAllowed(selector);
    }
    uint256 spent = sk.ethSpent + value;
    if (spent > sk.ethBudget) revert SessionKeyBudgetExceeded(value, sk.ethBudget - sk.ethSpent);
    sk.ethSpent = spent;

    success = IModuleWallet(wallet).execTransactionFromModule(to, value, data, 0);
    if (!success) sk.ethSpent = spent - value;
    emit SessionKeyUsed(wallet, msg.sender, to, value, data, success);
  }

  // ---------------------------------------------------------------------------
  // Views
  // ---------------------------------------------------------------------------

  /// @notice Full grant record for `(wallet, key)`. `validUntil == 0`
  ///         means no active grant.
  function sessionKey(address wallet, address key) public view returns (SessionKey memory) {
    return _sessionKeys[wallet][key];
  }

  /// @notice Whether the key is usable right now (granted and inside its
  ///         time window). Does not consider the remaining budget.
  function isSessionKeyActive(address wallet, address key) public view returns (bool) {
    SessionKey storage sk = _sessionKeys[wallet][key];
    return sk.validUntil != 0 && block.timestamp <= sk.validUntil && block.timestamp >= sk.validAfter;
  }

  /// @notice Whether the key's current grant allows calling `target`.
  function isSessionTargetAllowed(address wallet, address key, address target) public view returns (bool) {
    return _allowedTarget[keccak256(abi.encode(wallet, key, _sessionKeys[wallet][key].epoch, target))];
  }

  /// @notice Whether the key's current grant allows `selector`. Always true
  ///         when the grant doesn't restrict selectors.
  function isSessionSelectorAllowed(address wallet, address key, bytes4 selector) public view returns (bool) {
    SessionKey storage sk = _sessionKeys[wallet][key];
    if (!sk.restrictSelectors) return true;
    return _allowedSelector[keccak256(abi.encode(wallet, key, sk.epoch, selector))];
  }

  /// @notice Remaining wei the key may still spend in its session.
  function sessionBudgetRemaining(address wallet, address key) public view returns (uint256) {
    SessionKey storage sk = _sessionKeys[wallet][key];
    return sk.ethBudget > sk.ethSpent ? sk.ethBudget - sk.ethSpent : 0;
  }
}
