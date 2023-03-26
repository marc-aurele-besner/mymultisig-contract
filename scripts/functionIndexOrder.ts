import { ethers } from 'hardhat'

import Helper from '../test/shared'

type Function = {
  name: string
  signature: string
}

const getFunctionsSignatureInHexOrder = async (contractName: string) => {
  console.log('Contract: ', contractName)
  const factory = await ethers.getContractFactory(contractName)

  const functions: Function[] = []
  for (const [name] of Object.entries(factory.interface.functions)) {
    functions.push({
      name,
      signature: ethers.utils.id(name).substring(0, 10),
    })
  }
  functions.sort((a, b) => {
    return a.signature.localeCompare(b.signature)
  })
  return functions
}

async function main() {
  console.table(await getFunctionsSignatureInHexOrder(Helper.CONTRACT_FACTORY_NAME))

  console.table(await getFunctionsSignatureInHexOrder(Helper.CONTRACT_NAME))

  console.table(await getFunctionsSignatureInHexOrder(Helper.CONTRACT_NAME + 'Extended'))
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
