import { HardhatUserConfig } from 'hardhat/config'
import { TASK_COMPILE_GET_REMAPPINGS } from 'hardhat/builtin-tasks/task-names'
import { subtask } from 'hardhat/config'
import * as fs from 'fs'
import * as path from 'path'
import * as dotenv from 'dotenv'
import { glob as tcGlob, runTypeChain as tcRunTypeChain } from 'typechain'
import '@nomicfoundation/hardhat-toolbox'
import 'hardhat-awesome-cli'
import '@openzeppelin/hardhat-upgrades'

dotenv.config()

// Mirror the remappings.txt loader from hardhat.config.ts so the coverage
// build resolves `forge-std/...` and `@openzeppelin/...` imports the same
// way the regular compile does. Without this, `solidity-coverage` falls
// back to Hardhat's stock resolver (which returns `{}`) and the build
// fails with HH404 on `forge-std/Test.sol`.
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
    if (!to.endsWith('/')) to = to + '/'
    remappings[from] = to
  }
  return remappings
})

// Mirror the typechain glob workaround from hardhat.config.ts: the bundled
// `@typechain/hardhat` glob also matches per-source `build-info/` dirs and
// `*.dbg.json` debug artifacts, which aren't ABIs and make typechain throw
// `MalformedAbiError: Not a valid ABI`. Filter them out before driving
// `runTypeChain` directly.
subtask('typechain:generate-types').setAction(async ({ quiet }: { quiet: boolean }, { config }: { config: any }) => {
  const cwd = config.paths.root
  const tcCfg = config.typechain
  const isBuildInfoOrDbg = (p: string) => /[/\\]build-info[/\\]/.test(p) || /\.dbg\.json$/i.test(p)
  const allFiles = tcGlob(cwd, [`${config.paths.artifacts}/!(build-info)/**/+([a-zA-Z0-9_]).json`]).filter(
    (p: string) => !isBuildInfoOrDbg(p),
  )
  if (!quiet) {
    console.log(
      `Generating typings for: ${allFiles.length} artifacts in dir: ${tcCfg.outDir} for target: ${tcCfg.target}`,
    )
  }
  const result = await tcRunTypeChain({
    cwd,
    allFiles,
    filesToProcess: allFiles,
    outDir: tcCfg.outDir,
    target: tcCfg.target,
    flags: {
      alwaysGenerateOverloads: tcCfg.alwaysGenerateOverloads,
      discriminateTypes: tcCfg.discriminateTypes,
      tsNocheck: tcCfg.tsNocheck,
      environment: 'hardhat',
    },
  })
  if (!quiet) {
    console.log(`Successfully generated ${result.filesGenerated} typings!`)
  }
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
  privateKey03: string | undefined
) => {
  if (privateKey01 && privateKey02 && privateKey03) return [privateKey01, privateKey02, privateKey03]
  else return ['0x0000000000000000000000000000000000000000000000000000000000000000']
}

const config: HardhatUserConfig = {
  defaultNetwork: 'hardhat',
  networks: {
    hardhat: {
      // v0.5.0 — same FUSAKA_TX_GAS_LIMIT bypass as the main
      // `hardhat.config.ts` (16M is too small for the 108k deployer
      // bytecode). Magic value lifts the per-tx cap.
      blockGasLimit: 0x1fffffffffffff,
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
        PRIVATE_KEY_SEPOLIA_03
      ),
    },
    sepoliaFork: {
      url: `${RPC_SEPOLIA}`,
      chainId: 11155111,
      accounts: listPrivateKeysOrProvideDummyPk(
        PRIVATE_KEY_SEPOLIA_01,
        PRIVATE_KEY_SEPOLIA_02,
        PRIVATE_KEY_SEPOLIA_03
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
        PRIVATE_KEY_BNB_TESTNET_03
      ),
    },
    bnbTestnetFork: {
      url: `${RPC_BNB_TESTNET}`,
      chainId: 97,
      accounts: listPrivateKeysOrProvideDummyPk(
        PRIVATE_KEY_BNB_TESTNET_01,
        PRIVATE_KEY_BNB_TESTNET_02,
        PRIVATE_KEY_BNB_TESTNET_03
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
        version: '0.8.24',
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
          outputSelection: {
            '*': {
              '*': ['storageLayout'],
            },
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
