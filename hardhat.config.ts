import { HardhatUserConfig } from 'hardhat/config'
import * as dotenv from 'dotenv'
import '@nomicfoundation/hardhat-toolbox'
import 'deployment-tool'
import 'hardhat-contract-clarity'
import '@openzeppelin/hardhat-upgrades'

dotenv.config()

const {
  RPC_MAINNET,
  PRIVATE_KEY_MAINNET_01,
  PRIVATE_KEY_MAINNET_02,
  PRIVATE_KEY_MAINNET_03,
  RPC_GOERLI,
  PRIVATE_KEY_GOERLI_01,
  PRIVATE_KEY_GOERLI_02,
  PRIVATE_KEY_GOERLI_03,
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
  RPC_MUMBAI,
  PRIVATE_KEY_MUMBAI_01,
  PRIVATE_KEY_MUMBAI_02,
  PRIVATE_KEY_MUMBAI_03,
  ETHERSCAN_API_KEY,
  OPENAI_API_KEY,
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
      gas: 2100000,
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
    goerli: {
      url: `${RPC_GOERLI}`,
      chainId: 5,
      accounts: listPrivateKeysOrProvideDummyPk(PRIVATE_KEY_GOERLI_01, PRIVATE_KEY_GOERLI_02, PRIVATE_KEY_GOERLI_03),
    },
    goerliFork: {
      url: `${RPC_GOERLI}`,
      chainId: 5,
      accounts: listPrivateKeysOrProvideDummyPk(PRIVATE_KEY_GOERLI_01, PRIVATE_KEY_GOERLI_02, PRIVATE_KEY_GOERLI_03),
      forking: {
        url: `${RPC_GOERLI}`,
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
    mumbai: {
      url: `${RPC_MUMBAI}`,
      chainId: 80001,
      accounts: listPrivateKeysOrProvideDummyPk(PRIVATE_KEY_MUMBAI_01, PRIVATE_KEY_MUMBAI_02, PRIVATE_KEY_MUMBAI_03),
    },
    mumbaiFork: {
      url: `${RPC_MUMBAI}`,
      chainId: 80001,
      accounts: listPrivateKeysOrProvideDummyPk(PRIVATE_KEY_MUMBAI_01, PRIVATE_KEY_MUMBAI_02, PRIVATE_KEY_MUMBAI_03),
      forking: {
        url: `${RPC_MUMBAI}`,
      },
    },
  },
  etherscan: {
    apiKey: {
      mainnet: `${ETHERSCAN_API_KEY}`,
      goerli: `${ETHERSCAN_API_KEY}`,
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
  clarity: {
    openAIKey: OPENAI_API_KEY,
    summary: {
      // contract: 'contracts/MyMultiSigFactory.sol',
      output: 'clarity.txt',
      model: 'text-davinci-003',
      prompt: 'Summarize the following contract:\n\n',
      temperature: 0.7,
      max_tokens: 2000,
      top_p: 1.0,
      frequency_penalty: 0.0,
      presence_penalty: 0.0,
    },
    readme: {
      output: 'clarity-readme.md',
      model: 'text-davinci-003',
      prompt: 'With the following package.json, can you generate a descriptive readme in markdown?\n\n',
      temperature: 0.7,
      max_tokens: 2000,
      top_p: 1.0,
      frequency_penalty: 0.0,
      presence_penalty: 0.0,
    },
    AIhelp: {
      error: 'How to use hardhat with openAI',
      model: 'text-davinci-003',
      prompt: 'Using hardhat, I have this error message:\n\n',
      promptEnd: 'Can you explain why and how I can fix the error:\n\n',
      temperature: 0.7,
      max_tokens: 2000,
      top_p: 1.0,
      frequency_penalty: 0.0,
      presence_penalty: 0.0,
    },
  },
}

export default config
