import { expect } from 'chai'
import { network } from 'hardhat'

import {
  CANONICAL_CREATE2_DEPLOYER,
  SESSION_KEY_MODULE_ADDRESS,
  SESSION_KEY_MODULE_INIT_CODE,
  SESSION_KEY_MODULE_SALT,
} from '../constants/sessionKeyModule'

const { ethers, networkHelpers } = await network.getOrCreate()

// Runtime code of the canonical CREATE2 deployer (Arachnid's
// deterministic-deployment-proxy): calldata is `salt (32 bytes) ++ initCode`,
// it CREATE2-deploys and returns the 20-byte address.
const CREATE2_DEPLOYER_RUNTIME =
  '0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578182fd5b8082525050506014600cf3'

describe('SessionKeyModule - release constants', function () {
  it('commits the init code the current source compiles to', async function () {
    const factory = await ethers.getContractFactory('SessionKeyModule')
    expect(factory.bytecode).to.equal(SESSION_KEY_MODULE_INIT_CODE)
  })

  it('derives SESSION_KEY_MODULE_ADDRESS from the deployer, salt and init code', async function () {
    expect(
      ethers.getCreate2Address(
        CANONICAL_CREATE2_DEPLOYER,
        SESSION_KEY_MODULE_SALT,
        ethers.keccak256(SESSION_KEY_MODULE_INIT_CODE),
      ),
    ).to.equal(SESSION_KEY_MODULE_ADDRESS)
  })

  it('deploys at SESSION_KEY_MODULE_ADDRESS through the canonical deployer', async function () {
    await networkHelpers.setCode(CANONICAL_CREATE2_DEPLOYER, CREATE2_DEPLOYER_RUNTIME)
    const [sender] = await ethers.getSigners()
    const tx = await sender.sendTransaction({
      to: CANONICAL_CREATE2_DEPLOYER,
      data: ethers.concat([SESSION_KEY_MODULE_SALT, SESSION_KEY_MODULE_INIT_CODE]),
    })
    await tx.wait()
    expect(await ethers.provider.getCode(SESSION_KEY_MODULE_ADDRESS)).to.not.equal('0x')

    const module = await ethers.getContractAt('SessionKeyModule', SESSION_KEY_MODULE_ADDRESS)
    expect(await module.sessionBudgetRemaining(sender.address, sender.address)).to.equal(0n)
  })
})
