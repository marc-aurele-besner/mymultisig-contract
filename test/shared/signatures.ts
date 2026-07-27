import { network } from 'hardhat'

import constants from '../../constants'

const { ethers } = await network.getOrCreate()

export default {
  /// @notice Signs a wallet's EIP-712 transaction hash. Wallets bind
  ///         a single canonical version (`constants.CONTRACT_VERSION`)
  ///         into the domain separator; the typehash differs between
  ///         the v0.4.0 base wallet and the v0.5.0 extended wallet,
  ///         detected via `allowOnlyOwnerRequest()` on the contract.
  signMultiSigTxn: async function (
    contractOrAddress: any,
    sourceWallet: any,
    to: string,
    value: bigint,
    data: string,
    gas: number,
    nonce: bigint,
    validUntil: number = 0,
    operation: number = 0,
  ) {
    const contractAddress: string =
      typeof contractOrAddress === 'string' ? contractOrAddress : await contractOrAddress.getAddress()
    const contract =
      typeof contractOrAddress === 'string'
        ? (sourceWallet.provider && (await sourceWallet.provider.getNetwork()), null)
        : contractOrAddress
    const isExtended = contract && typeof (contract as any).allowOnlyOwnerRequest === 'function'
    const chainId = (await ethers.provider.getNetwork()).chainId
    if (isExtended) {
      return sourceWallet.signTypedData(
        {
          name: constants.CONTRACT_NAME,
          version: constants.CONTRACT_VERSION,
          chainId,
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
    return sourceWallet.signTypedData(
      {
        name: constants.CONTRACT_NAME,
        version: constants.CONTRACT_VERSION,
        chainId,
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
    const chainId = (await ethers.provider.getNetwork()).chainId
    const verifyingContract: string = await contract.getAddress()
    if (isExtended) {
      return owner.signTypedData(
        {
          name: constants.CONTRACT_NAME,
          version: constants.CONTRACT_VERSION,
          chainId,
          verifyingContract,
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
    return owner.signTypedData(
      {
        name: constants.CONTRACT_NAME,
        version: constants.CONTRACT_VERSION,
        chainId,
        verifyingContract,
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
  /// @notice Signs the extended wallet's single-signer allowance payload.
  ///         Uses the dedicated `AllowanceTransaction` typehash and the
  ///         wallet's `allowanceNonce()` domain — distinct from the
  ///         threshold `Transaction` typehash on purpose.
  signAllowanceTxn: async function (
    contract: any,
    sourceWallet: any,
    to: string,
    value: bigint,
    data: string,
    gas: number,
    nonce: bigint,
    validUntil: number = 0,
  ) {
    const chainId = (await ethers.provider.getNetwork()).chainId
    return sourceWallet.signTypedData(
      {
        name: constants.CONTRACT_NAME,
        version: constants.CONTRACT_VERSION,
        chainId,
        verifyingContract: await contract.getAddress(),
      },
      {
        AllowanceTransaction: [
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
  /// @notice Produces a raw 65-byte ECDSA signature over `digest` (no
  ///         EIP-712 envelope).
  signDigest: async function (signer: any, digest: string): Promise<string> {
    const sigObj = signer.signingKey.sign(digest)
    return ethers.hexlify(
      ethers.concat([
        ethers.zeroPadValue(sigObj.r, 32),
        ethers.zeroPadValue(sigObj.s, 32),
        ethers.toBeHex(sigObj.v, 1),
      ]),
    )
  },
}
