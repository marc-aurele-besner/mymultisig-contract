# 💰 MyMultiSig.app Smart Contract (Beta) 🚀

[![license](https://img.shields.io/github/license/jamesisaac/react-native-background-task.svg)](https://opensource.org/licenses/MIT)

A minimalistic Solidity smart contract designed for secure and streamlined transactions, MyMultiSig.app simplifies the multisig process for an easy and convenient experience 💻. The contract is integrated with the mymultisig.app web app for an enhanced user experience 📱.

🔥 This smart contract is a multi-signature wallet, which means that a certain number of owners need to sign off on a transaction before it's executed. 💰

💻 The code is written in Solidity and uses three external libraries, ReentrancyGuard, EIP712 and IERC1271, for added security and interop. 🔒

✨ EIP-1271 support: the wallet exposes the standard `isValidSignature(bytes32,bytes)` entry point so it can act as a signer for other Safe / multisig instances, SIWE verifiers, NFT marketplaces, etc. Contract owners ("nested wallets") can also vote on the wallet's transactions via their own EIP-1271 entry — the wallet's signature validation is agnostic to whether each vote is an EOA ECDSA signature or a contract-owned EIP-1271 blob.

📈 The contract keeps track of various important details, like the name of the contract, the transaction nonce, the number of owners, and who the owners are. 📝

🎉 The contract also has events for adding and removing owners, changing the threshold, executing and failing transactions, and reaching the end of its life (when the nonce hits a certain limit). 💬

💬 When you're ready to make a transaction, you can call the execTransaction function and pass along the destination address, the amount of Ether to transfer, any data you want to include, the gas limit, and the signatures from the necessary owners. 💸

💻 The signatures are verified using the \_validateSignature function, and the transaction is executed using the call opcode in assembly. 💻

🎉 If the signatures are valid and there's enough gas, the transaction is a success and a TransactionExecuted event is emitted. If not, a TransactionFailed event is emitted. 💬

## 🔒 Advantages of Using MyMultiSig.app

1. **Security:** 🔒 A multisig contract requires multiple signatures before a transaction can be executed, making it more secure compared to a single signature transaction.

2. **Decentralization:** 💪 The multisig contract can be managed by multiple parties, promoting decentralization and reducing the risk of a single point of control.

3. **Flexibility:** 💡 The contract can be customized to fit the specific requirements of different organizations, including the number of signatures required and the threshold.

4. **Transparency:** 🔍 All transactions executed by the multisig contract are recorded on the Ethereum blockchain, providing a transparent and auditable trail of all transactions.

_Note: This smart contract is currently in beta, use at your own risk._

## 🔌 EIP-1271

The wallet implements the [EIP-1271](https://eips.ethereum.org/EIPS/eip-1271) standard:

```solidity
function isValidSignature(bytes32 hash, bytes calldata signature)
    external view returns (bytes4 magicValue);
```

`signature` is an ABI-encoded `(address owner, bytes sig)[]` of owner votes. For each entry the wallet either `ecrecover`s a 65-byte ECDSA signature (EOA owner) or `staticcall`s `isValidSignature(hash, sig)` on the owner with a 200k gas stipend (contract owner). If the count of valid votes reaches `threshold`, returns the magic value `0x1626ba7e`; otherwise `0xffffffff`.

Off-chain, building the signature blob is one line:

```ts
import { ethers } from 'ethers'
const blob = ethers.utils.defaultAbiCoder.encode(
  ['tuple(address owner, bytes sig)[]'],
  [[{ owner: owner1, sig: sig1 }, { owner: owner2, sig: sig2 }]],
)
```

The same encoding is used by `execTransaction` and `isValidSignature(address,...,bytes)`. The pre-0.2.0 flat 65-byte chunk format is no longer supported — this is a breaking change documented in the v0.2.0 release notes.

## ⏰ v0.3.0 — deadlines, revokes, atomic batches

v0.3.0 hardens the wallet against three treasury pain points:

1. **`validUntil` deadline.** Every EIP-712 transaction hash now binds a `uint256 validUntil` field. Signers set a Unix timestamp past which the signature is invalid; `execTransaction` reverts with `SignatureExpired()` if a stale payload shows up. `validUntil == 0` means "no expiry" — legacy wallets keep working as long as they pass `0`. **Breaking**: every v0.2.0 off-chain payload is invalidated; update your signer to include `validUntil` in the typed-data `Transaction` struct and pass it through to `execTransaction`. The new 6-arg base-wallet overload `execTransaction(to, value, data, gas, validUntil, signatures)` and the 7-arg Extended overload `execTransaction(to, value, data, gas, nonce, validUntil, signatures)` are the supported entry points.

2. **`revokeApproval(bytes32 hash)`.** An owner can now withdraw their own on-chain approval without burning the whole nonce. Self-only — no admin override — reverts with `NotApproved()` if you try to revoke something you never approved. Emits `RevokeApproval(address indexed owner, bytes32 indexed hash)`.

3. **`multiRequestStrict(address[], uint256[], bytes[], uint256[])`.** New atomic-batch entry point: reverts the whole transaction on first failure (no partial side effects, no `MultiRequestExecuted` event). Use it when the second call depends on the first (e.g. approve-then-swap). Failure bubbles as `BatchCallFailed(uint256 index, bytes reason)`. The original `multiRequest` continues to be best-effort — every call runs, partial failures are surfaced via the existing `successes[]` / `returnData[]` arrays.

The base wallet's `version()` returns `'0.3.0'`. Helpers in `test/shared/signatures.ts`, `test/shared/functions.ts`, and the Foundry equivalents have been updated to thread `validUntil` through the new typehash; see the test suite for usage patterns.

## 🛡️ v0.4.0 — Timelock, Guard, Allowances, Modules

`MyMultiSigExtended` v0.4.0 adds four optional features, all **disabled by default** so existing v0.3.0 wallets and signatures continue to behave unchanged until the new setters are called. The base wallet `MyMultiSig` is untouched. `MyMultiSigExtended.version()` returns `'0.4.0'` (signers must include this in the EIP-712 domain via `CONTRACT_VERSION_EXTENDED` in `constants/index.ts`).

### 1. ⏰ Timelock on sensitive calls

Schedule/ready pattern (Safe/`TimelockController` style). A call is "sensitive" when `to == address(this) && _sensitiveSelectors[sel]` **or** `value >= _sensitiveValueThreshold`. The constructor pre-registers the wallet's admin selectors (incl. the new `enableModule`/`disableModule`) so the timelock applies to every privileged action by default.

```solidity
// Enable a 1-day delay on admin calls.
bytes memory data = abi.encodeWithSignature("setTimelockDelay(uint256)", 1 days);
wallet.execTransaction(address(wallet), 0, data, gas, sigs);  // sigs=threshold sigs
// At this point direct addOwner(...) reverts SensitiveCallRequiresDelay.

// Schedule instead:
bytes memory sigs = ...;  // >= threshold sigs over the addOwner payload
wallet.scheduleTransaction(target, 0, addOwnerCalldata, gas, nonce, validUntil, sigs);
// After `timelockDelay` seconds:
wallet.executeScheduled(target, 0, addOwnerCalldata, gas, nonce, validUntil, sigs);
```

View state: `timelockDelay()`, `sensitiveValueThreshold()`, `isSensitiveSelector(sel)`, `scheduledReadyAt(txHash)`, `scheduledValidUntil(txHash)`.

**Gotchas**
- Sensitive calls via regular `execTransaction` revert `SensitiveCallRequiresDelay(to, selector, value)` — route via `scheduleTransaction`.
- The schedule is keyed by `txHash`, so any payload mutation produces a brand-new id (impossible to corrupt).
- Replays blocked by the `type(uint256).max` sentinel on `_readyAt`; sentinel check returns `NotScheduled`.
- `validUntil` bounds the whole window — `executeScheduled` re-checks `block.timestamp <= _scheduledValidUntil`.
- `executeScheduled` deliberately does NOT bump `_txnNonce` (the base's `incrementNonce()` is `onlyThis`-gated and would revert `OnlyThisContract`). The (nonce, owner) anti-replay slots were already consumed at schedule time, so the next tx at this nonce requires fresh sigs anyway.

### 2. 🛡️ Transaction guard + built-in allowlist

Pluggable `ITransactionGuard` contract (interface in `contracts/interfaces/ITransactionGuard.sol`) wrapping every wallet-driven call. Guard reverts are wrapped via `GuardReverted(guard, reason)`. A built-in target allowlist is also available for off-chain / no-guard use.

```solidity
interface ITransactionGuard {
    function checkTransaction(address to, uint256 value, bytes calldata data) external;
    function checkAfterExecution(bytes32 txHash, bool success) external;
}

// Install a guard via sig'd execTransaction:
wallet.execTransaction(address(wallet), 0,
    abi.encodeWithSignature("setGuard(address)", guardAddr), gas, sigs);
// Allowlist (first call enables the gate):
wallet.execTransaction(address(wallet), 0,
    abi.encodeWithSignature("setAllowedTarget(address,bool)", safeTarget, true), gas, sigs);
```

View state: `guard()`, `allowedTargets(target)`, `allowedTargetsEnabled()`. `PostExecutionGuardFailed(guard, reason)` event fires (silent — never reverts) when `checkAfterExecution` fails.

**Gotchas**
- A fresh wallet has an empty allowlist and `allowedTargetsEnabled() == false`. The first `setAllowedTarget` flips it on.
- Guard also applies inside `multiRequest`/`multiRequestStrict` (per inner call) and `execTransactionFromModule` (modules are still gated).
- `checkAfterExecution` failures are NEVER reverts — they're logged, not enforced.

### 3. 💸 Per-owner daily spending allowance

Single-signer entry point: `execTransactionWithSpendingAllowance(to, value, data, gas, validUntil, signatures)`. Requires a single 65-byte ECDSA sig that recovers to `msg.sender`, who must be a current owner with a non-zero daily cap. Failed inner calls don't burn the cap.

```solidity
// Owner01 gets a 5 ETH/day allowance:
wallet.execTransaction(address(wallet), 0,
    abi.encodeWithSignature("setDailySpendingLimit(address,uint256)", owner01, 5 ether), gas, sigs);
// Owner01 transfers 1 ETH to someone, signed with their key alone:
bytes memory sig = sign(owner01Key, wallet, recipient, 1 ether, "0x", gas, _txnNonce, 0);
wallet.execTransactionWithSpendingAllowance(recipient, 1 ether, "0x", gas, 0, sig);
```

View state: `dailySpendingLimit(owner)`, `spendingLimitRemaining(owner)`.

**Gotchas**
- Day rollover is a fixed **24h relative window** per owner (not UTC midnight). At `block.timestamp >= _lastPeriodResetByOwner[owner] + 1 days` the cap resets.
- Commit-on-success semantics: failed inner calls DO NOT burn the cap.
- Bypass via regular `execTransaction` is unchanged — the allowance path is opt-in per call.
- This entry point does NOT bump `_txnNonce` (allowance is a UX shortcut, not a vault state mutation).

### 4. 🧩 Modules / plugins

Linked-list enabled module registry (Safe ModuleManager style). Modules bypass the signature threshold — they're operational plugins (recovery, streaming, automation). The factory `MyMultiSigFactory` exposes a `createMyMultiSigAdvanced` entry that wraps the Extended deployer for distinct bookkeeping.

```solidity
// Enable a module via sig'd execTransaction:
wallet.execTransaction(address(wallet), 0,
    abi.encodeWithSignature("enableModule(address)", moduleAddr), gas, sigs);
// Module can now push txns via:
module.execCall(target, value, data);             // CALL  (op=0)
module.execDelegateCall(calldata);               // DELEGATECALL (op=1, to == wallet only)
```

View state: `modulesHead()`, `isModule(mod)`, `moduleNext(mod)`, `getModules()`. See `contracts/mocks/MockModule.sol` for an example wrapper.

**Gotchas**
- `disableModule(prev, module)` follows Safe's strict pattern: when the module is the head, `prev` MUST be `address(0)`; otherwise `prev != 0 && _modulesNext[prev] == module` must hold. Else `ModulePrevMismatch`.
- Module-driven calls do NOT bump `_txnNonce` (modules bypass threshold and shouldn't invalidate pending owner-signed transactions).
- Guard + allowlist still apply to module-driven calls. Sensitive-call timelock does NOT (modules are trusted operational plugins).

### Factory + extras

`MyMultiSigFactory.createMyMultiSigAdvanced(name, owners, threshold, isOnlyOwnerRequest)` produces the v0.4.0 wallet through the factory's bookkeeping path. The `MyMultiSigAdvancedDeployer` is a tiny wrapper that defers to `MyMultiSigExtendedDeployer` (the v0.4.0 wallet bytecode is identical to the Extended wallet — the distinction lives in factory bookkeeping until a future v0.5.x Advanced-only release ships).

`MyMultiSigAdvancedTests()` is exported from `test/shared/tests.ts` (re-exported in `test/MyMultiSigAdvanced.test.ts` and `test/MyMultiSigAdvancedFromFactory.test.ts`) and exercised against both direct deployment and factory deployment. Foundry mirrors live in `contracts/test/shared/tests.t.sol`. Helpers (`setTimelockDelay`, `setGuard`, `enableModule`, …) are in `test/shared/functions.ts`.

`advancedFeaturesEnabled()` returns a bitmask (1=timelock active, 2=guard set, 4=allowlist enabled, 8=allowance cap set, 16=at least one module) for UI/explorer introspection.

### Cleanups bundled with v0.4.0

- `MyMultiSig.verifyNonce(uint256)` (zero references) was removed.
- `MyMultiSig._changeThreshold` now emits `ThresholdChanged(uint256)` (event declared at line 52, never previously emitted).

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
