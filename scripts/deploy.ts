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

  const owners: string[] = [owner01.address, owner02.address, owner03.address]
  ownerCount = owners.length
  deployment = await Helper.setupContract(
    Helper.CONTRACT_FACTORY_NAME,
    [owner01.address, owner02.address, owner03.address],
    2,
    true
  )
  contract = deployment.contract

  console.log(`Contract MyMultiSig Factory deployed to ${contract.address}`)
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
