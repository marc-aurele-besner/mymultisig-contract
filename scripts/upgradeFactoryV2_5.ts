import { ethers, addressBook, network, upgrades } from 'hardhat'

import Helper from '../test/shared'

// `upgradeFactoryV2_5` runs after `upgradeFactory` has swapped the
// implementation to the v0.5.0 build. It calls `reinitializeV2_5()` on
// the proxy to record the layout version (`reinitializer(2)`) so chains
// that already had the v0.4.0 factory deployed don't need to redeploy.
//
// Idempotent: calling this twice is a no-op because reinitializer(2)
// refuses to run when the proxy is already on version 2.

let provider: any
let owner01: any

async function main() {
  ;[provider, owner01] = await Helper.setupProviderAndAccount()

  const proxyAddress = addressBook.retrieveContract(Helper.CONTRACT_FACTORY_NAME, network.name)

  if (proxyAddress === undefined) {
    throw new Error(`Proxy address not found for ${Helper.CONTRACT_FACTORY_NAME} on ${network.name}`)
  }

  const MyMultiSigFactory = await ethers.getContractFactory(Helper.CONTRACT_FACTORY_NAME)
  const contract = await upgrades.upgradeProxy(proxyAddress, MyMultiSigFactory)

  // `reinitializeV2_5` only succeeds on chains that have NOT yet been
  // reinitialized for v0.5.0. The OpenZeppelin reinitializer(2)
  // modifier handles this for us — second invocation reverts.
  try {
    const tx = await contract.reinitializeV2_5()
    await tx.wait()
    console.log(`reinitializeV2_5() succeeded on ${network.name} at ${contract.address}`)
  } catch (e: any) {
    console.log(`reinitializeV2_5() skipped (already reinitialized or no permission): ${e?.message ?? e}`)
  }

  console.log(`Contract MyMultiSig Factory upgraded to ${contract.address}`)
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
