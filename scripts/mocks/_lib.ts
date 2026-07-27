import { existsSync, readFileSync, writeFileSync } from 'fs'
import { network } from 'hardhat'

export const ADDRESS_BOOK_FILE = 'contractsAddressDeployed.json'

export const readAddressBook = (): any[] => {
  if (!existsSync(ADDRESS_BOOK_FILE)) return []
  try {
    return JSON.parse(readFileSync(ADDRESS_BOOK_FILE, 'utf8'))
  } catch {
    return []
  }
}

export const writeAddressBook = (entries: any[]) => {
  writeFileSync(ADDRESS_BOOK_FILE, JSON.stringify(entries, null, 2) + '\n')
}

export const saveContract = (name: string, address: string, netName: string, deployer: string) => {
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

export const connection = await network.getOrCreate()

export const deployAndSave = async (factoryName: string, init?: (...args: any[]) => Promise<unknown>) => {
  const { ethers } = connection
  const [deployer] = await ethers.getSigners()
  const Factory = await ethers.getContractFactory(factoryName)
  const deployed = await Factory.deploy()
  await deployed.waitForDeployment()
  const addr = await deployed.getAddress()
  saveContract(factoryName, addr, connection.networkName, deployer.address)
  if (init) await init(deployed)
  console.log(`${factoryName} deployed to:`, addr)
}
