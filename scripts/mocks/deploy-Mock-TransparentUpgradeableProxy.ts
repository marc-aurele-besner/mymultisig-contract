import { existsSync, readFileSync, writeFileSync } from 'fs'
import { network } from 'hardhat'

const connection = await network.getOrCreate()
const { ethers } = connection
const networkName = connection.networkName

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

  const localNetworks = new Set(['default', 'hardhat', 'localhost'])
  const isLocal = localNetworks.has(networkName)

  let logicContract = ''
  if (!isLocal) {
    logicContract = retrieveContract('MockERC20Upgradeable', networkName)
    if (!logicContract) logicContract = retrieveContract('MockERC721Upgradeable', networkName)
    if (!logicContract) logicContract = retrieveContract('MockERC1155Upgradeable', networkName)
  }
  if (!logicContract) {
    const MockERC20Upgradeable = await ethers.getContractFactory('MockERC20Upgradeable')
    const mockERC20Upgradeable = await MockERC20Upgradeable.deploy()

    await mockERC20Upgradeable.waitForDeployment()
    const logicAddr = await mockERC20Upgradeable.getAddress()
    saveContract('MockERC20Upgradeable', logicAddr, networkName, deployer.address)
    await mockERC20Upgradeable.initialize('MockERC20Upgradeable', 'MOCK')

    console.log('MockERC20Upgradeable deployed to:', logicAddr)
    logicContract = logicAddr
  }
  let proxyAdminContract = ''
  if (!isLocal) {
    proxyAdminContract = retrieveContract('MockERC20Upgradeable', networkName)
  }
  if (!proxyAdminContract) {
    const MockProxyAdmin = await ethers.getContractFactory('MockProxyAdmin')
    const mockProxyAdmin = await MockProxyAdmin.deploy()

    await mockProxyAdmin.waitForDeployment()
    const adminAddr = await mockProxyAdmin.getAddress()
    saveContract('MockProxyAdmin', adminAddr, networkName, deployer.address)

    console.log('MockProxyAdmin deployed to:', adminAddr)
    proxyAdminContract = adminAddr
  }

  const MockTransparentUpgradeableProxy = await ethers.getContractFactory('MockTransparentUpgradeableProxy')
  const mockTransparentUpgradeableProxy = await MockTransparentUpgradeableProxy.deploy(
    logicContract,
    proxyAdminContract,
    '0x',
  )

  await mockTransparentUpgradeableProxy.waitForDeployment()
  const proxyAddr = await mockTransparentUpgradeableProxy.getAddress()
  saveContract('MockTransparentUpgradeableProxy', proxyAddr, networkName, deployer.address)

  console.log('MockTransparentUpgradeableProxy deployed to:', proxyAddr)
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
