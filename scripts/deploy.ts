import { ethers, network } from 'hardhat'
import Helper from '../test/shared'
import v2_5Constants from '../constants/v2_5'

let provider: any
let owner01: any
let owner02: any
let owner03: any
let ownerCount: number
let user01: any
let user02: any
let user03: any
let deployment: any
let contract: any

async function main() {
  ;[provider, owner01, owner02, owner03, user01, user02, user03] = await Helper.setupProviderAndAccount()

  console.log('Owners: ', owner01.address, owner02.address, owner03.address)

  const owners: string[] = [owner01.address, owner02.address, owner03.address]
  ownerCount = owners.length
  deployment = await Helper.setupContract(
    Helper.CONTRACT_FACTORY_NAME,
    [owner01.address, owner02.address, owner03.address],
    2,
    true
  )
  contract = deployment.contract

  // The factory delegates the actual `new MyMultiSig(...)` /
  // `new MyMultiSigExtended(...)` work to two tiny helper deployer contracts
  // so it doesn't have to embed their bytecode. Surface their addresses so
  // the operator can verify the deployment matches the artifacts.
  const myMultiSigDeployer = await ethers.getContractAt('MyMultiSigDeployer', await contract.myMultiSigDeployer())
  const myMultiSigExtendedDeployer = await ethers.getContractAt(
    'MyMultiSigExtendedDeployer',
    await contract.myMultiSigExtendedDeployer()
  )

  // v0.5.0 surface — surface the V2_5 implementation + V2_5 deployer so
  // the operator can confirm CREATE2 wallets resolve to the same
  // address on every chain. The canonical CREATE2 deployer + factory
  // salt are also logged here so operators can re-run the same deploy
  // through the CREATE2 path on chains where the canonical deployer is
  // pre-funded.
  const myMultiSigV2_5Impl = await contract.myMultiSigV2_5Impl()
  const myMultiSigV2_5Deployer = await contract.myMultiSigV2_5Deployer()

  console.log(`Contract MyMultiSig Factory deployed to ${contract.address}`)
  console.log(`  -> MyMultiSigDeployer:        ${myMultiSigDeployer.address}`)
  console.log(`  -> MyMultiSigExtendedDeployer: ${myMultiSigExtendedDeployer.address}`)
  console.log(`  -> MyMultiSigV2_5Deployer:     ${myMultiSigV2_5Deployer}`)
  console.log(`  -> MyMultiSigV2_5Impl:         ${myMultiSigV2_5Impl}`)
  console.log(`v0.5.0 deploy helpers:`)
  console.log(`  -> Canonical CREATE2 deployer: ${v2_5Constants.CANONICAL_CREATE2_DEPLOYER}`)
  console.log(`  -> Factory salt (hex):         ${Buffer.from(v2_5Constants.FACTORY_SALT).toString('hex')}`)
  console.log(`  -> EntryPoint v0.7 address:    ${v2_5Constants.ENTRY_POINT_V07_ADDRESS}`)
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
