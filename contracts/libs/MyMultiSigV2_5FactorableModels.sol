// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title MyMultiSigV2_5FactorableModels
/// @notice Shared models for the v0.5.0 CREATE2 wallet factory surface.
///         Lives alongside `MyMultiSigFactorableModels.sol` so v0.4.0
///         bytecode is not disturbed.
library MyMultiSigV2_5FactorableModels {
  /// @notice Salt-shape selector. Different values allow the same wallet
  ///         names to map to different addresses without colliding.
  enum SaltKind {
    OwnerSet,
    WalletName,
    CrossChainOwnerKey
  }

  /// @notice Parameters for both the address prediction and the
  ///         deployment. `saltKind` decides which fields are folded into
  ///         the salt; `chainAgnosticKey` is the user-supplied 32-byte
  ///         value reused across chains to make the address match.
  struct Create2Params {
    SaltKind saltKind;
    bytes32 chainAgnosticKey;
    string contractName;
    address[] owners;
    uint16 threshold;
  }
}
