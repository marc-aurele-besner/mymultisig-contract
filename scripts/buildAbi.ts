import { existsSync, mkdirSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from 'fs'
import { join } from 'path'

import constants from '../constants'

// v3's `artifacts` manager exposes `readArtifact` / `getArtifactPath` but no
// `getArtifactPaths`, so walk `artifacts/contracts/**/*.json` directly to
// surface every ABI the compile produced.
const collectArtifactPaths = (rootDir: string): string[] => {
  const results: string[] = []
  const walk = (dir: string) => {
    for (const entry of readdirSync(dir)) {
      const full = join(dir, entry)
      const stat = statSync(full)
      if (stat.isDirectory()) walk(full)
      else if (entry.endsWith('.json') && !entry.endsWith('.dbg.json') && !entry.endsWith('build-info.json'))
        results.push(full)
    }
  }
  walk(rootDir)
  return results
}

async function main() {
  if (existsSync('abi')) {
    rmSync('abi', { recursive: true })
  }

  const allArtifactPaths = collectArtifactPaths('artifacts/contracts')
  const filteredArtifactPaths = allArtifactPaths.filter((path: string) => path.includes(constants.CONTRACT_NAME))
  console.log('\x1b[32m', "Building ABI's for ", filteredArtifactPaths.length, '\x1b[0m', ' contracts')
  filteredArtifactPaths.forEach((path: string) => {
    if (existsSync(path)) {
      const file = JSON.parse(readFileSync(path, 'utf8'))
      if (!existsSync('abi')) mkdirSync('abi')
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
