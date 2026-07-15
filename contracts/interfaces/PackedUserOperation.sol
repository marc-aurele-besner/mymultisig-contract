// SPDX-License-Identifier: MIT
// Vendored from OpenZeppelin's draft-IERC4337.sol (April 2023 snapshot for v0.7).
// `PackedUserOperation` is the wire format the bundler relays to EntryPoint.handleOps.
pragma solidity ^0.8.0;

/// @notice Packed UserOperation (v0.7) — the format the bundler relays
///         to `EntryPoint.handleOps`. Layout is identical to the upstream
///         `@openzeppelin/contracts/interfaces/draft-IERC4337.sol` so the
///         wallet can interoperate with reference bundlers.
struct PackedUserOperation {
  address sender;
  uint256 nonce;
  bytes initCode; // concatenation of factory address + factory-call-data
  bytes callData;
  bytes32 accountGasLimits; // abi.encodePacked(verificationGasLimit, callGasLimit) — 16 bytes each
  uint256 preVerificationGas;
  bytes32 gasFees; // abi.encodePacked(maxPriorityFeePerGas, maxFeePerGas) — 16 bytes each
  bytes paymasterAndData;
  bytes signature;
}

/// @notice Helper to slice the 32-byte `accountGasLimits` field of a
///         `PackedUserOperation` back into its two 16-byte halves. Mirrors
///         `PackedUserOperationLib.unpackAccountGasLimits` from the upstream
///         `draft-IERC4337.sol`.
function unpackAccountGasLimits(bytes32 accountGasLimits) pure returns (uint128, uint128) {
  uint256 word = uint256(accountGasLimits);
  uint128 verificationGasLimit = uint128(word >> 128);
  uint128 callGasLimit = uint128(word & ((1 << 128) - 1));
  return (verificationGasLimit, callGasLimit);
}

/// @notice Helper to split the 32-byte `gasFees` field. Same encoding as upstream.
function unpackGasFees(bytes32 gasFees) pure returns (uint128, uint128) {
  uint256 word = uint256(gasFees);
  uint128 maxPriorityFeePerGas = uint128(word >> 128);
  uint128 maxFeePerGas = uint128(word & ((1 << 128) - 1));
  return (maxPriorityFeePerGas, maxFeePerGas);
}
