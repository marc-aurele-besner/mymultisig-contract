# 💰 MyMultiSig.app Smart Contract (Beta) 🚀

[![license](https://img.shields.io/github/license/jamesisaac/react-native-background-task.svg)](https://opensource.org/licenses/MIT)

A minimalistic Solidity smart contract designed for secure and streamlined transactions, MyMultiSig.app simplifies the multisig process for an easy and convenient experience 💻. The contract is integrated with the mymultisig.app web app for an enhanced user experience 📱.

## 🔒 Advantages of Using MyMultiSig.app

1. **Security:** 🔒 A multisig contract requires multiple signatures before a transaction can be executed, making it more secure compared to a single signature transaction.

2. **Decentralization:** 💪 The multisig contract can be managed by multiple parties, promoting decentralization and reducing the risk of a single point of control.

3. **Flexibility:** 💡 The contract can be customized to fit the specific requirements of different organizations, including the number of signatures required and the threshold.

4. **Transparency:** 🔍 All transactions executed by the multisig contract are recorded on the Ethereum blockchain, providing a transparent and auditable trail of all transactions.

_Note: This smart contract is currently in beta, use at your own risk._

## 🔧 Install Dependencies

To install all necessary dependencies, run the following command:

```shell
yarn
```

## 💻 Run Tests

To run tests, you have the option to use either Hardhat or Foundry.

### 🔨 Hardhat Tests

To run tests using Hardhat, use the following command:

```shell
yarn hardhat test
```

Additionally, you can run a coverage report using Hardhat with the following command:

```shell
yarn coverage
```

### 🔥 Foundry Tests

To run tests using Foundry, use the following command:

```shell
forge test
```

### 💥 Hardhat & Foundry Tests

To run tests using both Hardhat and Foundry, use the following command:

```shell
yarn test
```

## 🚀 Deploy Locally

To deploy the contract locally, you'll need to run a node with Hardhat.

In a first terminal, run the following command to start the Hardhat node:

```shell
npx hardhat node
```

In a second terminal, while the node is active, run the following command to deploy the contract:

```shell
yarn deploy-localhost
```

## 🙏 Acknowledgements

This project relies on the amazing work done by the Hardhat and Foundry teams. Thank you for your contributions to the Ethereum community!

- [Hardhat Documentation](https://hardhat.org/docs/)
- [Foundry Documentation](https://book.getfoundry.sh/)
