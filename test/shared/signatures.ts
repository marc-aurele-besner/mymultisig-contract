import { network } from 'hardhat'
import { BigNumber } from 'ethers'

import constants from '../../constants'

export default {
  signMultiSigTxn: async function (
    contractOrAddress: any,
    sourceWallet: any,
    to: string,
    value: BigNumber,
    data: string,
    gas: number,
    nonce: BigNumber,
    validUntil: number = 0,
    /**
     * Override the EIP-712 `version` field. When omitted AND the first
     * argument is a contract instance with a `version()` view, we read it
     * directly from the wallet so the typed-data domain separator stays in
     * sync with the v0.4.0 `MyMultiSigExtended` bump. Pass
     * `constants.CONTRACT_VERSION_EXTENDED` to force the Extended version
     * when the first argument is a string address.
     */
    explicitVersion?: string
  ) {
    // Resolve the signing contract address and the EIP-712 version. We
    // accept either a string address (legacy callers) or an ethers
    // Contract instance so the helper can self-detect the v0.4.0 domain
    // without requiring every call site to be updated.
    const contractAddress: string =
      typeof contractOrAddress === 'string' ? contractOrAddress : contractOrAddress.address
    let version: string = explicitVersion ?? constants.CONTRACT_VERSION
    if (!explicitVersion && contractOrAddress && typeof contractOrAddress === 'object' && typeof contractOrAddress.version === 'function') {
      const v = await contractOrAddress.version()
      if (typeof v === 'string' && v.length > 0) version = v
    }
    var signature = await sourceWallet._signTypedData(
      {
        name: constants.CONTRACT_NAME,
        version,
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
  signEip712Hash: async function (
    contract: any,
    owner: any,
    hashFields: any,
    version: string = constants.CONTRACT_VERSION
  ): Promise<string> {
    // For the v0.4.0 MyMultiSigExtended wallet, the caller's domain version
    // MUST match `wallet.version()`. Detect and pass through.
    const isExtended = typeof contract.allowOnlyOwnerRequest === 'function'
    if (isExtended) {
      const v = await contract.version()
      if (typeof v === 'string' && v.length > 0) version = v
    }
    return owner._signTypedData(
      {
        name: constants.CONTRACT_NAME,
        version,
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
