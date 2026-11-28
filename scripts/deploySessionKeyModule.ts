import { network } from 'hardhat'

import {
  CANONICAL_CREATE2_DEPLOYER,
  SESSION_KEY_MODULE_ADDRESS,
  SESSION_KEY_MODULE_INIT_CODE,
  SESSION_KEY_MODULE_SALT,
} from '../constants/sessionKeyModule'

// Deploys the shared SessionKeyModule at its fixed CREATE2 address on the
// selected network. Idempotent: a chain that already has code at the address
// is left alone. Usage: `npx hardhat run scripts/deploySessionKeyModule.ts --network sepolia`
const { ethers } = await network.getOrCreate()

async function main() {
  if ((await ethers.provider.getCode(SESSION_KEY_MODULE_ADDRESS)) !== '0x') {
    console.log(`SessionKeyModule already deployed at ${SESSION_KEY_MODULE_ADDRESS}`)
    return
  }
  if ((await ethers.provider.getCode(CANONICAL_CREATE2_DEPLOYER)) === '0x') {
    throw new Error(`The canonical CREATE2 deployer ${CANONICAL_CREATE2_DEPLOYER} is not deployed on this network`)
  }
  const [sender] = await ethers.getSigners()
  const tx = await sender.sendTransaction({
    to: CANONICAL_CREATE2_DEPLOYER,
    data: ethers.concat([SESSION_KEY_MODULE_SALT, SESSION_KEY_MODULE_INIT_CODE]),
  })
  console.log(`Deploying SessionKeyModule (tx ${tx.hash})`)
  await tx.wait()
  if ((await ethers.provider.getCode(SESSION_KEY_MODULE_ADDRESS)) === '0x') {
    throw new Error(`Deployment did not produce code at ${SESSION_KEY_MODULE_ADDRESS}`)
  }
  console.log(`SessionKeyModule deployed at ${SESSION_KEY_MODULE_ADDRESS}`)
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
