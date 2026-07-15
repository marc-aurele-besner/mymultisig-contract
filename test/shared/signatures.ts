import { network } from 'hardhat'
import { BigNumber } from 'ethers'

import constants from '../../constants'

export default {
  /// @notice Signs a wallet's EIP-712 transaction hash. Picks the
  ///         v0.4.0 6-field typehash for the base `MyMultiSig` wallet
  ///         and the v0.5.0 7-field typehash (with `operation` byte)
  ///         for `MyMultiSigExtended`. Detection uses the presence of
  ///         `allowOnlyOwnerRequest()` on the contract.
  signMultiSigTxn: async function (
    contractOrAddress: any,
    sourceWallet: any,
    to: string,
    value: BigNumber,
    data: string,
    gas: number,
    nonce: BigNumber,
    validUntil: number = 0,
    operation: number = 0,
  ) {
    const contractAddress: string =
      typeof contractOrAddress === 'string' ? contractOrAddress : contractOrAddress.address
    const contract =
      typeof contractOrAddress === 'string'
        ? (sourceWallet.provider && (await sourceWallet.provider.getNetwork()), null)
        : contractOrAddress
    // We need to decide whether this is the base or extended wallet.
    // If we got a string address, fall back to the v0.4.0 6-field
    // typehash (the most common case for direct EIP-1271 helpers).
    const isExtended = contract && typeof (contract as any).allowOnlyOwnerRequest === 'function'
    if (isExtended) {
      return sourceWallet._signTypedData(
        {
          name: constants.CONTRACT_NAME,
          version: constants.CONTRACT_VERSION_V2_5,
          chainId: network.config.chainId,
          verifyingContract: contractAddress,
        },
        {
          Transaction: [
            { name: 'to', type: 'address' },
            { name: 'value', type: 'uint256' },
            { name: 'data', type: 'bytes' },
            { name: 'gas', type: 'uint256' },
            { name: 'nonce', type: 'uint96' },
            { name: 'validUntil', type: 'uint256' },
            { name: 'operation', type: 'uint8' },
          ],
        },
        { to, value, data, gas, nonce, validUntil, operation },
      )
    }
    return sourceWallet._signTypedData(
      {
        name: constants.CONTRACT_NAME,
        version: constants.CONTRACT_VERSION,
        chainId: network.config.chainId,
        verifyingContract: contractAddress,
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
      { to, value, data, gas, nonce, validUntil },
    )
  },
  /// @notice Signs a wallet's EIP-712 transaction hash with each owner.
  ///         `hashFields.operation` is only used for extended wallets.
  signEip712Hash: async function (contract: any, owner: any, hashFields: any): Promise<string> {
    const isExtended = typeof (contract as any).allowOnlyOwnerRequest === 'function'
    if (isExtended) {
      return owner._signTypedData(
        {
          name: constants.CONTRACT_NAME,
          version: constants.CONTRACT_VERSION_V2_5,
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
            { name: 'operation', type: 'uint8' },
          ],
        },
        { ...hashFields, operation: hashFields.operation ?? 0 },
      )
    }
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
  /// @notice Produces a raw 65-byte ECDSA signature over `digest` (no
  ///         EIP-712 envelope).
  signDigest: async function (signer: any, digest: string): Promise<string> {
    const sigObj = signer._signingKey().signDigest(digest)
    const ethers = require('ethers')
    return ethers.utils.hexlify(
      ethers.utils.concat([
        ethers.utils.zeroPad(sigObj.r, 32),
        ethers.utils.zeroPad(sigObj.s, 32),
        ethers.utils.zeroPad(sigObj.v, 1),
      ]),
    )
  },
}
