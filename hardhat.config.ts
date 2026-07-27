import { defineConfig, configVariable } from 'hardhat/config'
import hardhatEthers from '@nomicfoundation/hardhat-ethers'
import hardhatChaiMatchers from '@nomicfoundation/hardhat-ethers-chai-matchers'
import hardhatMocha from '@nomicfoundation/hardhat-mocha'
import hardhatNetworkHelpers from '@nomicfoundation/hardhat-network-helpers'
import hardhatTypechain from '@nomicfoundation/hardhat-typechain'
import hardhatVerify from '@nomicfoundation/hardhat-verify'
import * as dotenv from 'dotenv'

dotenv.config()

export default defineConfig({
  plugins: [hardhatEthers, hardhatChaiMatchers, hardhatMocha, hardhatNetworkHelpers, hardhatTypechain, hardhatVerify],
  solidity: {
    compilers: [
      {
        version: '0.8.24',
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
          // Compile through Yul IR — keeps MyMultiSigExtended under the
          // EIP-170 size limit. Must stay in sync with `via_ir` in foundry.toml.
          viaIR: true,
        },
      },
    ],
  },
  networks: {
    default: {
      type: 'edr-simulated',
      chainType: 'l1',
      accounts: {
        mnemonic: 'test test test test test test test test test test test junk',
      },
      // Pin to `shanghai` so the EIP-7825 per-tx gas cap (16M) from
      // Osaka isn't enforced. v0.5.0 wallet deploys pass explicit
      // `gasLimit: 50_000_000` (see `test/shared/setup.ts`), which
      // exceeds EIP-7825's cap. Pinning the hardfork matches the
      // `evm_version: 'london'` set in `foundry.toml`.
      hardfork: 'shanghai',
      transactionGasCap: 281474976710655n,
      blockGasLimit: 0x1fffffffffffff,
      gas: 30_000_000n,
      gasPrice: 8_000_000_000n,
    },
    localhost: {
      type: 'http',
      chainType: 'l1',
      url: 'http://127.0.0.1:8545',
      accounts: { mnemonic: 'test test test test test test test test test test test junk' },
      chainId: 31337,
    },
    anvil: {
      type: 'http',
      chainType: 'l1',
      url: 'http://127.0.0.1:8545',
      accounts: { mnemonic: 'test test test test test test test test test test test junk' },
      chainId: 31337,
    },
    anvil9999: {
      type: 'http',
      chainType: 'l1',
      url: 'http://127.0.0.1:8546',
      accounts: { mnemonic: 'test test test test test test test test test test test junk' },
      chainId: 9999,
    },
    ethereum: {
      type: 'http',
      chainType: 'l1',
      url: configVariable('RPC_MAINNET'),
      chainId: 1,
      accounts: [
        configVariable('PRIVATE_KEY_MAINNET_01'),
        configVariable('PRIVATE_KEY_MAINNET_02'),
        configVariable('PRIVATE_KEY_MAINNET_03'),
      ],
    },
    ethereumFork: {
      type: 'http',
      chainType: 'l1',
      url: configVariable('RPC_MAINNET'),
      chainId: 1,
      accounts: [
        configVariable('PRIVATE_KEY_MAINNET_01'),
        configVariable('PRIVATE_KEY_MAINNET_02'),
        configVariable('PRIVATE_KEY_MAINNET_03'),
      ],
    },
    sepolia: {
      type: 'http',
      chainType: 'l1',
      url: configVariable('RPC_SEPOLIA'),
      chainId: 11155111,
      accounts: [
        configVariable('PRIVATE_KEY_SEPOLIA_01'),
        configVariable('PRIVATE_KEY_SEPOLIA_02'),
        configVariable('PRIVATE_KEY_SEPOLIA_03'),
      ],
    },
    sepoliaFork: {
      type: 'http',
      chainType: 'l1',
      url: configVariable('RPC_SEPOLIA'),
      chainId: 11155111,
      accounts: [
        configVariable('PRIVATE_KEY_SEPOLIA_01'),
        configVariable('PRIVATE_KEY_SEPOLIA_02'),
        configVariable('PRIVATE_KEY_SEPOLIA_03'),
      ],
    },
    bnb: {
      type: 'http',
      chainType: 'l1',
      url: configVariable('RPC_BNB'),
      chainId: 56,
      accounts: [
        configVariable('PRIVATE_KEY_BNB_01'),
        configVariable('PRIVATE_KEY_BNB_02'),
        configVariable('PRIVATE_KEY_BNB_03'),
      ],
    },
    bnbFork: {
      type: 'http',
      chainType: 'l1',
      url: configVariable('RPC_BNB'),
      chainId: 56,
      accounts: [
        configVariable('PRIVATE_KEY_BNB_01'),
        configVariable('PRIVATE_KEY_BNB_02'),
        configVariable('PRIVATE_KEY_BNB_03'),
      ],
    },
    bnbTestnet: {
      type: 'http',
      chainType: 'l1',
      url: configVariable('RPC_BNB_TESTNET'),
      chainId: 97,
      accounts: [
        configVariable('PRIVATE_KEY_BNB_TESTNET_01'),
        configVariable('PRIVATE_KEY_BNB_TESTNET_02'),
        configVariable('PRIVATE_KEY_BNB_TESTNET_03'),
      ],
    },
    bnbTestnetFork: {
      type: 'http',
      chainType: 'l1',
      url: configVariable('RPC_BNB_TESTNET'),
      chainId: 97,
      accounts: [
        configVariable('PRIVATE_KEY_BNB_TESTNET_01'),
        configVariable('PRIVATE_KEY_BNB_TESTNET_02'),
        configVariable('PRIVATE_KEY_BNB_TESTNET_03'),
      ],
    },
    polygon: {
      type: 'http',
      chainType: 'l1',
      url: configVariable('RPC_POLYGON'),
      chainId: 137,
      accounts: [
        configVariable('PRIVATE_KEY_POLYGON_01'),
        configVariable('PRIVATE_KEY_POLYGON_02'),
        configVariable('PRIVATE_KEY_POLYGON_03'),
      ],
    },
    polygonFork: {
      type: 'http',
      chainType: 'l1',
      url: configVariable('RPC_POLYGON'),
      chainId: 137,
      accounts: [
        configVariable('PRIVATE_KEY_POLYGON_01'),
        configVariable('PRIVATE_KEY_POLYGON_02'),
        configVariable('PRIVATE_KEY_POLYGON_03'),
      ],
    },
    amoy: {
      type: 'http',
      chainType: 'l1',
      url: configVariable('RPC_AMOY'),
      chainId: 80002,
      accounts: [
        configVariable('PRIVATE_KEY_AMOY_01'),
        configVariable('PRIVATE_KEY_AMOY_02'),
        configVariable('PRIVATE_KEY_AMOY_03'),
      ],
    },
    amoyFork: {
      type: 'http',
      chainType: 'l1',
      url: configVariable('RPC_AMOY'),
      chainId: 80002,
      accounts: [
        configVariable('PRIVATE_KEY_AMOY_01'),
        configVariable('PRIVATE_KEY_AMOY_02'),
        configVariable('PRIVATE_KEY_AMOY_03'),
      ],
    },
  },
  verify: {
    etherscan: {
      apiKey: configVariable('ETHERSCAN_API_KEY'),
    },
  },
  paths: {
    sources: './contracts',
    tests: './test',
    cache: './cache',
    artifacts: './artifacts',
  },
  typechain: {
    outDir: './typechain-types',
  },
  test: {
    mocha: {
      timeout: 40000,
    },
  },
})
