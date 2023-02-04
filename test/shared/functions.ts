import { expect } from 'chai'
import { ethers, network } from 'hardhat'

import constants from '../../constants'
import signature from './signatures'

export const sendRawTxn = async (input: any, sender: any, ethers: any, provider: any) => {
  const txCount = await provider.getTransactionCount(sender.address)
  const rawTx = {
    chainId: network.config.chainId,
    nonce: ethers.utils.hexlify(txCount),
    to: input.to,
    value: input.value || 0x00,
    gasLimit: ethers.utils.hexlify(3000000),
    gasPrice: ethers.utils.hexlify(25000000000),
    data: input.data,
  }
  const rawTransactionHex = await sender.signTransaction(rawTx)
  const { hash } = await provider.sendTransaction(rawTransactionHex)
  return await provider.waitForTransaction(hash)
}

export const checkRawTxnResult = async (input: any, sender: any, error: undefined | string) => {
  let result
  if (error)
    if (network.name === 'hardhat' || network.name === 'localhost')
      await expect(sendRawTxn(input, sender, ethers, ethers.provider)).to.be.revertedWith(error)
    else expect.fail('AssertionError: ' + error)
  else {
    result = await sendRawTxn(input, sender, ethers, ethers.provider)
    expect(result.status).to.equal(1)
  }
  return result
}

export const getEventFromReceipt = async (receipt: any, eventName: any) => {
  let contractInterface: any = await ethers.getContractFactory(constants.CONTRACT_NAME)
  const log = receipt.logs.map((log: any) => {
    try {
      return contractInterface.decodeEventLog(eventName, log.data, log.topics)
    } catch (e) {
      return
    }
  })
  return log
}

export const execTransaction = async (
  contract: any,
  submitter: any,
  owners: any[],
  to: string,
  value: number,
  data: string,
  txnGas: number,
  errorMsg?: string
) => {
  const nonce = await contract.nonce()
  let signatures = '0x'

  for (var i = 0; i < owners.length; i++) {
    const sig = await signature.signMultiSigTxn(contract.address, owners[i], to, value, data, txnGas, nonce)
    signatures += sig.substring(2)
  }

  const input = await contract
    .connect(submitter)
    .populateTransaction.execTransaction(to, value, data, txnGas, signatures)

  const receipt = await checkRawTxnResult(input, submitter, errorMsg)
  if (!errorMsg) {
    const event = await getEventFromReceipt(receipt, 'TransactionExecuted')
    for (var i = 0; i < event.length; i++) {
      if (event[i]) {
        expect(submitter.address).to.be.equal(event[i].sender)
        return
      }
    }
  }
}

export const isValidSignature = async (
  contract: any,
  submitter: any,
  owners: any[],
  to: string,
  value: number,
  data: string,
  gas: number,
  errorMsg?: string
) => {
  const nonce = (await contract.nonce()).toNumber()
  let signatures = '0x'

  for (var i = 0; i < owners.length; i++) {
    const sig = await signature.signMultiSigTxn(contract.address, owners[i], to, value, data, gas, nonce)
    signatures += sig.substring(2)
  }
  if (!errorMsg) return await contract.connect(submitter).isValidSignature(to, value, data, gas, signatures)
  else {
    const input = await contract
      .connect(submitter)
      .populateTransaction.isValidSignature(to, value, data, gas, signatures)
    await checkRawTxnResult(input, submitter, errorMsg)
    return false
  }
}

export const addOwner = async (
  contract: any,
  submitter: any,
  owners: any[],
  ownerToAdd: string,
  gas = constants.DEFAULT_GAS,
  errorMsg?: string
) => {
  const data = contract.interface.encodeFunctionData('addOwner(address)', [ownerToAdd])

  await execTransaction(contract, submitter, owners, contract.address, 0, data, gas, errorMsg)

  if (!errorMsg) expect(await contract.isOwner(ownerToAdd)).to.be.true
}

export const removeOwner = async (
  contract: any,
  submitter: any,
  owners: any[],
  ownerToRemove: string,
  gas = constants.DEFAULT_GAS,
  errorMsg?: string
) => {
  const data = contract.interface.encodeFunctionData('removeOwner(address)', [ownerToRemove])

  await execTransaction(contract, submitter, owners, contract.address, 0, data, gas, errorMsg)

  if (!errorMsg) expect(await contract.isOwner(ownerToRemove)).to.be.false
}

export const changeThreshold = async (
  contract: any,
  submitter: any,
  owners: any[],
  newThreshold: number,
  gas = constants.DEFAULT_GAS,
  errorMsg?: string
) => {
  const data = contract.interface.encodeFunctionData('changeThreshold(uint16)', [newThreshold])

  await execTransaction(contract, submitter, owners, contract.address, 0, data, gas, errorMsg)

  if (!errorMsg) expect(await contract.threshold()).to.be.equal(newThreshold)
}

export const replaceOwner = async (
  contract: any,
  submitter: any,
  owners: any[],
  ownerToAdd: string,
  ownerToRemove: string,
  gas = constants.DEFAULT_GAS,
  errorMsg?: string
) => {
  const data = contract.interface.encodeFunctionData('replaceOwner(address,address)', [ownerToRemove, ownerToAdd])

  await execTransaction(contract, submitter, owners, contract.address, 0, data, gas, errorMsg)

  if (!errorMsg) {
    expect(await contract.isOwner(ownerToAdd)).to.be.true
    expect(await contract.isOwner(ownerToRemove)).to.be.false
  }
}
