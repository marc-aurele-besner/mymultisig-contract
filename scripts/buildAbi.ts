import { artifacts } from 'hardhat'
import { existsSync, rmdirSync, mkdirSync, readFileSync, writeFileSync } from 'fs'

import constants from '../constants'

async function main() {
  if (existsSync('abi')) rmdirSync('abi', { recursive: true })

  const allArtifactPaths = await artifacts.getArtifactPaths()
  const filteredArtifactPaths = allArtifactPaths.filter((path: string) => path.includes(constants.CONTRACT_NAME))
  console.log('\x1b[32m', "Building ABI's for ", filteredArtifactPaths.length, '\x1b[0m', ' contracts')
  filteredArtifactPaths.forEach((path: string) => {
    // detect if file exists
    if (existsSync(path)) {
      // parse file
      const file = JSON.parse(readFileSync(path, 'utf8'))
      // if abi/ does not exist, create it
      if (!existsSync('abi')) mkdirSync('abi')
      // write file
      const filePath = 'abi/' + file.contractName + '.json'
      writeFileSync(filePath, JSON.stringify(file.abi, null, 2))
      console.log('\x1b[32m', 'Build ABI for ', '\x1b[0m', file.contractName, ' to ', '\x1b[34m', filePath, '\x1b[0m')
    }
  })
  console.log('\x1b[32m', "Done building ABI's", '\x1b[0m')
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
