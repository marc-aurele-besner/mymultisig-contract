// v2's `hardhat/functionList` plugin is gone in Hardhat 3. List
// selectors directly from the compiled artifacts instead.
import { existsSync, readdirSync, readFileSync } from 'fs'

import constants from '../constants'

const { Interface } = await import('ethers')

const collectSelectors = (artifactPath: string): { name: string; selector: string; signature: string }[] => {
  const artifact = JSON.parse(readFileSync(artifactPath, 'utf8'))
  const iface = new Interface(artifact.abi)
  return artifact.abi
    .filter((entry: any) => entry.type === 'function')
    .map((entry: any) => {
      const sig = `${entry.name}(${entry.inputs.map((i: any) => i.type).join(',')})`
      return {
        name: entry.name,
        selector: iface.getFunction(entry.name)!.selector,
        signature: sig,
      }
    })
}

async function main() {
  if (!existsSync('abi')) {
    console.error('Run `yarn build` first to generate abi/.')
    process.exit(1)
  }
  const abiFiles = readdirSync('abi').filter((f) => f.endsWith('.json'))
  for (const f of abiFiles) {
    const name = f.replace('.json', '')
    if (!name.includes(constants.CONTRACT_NAME)) continue
    const selectors = collectSelectors(`abi/${f}`)
    const report = selectors.map((s) => `  ${s.selector}  ${s.signature}`).join('\n')
    console.log(`\n${name} (${selectors.length} selectors):\n${report}`)
  }
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
