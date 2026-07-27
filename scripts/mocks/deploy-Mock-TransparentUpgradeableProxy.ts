import { existsSync, readFileSync, writeFileSync } from 'fs'
import { network } from 'hardhat'

const connection = await network.connect()
const { ethers } = connection

const ADDRESS_BOOK_FILE = 'contractsAddressDeployed.json'

const readAddressBook = (): any[] => {
  if (!existsSync(ADDRESS_BOOK_FILE)) return []
  try {
    return JSON.parse(readFileSync(ADDRESS_BOOK_FILE, 'utf8'))
  } catch {
    return []
  }
}

const writeAddressBook = (entries: any[]) => {
  writeFileSync(ADDRESS_BOOK_FILE, JSON.stringify(entries, null, 2) + '\n')
}

const saveContract = (name: string, address: string, netName: string, deployer: string) => {
  const entries = readAddressBook().filter((e) => !(e.name === name && e.network === netName))
  entries.unshift({
    name,
    address,
    network: netName,
    deployer,
    deploymentDate: new Date(),
    chainId: 0,
    blockHash: '',
    blockNumber: 0,
    tag: '',
    extra: {},
  })
  writeAddressBook(entries)
}

const retrieveContract = (name: string, netName: string): string => {
  const entries = readAddressBook()
  const match = entries.find((e) => e.name === name && e.network === netName)
  return match ? match.address : ''
}

async function main() {
  const [deployer] = await ethers.getSigners()

  const localNetworks = new Set(['hardhat', 'localhost'])
  const isLocal = localNetworks.has(network.name)

  let logicContract = ''
  if (!isLocal) {
    logicContract = retrieveContract('MockERC20Upgradeable', network.name)
    if (!logicContract) logicContract = retrieveContract('MockERC721Upgradeable', network.name)
    if (!logicContract) logicContract = retrieveContract('MockERC1155Upgradeable', network.name)
  }
  if (!logicContract) {
    const MockERC20Upgradeable = await ethers.getContractFactory('MockERC20Upgradeable')
    const mockERC20Upgradeable = await MockERC20Upgradeable.deploy()

    await mockERC20Upgradeable.waitForDeployment()
    const logicAddr = mockERC20Upgradeable.target ?? mockERC20Upgradeable.address
    saveContract('MockERC20Upgradeable', logicAddr, network.name, deployer.address)
    await mockERC20Upgradeable.initialize('MockERC20Upgradeable', 'MOCK')

    console.log('MockERC20Upgradeable deployed to:', logicAddr)
    logicContract = logicAddr
  }
  let proxyAdminContract = ''
  if (!isLocal) {
    proxyAdminContract = retrieveContract('MockERC20Upgradeable', network.name)
  }
  if (!proxyAdminContract) {
    const MockProxyAdmin = await ethers.getContractFactory('MockProxyAdmin')
    const mockProxyAdmin = await MockProxyAdmin.deploy()

    await mockProxyAdmin.waitForDeployment()
    const adminAddr = mockProxyAdmin.target ?? mockProxyAdmin.address
    saveContract('MockProxyAdmin', adminAddr, network.name, deployer.address)

    console.log('MockProxyAdmin deployed to:', adminAddr)
    proxyAdminContract = adminAddr
  }

  const MockTransparentUpgradeableProxy = await ethers.getContractFactory('MockTransparentUpgradeableProxy')
  const mockTransparentUpgradeableProxy = await MockTransparentUpgradeableProxy.deploy(
    logicContract,
    proxyAdminContract,
    '0x'
  )

  await mockTransparentUpgradeableProxy.waitForDeployment()
  const proxyAddr = mockTransparentUpgradeableProxy.target ?? mockTransparentUpgradeableProxy.address
  saveContract('MockTransparentUpgradeableProxy', proxyAddr, network.name, deployer.address)

  console.log('MockTransparentUpgradeableProxy deployed to:', proxyAddr)
}

main().catch((error) => {
    console.error(error)
    process.exitCode = 1
})
