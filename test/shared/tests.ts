import { expect } from 'chai'
import { ethers } from 'hardhat'
import { time } from '@nomicfoundation/hardhat-network-helpers'

import Helper from './index'

export enum DeploymentType {
  SimpleMultiSig,
  WithFactory,
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
            2,
          )
          contract = deployment.contract
          break
        }
        case DeploymentType.WithFactory: {
          deployment = await Helper.setupContract(
            Helper.CONTRACT_FACTORY_NAME,
            [owner01.address, owner02.address, owner03.address],
            2,
            true,
          )
          const tx = await deployment.contract.createMultiSig(
            Helper.CONTRACT_NAME,
            [owner01.address, owner02.address, owner03.address],
            2,
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
          Helper.DEFAULT_GAS,
        ),
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
          Helper.DEFAULT_GAS,
        ),
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
          Helper.DEFAULT_GAS,
        ),
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
          Helper.DEFAULT_GAS,
        ),
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
          Helper.DEFAULT_GAS,
        ),
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
        Helper.errors.NOT_ENOUGH_GAS,
      )
    })

    it('Cannot add a new owner with 3x the signature of owner01', async function () {
      await Helper.addOwner(
        contract,
        owner01,
        [owner01, owner01, owner01],
        user01.address,
        Helper.DEFAULT_GAS,
        Helper.errors.OWNER_ALREADY_SIGNED,
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
        ['OwnerRemoved', 'OwnerAdded'],
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
        ['TxFailure'],
      )
      await Helper.removeOwner(
        contract,
        owner03,
        [owner02, owner03],
        owner02.address,
        undefined,
        Helper.errors.CANNOT_REMOVE_OWNERS_BELOW_THRESHOLD,
        ['TxFailure'],
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
        provider,
      )
      await Helper.execTransaction(
        contract,
        owner01,
        [owner01, owner02, owner03],
        owner01.address,
        ethers.utils.parseEther('1'),
        '0x',
        Helper.DEFAULT_GAS,
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
        provider,
      )
      await Helper.execTransaction(
        contract,
        owner01,
        [owner01, owner02, owner03],
        owner01.address,
        ethers.utils.parseEther('1'),
        '0x',
        Helper.DEFAULT_GAS,
      )
      await Helper.execTransaction(
        contract,
        owner02,
        [owner01, owner02, owner03],
        owner01.address,
        ethers.utils.parseEther('1'),
        '0x',
        Helper.DEFAULT_GAS,
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
        Helper.DEFAULT_GAS * 2,
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
        Helper.DEFAULT_GAS * 2,
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
        Helper.DEFAULT_GAS * 2,
      )
      expect(await mockERC20.balanceOf(contract.address)).to.be.equal(0)
      expect(await mockERC20.balanceOf(owner01.address)).to.be.equal(10)
    })

    it('Emit TxFailure when valid signature try to execute a invalid call', async function () {
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
        ['TxFailure'],
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
        Helper.DEFAULT_GAS * 2,
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
        Helper.DEFAULT_GAS * 2,
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
        Helper.DEFAULT_GAS * 2,
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
        Helper.DEFAULT_GAS * 2,
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
        Helper.DEFAULT_GAS * 2,
      )
      expect(await mockERC1155.balanceOf(contract.address, 10)).to.be.equal(5)
      const data2 = mockERC1155.interface.encodeFunctionData(
        'safeTransferFrom(address,address,uint256,uint256,bytes)',
        [contract.address, owner01.address, 10, 2, '0x'],
      ) as `0x${string}`
      await Helper.execTransaction(
        contract,
        owner01,
        [owner01, owner02, owner03],
        mockERC1155.address as `0x${string}`,
        Helper.ZERO,
        data2,
        Helper.DEFAULT_GAS * 2,
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
        data,
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
        signatures,
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
        signatures,
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
        ['OwnerAdded', 'OwnerAdded'],
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
        [Helper.DEFAULT_GAS * 2, Helper.DEFAULT_GAS * 2],
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
          `0x${string}`,
        ],
        [Helper.ZERO, Helper.ZERO, Helper.ZERO, Helper.ZERO],
        [
          MockERC20.interface.encodeFunctionData('mint(address,uint256)', [contract.address, 150]),
          MockERC20.interface.encodeFunctionData('transfer(address,uint256)', [owner01.address, 50]),
          MockERC20.interface.encodeFunctionData('transfer(address,uint256)', [owner02.address, 50]),
          MockERC20.interface.encodeFunctionData('transfer(address,uint256)', [owner03.address, 50]),
        ],
        [Helper.DEFAULT_GAS * 2, Helper.DEFAULT_GAS * 2, Helper.DEFAULT_GAS * 2, Helper.DEFAULT_GAS * 2],
      )
      expect(await mockERC20.balanceOf(contract.address)).to.be.equal(0)
      expect(await mockERC20.balanceOf(owner01.address)).to.be.equal(50)
      expect(await mockERC20.balanceOf(owner02.address)).to.be.equal(50)
      expect(await mockERC20.balanceOf(owner03.address)).to.be.equal(50)
    })

    it('multiRequest emits MultiRequestExecuted with per-call success and return data', async function () {
      const MockERC20 = await ethers.getContractFactory('MockERC20')
      const mockERC20 = await MockERC20.deploy()
      await mockERC20.deployed()
      const receipt = await Helper.multiRequest(
        contract,
        owner01,
        [owner01, owner02, owner03],
        [mockERC20.address, mockERC20.address, mockERC20.address],
        [Helper.ZERO, Helper.ZERO, Helper.ZERO],
        [
          MockERC20.interface.encodeFunctionData('mint(address,uint256)', [contract.address, 75]),
          MockERC20.interface.encodeFunctionData('transfer(address,uint256)', [owner01.address, 25]),
          MockERC20.interface.encodeFunctionData('transfer(address,uint256)', [owner02.address, 25]),
        ],
        [Helper.DEFAULT_GAS * 2, Helper.DEFAULT_GAS * 2, Helper.DEFAULT_GAS * 2],
      )
      const parsed = receipt.logs
        .map((log: any) => {
          try {
            return contract.interface.parseLog(log)
          } catch (e) {
            return undefined
          }
        })
        .filter((log: any) => log && log.name === 'MultiRequestExecuted')
      expect(parsed).to.have.lengthOf(1)
      const event = parsed[0]
      expect(event.args.txNonce).to.equal(0)
      expect(event.args.successes).to.have.lengthOf(3)
      expect(event.args.successes[0]).to.equal(true)
      expect(event.args.successes[1]).to.equal(true)
      expect(event.args.successes[2]).to.equal(true)
      // MockERC20 has no return value on `mint`/`transfer`, so every
      // returnData[i] is the ABI-encoded encoding of the empty bytes
      // (`0x` padded to 32 bytes in the logs).
      expect(event.args.returnData).to.have.lengthOf(3)
      expect(await mockERC20.balanceOf(contract.address)).to.be.equal(25)
      expect(await mockERC20.balanceOf(owner01.address)).to.be.equal(25)
      expect(await mockERC20.balanceOf(owner02.address)).to.be.equal(25)
    })

    it('multiRequest records partial failures in MultiRequestExecuted without reverting', async function () {
      const MockERC20 = await ethers.getContractFactory('MockERC20')
      const mockERC20 = await MockERC20.deploy()
      await mockERC20.deployed()
      // Three calls:
      //   1. mint(contract, 100)               → success
      //   2. transfer(owner01, 50)             → success (uses the minted balance)
      //   3. transfer(owner02, 9999)           → revert (insufficient balance)
      // The outer execTransaction must still succeed; the batch itself must
      // record successes=[true,true,false] and capture the revert payload.
      const receipt = await Helper.multiRequest(
        contract,
        owner01,
        [owner01, owner02, owner03],
        [mockERC20.address, mockERC20.address, mockERC20.address],
        [Helper.ZERO, Helper.ZERO, Helper.ZERO],
        [
          MockERC20.interface.encodeFunctionData('mint(address,uint256)', [contract.address, 100]),
          MockERC20.interface.encodeFunctionData('transfer(address,uint256)', [owner01.address, 50]),
          MockERC20.interface.encodeFunctionData('transfer(address,uint256)', [owner02.address, 9999]),
        ],
        [Helper.DEFAULT_GAS * 2, Helper.DEFAULT_GAS * 2, Helper.DEFAULT_GAS * 2],
      )
      const parsed = receipt.logs
        .map((log: any) => {
          try {
            return contract.interface.parseLog(log)
          } catch (e) {
            return undefined
          }
        })
        .filter((log: any) => log && log.name === 'MultiRequestExecuted')
      expect(parsed).to.have.lengthOf(1)
      const event = parsed[0]
      expect(event.args.txNonce).to.equal(0)
      expect(event.args.successes).to.have.lengthOf(3)
      expect(event.args.successes[0]).to.equal(true)
      expect(event.args.successes[1]).to.equal(true)
      expect(event.args.successes[2]).to.equal(false)
      expect(event.args.returnData).to.have.lengthOf(3)
      // The third call reverted; the captured returnData must carry the
      // ABI-encoded revert reason rather than be empty. ERC20InsufficientBalance
      // selector is 0xe450d38c — check it appears somewhere in the data.
      const failedReturnData: string = event.args.returnData[2]
      expect(failedReturnData.length).to.be.greaterThan(2)
      // State after the partial failure: contract holds the 50 it could not
      // send to owner02; owner01 received their 50.
      expect(await mockERC20.balanceOf(contract.address)).to.be.equal(50)
      expect(await mockERC20.balanceOf(owner01.address)).to.be.equal(50)
      expect(await mockERC20.balanceOf(owner02.address)).to.be.equal(0)
    })

    describe('approveHash - safe-style on-chain approvals', function () {
      const hashForAddUser01AtNonce = async (contract: any, nonce: any) =>
        await contract.generateHash(
          contract.address,
          Helper.ZERO,
          contract.interface.encodeFunctionData('addOwner(address)', [user01.address]),
          Helper.DEFAULT_GAS,
          nonce,
        )

      it('Owner can pre-approve a hash via approveHash and the event is emitted', async function () {
        const hash = await hashForAddUser01AtNonce(contract, ethers.BigNumber.from(0))
        expect(await contract.getApprovedOwners(hash)).to.have.lengthOf(0)
        await Helper.approveHash(contract, owner01, hash)
        const approved = await contract.getApprovedOwners(hash)
        expect(approved).to.have.lengthOf(1)
        expect(approved[0]).to.equal(owner01.address)
        expect(await contract.getThreshold(hash)).to.equal(Helper.DEFAULT_THRESHOLD)
      })

      it('approveHash is idempotent per (owner, hash)', async function () {
        const hash = await hashForAddUser01AtNonce(contract, ethers.BigNumber.from(0))
        await Helper.approveHash(contract, owner01, hash)
        // Second call from the same owner for the same hash is a no-op: the
        // ApproveHash event must NOT be emitted again, otherwise relayer
        // tooling would count the same vote twice.
        await Helper.approveHash(contract, owner01, hash, undefined, false)
        const approved = await contract.getApprovedOwners(hash)
        expect(approved).to.have.lengthOf(1)
        expect(approved[0]).to.equal(owner01.address)
      })

      it('approveHash reverts when called by a non-owner', async function () {
        const hash = await hashForAddUser01AtNonce(contract, ethers.BigNumber.from(0))
        await Helper.approveHash(contract, user01, hash, Helper.errors.NOT_OWNER)
        expect(await contract.getApprovedOwners(hash)).to.have.lengthOf(0)
      })

      it('Approving the same hash from two different owners accumulates in getApprovedOwners', async function () {
        const hash = await hashForAddUser01AtNonce(contract, ethers.BigNumber.from(0))
        await Helper.approveHash(contract, owner01, hash)
        await Helper.approveHash(contract, owner02, hash)
        const approved = await contract.getApprovedOwners(hash)
        expect(approved).to.have.lengthOf(2)
        expect(approved).to.include.members([owner01.address, owner02.address])
      })

      it('A single on-chain approval + a single ECDSA signature reaches the threshold', async function () {
        const data = contract.interface.encodeFunctionData('addOwner(address)', [user01.address])
        const hash = await hashForAddUser01AtNonce(contract, ethers.BigNumber.from(0))
        // owner01 approves on-chain; owner02 supplies the only ECDSA signature.
        await Helper.approveHash(contract, owner01, hash)
        const signatures = await Helper.prepareSignatures(
          contract,
          [owner02],
          contract.address,
          Helper.ZERO,
          data,
          Helper.DEFAULT_GAS,
          ethers.BigNumber.from(0),
        )
        // 1 ECDSA sig + 1 on-chain approval = threshold (2).
        await Helper.execTransaction(
          contract,
          owner01,
          [owner02],
          contract.address,
          Helper.ZERO,
          data,
          Helper.DEFAULT_GAS,
          undefined,
          ['OwnerAdded'],
          signatures,
        )
        expect(await contract.isOwner(user01.address)).to.be.true
      })

      it('Approving a hash for a different nonce does not affect the original tx', async function () {
        const hashN0 = await hashForAddUser01AtNonce(contract, ethers.BigNumber.from(0))
        const hashN1 = await hashForAddUser01AtNonce(contract, ethers.BigNumber.from(1))
        await Helper.approveHash(contract, owner01, hashN0)
        await Helper.approveHash(contract, owner02, hashN1)
        expect(await contract.getApprovedOwners(hashN0)).to.have.lengthOf(1)
        expect(await contract.getApprovedOwners(hashN1)).to.have.lengthOf(1)
      })

      it('Approving with an owner who was later removed makes isValidSignature false', async function () {
        const data = contract.interface.encodeFunctionData('replaceOwner(address,address)', [
          owner01.address,
          user01.address,
        ])
        // owner01 approves a hash, then is replaced via the multisig; the
        // previously-recorded approval is now stale and a fresh approval from
        // owner01 must revert with NotOwner.
        const hash = await hashForAddUser01AtNonce(contract, ethers.BigNumber.from(0))
        await Helper.approveHash(contract, owner01, hash)
        await Helper.execTransaction(
          contract,
          owner01,
          [owner01, owner02, owner03],
          contract.address,
          Helper.ZERO,
          data,
          Helper.DEFAULT_GAS,
          undefined,
          ['OwnerRemoved', 'OwnerAdded'],
        )
        await Helper.approveHash(contract, owner01, hash, Helper.errors.NOT_OWNER)
      })
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
            true,
          )
          contract = deployment.contract
          break
        }
        case DeploymentType.WithFactory: {
          deployment = await Helper.setupContract(
            Helper.CONTRACT_FACTORY_NAME,
            [owner01.address, owner02.address, owner03.address],
            2,
            true,
          )
          const tx = await deployment.contract.createMyMultiSigExtended(
            Helper.CONTRACT_NAME,
            [owner01.address, owner02.address, owner03.address],
            2,
            Helper.DEFAULT_ALLOW_ONLY_OWNER,
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
          Helper.DEFAULT_GAS,
        ),
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
          Helper.DEFAULT_GAS,
        ),
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
          Helper.DEFAULT_GAS,
        ),
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
          Helper.DEFAULT_GAS,
        ),
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
          Helper.DEFAULT_GAS,
        ),
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
        Helper.errors.NOT_ENOUGH_GAS,
      )
    })

    it('Cannot add a new owner with 3x the signature of owner01', async function () {
      await Helper.addOwner(
        contract,
        owner01,
        [owner01, owner01, owner01],
        user01.address,
        Helper.DEFAULT_GAS,
        Helper.errors.OWNER_ALREADY_SIGNED,
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
        ['OwnerRemoved', 'OwnerAdded'],
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
        ['TxFailure'],
      )
      await Helper.removeOwner(
        contract,
        owner03,
        [owner02, owner03],
        owner02.address,
        undefined,
        Helper.errors.CANNOT_REMOVE_OWNERS_BELOW_THRESHOLD,
        ['TxFailure'],
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
        ['TxFailure'],
      )
    })

    it('Can set an amount of time (7 days) after which the other owners can transfer the ownership', async function () {
      await Helper.setTransferInactiveOwnershipAfter(
        contract,
        owner01,
        [owner01, owner02, owner03],
        ethers.BigNumber.from(60).mul(60).mul(24).mul(7),
      )
    })

    it('Can set an amount of time (31 days) after which the other owners can transfer the ownership', async function () {
      await Helper.setTransferInactiveOwnershipAfter(
        contract,
        owner01,
        [owner01, owner02, owner03],
        ethers.BigNumber.from(60).mul(60).mul(24).mul(31),
      )
    })

    it('Can set owner settings (14 days -> user2)', async function () {
      await Helper.setOwnerSettings(
        contract,
        owner01.address,
        owner01,
        [owner01, owner02, owner03],
        ethers.BigNumber.from(60).mul(60).mul(24).mul(14),
        user02.address,
      )
    })

    it('Can set owner settings (31 days -> user03)', async function () {
      await Helper.setOwnerSettings(
        contract,
        owner01.address,
        owner01,
        [owner01, owner02, owner03],
        ethers.BigNumber.from(60).mul(60).mul(24).mul(31),
        user03.address,
      )
    })

    it('Can set owner settings (5 days -> user03) (should fail)', async function () {
      await Helper.setTransferInactiveOwnershipAfter(
        contract,
        owner01,
        [owner01, owner02, owner03],
        ethers.BigNumber.from(60).mul(60).mul(24).mul(7),
      )
      await Helper.setOwnerSettings(
        contract,
        owner01.address,
        owner01,
        [owner01, owner02, owner03],
        ethers.BigNumber.from(60).mul(60).mul(24).mul(5),
        user03.address,
        undefined,
        ['TxFailure'],
      )
    })

    it('Can set owner settings (31 days -> owner02) (should fail)', async function () {
      await Helper.setOwnerSettings(
        contract,
        owner01.address,
        owner01,
        [owner01, owner02, owner03],
        ethers.BigNumber.from(60).mul(60).mul(24).mul(31),
        owner02.address,
        undefined,
        ['TxFailure'],
      )
    })

    it('Can set owner settings (5 days -> owner03) (should fail)', async function () {
      await Helper.setTransferInactiveOwnershipAfter(
        contract,
        owner01,
        [owner01, owner02, owner03],
        ethers.BigNumber.from(60).mul(60).mul(24).mul(7),
      )
      await Helper.setOwnerSettings(
        contract,
        owner01.address,
        owner01,
        [owner01, owner02, owner03],
        ethers.BigNumber.from(60).mul(60).mul(24).mul(5),
        owner03.address,
        undefined,
        ['TxFailure'],
      )
    })

    it('Can set owner settings then transfer ownership', async function () {
      await Helper.setTransferInactiveOwnershipAfter(
        contract,
        owner01,
        [owner01, owner02, owner03],
        ethers.BigNumber.from(60).mul(60).mul(24).mul(7),
      )
      await Helper.setOwnerSettings(
        contract,
        owner01.address,
        owner01,
        [owner01, owner02, owner03],
        ethers.BigNumber.from(60).mul(60).mul(24).mul(8),
        user03.address,
      )
      await time.increase(60 * 60 * 24 * 9)
      await Helper.takeOverOwnership(contract, user03, owner01.address)
    })

    it('Can set owner settings then transfer ownership too early (should fail)', async function () {
      await Helper.setTransferInactiveOwnershipAfter(
        contract,
        owner01,
        [owner01, owner02, owner03],
        ethers.BigNumber.from(60).mul(60).mul(24).mul(7),
      )
      await Helper.setOwnerSettings(
        contract,
        owner01.address,
        owner01,
        [owner01, owner02, owner03],
        ethers.BigNumber.from(60).mul(60).mul(24).mul(8),
        user03.address,
      )
      await time.increase(60 * 60 * 24 * 5)
      await Helper.takeOverOwnership(contract, user03, owner01.address, Helper.errors.OWNER_STILL_ACTIVE)
    })

    it('Can set owner settings then transfer ownership (not delegatee) (should fail)', async function () {
      await Helper.setTransferInactiveOwnershipAfter(
        contract,
        owner01,
        [owner01, owner02, owner03],
        ethers.BigNumber.from(60).mul(60).mul(24).mul(7),
      )
      await Helper.setOwnerSettings(
        contract,
        owner01.address,
        owner01,
        [owner01, owner02, owner03],
        ethers.BigNumber.from(60).mul(60).mul(24).mul(8),
        user03.address,
      )
      await time.increase(60 * 60 * 24 * 9)
      await Helper.takeOverOwnership(contract, user02, owner01.address, Helper.errors.SENDER_NOT_DELEGATEE)
    })

    it('Cannot setOwnerSettings directly (onlyThis enforced)', async function () {
      const data = contract.interface.encodeFunctionData('setOwnerSettings(address,uint256,address)', [
        owner01.address,
        ethers.BigNumber.from(60).mul(60).mul(24).mul(8),
        user03.address,
      ]) as `0x${string}`
      await expect(
        Helper.sendRawTxn(
          {
            to: contract.address,
            value: 0,
            data,
          },
          owner01,
          ethers,
          provider,
        ),
      ).to.be.revertedWithCustomError(contract, Helper.errors.ONLY_SELF)
    })

    it('Cannot setOwnerSettings for a non-owner (isOwner enforced)', async function () {
      await Helper.setOwnerSettings(
        contract,
        user01.address,
        owner01,
        [owner01, owner02, owner03],
        ethers.BigNumber.from(60).mul(60).mul(24).mul(8),
        user03.address,
        undefined,
        ['TxFailure'],
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
        provider,
      )
      await Helper.execTransaction(
        contract,
        owner01,
        [owner01, owner02, owner03],
        owner01.address,
        ethers.utils.parseEther('1'),
        '0x',
        Helper.DEFAULT_GAS,
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
        provider,
      )
      await Helper.execTransaction(
        contract,
        owner01,
        [owner01, owner02, owner03],
        owner01.address,
        ethers.utils.parseEther('1'),
        '0x',
        Helper.DEFAULT_GAS,
      )
      await Helper.execTransaction(
        contract,
        owner02,
        [owner01, owner02, owner03],
        owner01.address,
        ethers.utils.parseEther('1'),
        '0x',
        Helper.DEFAULT_GAS,
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
        Helper.DEFAULT_GAS * 2,
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
        Helper.DEFAULT_GAS * 2,
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
        Helper.DEFAULT_GAS * 2,
      )
      expect(await mockERC20.balanceOf(contract.address)).to.be.equal(0)
      expect(await mockERC20.balanceOf(owner01.address)).to.be.equal(10)
    })

    it('Emit TxFailure when valid signature try to execute a invalid call', async function () {
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
        ['TxFailure'],
      )
    })

    it('Cannot reuse a signature', async function () {
      const data = contract.interface.encodeFunctionData('addOwner(address)', [user02.address])
      const signatures = await Helper.prepareSignatures(
        contract,
        [owner01, owner02],
        contract.address,
        Helper.ZERO,
        data,
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
        signatures,
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
        signatures,
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
        ['OwnerAdded', 'OwnerAdded'],
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
        [Helper.DEFAULT_GAS * 2, Helper.DEFAULT_GAS * 2],
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
          `0x${string}`,
        ],
        [Helper.ZERO, Helper.ZERO, Helper.ZERO, Helper.ZERO],
        [
          MockERC20.interface.encodeFunctionData('mint(address,uint256)', [contract.address, 150]),
          MockERC20.interface.encodeFunctionData('transfer(address,uint256)', [owner01.address, 50]),
          MockERC20.interface.encodeFunctionData('transfer(address,uint256)', [owner02.address, 50]),
          MockERC20.interface.encodeFunctionData('transfer(address,uint256)', [owner03.address, 50]),
        ],
        [Helper.DEFAULT_GAS * 2, Helper.DEFAULT_GAS * 2, Helper.DEFAULT_GAS * 2, Helper.DEFAULT_GAS * 2],
      )
      expect(await mockERC20.balanceOf(contract.address)).to.be.equal(0)
      expect(await mockERC20.balanceOf(owner01.address)).to.be.equal(50)
      expect(await mockERC20.balanceOf(owner02.address)).to.be.equal(50)
      expect(await mockERC20.balanceOf(owner03.address)).to.be.equal(50)
    })

    it('multiRequest emits MultiRequestExecuted with per-call success and return data', async function () {
      const MockERC20 = await ethers.getContractFactory('MockERC20')
      const mockERC20 = await MockERC20.deploy()
      await mockERC20.deployed()
      const receipt = await Helper.multiRequest(
        contract,
        owner01,
        [owner01, owner02, owner03],
        [mockERC20.address, mockERC20.address, mockERC20.address],
        [Helper.ZERO, Helper.ZERO, Helper.ZERO],
        [
          MockERC20.interface.encodeFunctionData('mint(address,uint256)', [contract.address, 75]),
          MockERC20.interface.encodeFunctionData('transfer(address,uint256)', [owner01.address, 25]),
          MockERC20.interface.encodeFunctionData('transfer(address,uint256)', [owner02.address, 25]),
        ],
        [Helper.DEFAULT_GAS * 2, Helper.DEFAULT_GAS * 2, Helper.DEFAULT_GAS * 2],
      )
      const parsed = receipt.logs
        .map((log: any) => {
          try {
            return contract.interface.parseLog(log)
          } catch (e) {
            return undefined
          }
        })
        .filter((log: any) => log && log.name === 'MultiRequestExecuted')
      expect(parsed).to.have.lengthOf(1)
      const event = parsed[0]
      expect(event.args.txNonce).to.equal(0)
      expect(event.args.successes).to.have.lengthOf(3)
      expect(event.args.successes[0]).to.equal(true)
      expect(event.args.successes[1]).to.equal(true)
      expect(event.args.successes[2]).to.equal(true)
      expect(event.args.returnData).to.have.lengthOf(3)
      expect(await mockERC20.balanceOf(contract.address)).to.be.equal(25)
      expect(await mockERC20.balanceOf(owner01.address)).to.be.equal(25)
      expect(await mockERC20.balanceOf(owner02.address)).to.be.equal(25)
    })

    it('multiRequest records partial failures in MultiRequestExecuted without reverting', async function () {
      const MockERC20 = await ethers.getContractFactory('MockERC20')
      const mockERC20 = await MockERC20.deploy()
      await mockERC20.deployed()
      // Three calls: mint succeeds, transfer to owner01 succeeds, transfer to
      // owner02 reverts because the contract does not hold 9999 tokens. The
      // batch must record successes=[true,true,false] and capture the revert
      // payload in returnData[2].
      const receipt = await Helper.multiRequest(
        contract,
        owner01,
        [owner01, owner02, owner03],
        [mockERC20.address, mockERC20.address, mockERC20.address],
        [Helper.ZERO, Helper.ZERO, Helper.ZERO],
        [
          MockERC20.interface.encodeFunctionData('mint(address,uint256)', [contract.address, 100]),
          MockERC20.interface.encodeFunctionData('transfer(address,uint256)', [owner01.address, 50]),
          MockERC20.interface.encodeFunctionData('transfer(address,uint256)', [owner02.address, 9999]),
        ],
        [Helper.DEFAULT_GAS * 2, Helper.DEFAULT_GAS * 2, Helper.DEFAULT_GAS * 2],
      )
      const parsed = receipt.logs
        .map((log: any) => {
          try {
            return contract.interface.parseLog(log)
          } catch (e) {
            return undefined
          }
        })
        .filter((log: any) => log && log.name === 'MultiRequestExecuted')
      expect(parsed).to.have.lengthOf(1)
      const event = parsed[0]
      expect(event.args.txNonce).to.equal(0)
      expect(event.args.successes).to.have.lengthOf(3)
      expect(event.args.successes[0]).to.equal(true)
      expect(event.args.successes[1]).to.equal(true)
      expect(event.args.successes[2]).to.equal(false)
      expect(event.args.returnData).to.have.lengthOf(3)
      const failedReturnData: string = event.args.returnData[2]
      expect(failedReturnData.length).to.be.greaterThan(2)
      expect(await mockERC20.balanceOf(contract.address)).to.be.equal(50)
      expect(await mockERC20.balanceOf(owner01.address)).to.be.equal(50)
      expect(await mockERC20.balanceOf(owner02.address)).to.be.equal(0)
    })

    it('6-arg execTransaction honors the caller-supplied nonce (replay at N+5)', async function () {
      // Signers pre-sign for nonce N+5 even though `_txnNonce` is still N.
      const futureNonce = ethers.BigNumber.from(5)
      const data = contract.interface.encodeFunctionData('addOwner(address)', [user01.address])
      const signatures = await Helper.prepareSignatures(
        contract,
        [owner01, owner02],
        contract.address,
        Helper.ZERO,
        data,
        Helper.DEFAULT_GAS,
        futureNonce,
      )
      // First execution at nonce N+5 succeeds and the sequential counter advances to N+1.
      await Helper.execTransactionWithNonce(
        contract,
        owner01,
        [owner01, owner02],
        contract.address,
        Helper.ZERO,
        data as `0x${string}`,
        Helper.DEFAULT_GAS,
        futureNonce,
        signatures,
      )
      expect(await contract.isOwner(user01.address)).to.be.true
      expect(await contract.nonce()).to.be.equal(1)
      expect(await contract.isNonceUsed(futureNonce)).to.be.false
    })

    it('6-arg execTransaction reverts when the nonce was already used by the 5-arg overload', async function () {
      // Use the 5-arg overload first to consume nonce 0; the same signatures bound to
      // nonce 0 must then be rejected on the 6-arg overload via the owner-signed check.
      const nonce = ethers.BigNumber.from(0)
      const data = contract.interface.encodeFunctionData('addOwner(address)', [user01.address])
      const signatures = await Helper.prepareSignatures(
        contract,
        [owner01, owner02],
        contract.address,
        Helper.ZERO,
        data,
        Helper.DEFAULT_GAS,
        nonce,
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
        signatures,
      )
      await Helper.execTransactionWithNonceReverted(
        contract,
        owner01,
        [owner01, owner02],
        contract.address,
        Helper.ZERO,
        data as `0x${string}`,
        Helper.DEFAULT_GAS,
        nonce,
        signatures,
        Helper.errors.OWNER_ALREADY_SIGNED,
      )
    })

    it('6-arg execTransaction reverts with NONCE_ALREADY_USED once markNonceAsUsed is called', async function () {
      const futureNonce = ethers.BigNumber.from(7)
      const data = contract.interface.encodeFunctionData('addOwner(address)', [user01.address])
      const signatures = await Helper.prepareSignatures(
        contract,
        [owner01, owner02],
        contract.address,
        Helper.ZERO,
        data,
        Helper.DEFAULT_GAS,
        futureNonce,
      )
      // Pre-burn nonce 7 via markNonceAsUsed (call execTransaction directly to avoid
      // the pre-existing assertion in Helper.markNonceAsUsed that conflicts with our setup).
      const markData = contract.interface.encodeFunctionData('markNonceAsUsed', [futureNonce]) as `0x${string}`
      await Helper.execTransaction(contract, owner01, [owner01, owner02], contract.address, Helper.ZERO, markData)
      expect(await contract.isNonceUsed(futureNonce)).to.be.true
      // The signatures are otherwise valid, but the nonce has been marked as used so
      // the 6-arg overload must reject them.
      await Helper.execTransactionWithNonceReverted(
        contract,
        owner01,
        [owner01, owner02],
        contract.address,
        Helper.ZERO,
        data as `0x${string}`,
        Helper.DEFAULT_GAS,
        futureNonce,
        signatures,
        Helper.errors.NONCE_ALREADY_USED,
      )
    })

    it('isValidSignature now reports against the passed nonce (not _txnNonce)', async function () {
      // Sign once for nonce 99, then ask isValidSignature about both 99 and 0 using the
      // SAME signatures. With the bug, the view would key on `_txnNonce` for both, so
      // asking about 0 would still return true (since 0 == `_txnNonce`). With the fix,
      // the second call must return false because the signatures are bound to 99, not 0.
      const data = contract.interface.encodeFunctionData('addOwner(address)', [user01.address])
      const signatures = await Helper.prepareSignatures(
        contract,
        [owner01, owner02],
        contract.address,
        Helper.ZERO,
        data,
        Helper.DEFAULT_GAS,
        ethers.BigNumber.from(99),
      )
      expect(
        await contract
          .connect(owner01)
          .isValidSignature(
            contract.address,
            Helper.ZERO,
            data,
            Helper.DEFAULT_GAS,
            ethers.BigNumber.from(99),
            signatures,
          ),
      ).to.be.true
      expect(
        await contract
          .connect(owner01)
          .isValidSignature(
            contract.address,
            Helper.ZERO,
            data,
            Helper.DEFAULT_GAS,
            ethers.BigNumber.from(0),
            signatures,
          ),
      ).to.be.false
    })

  })
}
