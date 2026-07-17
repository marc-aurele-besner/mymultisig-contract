import { ethers, network, upgrades, addressBook } from 'hardhat'
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
  '\x1b[0m',
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
  deployFactory = false,
  deployExtended = false,
): Promise<SetupContractReturn> => {
  let ContractFactory
  let contract
  // v0.5.0 — the wallet bytecode is large enough that the hardhat
  // node's per-tx 16M cap can be hit by auto-estimation, so local dev
  // chains get an explicit `gasLimit` on every deploy. Live networks
  // reject any gas limit above their block gas limit ("gas limit too
  // high"), so there we pass no override and let the node estimate.
  const LOCAL_CHAIN_IDS = [31337, 9999]
  const isLocalNetwork =
    network.name === 'hardhat' || LOCAL_CHAIN_IDS.includes(network.config.chainId ?? 0)
  const deployOverrides = isLocalNetwork ? { gasLimit: 50_000_000 } : {}

  // Get contract artifacts and deploy contract
  if (deployFactory) {
    // The factory doesn't embed MyMultiSig / MyMultiSigExtended bytecode; it
    // delegates deployment to two tiny helper contracts whose addresses are
    // passed in via the implementation's constructor. Deploy them first.
    const MyMultiSigDeployer = await ethers.getContractFactory('MyMultiSigDeployer')
    const myMultiSigDeployer = await MyMultiSigDeployer.deploy(deployOverrides)
    await myMultiSigDeployer.deployed()
    const MyMultiSigExtendedDeployer = await ethers.getContractFactory('MyMultiSigExtendedDeployer')
    const myMultiSigExtendedDeployer = await MyMultiSigExtendedDeployer.deploy(deployOverrides)
    await myMultiSigExtendedDeployer.deployed()
    // The "Advanced" deployer is a tiny wrapper around the Extended
    // deployer — see `MyMultiSigAdvancedDeployer.sol` — so factory
    // bookkeeping can distinguish the creation path without paying for a
    // second copy of the wallet bytecode.
    const MyMultiSigAdvancedDeployer = await ethers.getContractFactory('MyMultiSigAdvancedDeployer')
    const myMultiSigAdvancedDeployer = await MyMultiSigAdvancedDeployer.deploy(
      myMultiSigExtendedDeployer.address,
      deployOverrides,
    )
    await myMultiSigAdvancedDeployer.deployed()

    ContractFactory = await ethers.getContractFactory(contractName)
    contract = await upgrades.deployProxy(ContractFactory, [], {
      constructorArgs: [
        myMultiSigDeployer.address,
        myMultiSigExtendedDeployer.address,
        myMultiSigAdvancedDeployer.address,
      ],
      ...deployOverrides,
    })
  } else {
    if (!deployExtended) {
      ContractFactory = await ethers.getContractFactory(contractName)
      contract = await ContractFactory.deploy(contractName, ownersAddresses, threshold, deployOverrides)
    } else {
      ContractFactory = await ethers.getContractFactory(contractName + 'Extended')
      // v0.5.0 `MyMultiSigExtended` constructor adds an `entryPoint_`
      // arg; pass the canonical EntryPoint v0.7 address so the
      // constructor's `InvalidOperation` check accepts it. The
      // address is the same on every EVM chain.
      contract = await ContractFactory.deploy(
        contractName,
        ownersAddresses,
        threshold,
        constants.DEFAULT_ALLOW_ONLY_OWNER,
        constants.ENTRY_POINT_V07_ADDRESS,
        deployOverrides,
      )
    }
  }

  const deploymentDetail =
    contractName === constants.CONTRACT_FACTORY_NAME
      ? {
          factoryName: constants.CONTRACT_FACTORY_NAME,
        }
      : {}

  // Wait for contract to be deployed
  await contract.deployed()

  // `saveContract` only persists to the address-book JSON files when its
  // trailing `forceAdd` flag is true; it always skips the hardhat/localhost/
  // anvil networks internally, so local test runs never touch the files.
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
      ...deploymentDetail,
      owners: ownersAddresses,
      threshold,
    },
    true,
  )
  // `retrieveContract` returns an empty string when no record matches, and a
  // stale record would return an old address — require the freshly deployed
  // address on the networks where the save is expected to persist.
  if (!isLocalNetwork && (await addressBook.retrieveContract(contractName, network.name)) !== contract.address)
    throw new Error('Error saving and retrieving contract from address book.')

  return { contract, contractName, contractAddress: contract.address, ownersAddresses, threshold }
}

const isHttpNetworkConfig = (networkConfig: NetworkConfig): networkConfig is HttpNetworkConfig => {
  return (networkConfig as HttpNetworkConfig).url !== undefined
}

const isHardhatNetworkHDAccountsConfig = (
  account: HardhatNetworkAccountsConfig | HttpNetworkAccountsConfig,
): account is HardhatNetworkHDAccountsConfig => {
  return (account as HardhatNetworkHDAccountsConfig).mnemonic !== undefined
}

const isHttpNetworkAccountsConfig = (
  account: HardhatNetworkAccountsConfig | HttpNetworkAccountsConfig,
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
      provider,
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
      provider,
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
      provider,
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
      provider,
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
      provider,
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
      provider,
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
