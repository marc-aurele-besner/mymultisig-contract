import { ethers } from 'hardhat'

async function main() {
  const MyMultiSig = await ethers.getContractFactory('MyMultiSig')
  const myMultiSig = await MyMultiSig.deploy()

  await myMultiSig.deployed()

  console.log(`Contract MyMultiSig deployed to ${myMultiSig.address}`)
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
