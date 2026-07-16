// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title IModuleWallet
/// @notice The minimal `MyMultiSigExtended` surface a module contract needs:
///         the module-driven execution entry point and the owner check used
///         for module-level access control (e.g. single-owner emergency
///         revocation in `SessionKeyModule`).
interface IModuleWallet {
  /// @notice Module-driven execution. The wallet reverts with `NotAModule`
  ///         unless `msg.sender` is a currently-enabled module. Guard and
  ///         allowlist gates still apply inside the wallet.
  /// @param operation 0 = CALL, 1 = DELEGATECALL (gated to `to == wallet`).
  function execTransactionFromModule(
    address to,
    uint256 value,
    bytes memory data,
    uint256 operation
  ) external payable returns (bool success);

  /// @notice Whether `owner` is a current owner of the wallet.
  function isOwner(address owner) external view returns (bool);
}
