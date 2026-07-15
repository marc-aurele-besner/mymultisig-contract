// Hardhat companion for the v0.5.0 wallet. Mirrors the Foundry
// `MyMultiSigV2_5.t.sol` surface. The 4337 round-trip test lives in
// `MyMultiSigV2_5.eip4337.test.ts`; the CREATE2 parity test lives in
// `MyMultiSigV2_5.create2.test.ts`. This file is the smoke surface.
import { expect } from 'chai'
import { ethers, network } from 'hardhat'

import constants from '../constants'
import v2_5Constants from '../constants/v2_5'

const ENTRY_POINT = v2_5Constants.ENTRY_POINT_V07_ADDRESS

describe(`MyMultiSigV2_5 - smoke (${network.name})`, () => {
  async function deployV2_5(signers: Awaited<ReturnType<typeof ethers.getSigners>>, threshold = 2) {
    const owners = signers.slice(0, 2).map((s) => s.address)
    const V2_5 = await ethers.getContractFactory('MyMultiSigV2_5')
    return V2_5.deploy(constants.CONTRACT_NAME_V2_5, owners, threshold, ENTRY_POINT)
  }

  it('exposes version() = 0.5.0', async () => {
    const signers = await ethers.getSigners()
    const wallet = await deployV2_5(signers)
    expect(await wallet.version()).to.equal('0.5.0')
  })

  it('exposes the pinned EntryPoint', async () => {
    const signers = await ethers.getSigners()
    const wallet = await deployV2_5(signers)
    expect((await wallet.ENTRY_POINT()).toLowerCase()).to.equal(ENTRY_POINT)
  })

  it('rejects the disabled base 5-arg execTransaction', async () => {
    const signers = await ethers.getSigners()
    const wallet = await deployV2_5(signers)
    await expect(
      wallet['execTransaction(address,uint256,bytes,uint256,bytes)'](
        ethers.constants.AddressZero,
        0,
        '0x',
        50_000,
        '0x',
      ),
    ).to.be.revertedWithCustomError(wallet, 'V2_5RequiresOperationByte')
  })

  it('rejects the disabled base 6-arg execTransaction', async () => {
    const signers = await ethers.getSigners()
    const wallet = await deployV2_5(signers)
    await expect(
      wallet['execTransaction(address,uint256,bytes,uint256,uint256,bytes)'](
        ethers.constants.AddressZero,
        0,
        '0x',
        50_000,
        0, // validUntil
        '0x',
      ),
    ).to.be.revertedWithCustomError(wallet, 'V2_5RequiresOperationByte')
  })

  it('rejects operation > 1', async () => {
    const signers = await ethers.getSigners()
    const wallet = await deployV2_5(signers)
    await expect(
      wallet['execTransaction(address,uint256,bytes,uint256,uint8,bytes)'](
        ethers.constants.AddressZero,
        0,
        '0x',
        50_000,
        2, // invalid operation
        '0x',
      ),
    ).to.be.revertedWithCustomError(wallet, 'InvalidOperation')
  })

  it('rejects DELEGATECALL to non-self', async () => {
    const signers = await ethers.getSigners()
    const wallet = await deployV2_5(signers)
    await expect(
      wallet['execTransaction(address,uint256,bytes,uint256,uint8,bytes)'](
        ethers.constants.AddressZero, // not address(this)
        0,
        '0x',
        50_000,
        1, // DELEGATECALL
        '0x',
      ),
    ).to.be.revertedWithCustomError(wallet, 'InvalidOperation')
  })

  it('rejects constructor with zero entryPoint', async () => {
    const V2_5 = await ethers.getContractFactory('MyMultiSigV2_5')
    const [owner, second] = await ethers.getSigners()
    await expect(
      V2_5.deploy(
        constants.CONTRACT_NAME_V2_5,
        [owner.address, second.address],
        1,
        ethers.constants.AddressZero, // forbidden
      ),
    ).to.be.revertedWithCustomError(V2_5, 'InvalidOperation')
  })
})
