import { network } from 'hardhat'
import { BigNumber } from 'ethers'

import constants from '../../constants'

export default {
  signMultiSigTxn: async function (
    contractAddress: string,
    sourceWallet: any,
    to: string,
    value: BigNumber,
    data: string,
    gas: number,
    nonce: BigNumber,
    validUntil: number = 0
  ) {
    var signature = await sourceWallet._signTypedData(
      {
        name: constants.CONTRACT_NAME,
        version: constants.CONTRACT_VERSION,
        chainId: network.config.chainId,
        verifyingContract: contractAddress,
      },
      {
        Transaction: [
          {
            name: 'to',
            type: 'address',
          },
          {
            name: 'value',
            type: 'uint256',
          },
          {
            name: 'data',
            type: 'bytes',
          },
          {
            name: 'gas',
            type: 'uint256',
          },
          {
            name: 'nonce',
            type: 'uint96',
          },
          {
            name: 'validUntil',
            type: 'uint256',
          },
        ],
      },
      {
        to,
        value,
        data,
        gas,
        nonce,
        validUntil,
      }
    )
    return signature
  },
  /// @notice Signs a wallet's EIP-712 transaction hash with each owner. The
  ///         returned array of 65-byte ECDSA blobs can be ABI-encoded as the
  ///         `(address,bytes)[]` payload to `isValidSignature(bytes32,bytes)`
  ///         when `hash = contract.generateHash(to, value, data, gas, nonce)`.
  /// @dev    Centralizes the typed-data signing for the EIP-1271 test path
  ///         so individual tests don't have to rebuild the domain/types.
  signEip712Hash: async function (contract: any, owner: any, hashFields: any): Promise<string> {
    return owner._signTypedData(
      {
        name: constants.CONTRACT_NAME,
        version: constants.CONTRACT_VERSION,
        chainId: network.config.chainId,
        verifyingContract: contract.address,
      },
      {
        Transaction: [
          { name: 'to', type: 'address' },
          { name: 'value', type: 'uint256' },
          { name: 'data', type: 'bytes' },
          { name: 'gas', type: 'uint256' },
          { name: 'nonce', type: 'uint96' },
          { name: 'validUntil', type: 'uint256' },
        ],
      },
      hashFields,
    )
  },
  /// @notice Produces a raw 65-byte ECDSA signature over `digest` using the
  ///         signing key of `signer`. Unlike `_signTypedData`, this does NOT
  ///         prepend the EIP-712 `\x19\x01 || domain` envelope, so the sig is
  ///         exactly what `ecrecover(digest, v, r, s)` recovers.
  /// @dev    Used by the EIP-1271 nested-wallet tests where the inner wallet
  ///         must produce signatures over an arbitrary outer-domain hash —
  ///         the inner wallet's `_validateVote` calls `ecrecover(hash, ...)`
  ///         directly, with no domain awareness.
  signDigest: async function (signer: any, digest: string): Promise<string> {
    // Use the lower-level SigningKey API and pack manually so we don't rely
    // on ethers' wrapper output conventions. `signDigest` returns
    // `{ v: 27|28, r, s }` already in the EIP-712 / ecrecover-friendly form.
    const sigObj = signer._signingKey().signDigest(digest)
    return ethers.utils.hexlify(
      ethers.utils.concat([
        ethers.utils.zeroPad(sigObj.r, 32),
        ethers.utils.zeroPad(sigObj.s, 32),
        ethers.utils.zeroPad(sigObj.v, 1),
      ]),
    )
  },
}
