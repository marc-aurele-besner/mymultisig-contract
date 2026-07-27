import { existsSync, readFileSync } from 'fs'
import { network } from 'hardhat'

import Helper from '../test/shared'

const connection = await network.connect()
const { ethers } = connection

let provider: any
let owner01: any
let owner02: any
let owner03: any
let user01: any
let user02: any
let user03: any

const retrieveContractAddress = (contractName: string, netName: string): string => {
  const file = 'contractsAddressDeployed.json'
  if (!existsSync(file)) return ''
  const entries = JSON.parse(readFileSync(file, 'utf8')) as Array<{ name: string; network: string; address: string }>
  const match = entries.find((e) => e.name === contractName && e.network === netName)
  return match ? match.address : ''
}

async function main() {
  ;[provider, owner01, owner02, owner03, user01, user02, user03] = await Helper.setupProviderAndAccount()

  const proxyAddress = retrieveContractAddress(Helper.CONTRACT_FACTORY_NAME, network.name)

  if (!proxyAddress) {
    throw new Error(`Proxy address not found for ${Helper.CONTRACT_FACTORY_NAME} on ${network.name}`)
  }

  // The Hardhat v3 ecosystem lacks a v3 `@openzeppelin/hardhat-upgrades`
  // plugin, so this script can't perform an in-place upgrade: an upgrade
  // requires the OZ upgrades plugin's storage-layout safety checks. The
  // operator must deploy a fresh implementation behind a new proxy and
  // migrate, OR use the OZ upgrades CLI tooling outside Hardhat.
  const MyMultiSigFactory = await ethers.getContractFactory(Helper.CONTRACT_FACTORY_NAME)

  console.log(`To upgrade MyMultiSig Factory at ${proxyAddress}, deploy a new implementation with:`)
  console.log(`  ${MyMultiSigFactory.interface.encodeFunctionData('initialize')}`)
  console.log(`then re-run the deploy script with the new implementation address.`)
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
