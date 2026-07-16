# Agent guidelines for mymultisig-contract

Multi-signature wallet smart contracts for [mymultisig.app](https://mymultisig.app). Solidity `0.8.24`, dual toolchain (Hardhat + Foundry).

## Commands

| Task | Command |
| --- | --- |
| Compile | `yarn compile` (hardhat) or `forge build` |
| Test (Hardhat, primary suite) | `npx hardhat test` |
| Test (Foundry) | `forge test` |
| Gas snapshot | `forge snapshot` |
| Regenerate committed ABI + types | `yarn build` |
| Coverage | `yarn coverage` (hardhat) / `yarn coverage-foundry` |
| Format contracts | `yarn prettier-contracts` |

Do not run `yarn test` (`test.sh`) from automation — it runs `git pull` and `yarn outdated` interactively.

## Architecture

- `contracts/MyMultiSig.sol` — base wallet: EIP-712 signed transactions, on-chain hash approvals, EIP-1271, batching (`multiRequest` / `multiRequestStrict`).
- `contracts/MyMultiSigExtended.sol` — extends the base wallet with inactivity/delegate handover, opt-in timelock / guard / allowlist / allowance / modules, an `operation` byte (CALL vs self-DELEGATECALL) and ERC-4337 v0.7 support.
- `contracts/abstracts/MyMultiSigFactorable.sol` + `contracts/MyMultiSigFactory.sol` — factory bookkeeping; the factory sits behind a TransparentUpgradeableProxy.
- `contracts/MyMultiSig*Deployer.sol` — thin wrappers holding the wallet creation bytecode so the factory stays under the EIP-170 size limit.
- Foundry tests live in `contracts/test/`, Hardhat tests in `test/`.

## Storage-layout rules

- **Wallets** (`MyMultiSig`, `MyMultiSigExtended`) are deployed fresh via `new` and are never proxied — their storage layout may change between releases, and new storage is appended at the end of each release block.
- **The factory** is behind an upgradeable proxy — never reorder, retype, or remove its state variables; only function-body changes and appended variables are safe.

## Code conventions

- **Comments must describe the CURRENT logic only.** Never write comments that describe what was removed, what the code used to do, before/after comparisons ("instead of X", "no longer", "previously"), or the reasoning of changes that are gone. That history belongs in commit messages and PR descriptions, not in the code. A comment must make sense to a reader who has never seen any earlier version of the file.
- Use custom errors (no `require` strings), NatSpec (`@notice` / `@dev` / `@param` / `@return`) on public surfaces.
- Commit messages follow Conventional Commits (enforced by commitlint).
- Generated artifacts: `abi/` is gitignored; `types/` and `constants/` are committed — regenerate with `yarn build` when the ABI changes.
