// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Vm } from 'forge-std/Vm.sol';

/// @title Signatures
/// @notice EIP-712 signing helpers ported from the (now removed) `foundry-test-utility`
///         dependency. Kept as a mixin so it composes with the rest of the test
///         shared/ contracts without pulling in any external package.
contract Signatures {
  Vm private constant _vm = Vm(address(uint160(uint256(keccak256('hevm cheat code')))));

  /// @notice EIP-712 digest: keccak256("\x19\x01" || domainSeparator || hash)
  function signature_signHashEip712(bytes32 domainSeparator_, bytes32 hash_) internal pure returns (bytes32) {
    return keccak256(abi.encodePacked('\x19\x01', domainSeparator_, hash_));
  }

  /// @notice Signs `hash_` under the given EIP-712 domain separator with
  ///         `signerPrivateKey_`, returning the packed `r || s || v` signature.
  function signature_signHashed(
    uint256 signerPrivateKey_,
    bytes32 domainSeparator_,
    bytes32 hash_
  ) internal pure returns (bytes memory signature) {
    (uint8 v, bytes32 r, bytes32 s) = _vm.sign(signerPrivateKey_, signature_signHashEip712(domainSeparator_, hash_));
    signature = abi.encodePacked(r, s, v);
  }
}