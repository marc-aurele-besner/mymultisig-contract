import { HardhatUserConfig } from 'hardhat/config'
import '@nomicfoundation/hardhat-toolbox'
import 'hardhat-awesome-cli'
import * as dotenv from 'dotenv'

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
    hardhat: {},
    ethereum: {
      url: `${RPC_MAINNET}`,
      chainId: 1,
      accounts: listPrivateKeysOrProvideDummyPk(PRIVATE_KEY_MAINNET_01, PRIVATE_KEY_MAINNET_02, PRIVATE_KEY_MAINNET_03),
    },
    goerli: {
      url: `${RPC_GOERLI}`,
      chainId: 5,
      accounts: listPrivateKeysOrProvideDummyPk(PRIVATE_KEY_GOERLI_01, PRIVATE_KEY_GOERLI_02, PRIVATE_KEY_GOERLI_03),
    },
    bnb: {
      url: `${RPC_BNB}`,
      chainId: 56,
      accounts: listPrivateKeysOrProvideDummyPk(PRIVATE_KEY_BNB_01, PRIVATE_KEY_BNB_02, PRIVATE_KEY_BNB_03),
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
    polygon: {
      url: `${RPC_POLYGON}`,
      chainId: 137,
      accounts: listPrivateKeysOrProvideDummyPk(PRIVATE_KEY_POLYGON_01, PRIVATE_KEY_POLYGON_02, PRIVATE_KEY_POLYGON_03),
    },
    mumbai: {
      url: `${RPC_MUMBAI}`,
      chainId: 80001,
      accounts: listPrivateKeysOrProvideDummyPk(PRIVATE_KEY_MUMBAI_01, PRIVATE_KEY_MUMBAI_02, PRIVATE_KEY_MUMBAI_03),
    },
  },
  solidity: {
    compilers: [
      {
        version: '0.8.18',
      },
      {
        version: '0.8.0',
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
