import { expect } from 'chai'
import { ethers } from 'hardhat'

import Helper from './shared'

let provider: any
let owner01: any
let owner02: any
let owner03: any
let ownerCount: number
let user01: any
let user02: any
let user03: any
let deployment: any
let contract: any

describe('MyMultiSig', function () {
  before(async function () {
    ;[provider, owner01, owner02, owner03, user01, user02, user03] = await Helper.setupProviderAndAccount()
  })

  beforeEach(async function () {
    const owners: string[] = [owner01.address, owner02.address, owner03.address]
    ownerCount = owners.length
    deployment = await Helper.setupContract(
      Helper.CONTRACT_NAME,
      [owner01.address, owner02.address, owner03.address],
      2
    )
    contract = deployment.contract
  })

  it('Contract return correct contract name', async function () {
    expect(await contract.name()).to.be.equal(Helper.CONTRACT_NAME)
  })

  it('Contract return correct contract version', async function () {
    expect(await contract.version()).to.be.equal(Helper.CONTRACT_VERSION)
  })

  it('Contract return correct threshold', async function () {
    expect(await contract.threshold()).to.be.equal(Helper.DEFAULT_THRESHOLD)
  })

  it('Contract return correct ownerCount', async function () {
    expect(await contract.ownerCount()).to.be.equal(ownerCount)
  })

  it('Contract return correct nonce', async function () {
    expect(await contract.nonce()).to.be.equal(0)
  })

  it('Contract return true when calling isOwner for the original owners addresses', async function () {
    expect(await contract.isOwner(owner01.address)).to.be.true
    expect(await contract.isOwner(owner02.address)).to.be.true
    expect(await contract.isOwner(owner03.address)).to.be.true
  })

  it('Contract return false when calling isOwner for non owners addresses', async function () {
    expect(await contract.isOwner(user01.address)).to.be.false
    expect(await contract.isOwner(user02.address)).to.be.false
    expect(await contract.isOwner(user03.address)).to.be.false
  })

  it('Contract return false if owners (1/2) sign a transaction and call isValidSignature', async function () {
    expect(
      await Helper.isValidSignature(
        contract,
        owner01,
        [owner01],
        contract.address,
        0,
        contract.interface.encodeFunctionData('addOwner(address)', [user01.address]),
        Helper.DEFAULT_GAS,
        Helper.errors.THRESHOLD_NOT_ACHIEVED
      )
    ).to.be.false
  })

  it('Contract return true if owners (2/2) sign a transaction and call isValidSignature', async function () {
    expect(
      await Helper.isValidSignature(
        contract,
        owner01,
        [owner01, owner02],
        contract.address,
        0,
        contract.interface.encodeFunctionData('addOwner(address)', [user01.address]),
        Helper.DEFAULT_GAS
      )
    ).to.be.true
  })

  it('Contract return true if owners (3/2) sign a transaction and call isValidSignature', async function () {
    expect(
      await Helper.isValidSignature(
        contract,
        owner01,
        [owner01, owner02, owner03],
        contract.address,
        0,
        contract.interface.encodeFunctionData('addOwner(address)', [user01.address]),
        Helper.DEFAULT_GAS
      )
    ).to.be.true
  })

  it('Contract return false if non-owners sign a transaction and call isValidSignature', async function () {
    expect(
      await Helper.isValidSignature(
        contract,
        user01,
        [user01, user02, user03],
        contract.address,
        0,
        contract.interface.encodeFunctionData('addOwner(address)', [user01.address]),
        Helper.DEFAULT_GAS,
        Helper.errors.INVALID_OWNER
      )
    ).to.be.false
  })

  it('Contract return false if non-owners and owners sign a transaction and call isValidSignature', async function () {
    expect(
      await Helper.isValidSignature(
        contract,
        user01,
        [owner01, user02, owner03],
        contract.address,
        0,
        contract.interface.encodeFunctionData('addOwner(address)', [user01.address]),
        Helper.DEFAULT_GAS,
        Helper.errors.INVALID_OWNER
      )
    ).to.be.false
  })

  it('Can add a new owner', async function () {
    await Helper.addOwner(contract, owner01, [owner01, owner02, owner03], user01.address)
  })

  it('Cannot add a new owner with just 10k gas', async function () {
    await Helper.addOwner(
      contract,
      owner01,
      [owner01, owner02, owner03],
      user01.address,
      10000,
      Helper.errors.NOT_ENOUGH_GAS
    )
  })

  it('Can add a new owner and then use it to sign a new transaction replaceOwner', async function () {
    await Helper.addOwner(contract, owner01, [owner01, owner02, owner03], user01.address)
    await Helper.replaceOwner(contract, owner01, [user01, owner02, owner03], user02.address, owner01.address)
  })

  it('Can add a new owner and then use it to sign a new transaction changeThreshold', async function () {
    await Helper.addOwner(contract, owner01, [owner01, owner02, owner03], user01.address)
    await Helper.changeThreshold(contract, owner01, [user01, owner02, owner03], 3)
  })

  it('Can add a new owner and then use it to sign a new transaction removeOwner', async function () {
    await Helper.addOwner(contract, owner01, [owner01, owner02, owner03], user01.address)
    await Helper.removeOwner(contract, owner01, [user01, owner02, owner03], owner01.address)
  })

  it('Cannot remove all owners', async function () {
    await Helper.removeOwner(contract, owner01, [owner01, owner02, owner03], owner01.address)
    await Helper.removeOwner(
      contract,
      owner02,
      [owner02, owner03],
      owner02.address,
      undefined,
      Helper.errors.INVALID_SIGNATURES
    )
    await Helper.removeOwner(contract, owner03, [owner03], owner03.address, undefined, Helper.errors.INVALID_SIGNATURES)
  })
})
