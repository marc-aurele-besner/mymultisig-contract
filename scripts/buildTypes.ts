import { existsSync, rmSync, mkdirSync, copyFileSync, readdirSync } from 'fs'

import constants from '../constants'

// The committed `types/` layout is flat: wallet/factory/deployer classes from
// `contracts/`, their interfaces from `contracts/interfaces/` and the factory
// abstract from `contracts/abstracts/` all sit side by side.
// In Hardhat 3 / `@typechain/hardhat@9` the generated layout drops the
// wrapping `contracts/` directory, so we read from the top-level source
// directories directly.
const TYPE_SOURCE_DIRS = [
  'typechain-types/',
  'typechain-types/abstracts/',
  'typechain-types/interfaces/',
  'typechain-types/mocks/',
  'typechain-types/modules/',
  'typechain-types/test/',
]

async function main() {
  if (existsSync('types')) rmSync('types', { recursive: true })

  for (const sourceDir of TYPE_SOURCE_DIRS) {
    if (!existsSync(sourceDir)) continue
    const allTypesPaths = readdirSync(sourceDir)
    const filteredTypesPaths = allTypesPaths.filter(
      (path: string) => path.includes(constants.CONTRACT_NAME) && !path.includes('.t.sol')
    )
    if (filteredTypesPaths.length === 0) continue
    console.log('\x1b[32m', 'Building typess for ', filteredTypesPaths.length, '\x1b[0m', ' contracts')
    filteredTypesPaths.forEach((file: string) => {
      const path = sourceDir + file
      if (existsSync(path)) {
        if (!existsSync('types')) mkdirSync('types')
        const newFilePath = 'types/' + file
        copyFileSync(path, newFilePath)
        console.log('\x1b[32m', 'Build types for ', '\x1b[0m', file, ' to ', '\x1b[34m', newFilePath, '\x1b[0m')
      }
    })
  }
  console.log('\x1b[32m', 'Done building types', '\x1b[0m')
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
