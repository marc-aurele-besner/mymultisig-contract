import { HardhatUserConfig } from 'hardhat/config'
import { TASK_COMPILE_GET_REMAPPINGS } from 'hardhat/builtin-tasks/task-names'
import { subtask } from 'hardhat/config'
import * as fs from 'fs'
import * as path from 'path'
import * as dotenv from 'dotenv'
import '@nomicfoundation/hardhat-toolbox'
import 'deployment-tool'
import '@openzeppelin/hardhat-upgrades'

dotenv.config()

// Hardhat's stock `TASK_COMPILE_GET_REMAPPINGS` returns `{}` and ignores
// `remappings.txt` entirely, which means imports from any library declared in
// remappings.txt (e.g. `forge-std/Test.sol`) fail to resolve under Hardhat.
// `contracts/test/` reuses the same remappings as Foundry; parse remappings.txt
// ourselves so Hardhat's resolver and Foundry see the same mapping.
subtask(TASK_COMPILE_GET_REMAPPINGS, async (): Promise<Record<string, string>> => {
  const remappingsFile = path.join(__dirname, 'remappings.txt')
  if (!fs.existsSync(remappingsFile)) return {}

  const remappings: Record<string, string> = {}
  for (const rawLine of fs.readFileSync(remappingsFile, 'utf8').split('\n')) {
    const line = rawLine.trim()
    if (line.length === 0 || line.startsWith('#')) continue
    const eq = line.indexOf('=')
    if (eq === -1) continue
    const from = line.slice(0, eq).trim()
    let to = line.slice(eq + 1).trim()
    if (from.length === 0 || to.length === 0) continue
    // Hardhat's `applyRemappings` does a plain prefix replace, so the `to` side
    // must keep its trailing `/` — otherwise `@openzeppelin/contracts/=node_modules/@openzeppelin/contracts`
    // collapses `@openzeppelin/contracts/security/Foo.sol` to
    // `node_modules/@openzeppelin/contractssecurity/Foo.sol`. Forge tolerates the
    // missing slash, so we patch it here for Hardhat only.
    if (!to.endsWith('/')) to = to + '/'
    remappings[from] = to
  }
  return remappings
})

const {
  RPC_MAINNET,
  PRIVATE_KEY_MAINNET_01,
  PRIVATE_KEY_MAINNET_02,
  PRIVATE_KEY_MAINNET_03,
  RPC_SEPOLIA,
  PRIVATE_KEY_SEPOLIA_01,
  PRIVATE_KEY_SEPOLIA_02,
  PRIVATE_KEY_SEPOLIA_03,
  RPC_BNB,
  PRIVATE_KEY_BNB_01,
  PRIVATE_KEY_BNB_02,
  PRIVATE_KEY_BNB_03,
  RPC_BNB_TESTNET,
  PRIVATE_KEY_BNB_TESTNET_01,
  PRIVATE_KEY_BNB_TESTNET_02,
  PRIVATE_KEY_BNB_TESTNET_03,
  RPC_POLYGON,
  PRIVATE_KEY_POLYGON_01,
  PRIVATE_KEY_POLYGON_02,
  PRIVATE_KEY_POLYGON_03,
  RPC_AMOY,
  PRIVATE_KEY_AMOY_01,
  PRIVATE_KEY_AMOY_02,
  PRIVATE_KEY_AMOY_03,
  ETHERSCAN_API_KEY,
  POLYGONSCAN_API_KEY,
} = process.env

const listPrivateKeysOrProvideDummyPk = (
  privateKey01: string | undefined,
  privateKey02: string | undefined,
  privateKey03: string | undefined,
) => {
  if (privateKey01 && privateKey02 && privateKey03) return [privateKey01, privateKey02, privateKey03]
  else return ['0x0000000000000000000000000000000000000000000000000000000000000000']
}

const config: HardhatUserConfig = {
  defaultNetwork: 'hardhat',
  networks: {
    hardhat: {
      // blockGasLimit: 1200000000,
      // Bumped from 2.1M to 6M so the factory's `MyMultiSigDeployer` and
      // `MyMultiSigExtendedDeployer` helper contracts can be deployed under
      // the hardhat network. Each helper embeds the full creation bytecode
      // of `MyMultiSig` / `MyMultiSigExtended`, which pushes a single
      // deploy transaction over 2.1M gas (~2.27M for the simple helper,
      // ~2.65M for the extended one). Bumping to 6M leaves headroom for the
      // OZ upgrades proxy deployment on top.
      gas: 6000000,
      gasPrice: 8000000000,
    },
    localhost: {
      accounts: {
        mnemonic: 'test test test test test test test test test test test junk',
      },
      chainId: 31337,
    },
    anvil: {
      url: 'http://127.0.0.1:8545',
      accounts: {
        mnemonic: 'test test test test test test test test test test test junk',
      },
      chainId: 31337,
    },
    anvil9999: {
      url: 'http://127.0.0.1:8546',
      accounts: {
        mnemonic: 'test test test test test test test test test test test junk',
      },
      chainId: 9999,
    },
    ethereum: {
      url: `${RPC_MAINNET}`,
      chainId: 1,
      accounts: listPrivateKeysOrProvideDummyPk(PRIVATE_KEY_MAINNET_01, PRIVATE_KEY_MAINNET_02, PRIVATE_KEY_MAINNET_03),
    },
    ethereumFork: {
      url: `${RPC_MAINNET}`,
      chainId: 1,
      accounts: listPrivateKeysOrProvideDummyPk(PRIVATE_KEY_MAINNET_01, PRIVATE_KEY_MAINNET_02, PRIVATE_KEY_MAINNET_03),
      forking: {
        url: `${RPC_MAINNET}`,
      },
    },
    sepolia: {
      url: `${RPC_SEPOLIA}`,
      chainId: 11155111,
      accounts: listPrivateKeysOrProvideDummyPk(
        PRIVATE_KEY_SEPOLIA_01,
        PRIVATE_KEY_SEPOLIA_02,
        PRIVATE_KEY_SEPOLIA_03,
      ),
    },
    sepoliaFork: {
      url: `${RPC_SEPOLIA}`,
      chainId: 11155111,
      accounts: listPrivateKeysOrProvideDummyPk(
        PRIVATE_KEY_SEPOLIA_01,
        PRIVATE_KEY_SEPOLIA_02,
        PRIVATE_KEY_SEPOLIA_03,
      ),
      forking: {
        url: `${RPC_SEPOLIA}`,
      },
    },
    bnb: {
      url: `${RPC_BNB}`,
      chainId: 56,
      accounts: listPrivateKeysOrProvideDummyPk(PRIVATE_KEY_BNB_01, PRIVATE_KEY_BNB_02, PRIVATE_KEY_BNB_03),
    },
    bnbFork: {
      url: `${RPC_BNB}`,
      chainId: 56,
      accounts: listPrivateKeysOrProvideDummyPk(PRIVATE_KEY_BNB_01, PRIVATE_KEY_BNB_02, PRIVATE_KEY_BNB_03),
      forking: {
        url: `${RPC_BNB}`,
      },
    },
    bnbTestnet: {
      url: `${RPC_BNB_TESTNET}`,
      chainId: 97,
      accounts: listPrivateKeysOrProvideDummyPk(
        PRIVATE_KEY_BNB_TESTNET_01,
        PRIVATE_KEY_BNB_TESTNET_02,
        PRIVATE_KEY_BNB_TESTNET_03,
      ),
    },
    bnbTestnetFork: {
      url: `${RPC_BNB_TESTNET}`,
      chainId: 97,
      accounts: listPrivateKeysOrProvideDummyPk(
        PRIVATE_KEY_BNB_TESTNET_01,
        PRIVATE_KEY_BNB_TESTNET_02,
        PRIVATE_KEY_BNB_TESTNET_03,
      ),
      forking: {
        url: `${RPC_BNB_TESTNET}`,
      },
    },
    polygon: {
      url: `${RPC_POLYGON}`,
      chainId: 137,
      accounts: listPrivateKeysOrProvideDummyPk(PRIVATE_KEY_POLYGON_01, PRIVATE_KEY_POLYGON_02, PRIVATE_KEY_POLYGON_03),
    },
    polygonFork: {
      url: `${RPC_POLYGON}`,
      chainId: 137,
      accounts: listPrivateKeysOrProvideDummyPk(PRIVATE_KEY_POLYGON_01, PRIVATE_KEY_POLYGON_02, PRIVATE_KEY_POLYGON_03),
      forking: {
        url: `${RPC_POLYGON}`,
      },
    },
    amoy: {
      url: `${RPC_AMOY}`,
      chainId: 80002,
      accounts: listPrivateKeysOrProvideDummyPk(PRIVATE_KEY_AMOY_01, PRIVATE_KEY_AMOY_02, PRIVATE_KEY_AMOY_03),
    },
    amoyFork: {
      url: `${RPC_AMOY}`,
      chainId: 80002,
      accounts: listPrivateKeysOrProvideDummyPk(PRIVATE_KEY_AMOY_01, PRIVATE_KEY_AMOY_02, PRIVATE_KEY_AMOY_03),
      forking: {
        url: `${RPC_AMOY}`,
      },
    },
  },
  etherscan: {
    apiKey: {
      mainnet: `${ETHERSCAN_API_KEY}`,
      sepolia: `${ETHERSCAN_API_KEY}`,
      ...(POLYGONSCAN_API_KEY ? { polygonAmoy: `${POLYGONSCAN_API_KEY}` } : {}),
    },
  },
  solidity: {
    compilers: [
      {
        version: '0.8.18',
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: '0.8.0',
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    ],
  },
  paths: {
    sources: './contracts',
    tests: './test',
    cache: './cache',
    artifacts: './artifacts',
  },
  mocha: {
    timeout: 40000,
  },
}

export default config
