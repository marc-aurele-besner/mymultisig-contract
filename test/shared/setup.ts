import { ethers, network, addressBook } from 'hardhat'
import {
  NetworkConfig,
  HardhatNetworkConfig,
  HttpNetworkConfig,
  HardhatNetworkAccountsConfig,
  HttpNetworkAccountsConfig,
  HardhatNetworkHDAccountsConfig,
} from 'hardhat/types'

import constants from '../../constants'

console.log(
  '\x1b[34m',
  `${constants.FIGLET_NAME}\n`,
  '\x1b[32m',
  'Connected to network: ',
  '\x1b[33m',
  network.name,
  '\x1b[0m'
)

export interface SetupContractReturn {
  contract: any
  contractName: string
  contractAddress: string
  ownersAddresses: string[]
  threshold: number
}

const setupContract = async (
  contractName = constants.CONTRACT_NAME as string,
  ownersAddresses = [] as string[],
  threshold = constants.DEFAULT_THRESHOLD as number,
  deployFactory = false
): Promise<SetupContractReturn> => {
  let ContractFactory
  let contract
  // Get contract artifacts and deploy contract
  if (deployFactory) {
    ContractFactory = await ethers.getContractFactory(contractName)
    contract = await ContractFactory.deploy()
  } else {
    ContractFactory = await ethers.getContractFactory(contractName)
    contract = await ContractFactory.deploy(contractName, ownersAddresses, threshold)
  }

  // Wait for contract to be deployed
  await contract.deployed()

  await addressBook.saveContract(
    contractName,
    contract.address,
    network.name,
    contract.deployTransaction.from,
    network.config.chainId,
    contract.deployTransaction.blockHash,
    contract.deployTransaction.blockNumber,
    undefined,
    {
      owners: ownersAddresses,
      threshold,
    }
  )
  if ((await addressBook.retrieveContract(contractName, network.name)) === undefined)
    throw new Error('Error saving and retrieving contract from address book.')

  return { contract, contractName, contractAddress: contract.address, ownersAddresses, threshold }
}

const isHttpNetworkConfig = (networkConfig: NetworkConfig): networkConfig is HttpNetworkConfig => {
  return (networkConfig as HttpNetworkConfig).url !== undefined
}

const isHardhatNetworkHDAccountsConfig = (
  account: HardhatNetworkAccountsConfig | HttpNetworkAccountsConfig
): account is HardhatNetworkHDAccountsConfig => {
  return (account as HardhatNetworkHDAccountsConfig).mnemonic !== undefined
}

const isHttpNetworkAccountsConfig = (
  account: HardhatNetworkAccountsConfig | HttpNetworkAccountsConfig
): account is HttpNetworkAccountsConfig => {
  return typeof (account as HttpNetworkAccountsConfig) === 'string'
}

const setupProviderAndAccount = async () => {
  let provider = ethers.provider
  let owner01: any
  let owner02: any
  let owner03: any

  if (isHardhatNetworkHDAccountsConfig(network.config.accounts))
    owner01 = new ethers.Wallet(
      ethers.Wallet.fromMnemonic(network.config.accounts.mnemonic, `m/44'/60'/0'/0/0`).privateKey,
      provider
    )
  else if (
    !isHttpNetworkAccountsConfig(network.config.accounts) &&
    network.config.accounts[0] !== undefined &&
    typeof network.config.accounts[0] === 'string'
  )
    owner01 = new ethers.Wallet(network.config.accounts[0], provider)

  if (isHardhatNetworkHDAccountsConfig(network.config.accounts))
    owner02 = new ethers.Wallet(
      ethers.Wallet.fromMnemonic(network.config.accounts.mnemonic, `m/44'/60'/0'/0/1`).privateKey,
      provider
    )
  else if (
    !isHttpNetworkAccountsConfig(network.config.accounts) &&
    network.config.accounts[1] !== undefined &&
    typeof network.config.accounts[1] === 'string'
  )
    owner02 = new ethers.Wallet(network.config.accounts[1], provider)

  if (isHardhatNetworkHDAccountsConfig(network.config.accounts))
    owner03 = new ethers.Wallet(
      ethers.Wallet.fromMnemonic(network.config.accounts.mnemonic, `m/44'/60'/0'/0/2`).privateKey,
      provider
    )
  else if (
    !isHttpNetworkAccountsConfig(network.config.accounts) &&
    network.config.accounts[2] !== undefined &&
    typeof network.config.accounts[2] === 'string'
  )
    owner03 = new ethers.Wallet(network.config.accounts[2], provider)

  let user01: any
  let user02: any
  let user03: any

  if (isHardhatNetworkHDAccountsConfig(network.config.accounts))
    user01 = new ethers.Wallet(
      ethers.Wallet.fromMnemonic(network.config.accounts.mnemonic, `m/44'/60'/0'/0/3`).privateKey,
      provider
    )
  else if (
    !isHttpNetworkAccountsConfig(network.config.accounts) &&
    network.config.accounts[3] !== undefined &&
    typeof network.config.accounts[3] === 'string'
  )
    user01 = new ethers.Wallet(network.config.accounts[3], provider)
  else user01 = ethers.Wallet.createRandom()

  if (isHardhatNetworkHDAccountsConfig(network.config.accounts))
    user02 = new ethers.Wallet(
      ethers.Wallet.fromMnemonic(network.config.accounts.mnemonic, `m/44'/60'/0'/0/4`).privateKey,
      provider
    )
  else if (
    !isHttpNetworkAccountsConfig(network.config.accounts) &&
    network.config.accounts[4] !== undefined &&
    typeof network.config.accounts[4] === 'string'
  )
    user02 = new ethers.Wallet(network.config.accounts[4], provider)
  else user02 = ethers.Wallet.createRandom()

  if (isHardhatNetworkHDAccountsConfig(network.config.accounts))
    user03 = new ethers.Wallet(
      ethers.Wallet.fromMnemonic(network.config.accounts.mnemonic, `m/44'/60'/0'/0/5`).privateKey,
      provider
    )
  else if (
    !isHttpNetworkAccountsConfig(network.config.accounts) &&
    network.config.accounts[5] !== undefined &&
    typeof network.config.accounts[5] === 'string'
  )
    user03 = new ethers.Wallet(network.config.accounts[5], provider)
  else user03 = ethers.Wallet.createRandom()

  if (network.name === 'hardhat' || network.name === 'localhost') {
    if (
      (await owner02.getBalance()).lt(ethers.utils.parseEther('1')) &&
      (await owner01.getBalance()).gt(ethers.utils.parseEther('1'))
    )
      await owner01.sendTransaction({
        to: owner02.address,
        value: ethers.utils.parseEther('1'),
      })
    if (
      (await owner03.getBalance()).lt(ethers.utils.parseEther('1')) &&
      (await owner01.getBalance()).gt(ethers.utils.parseEther('1'))
    )
      await owner01.sendTransaction({
        to: owner03.address,
        value: ethers.utils.parseEther('1'),
      })
    if (
      (await user01.getBalance()).lt(ethers.utils.parseEther('1')) &&
      (await owner01.getBalance()).gt(ethers.utils.parseEther('1'))
    )
      await owner01.sendTransaction({
        to: user01.address,
        value: ethers.utils.parseEther('1'),
      })
    if (
      (await user02.getBalance()).lt(ethers.utils.parseEther('1')) &&
      (await owner01.getBalance()).gt(ethers.utils.parseEther('1'))
    )
      await owner01.sendTransaction({
        to: user02.address,
        value: ethers.utils.parseEther('1'),
      })
    if (
      (await user03.getBalance()).lt(ethers.utils.parseEther('1')) &&
      (await owner01.getBalance()).gt(ethers.utils.parseEther('1'))
    )
      await owner01.sendTransaction({
        to: user03.address,
        value: ethers.utils.parseEther('1'),
      })
  }
  return [provider, owner01, owner02, owner03, user01, user02, user03]
}

export default {
  setupContract,
  setupProviderAndAccount,
}
