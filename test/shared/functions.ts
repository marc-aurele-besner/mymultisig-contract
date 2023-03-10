import { expect } from 'chai'
import { BigNumber, Contract } from 'ethers'
import { ethers, network } from 'hardhat'

import constants from '../../constants'
import signature from './signatures'

export const ZERO = BigNumber.from(0)

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

export const getEventFromReceipt = async (contract: Contract, receipt: any) => {
  const log = receipt.logs.map((log: any) => {
    try {
      return contract.interface.parseLog(log)
    } catch (e) {
      return
    }
  })
  return log
}

export const prepareSignatures = async (
  contract: any,
  owners: any[],
  to: string,
  value: BigNumber,
  data: string,
  gas = constants.DEFAULT_GAS as number
) => {
  const nonce = await contract.nonce()
  let signatures = '0x'
  for (var i = 0; i < owners.length; i++) {
    const sig = await signature.signMultiSigTxn(contract.address, owners[i], to, value, data, gas, nonce)
    signatures += sig.substring(2)
  }
  return signatures
}

export const execTransaction = async (
  contract: any,
  submitter: any,
  owners: any[],
  to: string,
  value: BigNumber,
  data: string,
  gas = constants.DEFAULT_GAS as number,
  errorMsg?: string,
  extraEvents?: string[],
  signatures?: string
) => {
  if (!signatures) signatures = await prepareSignatures(contract, owners, to, value, data, gas)

  const input = await contract.connect(submitter).populateTransaction.execTransaction(to, value, data, gas, signatures)

  const receipt = await checkRawTxnResult(input, submitter, errorMsg)
  if (!errorMsg) {
    const event = await getEventFromReceipt(contract, receipt)
    let found = false
    for (var i = 0; i < event.length; i++) {
      if (event[i] && event[i].name === 'TransactionExecuted') {
        expect(event[i].args.sender).to.be.equal(submitter.address)
        expect(event[i].args.to).to.be.equal(to)
        expect(event[i].args.value).to.be.equal(value)
        expect(event[i].args.data).to.be.equal(data)
        expect(event[i].args.txnGas).to.be.equal(gas)
        found = true
        return receipt
      } else {
        if (
          extraEvents &&
          extraEvents.find((extraEvent: string) => extraEvent === 'TransactionFailed') &&
          event[i] &&
          event[i].name === 'TransactionFailed'
        ) {
          expect(event[i].args.sender).to.be.equal(submitter.address)
          expect(event[i].args.to).to.be.equal(to)
          expect(event[i].args.value).to.be.equal(value)
          expect(event[i].args.data).to.be.equal(data)
          expect(event[i].args.txnGas).to.be.equal(gas)
          found = true
          return receipt
        } else {
          if (found) expect.fail('TransactionExecuted event not found')
        }
      }
    }
    if (event.length == 0) expect.fail('TransactionExecuted event not found')
    if (extraEvents && extraEvents.length > 0) {
      for (let i = 1; i < extraEvents.length; i++) {
        const eventsFound = await getEventFromReceipt(contract, receipt)
        for (var ii = 0; i < eventsFound.length; ii++) {
          if (eventsFound[ii] && eventsFound[ii].name === extraEvents[i]) {
            expect(submitter.address).to.be.equal(eventsFound[ii].sender)
            return receipt
          }
        }
      }
    }
  }
}

export const isValidSignature = async (
  contract: any,
  submitter: any,
  owners: any[],
  to: string,
  value: BigNumber,
  data: string,
  gas = constants.DEFAULT_GAS as number,
  errorMsg?: string
) => {
  const signatures = prepareSignatures(contract, owners, to, value, data, gas)

  if (!errorMsg) return await contract.connect(submitter).isValidSignature(to, value, data, gas, signatures)
  else {
    const input = await contract
      .connect(submitter)
      .populateTransaction.isValidSignature(to, value, data, gas, signatures)
    await checkRawTxnResult(input, submitter, errorMsg)
    return false
  }
}

export const multiRequest = async (
  contract: any,
  submitter: any,
  owners: any[],
  to_: string[],
  value_: BigNumber[],
  data_: string[],
  gas_: number[],
  errorMsg?: string,
  extraEvents?: string[]
) => {
  let gas = 0
  for (var i = 0; i < to_.length; i++) {
    gas += gas_[i]
  }
  await execTransaction(
    contract,
    submitter,
    owners,
    contract.address,
    0,
    contract.interface.encodeFunctionData('multiRequest(address[],uint256[],bytes[],uint256[])', [
      to_,
      value_,
      data_,
      gas_,
    ]),
    gas,
    errorMsg,
    extraEvents
  )
}

export const addOwner = async (
  contract: any,
  submitter: any,
  owners: any[],
  ownerToAdd: string,
  gas = constants.DEFAULT_GAS as number,
  errorMsg?: string,
  extraEvents?: string[]
) => {
  const data = contract.interface.encodeFunctionData('addOwner(address)', [ownerToAdd])

  await execTransaction(contract, submitter, owners, contract.address, ZERO, data, gas, errorMsg, extraEvents)

  if (!errorMsg) expect(await contract.isOwner(ownerToAdd)).to.be.true
}

export const removeOwner = async (
  contract: any,
  submitter: any,
  owners: any[],
  ownerToRemove: string,
  gas = constants.DEFAULT_GAS,
  errorMsg?: string,
  extraEvents?: string[]
) => {
  const data = contract.interface.encodeFunctionData('removeOwner(address)', [ownerToRemove])

  await execTransaction(contract, submitter, owners, contract.address, ZERO, data, gas, undefined, extraEvents)

  if (!errorMsg) expect(await contract.isOwner(ownerToRemove)).to.be.false
  else expect(await contract.isOwner(ownerToRemove)).to.be.true
}

export const changeThreshold = async (
  contract: any,
  submitter: any,
  owners: any[],
  newThreshold: number,
  gas = constants.DEFAULT_GAS,
  errorMsg?: string,
  extraEvents?: string[]
) => {
  const data = contract.interface.encodeFunctionData('changeThreshold(uint16)', [newThreshold])

  await execTransaction(contract, submitter, owners, contract.address, ZERO, data, gas, errorMsg, extraEvents)

  if (!errorMsg) expect(await contract.threshold()).to.be.equal(newThreshold)
}

export const replaceOwner = async (
  contract: any,
  submitter: any,
  owners: any[],
  ownerToAdd: string,
  ownerToRemove: string,
  gas = constants.DEFAULT_GAS,
  errorMsg?: string,
  extraEvents?: string[]
) => {
  const data = contract.interface.encodeFunctionData('replaceOwner(address,address)', [ownerToRemove, ownerToAdd])

  await execTransaction(contract, submitter, owners, contract.address, ZERO, data, gas, errorMsg, extraEvents)

  if (!errorMsg) {
    expect(await contract.isOwner(ownerToAdd)).to.be.true
    expect(await contract.isOwner(ownerToRemove)).to.be.false
  }
}
