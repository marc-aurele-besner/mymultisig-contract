import { artifacts } from 'hardhat'
import { existsSync, rmSync, mkdirSync, copyFileSync, readdirSync } from 'fs'

import constants from '../constants'

async function main() {
  if (existsSync('types')) rmSync('types', { recursive: true })

  // get all types paths from typechain-types
  const allTypesPaths = readdirSync('typechain-types/contracts/')
  const filteredTypesPaths = allTypesPaths.filter(
    (path: string) => path.includes(constants.CONTRACT_NAME) && !path.includes('.t.sol')
  )
  console.log('\x1b[32m', 'Building typess for ', filteredTypesPaths.length, '\x1b[0m', ' contracts')
  filteredTypesPaths.forEach((file: string) => {
    const path = 'typechain-types/contracts/' + file
    // detect if file exists
    if (existsSync(path)) {
      // if types/ does not exist, create it
      if (!existsSync('types')) mkdirSync('types')
      // copy file
      const newFilePath = 'types/' + file
      copyFileSync(path, newFilePath)
      console.log('\x1b[32m', 'Build types for ', '\x1b[0m', file, ' to ', '\x1b[34m', newFilePath, '\x1b[0m')
    }
  })
  console.log('\x1b[32m', 'Done building types', '\x1b[0m')
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
