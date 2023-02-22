import { clarity } from 'hardhat'

import Helper from '../test/shared'

async function main() {
  if (!process.env.OPENAI_API_KEY) throw new Error('Please set your OPENAI_API_KEY in a .env file')

  await clarity.clarity('contracts/' + Helper.CONTRACT_FACTORY_NAME + '.sol')

  await clarity.readme()
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
