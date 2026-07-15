import { expect } from 'chai'
import { BigNumber, BytesLike, Contract, Wallet } from 'ethers'
import { ethers, network } from 'hardhat'

import constants from '../../constants'
import signature from './signatures'
import { MyMultiSig, MyMultiSigExtended } from '../../typechain-types'

export const ZERO = BigNumber.from(0)

export const sendRawTxn = async (input: any, sender: Wallet, ethers: any, provider: any) => {
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

export const checkRawTxnResult = async (
  input: any,
  sender: Wallet,
  error: undefined | string,
  contract?: MyMultiSig | MyMultiSigExtended
) => {
  let result
  if (error)
    if (network.name === 'hardhat' || network.name === 'localhost')
      if (contract)
        await expect(sendRawTxn(input, sender, ethers, ethers.provider)).to.be.revertedWithCustomError(contract, error)
      else await expect(sendRawTxn(input, sender, ethers, ethers.provider)).to.be.revertedWith(error)
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
  contract: MyMultiSig | MyMultiSigExtended,
  owners: Wallet[],
  to: `0x${string}`,
  value: BigNumber,
  data: `0x${string}`,
  gas = constants.DEFAULT_GAS as number,
  nonce = BigNumber.from(0),
  validUntil: number = 0
) => {
  // Build the per-owner ECDSA signatures first.
  const votes: { owner: string; sig: string }[] = []
  for (var i = 0; i < owners.length; i++) {
    const sig = await signature.signMultiSigTxn(contract.address, owners[i], to, value, data, gas, nonce, validUntil)
    votes.push({ owner: owners[i].address, sig })
  }
  // ABI-encode as a dynamic tuple array: abi.encode( (address owner, bytes sig)[] ).
  // Solidity decodes this with `abi.decode(sig, (Vote[]))`.
  return ethers.utils.defaultAbiCoder.encode(['tuple(address owner, bytes sig)[]'], [votes])
}

export const execTransaction = async (
  contract: MyMultiSig | MyMultiSigExtended,
  submitter: Wallet,
  owners: Wallet[],
  to: `0x${string}`,
  value: BigNumber,
  data: `0x${string}`,
  gas = constants.DEFAULT_GAS as number,
  errorMsg?: string,
  extraEvents?: string[],
  signatures?: string,
  validUntil: number = 0
) => {
  const nonce = await contract.nonce()
  if (!signatures) signatures = await prepareSignatures(contract, owners, to, value, data, gas, nonce, validUntil)

  // Pick the right `execTransaction` overload for the deployed contract.
  // - `MyMultiSig` (base wallet) exposes BOTH the legacy 5-arg overload
  //   (no deadline) and a new 6-arg overload that takes `validUntil`.
  //   Default to the 5-arg overload for backwards-compat with existing
  //   callers that pass `validUntil = 0`; switch to the 6-arg overload
  //   whenever a non-zero deadline is supplied.
  // - `MyMultiSigExtended` exposes only the 7-arg overload with custom
  //   nonce + validUntil, so we pass both explicitly.
  // We detect the Extended variant by the presence of its
  // `allowOnlyOwnerRequest()` accessor (the base wallet doesn't have it).
  const isExtended = typeof (contract as any).allowOnlyOwnerRequest === 'function'
  const input = isExtended
    ? await contract
        .connect(submitter)
        .populateTransaction['execTransaction(address,uint256,bytes,uint256,uint256,uint256,bytes)'](
          to,
          value,
          data,
          gas,
          nonce,
          validUntil,
          signatures,
        )
    : validUntil !== 0
      ? await contract
          .connect(submitter)
          .populateTransaction['execTransaction(address,uint256,bytes,uint256,uint256,bytes)'](
            to,
            value,
            data,
            gas,
            validUntil,
            signatures,
          )
      : await contract
          .connect(submitter)
          .populateTransaction['execTransaction(address,uint256,bytes,uint256,bytes)'](
            to,
            value,
            data,
            gas,
            signatures,
          )

  const receipt = await checkRawTxnResult(input, submitter, errorMsg, contract)
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
          extraEvents.find((extraEvent: string) => extraEvent === 'TxFailure') &&
          event[i] &&
          event[i].name === 'TxFailure'
        ) {
          expect(event[i].args.sender).to.be.equal(submitter.address)
          expect(event[i].args.to).to.be.equal(to)
          expect(event[i].args.value).to.be.equal(value)
          expect(event[i].args.data).to.be.equal(data)
          expect(event[i].args.txnGas).to.be.equal(gas)
          found = true
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
          }
        }
      }
    }
  }
  return receipt
}

export const isValidSignature = async (
  contract: MyMultiSig | MyMultiSigExtended,
  submitter: Wallet,
  owners: Wallet[],
  to: `0x${string}`,
  value: BigNumber,
  data: `0x${string}`,
  gas = constants.DEFAULT_GAS as number,
  nonce = BigNumber.from(0),
  errorMsg?: string,
  validUntil: number = 0
) => {
  const signatures = await prepareSignatures(contract, owners, to, value, data, gas, nonce, validUntil)

  // ethers v5 can't disambiguate overloaded functions by name alone, so we
  // pin the overload via the explicit fragment selector. The new
  // `isValidSignature(bytes32,bytes)` (EIP-1271) is the only overload
  // available without an address first; the address-first overload is now
  // 7-arg to carry `validUntil`.
  const sevenArg = 'isValidSignature(address,uint256,bytes,uint256,uint256,uint256,bytes)'

  if (!errorMsg)
    return await contract.connect(submitter)[sevenArg](to, value, data, gas, nonce, validUntil, signatures)
  else {
    const input = await contract
      .connect(submitter)
      .populateTransaction[sevenArg](to, value, data, gas, nonce, validUntil, signatures)
    await checkRawTxnResult(input, submitter, errorMsg, contract)
    return false
  }
}

export const multiRequest = async (
  contract: MyMultiSig | MyMultiSigExtended,
  submitter: Wallet,
  owners: Wallet[],
  to_: `0x${string}`[],
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
  return await execTransaction(
    contract,
    submitter,
    owners,
    contract.address as `0x${string}`,
    BigNumber.from(0),
    contract.interface.encodeFunctionData('multiRequest', [to_, value_, data_, gas_]) as `0x${string}`,
    gas,
    errorMsg,
    extraEvents
  )
}

export const addOwner = async (
  contract: MyMultiSig | MyMultiSigExtended,
  submitter: Wallet,
  owners: Wallet[],
  ownerToAdd: string,
  gas = constants.DEFAULT_GAS as number,
  errorMsg?: string,
  extraEvents?: string[]
) => {
  const data = contract.interface.encodeFunctionData('addOwner', [ownerToAdd]) as `0x${string}`

  await execTransaction(
    contract,
    submitter,
    owners,
    contract.address as `0x${string}`,
    ZERO,
    data,
    gas,
    errorMsg,
    extraEvents
  )

  if (!errorMsg) expect(await contract.isOwner(ownerToAdd)).to.be.true
}

export const removeOwner = async (
  contract: MyMultiSig | MyMultiSigExtended,
  submitter: Wallet,
  owners: Wallet[],
  ownerToRemove: string,
  gas = constants.DEFAULT_GAS,
  errorMsg?: string,
  extraEvents?: string[]
) => {
  const data = contract.interface.encodeFunctionData('removeOwner', [ownerToRemove]) as `0x${string}`

  await execTransaction(
    contract,
    submitter,
    owners,
    contract.address as `0x${string}`,
    ZERO,
    data,
    gas,
    errorMsg,
    extraEvents
  )

  if (!errorMsg) expect(await contract.isOwner(ownerToRemove)).to.be.false
  else expect(await contract.isOwner(ownerToRemove)).to.be.true
}

export const changeThreshold = async (
  contract: MyMultiSig | MyMultiSigExtended,
  submitter: Wallet,
  owners: Wallet[],
  newThreshold: number,
  gas = constants.DEFAULT_GAS,
  errorMsg?: string,
  extraEvents?: string[]
) => {
  const data = contract.interface.encodeFunctionData('changeThreshold', [newThreshold]) as `0x${string}`

  await execTransaction(
    contract,
    submitter,
    owners,
    contract.address as `0x${string}`,
    ZERO,
    data,
    gas,
    errorMsg,
    extraEvents
  )

  if (!errorMsg) expect(await contract.threshold()).to.be.equal(newThreshold)
}

export const replaceOwner = async (
  contract: MyMultiSig | MyMultiSigExtended,
  submitter: Wallet,
  owners: Wallet[],
  ownerToAdd: string,
  ownerToRemove: string,
  gas = constants.DEFAULT_GAS,
  errorMsg?: string,
  extraEvents?: string[]
) => {
  const data = contract.interface.encodeFunctionData('replaceOwner', [ownerToRemove, ownerToAdd]) as `0x${string}`

  await execTransaction(
    contract,
    submitter,
    owners,
    contract.address as `0x${string}`,
    ZERO,
    data,
    gas,
    errorMsg,
    extraEvents
  )

  if (!errorMsg) {
    expect(await contract.isOwner(ownerToAdd)).to.be.true
    expect(await contract.isOwner(ownerToRemove)).to.be.false
  }
}

export const setOnlyOwnerRequest = async (
  contract: MyMultiSigExtended,
  submitter: Wallet,
  owners: Wallet[],
  isOnlyOwnerRequest: boolean,
  gas = constants.DEFAULT_GAS as number,
  errorMsg?: string,
  extraEvents?: string[]
) => {
  const data = contract.interface.encodeFunctionData('setOnlyOwnerRequest', [isOnlyOwnerRequest]) as `0x${string}`

  await execTransaction(
    contract,
    submitter,
    owners,
    contract.address as `0x${string}`,
    ZERO,
    data,
    gas,
    errorMsg,
    extraEvents
  )

  if (!errorMsg) expect(await contract.allowOnlyOwnerRequest()).to.be.equal(isOnlyOwnerRequest)
}

export const setTransferInactiveOwnershipAfter = async (
  contract: MyMultiSigExtended,
  submitter: Wallet,
  owners: Wallet[],
  transferInactiveOwnershipAfter: BigNumber,
  gas = constants.DEFAULT_GAS as number,
  errorMsg?: string,
  extraEvents?: string[]
) => {
  const data = contract.interface.encodeFunctionData('setTransferInactiveOwnershipAfter', [
    transferInactiveOwnershipAfter,
  ]) as `0x${string}`

  await execTransaction(
    contract,
    submitter,
    owners,
    contract.address as `0x${string}`,
    ZERO,
    data,
    gas,
    errorMsg,
    extraEvents
  )

  if (!errorMsg) expect(await contract.minimumTransferInactiveOwnershipAfter()).to.be.equal(transferInactiveOwnershipAfter)
}

export const markNonceAsUsed = async (
  contract: MyMultiSigExtended,
  submitter: Wallet,
  owners: Wallet[],
  nonce: BigNumber,
  gas = constants.DEFAULT_GAS as number,
  errorMsg?: string,
  extraEvents?: string[]
) => {
  const data = contract.interface.encodeFunctionData('markNonceAsUsed', [nonce]) as `0x${string}`

  await execTransaction(
    contract,
    submitter,
    owners,
    contract.address as `0x${string}`,
    ZERO,
    data,
    gas,
    errorMsg,
    extraEvents
  )
  expect(await contract.isNonceUsed(nonce)).to.be.true

  if (!errorMsg) expect(await contract.isNonceUsed(nonce)).to.be.false
}

export const setOwnerSettings = async (
  contract: MyMultiSigExtended,
  ownerToConfigure: string,
  submitter: Wallet,
  owners: Wallet[],
  transferInactiveOwnershipAfter: BigNumber,
  delegatee: `0x${string}`,
  errorMsg?: string,
  extraEvents?: string[]
) => {
  const data = contract.interface.encodeFunctionData('setOwnerSettings', [
    ownerToConfigure,
    transferInactiveOwnershipAfter,
    delegatee,
  ]) as `0x${string}`

  await execTransaction(
    contract,
    submitter,
    owners,
    contract.address as `0x${string}`,
    ZERO,
    data,
    constants.DEFAULT_GAS as number,
    errorMsg,
    extraEvents
  )

  if (!errorMsg) {
    const ownerSettings = await contract.ownerSettings(ownerToConfigure)
    expect(ownerSettings.lastAction).to.be.greaterThan(0)
    expect(ownerSettings.transferInactiveOwnershipAfter).to.be.equal(transferInactiveOwnershipAfter)
    expect(ownerSettings.delegate).to.be.equal(delegatee)
  }
}

export const takeOverOwnership = async (
  contract: MyMultiSigExtended,
  submitter: Wallet,
  originalOwner: `0x${string}`,
  errorMsg?: string
) => {
  if (!errorMsg) {
    const originalOwnerSettings = await contract.ownerSettings(originalOwner)

    const tx = await contract.connect(submitter).takeOverOwnership(originalOwner)
    await tx.wait()

    const finalOwnerSettings = await contract.ownerSettings(originalOwner)

    expect(await contract.isOwner(originalOwnerSettings.delegate)).to.be.true
    expect(await contract.isOwner(originalOwner)).to.be.false
    // expect(finalOwnerSettings.delegate).to.be.equal(ethers.constants.AddressZero)
  } else {
    await expect(contract.connect(submitter).takeOverOwnership(originalOwner)).to.be.revertedWithCustomError(
      contract,
      errorMsg
    )
  }
}

/// @notice Calls the Extended-wallet `execTransaction` overload (now 7-arg in
/// v0.3.0) with a caller-supplied nonce AND validUntil. Returns the raw
/// transaction result so callers can assert success/failure directly.
export const execTransactionWithNonce = async (
  contract: MyMultiSig | MyMultiSigExtended,
  submitter: Wallet,
  owners: Wallet[],
  to: `0x${string}`,
  value: BigNumber,
  data: `0x${string}`,
  gas: number,
  nonce: BigNumber,
  validUntil: number,
  signatures: string
) => {
  const input = await contract
    .connect(submitter)
    .populateTransaction['execTransaction(address,uint256,bytes,uint256,uint256,uint256,bytes)'](
      to,
      value,
      data,
      gas,
      nonce,
      validUntil,
      signatures,
    )
  return await sendRawTxn(input, submitter, ethers, ethers.provider)
}

/// @notice Wraps `execTransactionWithNonce` and asserts the tx reverts with `errorMsg`.
export const execTransactionWithNonceReverted = async (
  contract: MyMultiSig | MyMultiSigExtended,
  submitter: Wallet,
  owners: Wallet[],
  to: `0x${string}`,
  value: BigNumber,
  data: `0x${string}`,
  gas: number,
  nonce: BigNumber,
  validUntil: number,
  signatures: string,
  errorMsg: string
) => {
  const input = await contract
    .connect(submitter)
    .populateTransaction['execTransaction(address,uint256,bytes,uint256,uint256,uint256,bytes)'](
      to,
      value,
      data,
      gas,
      nonce,
      validUntil,
      signatures,
    )
  return await expect(
    sendRawTxn(input, submitter, ethers, ethers.provider),
  ).to.be.revertedWithCustomError(contract, errorMsg)
}

/// @notice Calls `approveHash(hash)` from `owner` and asserts the resulting
/// `ApproveHash` event is emitted (or reverts when `errorMsg` is supplied).
/// When `expectEvent` is false (idempotent re-call), the helper only asserts
/// the call succeeded without requiring an event.
export const approveHash = async (
  contract: MyMultiSig | MyMultiSigExtended,
  owner: Wallet,
  hash: string,
  errorMsg?: string,
  expectEvent = true
) => {
  if (!errorMsg) {
    const tx = await contract.connect(owner).approveHash(hash)
    const receipt = await tx.wait()
    if (expectEvent) {
      const parsed = receipt.logs
        .map((log: any) => {
          try {
            return contract.interface.parseLog(log)
          } catch (e) {
            return
          }
        })
        .find((e: any) => e && e.name === 'ApproveHash')
      expect(parsed, 'ApproveHash event not found').to.not.equal(undefined)
      expect(parsed!.args.owner).to.equal(owner.address)
      expect(parsed!.args.hash).to.equal(hash)
    }
  } else {
    await expect(contract.connect(owner).approveHash(hash)).to.be.revertedWithCustomError(contract, errorMsg)
  }
}
