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

describe('MyMultiSig - Deployed From Factory', function () {
  before(async function () {
    ;[provider, owner01, owner02, owner03, user01, user02, user03] = await Helper.setupProviderAndAccount()
  })

  beforeEach(async function () {
    const owners: string[] = [owner01.address, owner02.address, owner03.address]
    ownerCount = owners.length
    deployment = await Helper.setupContract(
      Helper.CONTRACT_FACTORY_NAME,
      [owner01.address, owner02.address, owner03.address],
      2,
      true
    )
    const tx = await deployment.contract.createMultiSig(
      Helper.CONTRACT_NAME,
      [owner01.address, owner02.address, owner03.address],
      2
    )
    await tx.wait()
    const contractAddress = await deployment.contract.multiSig(0)

    const Contract = await ethers.getContractFactory(Helper.CONTRACT_NAME)
    contract = new ethers.Contract(contractAddress, Contract.interface, provider)
  })

  it('Contract Factory return correct contract name', async function () {
    expect(await deployment.contract.name()).to.be.equal(Helper.CONTRACT_FACTORY_NAME)
  })

  it('Contract Factory return correct contract version', async function () {
    expect(await deployment.contract.version()).to.be.equal(Helper.CONTRACT_FACTORY_VERSION)
  })

  it('Contract Factory return correct multisig count', async function () {
    expect(await deployment.contract.multiSigCount()).to.be.equal(1)
  })

  it('Contract Factory return correct multisig contract address', async function () {
    expect(await deployment.contract.multiSig(0)).to.be.equal(contract.address)
  })

  it('Contract Factory return correct creator count', async function () {
    expect(await deployment.contract.multiSigCreatorCount(owner01.address)).to.be.equal(1)
  })

  it('Contract Factory return correct multisig contract address when calling multiSigByCreator(creator, id)', async function () {
    expect(await deployment.contract.multiSigByCreator(owner01.address, 0)).to.be.equal(contract.address)
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
        Helper.ZERO,
        contract.interface.encodeFunctionData('addOwner(address)', [user01.address]),
        Helper.DEFAULT_GAS
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
        Helper.ZERO,
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
        Helper.ZERO,
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
        Helper.ZERO,
        contract.interface.encodeFunctionData('addOwner(address)', [user01.address]),
        Helper.DEFAULT_GAS
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
        Helper.ZERO,
        contract.interface.encodeFunctionData('addOwner(address)', [user01.address]),
        Helper.DEFAULT_GAS
      )
    ).to.be.false
  })

  it('Can add a new owner', async function () {
    await Helper.addOwner(contract, owner01, [owner01, owner02, owner03], user01.address, undefined, undefined, [
      'OwnerAdded',
    ])
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

  it('Cannot add a new owner with 3x the signature of owner01', async function () {
    await Helper.addOwner(
      contract,
      owner01,
      [owner01, owner01, owner01],
      user01.address,
      Helper.DEFAULT_GAS,
      Helper.errors.OWNER_ALREADY_SIGNED
    )
  })

  it('Can add a new owner and then use it to sign a new transaction replaceOwner', async function () {
    await Helper.addOwner(contract, owner01, [owner01, owner02, owner03], user01.address, undefined, undefined, [
      'OwnerAdded',
    ])
    await Helper.replaceOwner(
      contract,
      owner01,
      [user01, owner02, owner03],
      user02.address,
      owner01.address,
      undefined,
      undefined,
      ['OwnerRemoved', 'OwnerAdded']
    )
  })

  it('Can add a new owner and then use it to sign a new transaction changeThreshold', async function () {
    await Helper.addOwner(contract, owner01, [owner01, owner02, owner03], user01.address, undefined, undefined, [
      'OwnerAdded',
    ])
    await Helper.changeThreshold(contract, owner01, [user01, owner02, owner03], 3, undefined, undefined, [
      'ThresholdChanged',
    ])
  })

  it('Can add a new owner and then use it to sign a new transaction removeOwner', async function () {
    await Helper.addOwner(contract, owner01, [owner01, owner02, owner03], user01.address, undefined, undefined, [
      'OwnerAdded',
    ])
    await Helper.removeOwner(contract, owner01, [user01, owner02, owner03], owner01.address, undefined, undefined, [
      'OwnerRemoved',
    ])
  })

  it('Cannot remove all owners', async function () {
    await Helper.removeOwner(contract, owner01, [owner02, owner03], owner01.address, undefined, undefined, [
      'OwnerRemoved',
    ])
    await Helper.removeOwner(
      contract,
      owner02,
      [owner02, owner03],
      owner03.address,
      undefined,
      Helper.errors.CANNOT_REMOVE_OWNERS_BELOW_THRESHOLD,
      ['TransactionFailed']
    )
    await Helper.removeOwner(
      contract,
      owner03,
      [owner02, owner03],
      owner02.address,
      undefined,
      Helper.errors.CANNOT_REMOVE_OWNERS_BELOW_THRESHOLD,
      ['TransactionFailed']
    )
  })

  it('Execute transaction without data but 1 ETH in value', async function () {
    await Helper.sendRawTxn(
      {
        to: contract.address,
        value: ethers.utils.parseEther('1'),
        data: '',
      },
      owner01,
      ethers,
      provider
    )
    await Helper.execTransaction(
      contract,
      owner01,
      [owner01, owner02, owner03],
      owner01.address,
      ethers.utils.parseEther('1'),
      '0x',
      Helper.DEFAULT_GAS
    )
  })

  it('Execute transaction without data but 2x 1 ETH in value', async function () {
    await Helper.sendRawTxn(
      {
        to: contract.address,
        value: ethers.utils.parseEther('2'),
        data: '',
      },
      owner01,
      ethers,
      provider
    )
    await Helper.execTransaction(
      contract,
      owner01,
      [owner01, owner02, owner03],
      owner01.address,
      ethers.utils.parseEther('1'),
      '0x',
      Helper.DEFAULT_GAS
    )
    await Helper.execTransaction(
      contract,
      owner02,
      [owner01, owner02, owner03],
      owner01.address,
      ethers.utils.parseEther('1'),
      '0x',
      Helper.DEFAULT_GAS
    )
  })

  it('Can mint token from MockERC20 contract', async function () {
    const MockERC20 = await ethers.getContractFactory('MockERC20')
    const mockERC20 = await MockERC20.deploy()
    await mockERC20.deployed()
    const data = MockERC20.interface.encodeFunctionData('mint(address,uint256)', [contract.address, 10])
    await Helper.execTransaction(
      contract,
      owner01,
      [owner01, owner02, owner03],
      mockERC20.address,
      Helper.ZERO,
      data,
      Helper.DEFAULT_GAS * 2
    )
    expect(await mockERC20.balanceOf(contract.address)).to.be.equal(10)
  })

  it('Can mint token from MockERC20 contract, then transfer them to owner01', async function () {
    const MockERC20 = await ethers.getContractFactory('MockERC20')
    const mockERC20 = await MockERC20.deploy()
    await mockERC20.deployed()
    const data = MockERC20.interface.encodeFunctionData('mint(address,uint256)', [contract.address, 10])
    await Helper.execTransaction(
      contract,
      owner01,
      [owner01, owner02, owner03],
      mockERC20.address,
      Helper.ZERO,
      data,
      Helper.DEFAULT_GAS * 2
    )
    expect(await mockERC20.balanceOf(contract.address)).to.be.equal(10)
    const data2 = MockERC20.interface.encodeFunctionData('transfer(address,uint256)', [owner01.address, 10])
    await Helper.execTransaction(
      contract,
      owner01,
      [owner01, owner02, owner03],
      mockERC20.address,
      Helper.ZERO,
      data2,
      Helper.DEFAULT_GAS * 2
    )
    expect(await mockERC20.balanceOf(contract.address)).to.be.equal(0)
    expect(await mockERC20.balanceOf(owner01.address)).to.be.equal(10)
  })

  it('Emit TransactionFailed when valid signature try to execute a invalid call', async function () {
    const MockERC20 = await ethers.getContractFactory('MockERC20')
    const data = MockERC20.interface.encodeFunctionData('transferFrom(address,address,uint256)', [
      contract.address,
      owner01.address,
      10,
    ])
    await Helper.execTransaction(
      contract,
      owner01,
      [owner01, owner02, owner03],
      contract.address,
      Helper.ZERO,
      data,
      Helper.DEFAULT_GAS,
      undefined,
      ['TransactionFailed']
    )
  })

  it('Cannot reuse a signature', async function () {
    const data = contract.interface.encodeFunctionData('addOwner(address)', [user02.address])
    const signatures = await Helper.prepareSignatures(contract, [owner01, owner02], contract.address, Helper.ZERO, data)
    await Helper.execTransaction(
      contract,
      owner01,
      [owner01, owner02],
      contract.address,
      Helper.ZERO,
      data,
      Helper.DEFAULT_GAS,
      undefined,
      ['OwnerAdded'],
      signatures
    )
    await Helper.execTransaction(
      contract,
      owner01,
      [owner01, owner02],
      contract.address,
      Helper.ZERO,
      data,
      Helper.DEFAULT_GAS,
      Helper.errors.INVALID_OWNER,
      undefined,
      signatures
    )
  })

  it('Can execute a multiRequest', async function () {
    await Helper.multiRequest(
      contract,
      owner01,
      [owner01, owner02, owner03],
      [contract.address, contract.address, contract.address],
      [Helper.ZERO, Helper.ZERO, Helper.ZERO],
      [
        contract.interface.encodeFunctionData('addOwner(address)', [user01.address]),
        contract.interface.encodeFunctionData('addOwner(address)', [user02.address]),
        contract.interface.encodeFunctionData('addOwner(address)', [user03.address]),
      ],
      [Helper.DEFAULT_GAS, Helper.DEFAULT_GAS, Helper.DEFAULT_GAS],
      undefined,
      ['OwnerAdded', 'OwnerAdded']
    )
    expect(await contract.isOwner(user01.address)).to.be.true
    expect(await contract.isOwner(user02.address)).to.be.true
    expect(await contract.isOwner(user03.address)).to.be.true
  })

  it('Can mint token from MockERC20 contract, then transfer them to owner01 in a multiRequest', async function () {
    const MockERC20 = await ethers.getContractFactory('MockERC20')
    const mockERC20 = await MockERC20.deploy()
    await mockERC20.deployed()
    await Helper.multiRequest(
      contract,
      owner01,
      [owner01, owner02, owner03],
      [mockERC20.address, mockERC20.address],
      [Helper.ZERO, Helper.ZERO],
      [
        MockERC20.interface.encodeFunctionData('mint(address,uint256)', [contract.address, 10]),
        MockERC20.interface.encodeFunctionData('transfer(address,uint256)', [owner01.address, 10]),
      ],
      [Helper.DEFAULT_GAS * 2, Helper.DEFAULT_GAS * 2]
    )
    expect(await mockERC20.balanceOf(contract.address)).to.be.equal(0)
    expect(await mockERC20.balanceOf(owner01.address)).to.be.equal(10)
  })

  it('Can mint token from MockERC20 contract, then transfer them to owner01, owner02 ans owner03 in a multiRequest', async function () {
    const MockERC20 = await ethers.getContractFactory('MockERC20')
    const mockERC20 = await MockERC20.deploy()
    await mockERC20.deployed()
    await Helper.multiRequest(
      contract,
      owner01,
      [owner01, owner02, owner03],
      [mockERC20.address, mockERC20.address, mockERC20.address, mockERC20.address],
      [Helper.ZERO, Helper.ZERO, Helper.ZERO, Helper.ZERO],
      [
        MockERC20.interface.encodeFunctionData('mint(address,uint256)', [contract.address, 150]),
        MockERC20.interface.encodeFunctionData('transfer(address,uint256)', [owner01.address, 50]),
        MockERC20.interface.encodeFunctionData('transfer(address,uint256)', [owner02.address, 50]),
        MockERC20.interface.encodeFunctionData('transfer(address,uint256)', [owner03.address, 50]),
      ],
      [Helper.DEFAULT_GAS * 2, Helper.DEFAULT_GAS * 2, Helper.DEFAULT_GAS * 2, Helper.DEFAULT_GAS * 2]
    )
    expect(await mockERC20.balanceOf(contract.address)).to.be.equal(0)
    expect(await mockERC20.balanceOf(owner01.address)).to.be.equal(50)
    expect(await mockERC20.balanceOf(owner02.address)).to.be.equal(50)
    expect(await mockERC20.balanceOf(owner03.address)).to.be.equal(50)
  })
})
