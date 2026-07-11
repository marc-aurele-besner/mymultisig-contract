import { ethers, network } from 'hardhat'
import Helper from '../test/shared'

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
  console.log(`Contract MyMultiSig Factory deployed to ${contract.address}`)
  console.log(`  -> MyMultiSigDeployer:        ${myMultiSigDeployer.address}`)
  console.log(`  -> MyMultiSigExtendedDeployer: ${myMultiSigExtendedDeployer.address}`)
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
