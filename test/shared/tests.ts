import { expect } from 'chai'
import { ethers } from 'hardhat'
import { time } from '@nomicfoundation/hardhat-network-helpers'

import Helper from './index'

export enum DeploymentType {
  SimpleMultiSig,
  WithFactory,
  WithChugSplash,
}

export async function MyMultiSigStandardTests(deploymentType = DeploymentType.SimpleMultiSig) {
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

  describe('MyMultiSig - Standard Tests', function () {
    before(async function () {
      ;[provider, owner01, owner02, owner03, user01, user02, user03] = await Helper.setupProviderAndAccount()
    })

    beforeEach(async function () {
      const owners: string[] = [owner01.address, owner02.address, owner03.address]
      ownerCount = owners.length
      switch (deploymentType) {
        case DeploymentType.SimpleMultiSig: {
          deployment = await Helper.setupContract(
            Helper.CONTRACT_NAME,
            [owner01.address, owner02.address, owner03.address],
            2
          )
          contract = deployment.contract
          break
        }
        case DeploymentType.WithFactory: {
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
          break
        }
        case DeploymentType.WithChugSplash: {
          deployment = await Helper.setupContractWithChugSplash(
            Helper.CONTRACT_FACTORY_NAME + 'WithChugSplash',
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
          break
        }
        default:
          throw new Error('Invalid deployment type')
          break
      }
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
      const data = MockERC20.interface.encodeFunctionData('mint(address,uint256)', [
        contract.address,
        10,
      ]) as `0x${string}`
      await Helper.execTransaction(
        contract,
        owner01,
        [owner01, owner02, owner03],
        mockERC20.address as `0x${string}`,
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
      const data = MockERC20.interface.encodeFunctionData('mint(address,uint256)', [
        contract.address,
        10,
      ]) as `0x${string}`
      await Helper.execTransaction(
        contract,
        owner01,
        [owner01, owner02, owner03],
        mockERC20.address as `0x${string}`,
        Helper.ZERO,
        data,
        Helper.DEFAULT_GAS * 2
      )
      expect(await mockERC20.balanceOf(contract.address)).to.be.equal(10)
      const data2 = MockERC20.interface.encodeFunctionData('transfer(address,uint256)', [
        owner01.address,
        10,
      ]) as `0x${string}`
      await Helper.execTransaction(
        contract,
        owner01,
        [owner01, owner02, owner03],
        mockERC20.address as `0x${string}`,
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
      ]) as `0x${string}`
      await Helper.execTransaction(
        contract,
        owner01,
        [owner01, owner02, owner03],
        contract.address,
        Helper.ZERO,
        data as `0x${string}`,
        Helper.DEFAULT_GAS,
        undefined,
        ['TransactionFailed']
      )
    })

    it('Can mint token from MockERC721 contract', async function () {
      const MockERC721 = await ethers.getContractFactory('MockERC721')
      const mockERC721 = await MockERC721.deploy()
      await mockERC721.deployed()
      const data = MockERC721.interface.encodeFunctionData('mint(address,uint256)', [
        contract.address,
        10,
      ]) as `0x${string}`
      await Helper.execTransaction(
        contract,
        owner01,
        [owner01, owner02, owner03],
        mockERC721.address as `0x${string}`,
        Helper.ZERO,
        data,
        Helper.DEFAULT_GAS * 2
      )
      expect(await mockERC721.balanceOf(contract.address)).to.be.equal(1)
      expect(await mockERC721.ownerOf(10)).to.be.equal(contract.address)
    })

    it('Can mint token from MockERC721 contract, then transfer them to owner01', async function () {
      const MockERC721 = await ethers.getContractFactory('MockERC721')
      const mockERC721 = await MockERC721.deploy()
      await mockERC721.deployed()
      const data = MockERC721.interface.encodeFunctionData('mint(address,uint256)', [
        contract.address,
        10,
      ]) as `0x${string}`
      await Helper.execTransaction(
        contract,
        owner01,
        [owner01, owner02, owner03],
        mockERC721.address as `0x${string}`,
        Helper.ZERO,
        data,
        Helper.DEFAULT_GAS * 2
      )
      expect(await mockERC721.balanceOf(contract.address)).to.be.equal(1)
      expect(await mockERC721.ownerOf(10)).to.be.equal(contract.address)
      const data2 = mockERC721.interface.encodeFunctionData('transferFrom(address,address,uint256)', [
        contract.address,
        owner01.address,
        10,
      ]) as `0x${string}`
      await Helper.execTransaction(
        contract,
        owner01,
        [owner01, owner02, owner03],
        mockERC721.address as `0x${string}`,
        Helper.ZERO,
        data2,
        Helper.DEFAULT_GAS * 2
      )
      expect(await mockERC721.balanceOf(contract.address)).to.be.equal(0)
      expect(await mockERC721.balanceOf(owner01.address)).to.be.equal(1)
      expect(await mockERC721.ownerOf(10)).to.be.equal(owner01.address)
    })

    it('Can mint token from MockERC1155 contract', async function () {
      const MockERC1155 = await ethers.getContractFactory('MockERC1155')
      const mockERC1155 = await MockERC1155.deploy()
      await mockERC1155.deployed()
      const data = MockERC1155.interface.encodeFunctionData('mint(address,uint256,uint256)', [
        contract.address,
        10,
        5,
      ]) as `0x${string}`
      await Helper.execTransaction(
        contract,
        owner01,
        [owner01, owner02, owner03],
        mockERC1155.address as `0x${string}`,
        Helper.ZERO,
        data,
        Helper.DEFAULT_GAS * 2
      )
      expect(await mockERC1155.balanceOf(contract.address, 10)).to.be.equal(5)
    })

    it('Can mint token from MockERC1155 contract, then transfer them to owner01', async function () {
      const MockERC1155 = await ethers.getContractFactory('MockERC1155')
      const mockERC1155 = await MockERC1155.deploy()
      await mockERC1155.deployed()
      const data = MockERC1155.interface.encodeFunctionData('mint(address,uint256,uint256)', [
        contract.address,
        10,
        5,
      ]) as `0x${string}`
      await Helper.execTransaction(
        contract,
        owner01,
        [owner01, owner02, owner03],
        mockERC1155.address as `0x${string}`,
        Helper.ZERO,
        data,
        Helper.DEFAULT_GAS * 2
      )
      expect(await mockERC1155.balanceOf(contract.address, 10)).to.be.equal(5)
      const data2 = mockERC1155.interface.encodeFunctionData(
        'safeTransferFrom(address,address,uint256,uint256,bytes)',
        [contract.address, owner01.address, 10, 2, '0x']
      ) as `0x${string}`
      await Helper.execTransaction(
        contract,
        owner01,
        [owner01, owner02, owner03],
        mockERC1155.address as `0x${string}`,
        Helper.ZERO,
        data2,
        Helper.DEFAULT_GAS * 2
      )
      expect(await mockERC1155.balanceOf(contract.address, 10)).to.be.equal(3)
      expect(await mockERC1155.balanceOf(owner01.address, 10)).to.be.equal(2)
    })

    it('Cannot reuse a signature', async function () {
      const data = contract.interface.encodeFunctionData('addOwner(address)', [user02.address]) as `0x${string}`
      const signatures = await Helper.prepareSignatures(
        contract,
        [owner01, owner02],
        contract.address,
        Helper.ZERO,
        data
      )
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
        [mockERC20.address, mockERC20.address] as [`0x${string}`, `0x${string}`],
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
        [mockERC20.address, mockERC20.address, mockERC20.address, mockERC20.address] as [
          `0x${string}`,
          `0x${string}`,
          `0x${string}`,
          `0x${string}`
        ],
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
}

export async function MyMultiSigExtendedTests(deploymentType = DeploymentType.SimpleMultiSig) {
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

  describe('MyMultiSig - Extended Tests', function () {
    before(async function () {
      ;[provider, owner01, owner02, owner03, user01, user02, user03] = await Helper.setupProviderAndAccount()
    })

    beforeEach(async function () {
      const owners: string[] = [owner01.address, owner02.address, owner03.address]
      ownerCount = owners.length
      switch (deploymentType) {
        case DeploymentType.SimpleMultiSig: {
          deployment = await Helper.setupContract(
            Helper.CONTRACT_NAME,
            [owner01.address, owner02.address, owner03.address],
            2,
            false,
            true
          )
          contract = deployment.contract
          break
        }
        case DeploymentType.WithFactory: {
          deployment = await Helper.setupContract(
            Helper.CONTRACT_FACTORY_NAME,
            [owner01.address, owner02.address, owner03.address],
            2,
            true
          )
          const tx = await deployment.contract.createMyMultiSigExtended(
            Helper.CONTRACT_NAME,
            [owner01.address, owner02.address, owner03.address],
            2,
            Helper.DEFAULT_ALLOW_ONLY_OWNER
          )
          await tx.wait()
          const contractAddress = await deployment.contract.multiSig(0)

          const Contract = await ethers.getContractFactory(Helper.CONTRACT_NAME_EXTENDED)
          contract = new ethers.Contract(contractAddress, Contract.interface, provider)
          break
        }
        case DeploymentType.WithChugSplash: {
          deployment = await Helper.setupContractWithChugSplash(
            Helper.CONTRACT_FACTORY_NAME + 'WithChugSplash',
            [owner01.address, owner02.address, owner03.address],
            2,
            true
          )
          const tx = await deployment.contract.createMyMultiSigExtended(
            Helper.CONTRACT_NAME,
            [owner01.address, owner02.address, owner03.address],
            2,
            Helper.DEFAULT_ALLOW_ONLY_OWNER
          )
          await tx.wait()
          const contractAddress = await deployment.contract.multiSig(0)

          const Contract = await ethers.getContractFactory(Helper.CONTRACT_NAME_EXTENDED)
          contract = new ethers.Contract(contractAddress, Contract.interface, provider)
          break
        }
        default:
          throw new Error('Invalid deployment type')
          break
      }
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

    it('Contract return correct allowOnlyOwnerRequest', async function () {
      expect(await contract.allowOnlyOwnerRequest()).to.be.equal(Helper.DEFAULT_ALLOW_ONLY_OWNER)
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

    it('Can set the contract so only owners can send request', async function () {
      await Helper.setOnlyOwnerRequest(contract, owner01, [owner01, owner02, owner03], true)
    })

    it('Can set the contract so anyone can send request', async function () {
      await Helper.setOnlyOwnerRequest(contract, owner01, [owner01, owner02, owner03], false)
    })

    it('Can set an amount of time (1 day) after which the other owners can transfer the ownership', async function () {
      await Helper.setTransferInactiveOwnershipAfter(
        contract,
        owner01,
        [owner01, owner02, owner03],
        ethers.BigNumber.from(60).mul(60).mul(24),
        Helper.DEFAULT_GAS,
        undefined,
        ['TransactionFailed']
      )
    })

    it('Can set an amount of time (7 days) after which the other owners can transfer the ownership', async function () {
      await Helper.setTransferInactiveOwnershipAfter(
        contract,
        owner01,
        [owner01, owner02, owner03],
        ethers.BigNumber.from(60).mul(60).mul(24).mul(7)
      )
    })

    it('Can set an amount of time (31 days) after which the other owners can transfer the ownership', async function () {
      await Helper.setTransferInactiveOwnershipAfter(
        contract,
        owner01,
        [owner01, owner02, owner03],
        ethers.BigNumber.from(60).mul(60).mul(24).mul(31)
      )
    })

    it('Can set owner settings (14 days -> user2)', async function () {
      await Helper.setOwnerSettings(
        contract,
        owner01,
        ethers.BigNumber.from(60).mul(60).mul(24).mul(14),
        user02.address
      )
    })

    it('Can set owner settings (31 days -> user03)', async function () {
      await Helper.setOwnerSettings(
        contract,
        owner01,
        ethers.BigNumber.from(60).mul(60).mul(24).mul(31),
        user03.address
      )
    })

    it('Can set owner settings (5 days -> user03) (should fail)', async function () {
      await Helper.setTransferInactiveOwnershipAfter(
        contract,
        owner01,
        [owner01, owner02, owner03],
        ethers.BigNumber.from(60).mul(60).mul(24).mul(7)
      )
      await Helper.setOwnerSettings(
        contract,
        owner01,
        ethers.BigNumber.from(60).mul(60).mul(24).mul(5),
        user03.address,
        undefined,
        Helper.errors.OWNER_SETTINGS_MUST_BE_GREATER_THAN_MINIMUM
      )
    })

    it('Can set owner settings (31 days -> owner02) (should fail)', async function () {
      await Helper.setOwnerSettings(
        contract,
        owner01,
        ethers.BigNumber.from(60).mul(60).mul(24).mul(31),
        owner02.address,
        undefined,
        Helper.errors.OWNER_SETTINGS_DELEGATEE_MUST_NOT_BE_OWNER
      )
    })

    it('Can set owner settings (5 days -> owner03) (should fail)', async function () {
      await Helper.setTransferInactiveOwnershipAfter(
        contract,
        owner01,
        [owner01, owner02, owner03],
        ethers.BigNumber.from(60).mul(60).mul(24).mul(7)
      )
      await Helper.setOwnerSettings(
        contract,
        owner01,
        ethers.BigNumber.from(60).mul(60).mul(24).mul(5),
        owner03.address,
        undefined,
        Helper.errors.OWNER_SETTINGS_MUST_BE_GREATER_THAN_MINIMUM
      )
    })

    it('Can set owner settings then transfer ownership', async function () {
      await Helper.setTransferInactiveOwnershipAfter(
        contract,
        owner01,
        [owner01, owner02, owner03],
        ethers.BigNumber.from(60).mul(60).mul(24).mul(7)
      )
      await Helper.setOwnerSettings(contract, owner01, ethers.BigNumber.from(60).mul(60).mul(24).mul(8), user03.address)
      await time.increase(60 * 60 * 24 * 9)
      await Helper.takeOverOwnership(contract, user03, owner01.address)
    })

    it('Can set owner settings then transfer ownership too early (should fail)', async function () {
      await Helper.setTransferInactiveOwnershipAfter(
        contract,
        owner01,
        [owner01, owner02, owner03],
        ethers.BigNumber.from(60).mul(60).mul(24).mul(7)
      )
      await Helper.setOwnerSettings(contract, owner01, ethers.BigNumber.from(60).mul(60).mul(24).mul(8), user03.address)
      await time.increase(60 * 60 * 24 * 5)
      await Helper.takeOverOwnership(contract, user03, owner01.address, Helper.errors.OWNER_STILL_ACTIVE)
    })

    it('Can set owner settings then transfer ownership (not delegatee) (should fail)', async function () {
      await Helper.setTransferInactiveOwnershipAfter(
        contract,
        owner01,
        [owner01, owner02, owner03],
        ethers.BigNumber.from(60).mul(60).mul(24).mul(7)
      )
      await Helper.setOwnerSettings(contract, owner01, ethers.BigNumber.from(60).mul(60).mul(24).mul(8), user03.address)
      await time.increase(60 * 60 * 24 * 9)
      await Helper.takeOverOwnership(contract, user02, owner01.address, Helper.errors.SENDER_NOT_DELEGATEE)
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
      const data = MockERC20.interface.encodeFunctionData('mint(address,uint256)', [
        contract.address,
        10,
      ]) as `0x${string}`
      await Helper.execTransaction(
        contract,
        owner01,
        [owner01, owner02, owner03],
        mockERC20.address as `0x${string}`,
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
      const data = MockERC20.interface.encodeFunctionData('mint(address,uint256)', [
        contract.address,
        10,
      ]) as `0x${string}`
      await Helper.execTransaction(
        contract,
        owner01,
        [owner01, owner02, owner03],
        mockERC20.address as `0x${string}`,
        Helper.ZERO,
        data,
        Helper.DEFAULT_GAS * 2
      )
      expect(await mockERC20.balanceOf(contract.address)).to.be.equal(10)
      const data2 = MockERC20.interface.encodeFunctionData('transfer(address,uint256)', [
        owner01.address,
        10,
      ]) as `0x${string}`
      await Helper.execTransaction(
        contract,
        owner01,
        [owner01, owner02, owner03],
        mockERC20.address as `0x${string}`,
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
        data as `0x${string}`,
        Helper.DEFAULT_GAS,
        undefined,
        ['TransactionFailed']
      )
    })

    it('Cannot reuse a signature', async function () {
      const data = contract.interface.encodeFunctionData('addOwner(address)', [user02.address])
      const signatures = await Helper.prepareSignatures(
        contract,
        [owner01, owner02],
        contract.address,
        Helper.ZERO,
        data
      )
      await Helper.execTransaction(
        contract,
        owner01,
        [owner01, owner02],
        contract.address,
        Helper.ZERO,
        data as `0x${string}`,
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
        data as `0x${string}`,
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
        [contract.address, contract.address, contract.address] as [`0x${string}`, `0x${string}`, `0x${string}`],
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
        [mockERC20.address, mockERC20.address] as [`0x${string}`, `0x${string}`],
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
        [mockERC20.address, mockERC20.address, mockERC20.address, mockERC20.address] as [
          `0x${string}`,
          `0x${string}`,
          `0x${string}`,
          `0x${string}`
        ],
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
}
