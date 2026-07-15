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

## 🚀 v0.5.0 — CREATE2, DELEGATECALL op, ERC-4337

The v0.5.0 release is a single wallet-class addition (`MyMultiSigV2_5`), shipped alongside the existing v0.4.0 wallets (which stay frozen). Every V2_5 wallet:

- inherits `MyMultiSig` (the v0.4.0 base), **not** `MyMultiSigExtended` (no built-in timelock / guard / allowance / modules machinery);
- exposes `version() == '0.5.0'`, binding the EIP-712 domain separator to this version, so v0.4.0 signatures never validate here even if payload fields match;
- emits a `MyMultiSigV2_5Created(creator, address, salt, contractName, owners, threshold)` event on creation through the factory.

### 1. 🌐 CREATE2 deterministic wallets

Wallets are deployed as EIP-1167 minimal proxies via OZ `Clones.cloneDeterministic(salt, impl)` from a single, immutable `MyMultiSigV2_5` implementation contract. The factory predicts the wallet address with:

```solidity
MyMultiSigFactorableV2_5.predictWalletAddress(
  MyMultiSigV2_5FactorableModels.Create2Params({
    saltKind: MyMultiSigV2_5FactorableModels.SaltKind.OwnerSet,
    chainAgnosticKey: bytes32 <32-byte user-supplied random>,
    contractName: 'MyMultisig',
    owners: [0x.., 0x.., 0x..],
    threshold: 2
  })
) -> (walletAddress, implementationAddress)
```

Same parameters on every chain ⇒ same address by construction. The salt is `keccak256(saltKind, chainAgnosticKey, owners, threshold, contractName)`. `chainAgnosticKey` is the only user-controlled input that must be reused cross-chain to make the address match; generate a fresh 32-byte random once (`hexlify(crypto.randomBytes(32))`) and store it next to the wallet name.

The factory upgrade ships a hard-coded vanity salt + the OZ canonical CREATE2 deployer address (`0x4e59b44847b379578588920cA78FbF26c0B4956C`). Both are surfaced in `scripts/deploy.ts` output and `constants/v2_5.ts` so operators can verify and re-run the same deploy across chains.

⚠️ **Stability:** the salt becomes part of the address on every chain, so changing it requires re-deploying the factory proxy across the entire multi-chain rollout. Pick carefully.

### 2. 🛡️ DELEGATECALL operation type

A new `uint8 operation` byte on the owner-signed `execTransaction` overloads:

```solidity
execTransaction(to, value, data, gas, operation, signatures) -> success
execTransaction(to, value, data, gas, validUntil, operation, signatures) -> success
```

`operation == 0` (default) → standard CALL. `operation == 1` → DELEGATECALL into `to`, gated to **`to == address(this)`** (mirrors the same gating in `MyMultiSigExtended.execTransactionFromModule`). Anything else reverts with `InvalidOperation(uint8 op)`.

⚠️ **Back-compat**: the old 5-arg and 6-arg `execTransaction` overloads (no `operation`) are **disabled** on `MyMultiSigV2_5` — they revert with `V2_5RequiresOperationByte()`. Frontends should call only the new overloads.

⚠️ **`multiRequest` / `multiRequestStrict` are CALL-only.** The v0.5.0 batch helpers inherit the base-wallet semantics and never honor the `operation` byte; inner calls remain CALL. This matches Safe's convention.

The new event `TransactionExecutedV2_5(..., uint8 operation)` carries the byte as a non-indexed field so off-chain indexers can route CALL vs DELEGATECALL.

### 3. ⚡ ERC-4337 v0.7 account abstraction

`MyMultiSigV2_5` implements `IAccount` against an immutable `IEntryPoint` address passed at construction. The canonical EntryPoint v0.7 address is `0x0000000071727De22E5E9d8BDe0dFeC0CEB6a7d7` (same on every chain). Bundlers flow:

1. Bundler calls `EntryPoint.handleOps([userOp], beneficiary)`.
2. EntryPoint calls the wallet's `validateUserOp(PackedUserOperation, bytes32 userOpHash, uint256 missingAccountFunds)` — returns `0` on success, `1` (`SIG_VALIDATION_FAILED`) on failure.
3. EntryPoint funds execution and calls the wallet's `executeUserOp(PackedUserOperation)`, which reconstructs the inner call from `userOp.callData = abi.encode(address to, uint256 value, bytes data, uint256 gas, uint256 validUntil, uint8 operation)` and runs it through the gated `_execV2_5` path.

Paymaster support drops out naturally: a paymaster can pre-fund via `EntryPoint.depositTo(address(this))`; bundlers assemble UserOps with `paymasterAndData != 0` and the wallet's `validateUserOp` is permissive on value-funded flows.

⚠️ **Dual-use caveat**: an EOA `execTransaction` against a wallet whose nonce was already advanced by a bundled UserOp will revert with `InvalidSignatures` — expected behaviour, since the slot `(nonce, owner)` is consumed by the bundler flow and a fresh EOA vote for the same nonce would no longer count.

### Migration story

v0.4.0 wallets **cannot** opt in to v0.5.0 features (wallet code is non-upgradeable). To migrate, the owners move the wallet's funds into a freshly-deployed `MyMultiSigV2_5` with the same owners / threshold. The legacy `MyMultiSig` and `MyMultiSigExtended` paths continue to work for any organization that does not want to migrate.

### Cleanups bundled with v0.5.0

- `MyMultiSigFactorable.version()` bumped `'0.1.1'` → `'0.2.0'`; `package.json` bumped `'0.2.0'` → `'0.5.0'`. Done in lock-step with the `MyMultiSigV2_5.version() = '0.5.0'` change so the on-chain identity and the artifact registry stay aligned.
- `MyMultiSigFactory` constructor takes 5 arguments now: the v0.4.0 deployer trio + the V2_5 implementation address + the V2_5 deployer address. OZ hardhat-upgrades validates this layout on every upgrade.
- Two new entry points on `MyMultiSigFactory`: `reinitializeV2_5()` (re-initializer for chains that already had v0.4.0 deployed) and `createMyMultiSigV2_5(params, entryPoint)` (CREATE2 deployment).
- Run `yarn upgrade-factory:sepolia` (or any other network) followed by `reinitializeV2_5()` to wire the v0.5.0 surface into the existing factory proxy.

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
