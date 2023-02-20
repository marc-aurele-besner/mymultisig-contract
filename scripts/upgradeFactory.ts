import { ethers, addressBook, network, upgrades } from 'hardhat'

import Helper from '../test/shared'

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

async function main() {
  ;[provider, owner01, owner02, owner03, user01, user02, user03] = await Helper.setupProviderAndAccount()

  const proxyAddress = addressBook.retrieveContract(Helper.CONTRACT_FACTORY_NAME, network.name)

  if (proxyAddress === undefined) {
    throw new Error(`Proxy address not found for ${Helper.CONTRACT_FACTORY_NAME} on ${network.name}`)
  }

  const MyMultiSigFactory = await ethers.getContractFactory(Helper.CONTRACT_FACTORY_NAME)
  const contract = await upgrades.upgradeProxy(proxyAddress, MyMultiSigFactory)

  console.log(`Contract MyMultiSig Factory upgraded to ${contract.address}`)
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
