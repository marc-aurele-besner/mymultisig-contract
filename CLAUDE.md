# Claude guidance for mymultisig-contract

Full project guide: see @AGENTS.md — architecture, commands, and storage-layout rules live there.

## Rules

- **Comments must describe the CURRENT logic only.** Never write comments that describe what was removed, what the code used to do, before/after comparisons ("instead of X", "no longer", "previously"), or the reasoning of changes that are gone. That history belongs in commit messages and PR descriptions, not in the code. A comment must make sense to a reader who has never seen any earlier version of the file.
- Run both test suites before committing contract changes: `npx hardhat test` and `forge test`. Do not use `yarn test` (`test.sh`) — it runs `git pull` interactively.
- The factory (`MyMultiSigFactorable` / `MyMultiSigFactory`) is behind an upgradeable proxy: never reorder, retype, or remove its state variables. Wallets are deployed fresh via `new` and are not proxied.
- Regenerate committed types with `yarn build` when a contract's ABI changes.
