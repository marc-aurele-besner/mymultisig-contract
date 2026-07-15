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

As of v0.4.0 both `MyMultiSig` and `MyMultiSigExtended` return `'0.4.0'` from `version()`. The EIP-712 domain separator is fixed at deploy time, so wallets deployed against this release (or later) bind signatures to that version. Helpers in `test/shared/signatures.ts`, `test/shared/functions.ts`, and the Foundry equivalents have been updated to thread `validUntil` through the typehash; see the test suite for usage patterns.

## 🛡️ v0.4.0 — Timelock, Guard, Allowances, Modules

`MyMultiSigExtended` v0.4.0 adds four optional features, all **disabled by default** so previously-deployed wallets behave unchanged until the new setters are called. Both wallets now return `'0.4.0'` from `version()`.

### 1. ⏰ Timelock on sensitive calls

Schedule/ready pattern. A call is "sensitive" when it targets `address(this)` at a registered sensitive selector, or when its `value` meets the configured wei threshold. The constructor pre-registers the wallet's admin selectors (incl. `enableModule`/`disableModule`) so the timelock applies to every privileged action by default.

```solidity
wallet.execTransaction(address(wallet), 0,
    abi.encodeWithSignature("setTimelockDelay(uint256)", 1 days), gas, sigs);
// Direct addOwner(...) now reverts SensitiveCallRequiresDelay. Schedule instead:
wallet.scheduleTransaction(target, 0, addOwnerCalldata, gas, nonce, validUntil, sigs);
// After timelockDelay seconds:
wallet.executeScheduled(target, 0, addOwnerCalldata, gas, nonce, validUntil, sigs);
```

**Gotchas:** schedule is keyed by `txHash`, so any payload mutation produces a new id. Replays are blocked by a `type(uint256).max` sentinel. `validUntil` bounds the whole schedule window (re-checked at execute). `executeScheduled` deliberately does NOT bump `_txnNonce` (the (nonce, owner) anti-replay slots consumed at schedule time already block any further tx at this nonce without fresh sigs).

### 2. 🛡️ Transaction guard + built-in allowlist

Pluggable `ITransactionGuard` (pre-call `checkTransaction` + silent post-call `checkAfterExecution`). Reverts are wrapped into `GuardReverted(guard, reason)`. A built-in target allowlist is also available for off-chain / no-guard use.

```solidity
wallet.execTransaction(address(wallet), 0,
    abi.encodeWithSignature("setGuard(address)", guardAddr), gas, sigs);
wallet.execTransaction(address(wallet), 0,
    abi.encodeWithSignature("setAllowedTarget(address,bool)", safeTarget, true), gas, sigs);
```

**Gotchas:** the allowlist is OFF until the first `setAllowedTarget(...)` flips it on. Guard + allowlist apply inside `multiRequest*` (per inner call) and `execTransactionFromModule`. `checkAfterExecution` failures are NEVER reverts.

### 3. 💸 Per-owner daily spending allowance

Single-signer entry point: `execTransactionWithSpendingAllowance(to, value, data, gas, validUntil, signatures)`. Requires a single 65-byte ECDSA sig that recovers to `msg.sender`, who must be a current owner with a non-zero daily cap.

```solidity
wallet.execTransaction(address(wallet), 0,
    abi.encodeWithSignature("setDailySpendingLimit(address,uint256)", owner01, 5 ether), gas, sigs);
bytes memory sig = sign(owner01, wallet, recipient, 1 ether, "0x", gas, nonce, 0);
wallet.execTransactionWithSpendingAllowance(recipient, 1 ether, "0x", gas, 0, sig);
```

**Gotchas:** 24h relative window per owner (not UTC midnight). Commit-on-success: failed inner calls don't burn the cap. The allowance path does NOT bump `_txnNonce` (it's a UX shortcut).

### 4. 🧩 Modules / plugins

Linked-list enabled module registry (Safe `ModuleManager` pattern). Modules bypass the signature threshold — they're operational plugins (recovery, streaming, automation). Use `MyMultiSigFactory.createMyMultiSigAdvanced` for distinct factory bookkeeping.

```solidity
wallet.execTransaction(address(wallet), 0,
    abi.encodeWithSignature("enableModule(address)", moduleAddr), gas, sigs);
module.execCall(target, value, data);     // CALL  (op=0)
module.execDelegateCall(calldata);       // DELEGATECALL (op=1, to == wallet only)
```

**Gotchas:** `disableModule(prev, module)` follows Safe's strict pattern — when the module is the head, `prev` MUST be `address(0)`; otherwise `_modulesNext[prev] == module` must hold. Module-driven calls do NOT bump `_txnNonce`. Guard + allowlist still apply; timelock does NOT.

### Factory + introspection

`MyMultiSigFactory.createMyMultiSigAdvanced(...)` produces the v0.4.0 wallet through a new `MyMultiSigAdvancedDeployer` (a tiny wrapper that defers to `MyMultiSigExtendedDeployer`; the v0.4.0 wallet bytecode is currently identical to v0.3.0 Extended, and the distinction lives in factory bookkeeping until a future Advanced-only release).

`advancedFeaturesEnabled()` returns a bitmask (1=timelock, 2=guard, 4=allowlist, 8=allowance, 16=module) for UI/explorer use.

### Factory bookkeeping (v0.4.0)

The factory now tracks per-type counts and exposes an address-keyed type lookup:

```solidity
uint256 simpleCount();      // base MyMultiSig wallets
uint256 extendedCount();     // MyMultiSigExtended (incl. Advanced)
uint256 advancedCount();     // wallets created via the Advanced deployer
uint256 creationTypeCount(MyMultiSigFactorableModels.CreationType);
MyMultiSigFactorableModels.CreationType creationTypeOf(address wallet);
bool isExtended(address wallet);    // true for Extended + Advanced
```

`MyMultiSigAdvancedTests()` is the new exported test group in `test/shared/tests.ts` (entry files `test/MyMultiSigAdvanced.test.ts` and `test/MyMultiSigAdvancedFromFactory.test.ts`); Foundry mirrors under `contracts/test/shared/tests.t.sol`. Helpers (`setTimelockDelay`, `enableModule`, …) live in `test/shared/functions.ts`.

### Cleanups bundled with v0.4.0

- `MyMultiSig.verifyNonce(uint256)` removed (zero references).
- `MyMultiSig._changeThreshold` now emits `ThresholdChanged(uint256)` (event declared at line 52 but never previously emitted).

## 🚀 v0.5.0 — DELEGATECALL op + ERC-4337 rolled into `MyMultiSigExtended`

> ⚠️ **v0.5.0 ships the new wallet features as additions to the existing `MyMultiSigExtended` class — there is no separate `MyMultiSigV2_5` wallet contract.** All wallets deployed through the factory after this release are `MyMultiSigExtended` instances that now also expose the `operation` byte and the `IAccount` surface.

`MyMultiSigExtended` v0.5.0 adds three forward-looking capabilities on top of the existing v0.4.0 features (timelock, guard, allowance, modules):

### 1. 🛡️ `operation` byte on the owner-signed `execTransaction`

A new `uint8 operation` parameter is bound into the EIP-712 typed-data payload. Three new `execTransaction` overloads:

```solidity
execTransaction(to, value, data, gas, operation, signatures) -> success
execTransaction(to, value, data, gas, validUntil, operation, signatures) -> success
execTransaction(to, value, data, gas, txnNonce, validUntil, operation, signatures) -> success
```

`operation == 0` (default) → standard CALL. `operation == 1` → DELEGATECALL into `to`, gated to **`to == address(this)`** (mirrors the same gating already used by `MyMultiSigExtended.execTransactionFromModule`). Anything else reverts with the new custom error `InvalidOperationV2_5(uint8 op)`.

⚠️ **Breaking**: the pre-existing 5/6/7-arg `execTransaction` overloads on `MyMultiSigExtended` are **disabled** — they now revert with `V2_5RequiresOperationByte()`. All frontends must switch to the new overloads that include `operation`. The base `MyMultiSig` wallet is **untouched** and continues to expose the old 5/6-arg signatures against the v0.4.0 typehash.

⚠️ **EIP-712 footer changed.** The new typehash binds `operation`:
```
Transaction(address to, uint256 value, bytes data, uint256 gas, uint96 nonce, uint256 validUntil, uint8 operation)
```
Existing v0.4.0 `MyMultiSigExtended` signatures do **not** validate on v0.5.0 wallets because the domain separator now hashes `version() == '0.5.0'` and the typehash includes `operation`. Migrate your off-chain signer to bind `operation` (default `0`) into the typed data before deploying.

### 2. ⚡ ERC-4337 v0.7 account abstraction

`MyMultiSigExtended` implements `IAccount` against an immutable `IEntryPoint` v0.7 address passed at construction. The canonical EntryPoint v0.7 address (same on every EVM chain) is `0x0000000071727De22E5E9d8BDe0dFeC0CEB6a7d7`.

Constructor signature: `new MyMultiSigExtended(name, owners, threshold, isOnlyOwnerRequest, entryPoint)`. Bundler flow:

1. Bundler calls `EntryPoint.handleOps([userOp], beneficiary)`.
2. EntryPoint calls the wallet's `validateUserOp(PackedUserOperation, bytes32 userOpHash, uint256 missingAccountFunds)`. Returns `0` on success / `1` (`SIG_VALIDATION_FAILED`) on failure. Requires `msg.sender == ENTRY_POINT`, `userOp.sender == address(this)`, `operation == 0`, `userOp.nonce == _txnNonce`, and threshold reached via the same signature-validation path used by `execTransaction`.
3. EntryPoint funds execution and calls `executeUserOp(PackedUserOperation)`, which reconstructs the inner call from `userOp.callData = abi.encode(address to, uint256 value, bytes data, uint256 gas, uint256 validUntil, uint8 operation)` and runs it through the gated `_execExtended` path.

Paymaster support drops out naturally: a paymaster can pre-fund via `EntryPoint.depositTo(address(this))`; bundlers assemble UserOps with `paymasterAndData != 0` and the wallet's `validateUserOp` is permissive on value-funded flows.

### 3. 🌐 CREATE2 deterministic wallets (deferred to a follow-up)

The original v0.5.0 plan called for a CREATE2-based factory path (`Clones.cloneDeterministic` against a dedicated implementation). That work would require converting `MyMultiSigExtended` into `Initializable` (a non-trivial storage layout shift on a non-upgradeable wallet), so it was **deferred to a follow-up release** to keep this PR focused. The v0.5.0 factory stores the same deployer trio as v0.4.0 (`MyMultiSigDeployer`, `MyMultiSigExtendedDeployer`, `MyMultiSigAdvancedDeployer`).

When CREATE2 ships, the plan is:
- Make `MyMultiSigExtended` `Initializable`; `MyMultiSigExtendedDeployer` calls `new MyMultiSigExtendedProxy()` followed by `initialize(name, owners, threshold, isOnlyOwnerRequest, entryPoint)`.
- The factory holds an immutable `myMultiSigV2_5Impl` (the wallet implementation used as a `Clones.cloneDeterministic` target) and uses `OZ Clones.cloneDeterministic(salt, myMultiSigV2_5Impl)` to deploy.

### Migration story

Existing v0.4.0 `MyMultiSig` and `MyMultiSigExtended` wallets stay frozen at v0.4.0 bytecode — they keep `version() == '0.4.0'` and the old 6-field EIP-712 typehash. They do **not** have the v0.5.0 surface. To migrate, the owners move the wallet's funds into a freshly-deployed `MyMultiSigExtended` v0.5.0 with the same owners / threshold.

### Cleanups bundled with v0.5.0

- `MyMultiSigFactorable.version()` bumped `'0.1.1'` → `'0.2.0'`. `MyMultiSigExtended.version()` bumped `'0.4.0'` → `'0.5.0'`. `package.json` bumped `'0.2.0'` → `'0.5.0'`. Done in lock-step with the constructor signature change so the on-chain identity and the artifact registry stay aligned.
- `MyMultiSigExtendedDeployer.deployMyMultiSigExtended(...)` and `MyMultiSigAdvancedDeployer.deployMyMultiSigAdvanced(...)` now take an `entryPoint` argument and forward it through.
- `MyMultiSigFactorable.createMyMultiSigExtended(...)` and `createMyMultiSigAdvanced(...)` now take an `entryPoint` and forward it.
- New custom errors: `InvalidOperationV2_5(uint8)`, `NotEntryPoint()`, `InvalidNonceV2_5(expected, got)`, `V2_5RequiresOperationByte()`. New events: `TransactionExecutedV2_5(...)`, `TxFailureV2_5(...)`, `UserOpExecuted(bytes32 userOpHash, uint256 nonce)`.

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
