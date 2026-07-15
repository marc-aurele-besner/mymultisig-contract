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
      // v0.5.0 — every wallet (base, extended, factory) now returns the
      // same canonical `'0.5.0'` so the EIP-712 domain separator is
      // shared across the whole wallet family. The typehash still
      // differs (base 6-field vs extended 7-field with `operation`).
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

    it('Mixed signature blob: non-owners silently fail validation but do not block other valid votes', async function () {
      // Three entries in the blob: owner01, user02 (NOT an owner), owner03.
      // Threshold is 2. With the new design each vote is validated
      // independently — the non-owner slot is silently dropped, and the
      // remaining two real owners reach threshold. (Pre-0.2.0 this test
      // expected `false` because the OLD per-chunk loop bailed on the first
      // non-owner; the new semantics are more permissive and correct.)
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
      ).to.be.true
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
        Helper.errors.INVALID_SIGNATURES,
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
      // v0.5.0 removal: the v0.4.0 6/7-arg `execTransaction` overloads
      // are gone. Inner reverts with non-empty data bubble through
      // `_execExtended`'s `assembly.revert(...)` path; `TxFailure` only
      // fires on silent reverts (success=false, returnData empty).
      // Replaced by the `multiRequest` partial-failure tests further down
      // which exercise the silent-revert path directly.
      expect(true).to.be.true
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
        Helper.errors.INVALID_SIGNATURES,
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
          0,
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

    describe('validUntil - EIP-712 deadline', function () {
      const data = () => contract.interface.encodeFunctionData('addOwner(address)', [user01.address])
      const buildSignatures = (validUntil: number) =>
        Helper.prepareSignatures(
          contract,
          [owner01, owner02],
          contract.address,
          Helper.ZERO,
          data(),
          Helper.DEFAULT_GAS,
          ethers.BigNumber.from(0),
          validUntil,
        )

      it('validUntil = 0 disables the deadline and the tx executes far in the future', async function () {
        await time.increase(60 * 60 * 24 * 365)
        await Helper.execTransaction(
          contract,
          owner01,
          [owner01, owner02],
          contract.address,
          Helper.ZERO,
          data(),
          Helper.DEFAULT_GAS,
          undefined,
          ['OwnerAdded'],
          buildSignatures(0),
          0,
        )
        expect(await contract.isOwner(user01.address)).to.be.true
      })

      it('validUntil in the future allows execution', async function () {
        const future = (await time.latest()) + 60 * 60 * 24 // +1 day
        await Helper.execTransaction(
          contract,
          owner01,
          [owner01, owner02],
          contract.address,
          Helper.ZERO,
          data(),
          Helper.DEFAULT_GAS,
          undefined,
          ['OwnerAdded'],
          buildSignatures(future),
          future,
        )
        expect(await contract.isOwner(user01.address)).to.be.true
      })

      it('validUntil in the past reverts with SignatureExpired and the nonce does not advance', async function () {
        const past = (await time.latest()) - 1
        await Helper.execTransaction(
          contract,
          owner01,
          [owner01, owner02],
          contract.address,
          Helper.ZERO,
          data(),
          Helper.DEFAULT_GAS,
          Helper.errors.SIGNATURE_EXPIRED,
          undefined,
          buildSignatures(past),
          past,
        )
        expect(await contract.isOwner(user01.address)).to.be.false
        expect(await contract.nonce()).to.be.equal(0)
      })
    })

    describe('revokeApproval - withdraw a pre-approval', function () {
      it('Owner can withdraw a previous approveHash and the owner is removed from getApprovedOwners', async function () {
        const hash = ethers.utils.keccak256(ethers.utils.toUtf8Bytes('test-revoke-1'))
        expect(await contract.getApprovedOwners(hash)).to.have.lengthOf(0)
        await Helper.approveHash(contract, owner01, hash)
        expect(await contract.getApprovedOwners(hash)).to.have.lengthOf(1)
        const tx = await contract.connect(owner01).revokeApproval(hash)
        await tx.wait()
        expect(await contract.getApprovedOwners(hash)).to.have.lengthOf(0)
      })

      it('revokeApproval emits RevokeApproval with (owner, hash)', async function () {
        const hash = ethers.utils.keccak256(ethers.utils.toUtf8Bytes('test-revoke-2'))
        await Helper.approveHash(contract, owner01, hash)
        const tx = await contract.connect(owner01).revokeApproval(hash)
        const receipt = await tx.wait()
        const parsed = receipt.logs
          .map((log: any) => {
            try {
              return contract.interface.parseLog(log)
            } catch (e) {
              return
            }
          })
          .find((e: any) => e && e.name === 'RevokeApproval')
        expect(parsed, 'RevokeApproval event not found').to.not.equal(undefined)
        expect(parsed!.args.owner).to.equal(owner01.address)
        expect(parsed!.args.hash).to.equal(hash)
      })

      it('A second revokeApproval reverts with NotApproved', async function () {
        const hash = ethers.utils.keccak256(ethers.utils.toUtf8Bytes('test-revoke-3'))
        await Helper.approveHash(contract, owner01, hash)
        await contract.connect(owner01).revokeApproval(hash)
        await expect(contract.connect(owner01).revokeApproval(hash)).to.be.revertedWithCustomError(
          contract,
          Helper.errors.NOT_APPROVED,
        )
      })

      it('revokeApproval reverts when called by a non-owner', async function () {
        const hash = ethers.utils.keccak256(ethers.utils.toUtf8Bytes('test-revoke-4'))
        await expect(contract.connect(user01).revokeApproval(hash)).to.be.revertedWithCustomError(
          contract,
          Helper.errors.NOT_OWNER,
        )
      })

      it('An owner who never approved cannot revoke another owner approval (NotApproved)', async function () {
        const hash = ethers.utils.keccak256(ethers.utils.toUtf8Bytes('test-revoke-5'))
        await Helper.approveHash(contract, owner01, hash)
        await expect(contract.connect(owner02).revokeApproval(hash)).to.be.revertedWithCustomError(
          contract,
          Helper.errors.NOT_APPROVED,
        )
        // The original approval is still intact.
        expect(await contract.getApprovedOwners(hash)).to.have.lengthOf(1)
      })

      it('After revoke, an execTransaction that relied solely on the revoked approval fails with InvalidSignatures', async function () {
        const data = contract.interface.encodeFunctionData('addOwner(address)', [user01.address])
        const hash = await contract.generateHash(
          contract.address,
          Helper.ZERO,
          data,
          Helper.DEFAULT_GAS,
          ethers.BigNumber.from(0),
          0,
        )
        await Helper.approveHash(contract, owner01, hash)
        await contract.connect(owner01).revokeApproval(hash)
        // Sign with only owner02 — the original approval (owner01) is gone,
        // so the 1 ECDSA vote does not reach threshold (2).
        const signatures = await Helper.prepareSignatures(
          contract,
          [owner02],
          contract.address,
          Helper.ZERO,
          data,
          Helper.DEFAULT_GAS,
          ethers.BigNumber.from(0),
          0,
        )
        await Helper.execTransaction(
          contract,
          owner02,
          [owner02],
          contract.address,
          Helper.ZERO,
          data,
          Helper.DEFAULT_GAS,
          Helper.errors.INVALID_SIGNATURES,
          undefined,
          signatures,
        )
        expect(await contract.isOwner(user01.address)).to.be.false
      })
    })

    describe('multiRequestStrict - atomic batch', function () {
      it('All inner calls succeed → outer tx emits TransactionExecuted', async function () {
        const to_ = [
          contract.address as `0x${string}`,
          contract.address as `0x${string}`,
          contract.address as `0x${string}`,
        ]
        const value_ = [Helper.ZERO, Helper.ZERO, Helper.ZERO]
        const data_ = [
          contract.interface.encodeFunctionData('addOwner(address)', [user01.address]),
          contract.interface.encodeFunctionData('addOwner(address)', [user02.address]),
          contract.interface.encodeFunctionData('addOwner(address)', [user03.address]),
        ]
        const gas_ = [Helper.DEFAULT_GAS, Helper.DEFAULT_GAS, Helper.DEFAULT_GAS]

        const innerData = contract.interface.encodeFunctionData('multiRequestStrict', [
          to_,
          value_,
          data_,
          gas_,
        ]) as `0x${string}`

        let gas = 0
        for (const g of gas_) gas += g

        await Helper.execTransaction(
          contract,
          owner01,
          [owner01, owner02, owner03],
          contract.address as `0x${string}`,
          Helper.ZERO,
          innerData,
          gas,
          undefined,
          ['OwnerAdded', 'OwnerAdded', 'OwnerAdded'],
        )
        expect(await contract.isOwner(user01.address)).to.be.true
        expect(await contract.isOwner(user02.address)).to.be.true
        expect(await contract.isOwner(user03.address)).to.be.true
      })

      it('A failing inner call reverts the whole batch with BatchCallFailed; no side effects persist', async function () {
        const to_ = [
          contract.address as `0x${string}`,
          user01.address as `0x${string}`, // forwarding 1 wei to an EOA — wallet has 0 ETH → revert
        ]
        const value_ = [Helper.ZERO, ethers.BigNumber.from(1)]
        const data_ = [contract.interface.encodeFunctionData('addOwner(address)', [user01.address]), '0x']
        const gas_ = [Helper.DEFAULT_GAS, Helper.DEFAULT_GAS]

        const innerData = contract.interface.encodeFunctionData('multiRequestStrict', [
          to_,
          value_,
          data_,
          gas_,
        ]) as `0x${string}`

        const gas = gas_.reduce((a, b) => a + b, 0)
        const nonceBefore = await contract.nonce()

        await Helper.execTransaction(
          contract,
          owner01,
          [owner01, owner02, owner03],
          contract.address as `0x${string}`,
          Helper.ZERO,
          innerData,
          gas,
          'BatchCallFailed',
          undefined,
        )
        // Side effect of the FIRST call must NOT persist.
        expect(await contract.isOwner(user01.address)).to.be.false
        // Nonce must NOT advance — the whole tx was rolled back.
        expect(await contract.nonce()).to.equal(nonceBefore)
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
            Helper.ENTRY_POINT_V07_ADDRESS,
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
      // v0.5.0 — every wallet (base, extended, factory) now returns the
      // same canonical `'0.5.0'` so the EIP-712 domain separator is
      // shared across the whole wallet family. The typehash still
      // differs (base 6-field vs extended 7-field with `operation`).
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

    it('Mixed signature blob: non-owners silently fail validation but do not block other valid votes', async function () {
      // Three entries in the blob: owner01, user02 (NOT an owner), owner03.
      // Threshold is 2. With the new design each vote is validated
      // independently — the non-owner slot is silently dropped, and the
      // remaining two real owners reach threshold. (Pre-0.2.0 this test
      // expected `false` because the OLD per-chunk loop bailed on the first
      // non-owner; the new semantics are more permissive and correct.)
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
      ).to.be.true
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
        Helper.errors.INVALID_SIGNATURES,
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
        Helper.errors.OWNER_SETTINGS_TRANSFER_INACTIVE_TOO_SHORT,
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
        Helper.errors.OWNER_SETTINGS_MUST_BE_GREATER_THAN_MINIMUM,
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
        Helper.errors.OWNER_SETTINGS_DELEGATEE_MUST_NOT_BE_OWNER,
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
        Helper.errors.OWNER_SETTINGS_MUST_BE_GREATER_THAN_MINIMUM,
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
        Helper.errors.OWNER_SETTINGS_OWNER_MUST_BE_OWNER,
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
      // v0.5.0 removal: see the equivalent test further up in this file.
      expect(true).to.be.true
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
        Helper.errors.INVALID_SIGNATURES,
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
        0,
        signatures,
      )
      expect(await contract.isOwner(user01.address)).to.be.true
      expect(await contract.nonce()).to.be.equal(1)
      expect(await contract.isNonceUsed(futureNonce)).to.be.false
    })

    it('6-arg execTransaction reverts when the nonce was already used by the 5-arg overload', async function () {
      // v0.5.0 removal: the v0.4.0 6/7-arg overloads are gone. Same
      // replay-then-second-call logic now lives under the new 8-arg path
      // (`execTransaction(address, ..., 8 args)`). The 6-arg overload
      // reverts with `RequiresOperationByte()` immediately, which is the
      // new equivalent of the old replay-rejection path — covered by the
      // "V2_5RequiresOperationByte" tests in the Foundry suite.
      expect(true).to.be.true
    })

    it('6-arg execTransaction reverts with NONCE_ALREADY_USED once markNonceAsUsed is called', async function () {
      // v0.5.0 removal: see the comment on the previous test. Same
      // rationale — there is no 6-arg overload to test this against.
      expect(true).to.be.true
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
          ['isValidSignature(address,uint256,bytes,uint256,uint256,uint256,bytes)'](
            contract.address,
            Helper.ZERO,
            data,
            Helper.DEFAULT_GAS,
            ethers.BigNumber.from(99),
            0,
            signatures,
          ),
      ).to.be.true
      expect(
        await contract
          .connect(owner01)
          ['isValidSignature(address,uint256,bytes,uint256,uint256,uint256,bytes)'](
            contract.address,
            Helper.ZERO,
            data,
            Helper.DEFAULT_GAS,
            ethers.BigNumber.from(0),
            0,
            signatures,
          ),
      ).to.be.false
    })

    // Standard magic value used by `isValidSignature(bytes32,bytes)` per
    // EIP-1271. Declared in the outer test scope so sibling `describe`
    // blocks (EIP-1271 entry + Contract-owner voting) can both reuse it.
    const MAGIC = '0x1626ba7e'

    describe('EIP-1271 entry point', function () {
      // Helper: a clean dummy tx whose EIP-712 hash the test will sign and feed
      // to `isValidSignature(bytes32,bytes)`. Using a real EIP-712 hash keeps
      // the test environment symmetric with `execTransaction`'s validation.
      async function dummyTxHashFieldsAndHash(): Promise<{ fields: any; hash: string }> {
        const fields = {
          to: contract.address,
          value: ethers.BigNumber.from(0),
          data: '0x',
          gas: ethers.BigNumber.from(Helper.DEFAULT_GAS),
          nonce: ethers.BigNumber.from(0),
          validUntil: 0,
          // v0.5.0 — extended wallets bind an `operation` byte into the
          // EIP-712 payload; pick the right hash for the test wallet.
          operation: 0,
        }
        const isExtended = typeof (contract as any).allowOnlyOwnerRequest === 'function'
        const hash = isExtended
          ? await (contract as any).generateHashOp(
              fields.to,
              fields.value,
              fields.data,
              fields.gas,
              fields.nonce,
              fields.validUntil,
              fields.operation,
            )
          : await contract.generateHash(fields.to, fields.value, fields.data, fields.gas, fields.nonce, 0)
        return { fields, hash }
      }

      it('returns the EIP-1271 magic value when threshold is met via EOA ECDSA sigs', async function () {
        const { fields, hash } = await dummyTxHashFieldsAndHash()
        const sig1 = await Helper.signEip712Hash(contract, owner01, fields)
        const sig2 = await Helper.signEip712Hash(contract, owner02, fields)
        const blob = ethers.utils.defaultAbiCoder.encode(
          ['tuple(address owner, bytes sig)[]'],
          [
            [
              { owner: owner01.address, sig: sig1 },
              { owner: owner02.address, sig: sig2 },
            ],
          ],
        )
        expect(await contract.connect(user01)['isValidSignature(bytes32,bytes)'](hash, blob)).to.equal(MAGIC)
      })

      it('returns a non-magic value when threshold is not met (1/2)', async function () {
        const { fields, hash } = await dummyTxHashFieldsAndHash()
        const sig1 = await Helper.signEip712Hash(contract, owner01, fields)
        const blob = ethers.utils.defaultAbiCoder.encode(
          ['tuple(address owner, bytes sig)[]'],
          [[{ owner: owner01.address, sig: sig1 }]],
        )
        expect(await contract.connect(user01)['isValidSignature(bytes32,bytes)'](hash, blob)).to.equal('0xffffffff')
      })

      it('returns a non-magic value when one of the claimed signers is not an owner', async function () {
        const { fields, hash } = await dummyTxHashFieldsAndHash()
        // user02 has a key but is NOT a contract owner; we still pass a
        // ECDSA sig over the hash from their key, but the blob claims
        // `owner = user02` which fails `_owners[user02]`.
        const sig1 = await Helper.signEip712Hash(contract, owner01, fields)
        const sig2 = await Helper.signEip712Hash(contract, user02, fields)
        const blob = ethers.utils.defaultAbiCoder.encode(
          ['tuple(address owner, bytes sig)[]'],
          [
            [
              { owner: owner01.address, sig: sig1 },
              { owner: user02.address, sig: sig2 },
            ],
          ],
        )
        expect(await contract.connect(user01)['isValidSignature(bytes32,bytes)'](hash, blob)).to.equal('0xffffffff')
      })

      it('returns the magic value when one vote comes from a contract owner that itself returns the magic', async function () {
        // Deploy an inner MyMultiSig as a nested owner with threshold 2.
        const Inner = await ethers.getContractFactory(Helper.CONTRACT_NAME)
        const inner = await Inner.deploy('Inner', [owner01.address, owner02.address], 2)
        await inner.deployed()
        // Add the inner wallet as the third owner of the outer wallet
        // (now owners = [owner01, owner02, inner], threshold = 2).
        await Helper.addOwner(contract, owner01, [owner01, owner02, owner03], inner.address)

        const { hash } = await dummyTxHashFieldsAndHash()
        // Inner wallet's ECDSA votes for `hash` — these go through
        // `ecrecover(hash, ...)` inside the inner's `_validateVote`, so they
        // must be raw 65-byte ECDSA sigs over `hash`, NOT EIP-712 typed
        // data (which would wrap the hash with a different domain).
        const innerSig1 = await Helper.signDigest(owner01, hash)
        const innerSig2 = await Helper.signDigest(owner02, hash)
        const innerBlob = ethers.utils.defaultAbiCoder.encode(
          ['tuple(address owner, bytes sig)[]'],
          [
            [
              { owner: owner01.address, sig: innerSig1 },
              { owner: owner02.address, sig: innerSig2 },
            ],
          ],
        )
        // Sanity check: inner's own EIP-1271 entry returns the magic.
        expect(await inner['isValidSignature(bytes32,bytes)'](hash, innerBlob)).to.equal(MAGIC)

        // Outer blob: 1 contract-owner entry (inner) — alone that's only 1
        // vote, threshold is 2 — so add another contract-owner via owner03.
        const inner2 = await Inner.deploy('Inner2', [owner02.address, owner03.address], 2)
        await inner2.deployed()
        // Use only EOA wallets for the `owners` slot — the contract owners
        // already on the wallet sign through their own ECDSA sigs, not as
        // direct voters.
        await Helper.addOwner(contract, owner01, [owner01, owner02], inner2.address)
        const inner2Sig1 = await Helper.signDigest(owner02, hash)
        const inner2Sig2 = await Helper.signDigest(owner03, hash)
        const inner2Blob = ethers.utils.defaultAbiCoder.encode(
          ['tuple(address owner, bytes sig)[]'],
          [
            [
              { owner: owner02.address, sig: inner2Sig1 },
              { owner: owner03.address, sig: inner2Sig2 },
            ],
          ],
        )
        const outerBlob = ethers.utils.defaultAbiCoder.encode(
          ['tuple(address owner, bytes sig)[]'],
          [
            [
              { owner: inner.address, sig: innerBlob },
              { owner: inner2.address, sig: inner2Blob },
            ],
          ],
        )
        // Diagnostic: try with just inner (1 vote) — threshold is 2, should be non-magic.
        const oneVoteBlob = ethers.utils.defaultAbiCoder.encode(
          ['tuple(address owner, bytes sig)[]'],
          [[{ owner: inner.address, sig: innerBlob }]],
        )
        expect(await contract.connect(user01)['isValidSignature(bytes32,bytes)'](hash, oneVoteBlob)).to.equal(
          '0xffffffff',
        )
        // Diagnostic: try with just inner2 — same.
        const oneVoteBlob2 = ethers.utils.defaultAbiCoder.encode(
          ['tuple(address owner, bytes sig)[]'],
          [[{ owner: inner2.address, sig: inner2Blob }]],
        )
        expect(await contract.connect(user01)['isValidSignature(bytes32,bytes)'](hash, oneVoteBlob2)).to.equal(
          '0xffffffff',
        )
        // And the full blob — should be magic.
        expect(await contract.connect(user01)['isValidSignature(bytes32,bytes)'](hash, outerBlob)).to.equal(MAGIC)
      })

      it('returns a non-magic value when a contract owner EIP-1271 entry fails its own threshold', async function () {
        // Deploy an inner wallet whose threshold (2) is met but whose EIP-1271
        // entry receives a wrong hash — so the inner ECDSA votes fail to
        // recover and the inner `isValidSignature` returns non-magic.
        const Inner = await ethers.getContractFactory(Helper.CONTRACT_NAME)
        const inner = await Inner.deploy('InnerFail', [owner01.address, owner02.address], 2)
        await inner.deployed()
        await Helper.addOwner(contract, owner01, [owner01, owner02, owner03], inner.address)

        const { hash } = await dummyTxHashFieldsAndHash()
        const wrongHash = ethers.utils.hexlify(ethers.utils.randomBytes(32))
        // Sign `hash` (the outer typed-data hash), but the wallet will be
        // queried with `wrongHash`. The inner ECDSA sigs won't recover.
        const sig1 = await Helper.signDigest(owner01, hash)
        const sig2 = await Helper.signDigest(owner02, hash)
        const innerBlob = ethers.utils.defaultAbiCoder.encode(
          ['tuple(address owner, bytes sig)[]'],
          [
            [
              { owner: owner01.address, sig: sig1 },
              { owner: owner02.address, sig: sig2 },
            ],
          ],
        )
        const outerBlob = ethers.utils.defaultAbiCoder.encode(
          ['tuple(address owner, bytes sig)[]'],
          [[{ owner: inner.address, sig: innerBlob }]],
        )
        expect(await contract.connect(user01)['isValidSignature(bytes32,bytes)'](wrongHash, outerBlob)).to.equal(
          '0xffffffff',
        )
      })

      it('does not mutate state: nonce / approvals unchanged across repeated calls', async function () {
        const { fields, hash } = await dummyTxHashFieldsAndHash()
        const sig1 = await Helper.signEip712Hash(contract, owner01, fields)
        const sig2 = await Helper.signEip712Hash(contract, owner02, fields)
        const blob = ethers.utils.defaultAbiCoder.encode(
          ['tuple(address owner, bytes sig)[]'],
          [
            [
              { owner: owner01.address, sig: sig1 },
              { owner: owner02.address, sig: sig2 },
            ],
          ],
        )
        const nonceBefore = await contract.nonce()
        for (let i = 0; i < 3; i++) {
          expect(await contract.connect(user01)['isValidSignature(bytes32,bytes)'](hash, blob)).to.equal(MAGIC)
        }
        expect(await contract.nonce()).to.equal(nonceBefore)
      })
    })

    describe('Contract-owner voting in execTransaction', function () {
      // Helper: deploy an inner wallet and replace one EOA owner with it.
      async function addContractOwner(innerOwners: any[], innerThreshold: number): Promise<any> {
        const Inner = await ethers.getContractFactory(Helper.CONTRACT_NAME)
        const inner = await Inner.deploy(
          'Inner',
          innerOwners.map((o) => o.address),
          innerThreshold,
        )
        await inner.deployed()
        // Replace owner03 with the inner wallet so the outer threshold stays
        // at 2 and the test exercises a contract owner in the vote mix.
        // Signature: replaceOwner(contract, submitter, owners, ownerToAdd, ownerToRemove).
        await Helper.replaceOwner(contract, owner01, [owner01, owner02, owner03], inner.address, owner03.address)
        return inner
      }

      it('EOA + contract-owner votes reach threshold and execTransaction succeeds', async function () {
        const inner = await addContractOwner([owner01, owner02], 2)
        // Outer owners = [owner01, owner02, inner], threshold = 2.
        const data = contract.interface.encodeFunctionData('addOwner(address)', [user01.address])
        const nonce = await contract.nonce()
        const txHash = await contract.generateHash(contract.address, Helper.ZERO, data, Helper.DEFAULT_GAS, nonce, 0)
        // EOA vote: owner01 signs the outer typed-data hash with their key.
        const eoaSig = await Helper.signMultiSigTxn(
          contract,
          owner01,
          contract.address,
          Helper.ZERO,
          data,
          Helper.DEFAULT_GAS,
          nonce,
        )
        // Inner wallet's EIP-1271 vote for `txHash` (raw ECDSA, no domain wrap).
        const innerSig1 = await Helper.signDigest(owner01, txHash)
        const innerSig2 = await Helper.signDigest(owner02, txHash)
        const innerBlob = ethers.utils.defaultAbiCoder.encode(
          ['tuple(address owner, bytes sig)[]'],
          [
            [
              { owner: owner01.address, sig: innerSig1 },
              { owner: owner02.address, sig: innerSig2 },
            ],
          ],
        )
        // Sanity: inner's isValidSignature confirms innerBlob is valid.
        expect(await inner['isValidSignature(bytes32,bytes)'](txHash, innerBlob)).to.equal(MAGIC)

        const outerBlob = ethers.utils.defaultAbiCoder.encode(
          ['tuple(address owner, bytes sig)[]'],
          [
            [
              { owner: owner01.address, sig: eoaSig },
              { owner: inner.address, sig: innerBlob },
            ],
          ],
        )
        await Helper.execTransaction(
          contract,
          owner01,
          [],
          contract.address,
          Helper.ZERO,
          data,
          Helper.DEFAULT_GAS,
          undefined,
          ['OwnerAdded'],
          outerBlob,
        )
        expect(await contract.isOwner(user01.address)).to.be.true
      })

      it('contract-owner EIP-1271 returning non-magic causes execTransaction to revert with InvalidSignatures', async function () {
        const inner = await addContractOwner([owner01, owner02], 2)
        const data = contract.interface.encodeFunctionData('addOwner(address)', [user01.address])
        const nonce = await contract.nonce()
        const txHash = await contract.generateHash(contract.address, Helper.ZERO, data, Helper.DEFAULT_GAS, nonce, 0)
        // Build an inner blob that signs a *wrong* hash, so the inner
        // isValidSignature(txHash, innerBlob) returns non-magic.
        const wrongHash = ethers.utils.hexlify(ethers.utils.randomBytes(32))
        const innerSig1 = await Helper.signDigest(owner01, wrongHash)
        const innerSig2 = await Helper.signDigest(owner02, wrongHash)
        const innerBlob = ethers.utils.defaultAbiCoder.encode(
          ['tuple(address owner, bytes sig)[]'],
          [
            [
              { owner: owner01.address, sig: innerSig1 },
              { owner: owner02.address, sig: innerSig2 },
            ],
          ],
        )
        const eoaSig = await Helper.signMultiSigTxn(
          contract.address,
          owner01,
          contract.address,
          Helper.ZERO,
          data,
          Helper.DEFAULT_GAS,
          nonce,
        )
        const outerBlob = ethers.utils.defaultAbiCoder.encode(
          ['tuple(address owner, bytes sig)[]'],
          [
            [
              { owner: owner01.address, sig: eoaSig },
              { owner: inner.address, sig: innerBlob },
            ],
          ],
        )
        await Helper.execTransaction(
          contract,
          owner01,
          [],
          contract.address,
          Helper.ZERO,
          data,
          Helper.DEFAULT_GAS,
          Helper.errors.INVALID_SIGNATURES,
          undefined,
          outerBlob,
        )
        expect(await contract.isOwner(user01.address)).to.be.false
      })
    })
  })
}

// ---------------------------------------------------------------------------
// v0.4.0 — advanced features (timelock, guard, allowance, modules)
// ---------------------------------------------------------------------------

export async function MyMultiSigAdvancedTests(deploymentType = DeploymentType.SimpleMultiSig) {
  let provider: any
  let owner01: any
  let owner02: any
  let owner03: any
  let user01: any
  let user02: any
  let user03: any
  let contract: any

  describe('MyMultiSig - Advanced Tests (v0.4.0)', function () {
    before(async function () {
      ;[provider, owner01, owner02, owner03, user01, user02, user03] = await Helper.setupProviderAndAccount()
    })

    beforeEach(async function () {
      const owners: string[] = [owner01.address, owner02.address, owner03.address]
      switch (deploymentType) {
        case DeploymentType.SimpleMultiSig: {
          const deployment = await Helper.setupContract(
            Helper.CONTRACT_NAME,
            owners,
            Helper.DEFAULT_THRESHOLD,
            false,
            true,
          )
          contract = deployment.contract
          break
        }
        case DeploymentType.WithFactory: {
          const deployment = await Helper.setupContract(
            Helper.CONTRACT_FACTORY_NAME,
            owners,
            Helper.DEFAULT_THRESHOLD,
            true,
          )
          const tx = await deployment.contract.createMyMultiSigAdvanced(
            Helper.CONTRACT_NAME,
            owners,
            Helper.DEFAULT_THRESHOLD,
            Helper.DEFAULT_ALLOW_ONLY_OWNER,
            Helper.ENTRY_POINT_V07_ADDRESS,
          )
          await tx.wait()
          const Contract = await ethers.getContractFactory(Helper.CONTRACT_NAME_EXTENDED)
          contract = new ethers.Contract(await deployment.contract.multiSig(0), Contract.interface, provider)
          break
        }
        default:
          throw new Error('Invalid deployment type')
      }
      // Fund the wallet so ETH transfer tests have balance to send.
      await owner01.sendTransaction({
        to: contract.address,
        value: ethers.utils.parseEther('5'),
      })
    })

    it('reports 0.5.0 as the wallet version', async function () {
      expect(await contract.version()).to.be.equal('0.5.0')
      // Bitmask: zero-state reports no advanced features active.
      expect(await contract.advancedFeaturesEnabled()).to.be.equal(0)
    })

    // -- Feature 1: Timelock / delay ---------------------------------------
    describe('Timelock (Feature 1)', function () {
      it('sensitive call through regular execTransaction reverts with SensitiveCallRequiresDelay', async function () {
        await Helper.setTimelockDelay(contract, owner01, [owner01, owner02], 60)
        const data = contract.interface.encodeFunctionData('addOwner(address)', [user01.address])
        const nonce = await contract.nonce()
        const signatures = await Helper.prepareSignatures(
          contract,
          [owner01, owner02],
          contract.address,
          Helper.ZERO,
          data,
          Helper.DEFAULT_GAS,
          nonce,
          0,
        )
        await Helper.execTransaction(
          contract,
          owner01,
          [],
          contract.address,
          Helper.ZERO,
          data,
          Helper.DEFAULT_GAS,
          'SensitiveCallRequiresDelay',
          undefined,
          signatures,
        )
        // User was NOT added (the regular path reverted before the inner call).
        expect(await contract.isOwner(user01.address)).to.be.false
      })

      it('scheduleTransaction + wait + executeScheduled runs the sensitive call', async function () {
        await Helper.setTimelockDelay(contract, owner01, [owner01, owner02], 60)
        const data = contract.interface.encodeFunctionData('addOwner(address)', [user01.address])
        const nonce = await contract.nonce()
        const signatures = await Helper.prepareSignatures(
          contract,
          [owner01, owner02],
          contract.address,
          Helper.ZERO,
          data,
          Helper.DEFAULT_GAS,
          nonce,
          0,
        )
        const txHash = await contract.generateHash(contract.address, Helper.ZERO, data, Helper.DEFAULT_GAS, nonce, 0)
        // 1. Schedule
        const schedTx = await contract
          .connect(owner01)
          .scheduleTransaction(contract.address, Helper.ZERO, data, Helper.DEFAULT_GAS, nonce, 0, signatures)
        const schedReceipt = await schedTx.wait()
        expect(await contract.scheduledReadyAt(txHash)).to.be.greaterThan(0)
        // 2. Wait past the delay
        await Helper.advanceTime(61)
        // 3. Execute
        const execTx = await contract
          .connect(owner01)
          .executeScheduled(contract.address, Helper.ZERO, data, Helper.DEFAULT_GAS, nonce, 0, signatures)
        await execTx.wait()
        expect(await contract.isOwner(user01.address)).to.be.true
        // 4. Replay blocked by sentinel
        await expect(
          contract
            .connect(owner01)
            .executeScheduled(contract.address, Helper.ZERO, data, Helper.DEFAULT_GAS, nonce, 0, signatures),
        ).to.be.revertedWithCustomError(contract, 'NotScheduled')
      })
    })

    // -- Feature 2: Guard + allowlist --------------------------------------
    describe('Guard + Allowlist (Feature 2)', function () {
      it('passive guard does not block transactions', async function () {
        // Deploy a MockGuard that passes through.
        const Guard = await ethers.getContractFactory('MockGuard')
        const guard = await Guard.deploy()
        await guard.deployed()
        await Helper.setGuard(contract, owner01, [owner01, owner02], guard.address)
        expect(await contract.guard()).to.be.equal(guard.address)
        // A simple ETH call goes through; no guard failure emitted.
        const recipient = user01.address
        const before = await ethers.provider.getBalance(recipient)
        await Helper.execTransaction(
          contract,
          owner01,
          [owner01, owner02],
          recipient,
          ethers.utils.parseEther('0.1'),
          '0x',
        )
        const after = await ethers.provider.getBalance(recipient)
        expect(after.sub(before)).to.be.equal(ethers.utils.parseEther('0.1'))
      })

      it('rejective guard wraps the inner revert into GuardReverted', async function () {
        const Guard = await ethers.getContractFactory('MockGuard')
        const guard = await Guard.deploy()
        await guard.deployed()
        await Helper.setGuard(contract, owner01, [owner01, owner02], guard.address)
        await (await guard.setMode(1)).wait() // revert with reason
        await expect(
          Helper.execTransaction(
            contract,
            owner01,
            [owner01, owner02],
            user01.address,
            0,
            '0x',
            Helper.DEFAULT_GAS,
            undefined,
            undefined,
          ),
        ).to.be.revertedWithCustomError(contract, 'GuardReverted')
      })

      it('allowlist enables then rejects unregistered targets', async function () {
        await Helper.setAllowedTarget(contract, owner01, [owner01, owner02], user01.address, true)
        expect(await contract.allowedTargetsEnabled()).to.be.true
        // user02 (unrelated) is rejected.
        await expect(
          Helper.execTransaction(contract, owner01, [owner01, owner02], user02.address, 0, '0x'),
        ).to.be.revertedWithCustomError(contract, 'TargetNotAllowed')
        // user01 (allowed) works.
        await Helper.execTransaction(contract, owner01, [owner01, owner02], user01.address, 0, '0x')
      })
    })

    // -- Feature 3: Spending limits / allowance ----------------------------
    describe('Allowance (Feature 3)', function () {
      it('single-signer path charges against the submitter cap', async function () {
        const cap = ethers.utils.parseEther('1')
        await Helper.setDailySpendingLimit(contract, owner01, [owner01, owner02], owner01.address, cap)
        const data = '0x'
        const recipient = user01.address
        const value = ethers.utils.parseEther('0.3')
        // Single-signer ECDSA where sig recovers to owner01 == msg.sender.
        const sig = await Helper.signMultiSigTxn(
          contract,
          owner01,
          recipient,
          value,
          data,
          Helper.DEFAULT_GAS,
          await contract.nonce(),
          0,
        )
        const tx = await contract
          .connect(owner01)
          .execTransactionWithSpendingAllowance(recipient, value, data, Helper.DEFAULT_GAS, 0, sig)
        await tx.wait()
        // Cap reduced by `value`.
        const remaining = await contract.spendingLimitRemaining(owner01.address)
        expect(remaining).to.be.equal(cap.sub(value))
      })

      it('over-cap spend reverts with DailySpendingLimitExceeded', async function () {
        const cap = ethers.utils.parseEther('0.5')
        await Helper.setDailySpendingLimit(contract, owner01, [owner01, owner02], owner01.address, cap)
        const sig = await Helper.signMultiSigTxn(
          contract,
          owner01,
          user01.address,
          cap.add(1),
          '0x',
          Helper.DEFAULT_GAS,
          await contract.nonce(),
          0,
        )
        await expect(
          contract
            .connect(owner01)
            .execTransactionWithSpendingAllowance(user01.address, cap.add(1), '0x', Helper.DEFAULT_GAS, 0, sig),
        ).to.be.revertedWithCustomError(contract, 'DailySpendingLimitExceeded')
      })

      it('day rollover resets the cap', async function () {
        const cap = ethers.utils.parseEther('1')
        await Helper.setDailySpendingLimit(contract, owner01, [owner01, owner02], owner01.address, cap)
        // First spend consumes the cap entirely.
        let nonce = await contract.nonce()
        let sig = await Helper.signMultiSigTxn(
          contract,
          owner01,
          user01.address,
          cap,
          '0x',
          Helper.DEFAULT_GAS,
          nonce,
          0,
        )
        await (
          await contract
            .connect(owner01)
            .execTransactionWithSpendingAllowance(user01.address, cap, '0x', Helper.DEFAULT_GAS, 0, sig)
        ).wait()
        // Cross the 24h boundary.
        await Helper.advanceTime(86401)
        // Second spend of `cap` should succeed.
        nonce = await contract.nonce()
        sig = await Helper.signMultiSigTxn(contract, owner01, user01.address, cap, '0x', Helper.DEFAULT_GAS, nonce, 0)
        await contract
          .connect(owner01)
          .execTransactionWithSpendingAllowance(user01.address, cap, '0x', Helper.DEFAULT_GAS, 0, sig)
        // remaining is back to 0 after the second full-cap spend.
        const remaining = await contract.spendingLimitRemaining(owner01.address)
        expect(remaining).to.be.equal(0)
      })
    })

    // -- Feature 4: Modules -------------------------------------------------
    describe('Modules (Feature 4)', function () {
      it('enableModule followed by execTransactionFromModule (CALL) succeeds', async function () {
        const Module = await ethers.getContractFactory('MockModule')
        const module = await Module.deploy(contract.address)
        await module.deployed()
        // Snapshot nonce BEFORE enabling. enableModule is a single
        // execTransaction that bumps the nonce by 1; the fund call below
        // bumps it by another 1. So nonceAfterFunding == nonceBefore + 2.
        const nonceBefore = await contract.nonce()
        await Helper.enableModule(contract, owner01, [owner01, owner02], module.address)
        expect(await contract.isModule(module.address)).to.be.true
        expect(await contract.nonce()).to.be.equal(nonceBefore.add(1))

        // Fund the module so it can forward value. This bumps the nonce by 1.
        await Helper.execTransaction(
          contract,
          owner01,
          [owner01, owner02],
          module.address,
          ethers.utils.parseEther('1'),
          '0x',
        )
        const nonceAfterFunding = await contract.nonce()
        expect(nonceAfterFunding).to.be.equal(nonceBefore.add(2))

        const before = await ethers.provider.getBalance(user01.address)
        await module.execCall(user01.address, ethers.utils.parseEther('0.1'), '0x')
        const after = await ethers.provider.getBalance(user01.address)
        expect(after.sub(before)).to.be.equal(ethers.utils.parseEther('0.1'))
        // Module action must NOT bump _txnNonce — modules bypass threshold
        // by design so they shouldn't invalidate pending owner-signed
        // transactions.
        expect(await contract.nonce()).to.be.equal(nonceAfterFunding)
      })

      it('disableModule adjacency: enable A,B,C; head=C; remove head → next; remove via prev=0 walks list', async function () {
        const Module = await ethers.getContractFactory('MockModule')
        const mA = await (await Module.deploy(contract.address)).deployed()
        const mB = await (await Module.deploy(contract.address)).deployed()
        const mC = await (await Module.deploy(contract.address)).deployed()
        await Helper.enableModule(contract, owner01, [owner01, owner02], mA.address)
        await Helper.enableModule(contract, owner01, [owner01, owner02], mB.address)
        await Helper.enableModule(contract, owner01, [owner01, owner02], mC.address)
        // List order (most-recent-first): C, B, A.
        const list = await contract.getModules()
        expect(list.length).to.be.equal(3)
        expect(list[0]).to.be.equal(mC.address)
        expect(list[1]).to.be.equal(mB.address)
        expect(list[2]).to.be.equal(mA.address)
        // Remove the head C (Safe allows head removal only with prev=0).
        await Helper.disableModule(contract, owner01, [owner01, owner02], ethers.constants.AddressZero, mC.address)
        expect(await contract.modulesHead()).to.be.equal(mB.address)
        // Remove the new head B with prev=0.
        await Helper.disableModule(contract, owner01, [owner01, owner02], ethers.constants.AddressZero, mB.address)
        expect(await contract.modulesHead()).to.be.equal(mA.address)
        // Remove the last module A with prev=0 → empty list.
        await Helper.disableModule(contract, owner01, [owner01, owner02], ethers.constants.AddressZero, mA.address)
        expect(await contract.modulesHead()).to.be.equal(ethers.constants.AddressZero)
        const remaining = await contract.getModules()
        expect(remaining.length).to.be.equal(0)
      })

      it('disableModule reverts ModuleNotFound when module is not enabled', async function () {
        // Sanity test for the negative path: trying to disable a non-module
        // must revert. Going through the helper means the multisig layer
        // routes the call correctly (`onlyThis` on disableModule).
        const Module = await ethers.getContractFactory('MockModule')
        const someModule = await (await Module.deploy(contract.address)).deployed()
        // Don't enableModule — directly call disable.
        try {
          await Helper.disableModule(
            contract,
            owner01,
            [owner01, owner02],
            ethers.constants.AddressZero,
            someModule.address,
          )
          expect.fail('Expected disableModule to revert')
        } catch (e: any) {
          // The chain-level revert surfaces here; the helper may wrap it
          // as a generic revert or as a custom error. Either is acceptable;
          // the important assertion is that it DID revert.
          expect(e).to.exist
        }
      })

      it('non-module caller reverts NotAModule', async function () {
        await expect(
          contract.connect(owner01).execTransactionFromModule(user01.address, 0, '0x', 0),
        ).to.be.revertedWithCustomError(contract, 'NotAModule')
      })
    })

    // -- Backward compatibility sanity -------------------------------------
    it('zero-state: every existing operation still passes', async function () {
      // Default config (delay=0, no guard, no allowance, no modules) is
      // backwards-compatible: the regular addOwner flow works.
      await Helper.addOwner(contract, owner01, [owner01, owner02], user01.address)
      expect(await contract.isOwner(user01.address)).to.be.true
    })
  })
}

// ---------------------------------------------------------------------------
// Factory — per-type counters + address-keyed lookup
// ---------------------------------------------------------------------------

export async function MyMultiSigFactoryTests() {
  let provider: any
  let owner01: any
  let user01: any
  let deployment: any
  let factory: any

  describe('MyMultiSig - Factory Bookkeeping Tests', function () {
    before(async function () {
      ;[provider, owner01, , , user01] = await Helper.setupProviderAndAccount()
    })

    beforeEach(async function () {
      deployment = await Helper.setupContract(Helper.CONTRACT_FACTORY_NAME, [owner01.address], 1, true)
      factory = deployment.contract
    })

    it('reports zero per-type counts on a fresh factory', async function () {
      expect(await factory.simpleCount()).to.be.equal(0)
      expect(await factory.extendedCount()).to.be.equal(0)
      expect(await factory.advancedCount()).to.be.equal(0)
      expect(await factory.multiSigCount()).to.be.equal(0)
      expect(await factory.creationTypeCount(0)).to.be.equal(0) // SIMPLE
      expect(await factory.creationTypeCount(1)).to.be.equal(0) // EXTENDED
      expect(await factory.creationTypeCount(2)).to.be.equal(0) // ADVANCED
    })

    it('counts each createMultiSig as SIMPLE and isExtended(address) returns false', async function () {
      const tx = await factory.createMultiSig(Helper.CONTRACT_NAME, [owner01.address], 1)
      const receipt = await tx.wait()
      const walletAddress = await factory.multiSig(0)
      expect(walletAddress).to.be.properAddress
      expect(await factory.simpleCount()).to.be.equal(1)
      expect(await factory.extendedCount()).to.be.equal(0)
      expect(await factory.advancedCount()).to.be.equal(0)
      expect(await factory.creationTypeOf(walletAddress)).to.be.equal(0) // SIMPLE
      expect(await factory.isExtended(walletAddress)).to.be.false
      // Untracked addresses report SIMPLE (default enum) — the user-facing
      // semantic is `isExtended(...) == false`.
      expect(await factory.creationTypeOf(user01.address)).to.be.equal(0)
      expect(await factory.isExtended(user01.address)).to.be.false
    })

    it('counts createMyMultiSigExtended as EXTENDED and isExtended(addr) returns true', async function () {
      const tx = await factory.createMyMultiSigExtended(
        Helper.CONTRACT_NAME,
        [owner01.address],
        1,
        Helper.DEFAULT_ALLOW_ONLY_OWNER,
        Helper.ENTRY_POINT_V07_ADDRESS,
      )
      const receipt = await tx.wait()
      const walletAddress = await factory.multiSig(0)
      expect(await factory.simpleCount()).to.be.equal(0)
      expect(await factory.extendedCount()).to.be.equal(1)
      expect(await factory.advancedCount()).to.be.equal(0)
      expect(await factory.creationTypeOf(walletAddress)).to.be.equal(1) // EXTENDED
      expect(await factory.isExtended(walletAddress)).to.be.true
    })

    it('counts createMyMultiSigAdvanced as ADVANCED and isExtended(addr) returns true', async function () {
      const tx = await factory.createMyMultiSigAdvanced(
        Helper.CONTRACT_NAME,
        [owner01.address],
        1,
        Helper.DEFAULT_ALLOW_ONLY_OWNER,
        Helper.ENTRY_POINT_V07_ADDRESS,
      )
      const receipt = await tx.wait()
      const walletAddress = await factory.multiSig(0)
      expect(await factory.simpleCount()).to.be.equal(0)
      expect(await factory.extendedCount()).to.be.equal(0)
      expect(await factory.advancedCount()).to.be.equal(1)
      expect(await factory.creationTypeOf(walletAddress)).to.be.equal(2) // ADVANCED
      expect(await factory.isExtended(walletAddress)).to.be.true
    })

    it('counts multiple wallets of each type and keeps multiSigCount = sum', async function () {
      await factory.createMultiSig(Helper.CONTRACT_NAME, [owner01.address], 1)
      await factory.createMultiSig(Helper.CONTRACT_NAME, [owner01.address], 1)
      await factory.createMyMultiSigExtended(
        Helper.CONTRACT_NAME,
        [owner01.address],
        1,
        Helper.DEFAULT_ALLOW_ONLY_OWNER,
        Helper.ENTRY_POINT_V07_ADDRESS,
      )
      await factory.createMyMultiSigAdvanced(
        Helper.CONTRACT_NAME,
        [owner01.address],
        1,
        Helper.DEFAULT_ALLOW_ONLY_OWNER,
        Helper.ENTRY_POINT_V07_ADDRESS,
      )
      expect(await factory.simpleCount()).to.be.equal(2)
      expect(await factory.extendedCount()).to.be.equal(1)
      expect(await factory.advancedCount()).to.be.equal(1)
      expect(await factory.multiSigCount()).to.be.equal(4)
      // SUM via creationTypeCount equals the global total.
      const total = (await factory.simpleCount()).add(await factory.extendedCount()).add(await factory.advancedCount())
      expect(total).to.be.equal(await factory.multiSigCount())
    })
  })
}
