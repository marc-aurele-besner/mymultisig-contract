import { expect } from 'chai'
import { network } from 'hardhat'

const { ethers } = await network.connect()

let mockERC721Upgradeable: any
let deployer: any

describe('MockERC721UpgradeableUpgradeable', function () {
  beforeEach(async function () {
    ;[deployer] = await ethers.getSigners()

    const MockERC721Upgradeable = await ethers.getContractFactory('MockERC721Upgradeable')
    mockERC721Upgradeable = await MockERC721Upgradeable.deploy()
    await mockERC721Upgradeable.waitForDeployment()
    await mockERC721Upgradeable.initialize('MockERC721Upgradeable', 'MOCK')
  })

  it('Should return the name of the token', async function () {
    expect(await mockERC721Upgradeable.name()).to.equal('MockERC721Upgradeable')
  })

  it('Should return the symbol of the token', async function () {
    expect(await mockERC721Upgradeable.symbol()).to.equal('MOCK')
  })
})
