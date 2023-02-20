import { ethers } from 'hardhat'

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

  if (process.env.METAMASK_TEST_WALLET01 === undefined) throw new Error('METAMASK_TEST_WALLET01 is undefined')
  if (process.env.METAMASK_TEST_WALLET02 === undefined) throw new Error('METAMASK_TEST_WALLET02 is undefined')
  if (process.env.METAMASK_TEST_WALLET03 === undefined) throw new Error('METAMASK_TEST_WALLET03 is undefined')

  await owner01.sendTransaction({
    to: process.env.METAMASK_TEST_WALLET01,
    value: ethers.utils.parseEther('1'),
  })
  console.log(`Transfer Eth to ${process.env.METAMASK_TEST_WALLET01}`)

  await owner01.sendTransaction({
    to: process.env.METAMASK_TEST_WALLET02,
    value: ethers.utils.parseEther('1'),
  })
  console.log(`Transfer Eth to ${process.env.METAMASK_TEST_WALLET02}`)

  await owner01.sendTransaction({
    to: process.env.METAMASK_TEST_WALLET03,
    value: ethers.utils.parseEther('1'),
  })
  console.log(`Transfer Eth to ${process.env.METAMASK_TEST_WALLET03}`)
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
