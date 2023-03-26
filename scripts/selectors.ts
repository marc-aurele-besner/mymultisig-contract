import { functionList } from 'hardhat'

import Helper from '../test/shared'

async function main() {
  await functionList.listSelectors(Helper.CONTRACT_FACTORY_NAME)
  await functionList.listSelectors(Helper.CONTRACT_NAME)
  await functionList.listSelectors(Helper.CONTRACT_NAME + 'Extended')
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
