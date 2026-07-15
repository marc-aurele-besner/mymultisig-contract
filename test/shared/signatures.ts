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
  ) {
    // Accept either a string address or an ethers Contract instance.
    const contractAddress: string =
      typeof contractOrAddress === 'string' ? contractOrAddress : contractOrAddress.address
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
  /// @notice Signs a wallet's EIP-712 transaction hash with each owner. The
  ///         returned 65-byte ECDSA blob can be ABI-encoded as the
  ///         `(address,bytes)[]` payload to `isValidSignature(bytes32,bytes)`.
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
  /// @notice Produces a raw 65-byte ECDSA signature over `digest` (no
  ///         EIP-712 envelope) for EIP-1271 nested-wallet tests where the
  ///         inner wallet calls `ecrecover(digest, ...)` directly.
  signDigest: async function (signer: any, digest: string): Promise<string> {
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
