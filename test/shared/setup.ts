import { existsSync, readFileSync, writeFileSync } from 'fs'
import { network } from 'hardhat'

import constants from '../../constants'

const connection = await network.connect()
const { ethers } = connection
const networkName = network.name

console.log(
  '\x1b[34m',
  `${constants.FIGLET_NAME}\n`,
  '\x1b[32m',
  'Connected to network: ',
  '\x1b[33m',
  networkName,
  '\x1b[0m',
)

export interface SetupContractReturn {
  contract: any
  contractName: string
  contractAddress: string
  ownersAddresses: string[]
  threshold: number
}

// Manual ERC1967-style transparent proxy deployment. The Hardhat v3
// ecosystem has no `@openzeppelin/hardhat-upgrades` plugin (yet), but the
// `MockTransparentUpgradeableProxy` mock the repo already ships under
// `contracts/mocks/` is the same wrapper a v2 `upgrades.deployProxy`
// would produce. We deploy the implementation, then the proxy pointing
// at it with the `initialize()` selector as the bootstrap call.
const deployProxy = async (
  implementationFactory: any,
  constructorArgs: any[],
  deployerAddress: string,
  initCalldata: string,
  overrides: { gasLimit?: number } = {},
) => {
  const implementation = await implementationFactory.deploy(...constructorArgs, overrides)
  await implementation.waitForDeployment()
  const proxyFactory = await ethers.getContractFactory('MockTransparentUpgradeableProxy')
  const proxy = await proxyFactory.deploy(implementation.target ?? implementation.address, deployerAddress, initCalldata, overrides)
  await proxy.waitForDeployment()
  return { implementation, proxy }
}

// Lightweight replacement for `deployment-tool`'s `addressBook`. The address
// book only persists to disk on live networks; on `hardhat`/`localhost`/
// `anvil` the original implementation was a no-op.
const ADDRESS_BOOK_FILES = ['contractsAddressDeployed.json', 'contractsAddressDeployedHistory.json']
const localNetworks = new Set(['hardhat', 'localhost', 'anvil', 'anvil9999'])

const readAddressBook = (file: string): any[] => {
  if (!existsSync(file)) return []
  try {
    return JSON.parse(readFileSync(file, 'utf8'))
  } catch {
    return []
  }
}

const writeAddressBook = (file: string, entries: any[]) => {
  writeFileSync(file, JSON.stringify(entries, null, 2) + '\n')
}

const saveContract = async (
  contractName: string,
  contractAddress: string,
  netName: string,
  deployerAddress: string,
  chainId: number,
  blockHash: string,
  blockNumber: number,
  _tag: any,
  extra: Record<string, any>,
) => {
  if (localNetworks.has(netName)) return
  const entry = {
    name: contractName,
    address: contractAddress,
    network: netName,
    deployer: deployerAddress,
    deploymentDate: new Date(),
    chainId,
    blockHash,
    blockNumber,
    tag: '',
    extra,
  }
  const fileEntries = readAddressBook(ADDRESS_BOOK_FILES[0]).filter((e) => !(e.name === contractName && e.network === netName))
  fileEntries.unshift(entry)
  writeAddressBook(ADDRESS_BOOK_FILES[0], fileEntries)
  const historyEntries = readAddressBook(ADDRESS_BOOK_FILES[1])
  historyEntries.push(entry)
  writeAddressBook(ADDRESS_BOOK_FILES[1], historyEntries)
}

const retrieveContract = async (contractName: string, netName: string): Promise<string> => {
  const entries = readAddressBook(ADDRESS_BOOK_FILES[0])
  const match = entries.find((e) => e.name === contractName && e.network === netName)
  return match ? (match.address as string) : ''
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
  const LOCAL_CHAIN_IDS = [31337n, 9999n]
  const networkInfo = await ethers.provider.getNetwork()
  const isLocalNetwork =
    networkName === 'hardhat' || LOCAL_CHAIN_IDS.includes(networkInfo.chainId)
  // Cap the explicit deploy `gasLimit` under EIP-7825's 16M per-tx
  // gas cap. EDR enforces this cap even when `transactionGasCap`
  // is set in config, and the explicit `gasLimit` here would
  // otherwise exceed it. Live networks still pass no override so
  // the node estimates.
  const deployOverrides = isLocalNetwork ? { gasLimit: 15_000_000 } : {}

  // Get contract artifacts and deploy contract
  if (deployFactory) {
    // The factory doesn't embed MyMultiSig / MyMultiSigExtended bytecode; it
    // delegates deployment to two tiny helper contracts whose addresses are
    // passed in via the implementation's constructor. Deploy them first.
    const MyMultiSigDeployer = await ethers.getContractFactory('MyMultiSigDeployer')
    const myMultiSigDeployer = await MyMultiSigDeployer.deploy(deployOverrides)
    await myMultiSigDeployer.waitForDeployment()
    const MyMultiSigExtendedDeployer = await ethers.getContractFactory('MyMultiSigExtendedDeployer')
    const myMultiSigExtendedDeployer = await MyMultiSigExtendedDeployer.deploy(deployOverrides)
    await myMultiSigExtendedDeployer.waitForDeployment()
    // The "Advanced" deployer is a tiny wrapper around the Extended
    // deployer — see `MyMultiSigAdvancedDeployer.sol` — so factory
    // bookkeeping can distinguish the creation path without paying for a
    // second copy of the wallet bytecode.
    const MyMultiSigAdvancedDeployer = await ethers.getContractFactory('MyMultiSigAdvancedDeployer')
    const myMultiSigAdvancedDeployer = await MyMultiSigAdvancedDeployer.deploy(
      myMultiSigExtendedDeployer.target ?? myMultiSigExtendedDeployer.address,
      deployOverrides,
    )
    await myMultiSigAdvancedDeployer.waitForDeployment()

    // Manual transparent-proxy deployment replacing `upgrades.deployProxy`.
    ContractFactory = await ethers.getContractFactory(contractName)
    const implementationContract = await ContractFactory.deploy(
      myMultiSigDeployer.target ?? myMultiSigDeployer.address,
      myMultiSigExtendedDeployer.target ?? myMultiSigExtendedDeployer.address,
      myMultiSigAdvancedDeployer.target ?? myMultiSigAdvancedDeployer.address,
      deployOverrides,
    )
    await implementationContract.waitForDeployment()

    // `MyMultiSigFactory.initialize()` is the bootstrap call. The Hardhat v3
    // ecosystem lacks a v3 `oz-upgrades` plugin, so we encode the selector
    // by hand and pass it as the proxy's `_data`.
    const initFragment = ContractFactory.interface.getFunction('initialize')
    const initCalldata = ContractFactory.interface.encodeFunctionData(initFragment, [])

    const [signer] = await ethers.getSigners()
    const proxyAdmin = signer.address

    const ProxyFactory = await ethers.getContractFactory('MockTransparentUpgradeableProxy')
    const proxy = await ProxyFactory.deploy(
      implementationContract.target ?? implementationContract.address,
      proxyAdmin,
      initCalldata,
      deployOverrides,
    )
    await proxy.waitForDeployment()
    contract = implementationContract.attach(proxy.target ?? proxy.address) as any
  } else {
    if (!deployExtended) {
      ContractFactory = await ethers.getContractFactory(contractName)
      contract = await ContractFactory.deploy(contractName, ownersAddresses, threshold, deployOverrides)
      await contract.waitForDeployment()
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
      await contract.waitForDeployment()
    }
  }

  const deploymentDetail =
    contractName === constants.CONTRACT_FACTORY_NAME
      ? {
          factoryName: constants.CONTRACT_FACTORY_NAME,
        }
      : {}

  // `saveContract` only persists to the address-book JSON files when its
  // trailing `forceAdd` flag is true; it always skips the hardhat/localhost/
  // anvil networks internally, so local test runs never touch the files.
  const deployTx = (contract as any).deploymentTransaction ?? (contract as any).deployTransaction
  const deployFrom = deployTx?.from ?? ''
  await saveContract(
    contractName,
    contract.target ?? contract.address,
    networkName,
    deployFrom,
    Number(networkInfo.chainId),
    deployTx?.blockHash ?? '',
    Number(deployTx?.blockNumber ?? 0),
    undefined,
    {
      ...deploymentDetail,
      owners: ownersAddresses,
      threshold,
    },
  )
  // `retrieveContract` returns an empty string when no record matches, and a
  // stale record would return an old address — require the freshly deployed
  // address on the networks where the save is expected to persist.
  if (
    !isLocalNetwork &&
    (await retrieveContract(contractName, networkName)) !== (contract.target ?? contract.address)
  )
    throw new Error('Error saving and retrieving contract from address book.')

  return { contract, contractName, contractAddress: contract.target ?? contract.address, ownersAddresses, threshold }
}

const HD_PATH_HARDHAT = (m: string) => `m/44'/60'/0'/0/${m}`

const isStringArray = (accounts: any): accounts is string[] =>
  Array.isArray(accounts) && accounts.every((a) => typeof a === 'string')

const isHDConfig = (accounts: any): accounts is { mnemonic: string; path?: string } =>
  typeof accounts?.mnemonic === 'string'

const setupProviderAndAccount = async () => {
  const provider = ethers.provider
  // In Hardhat 3 the connection holds its own network config; reach it
  // through the global `connection` established at module load.
  const accountsConfig = (connection as any).networkConfig?.accounts
  const getAccountValues = (): string[] => {
    if (isHDConfig(accountsConfig)) {
      const out: string[] = []
      for (let i = 0; i < 6; i++) {
        const w = ethers.Wallet.fromPhrase(accountsConfig.mnemonic, undefined, `${accountsConfig.path ?? "m/44'/60'/0'/0"}/${i}`)
        out.push(w.privateKey)
      }
      return out
    }
    if (isStringArray(accountsConfig)) return accountsConfig
    return []
  }

  const accountValues = getAccountValues()

  const buildWallet = (idx: number) => {
    const pk = accountValues[idx]
    if (pk && pk.length === 66 && pk.startsWith('0x')) {
      return new ethers.Wallet(pk, provider)
    }
    return ethers.Wallet.createRandom().connect(provider)
  }

  const owner01 = buildWallet(0)
  const owner02 = buildWallet(1)
  const owner03 = buildWallet(2)
  const user01 = accountValues[3] ? buildWallet(3) : ethers.Wallet.createRandom().connect(provider)
  const user02 = accountValues[4] ? buildWallet(4) : ethers.Wallet.createRandom().connect(provider)
  const user03 = accountValues[5] ? buildWallet(5) : ethers.Wallet.createRandom().connect(provider)

  if (networkName === 'hardhat' || networkName === 'localhost') {
    const oneEth = ethers.parseEther('1')
    const fundIfPoor = async (recipient: any) => {
      if (
        (await recipient.getBalance()) < oneEth &&
        (await owner01.getBalance()) > oneEth
      ) {
        await owner01.sendTransaction({ to: recipient.address, value: oneEth })
      }
    }
    for (const recipient of [owner02, owner03, user01, user02, user03]) {
      await fundIfPoor(recipient)
    }
  }
  return [provider, owner01, owner02, owner03, user01, user02, user03]
}

export default {
  setupContract,
  setupProviderAndAccount,
}
