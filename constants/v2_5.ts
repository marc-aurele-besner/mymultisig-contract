// v0.5.0 deployment constants. Held in a dedicated file so the v0.4.0
// constants/index.ts stays untouched (it is published to npm and the
// frontend pins the v0.4.0 lines).
//
// `FACTORY_SALT` is the hard-coded 32-byte salt fed into OpenZeppelin's
// canonical CREATE2 deployer at
// `0x4e59b44847b379578588920cA78FbF26c0B4956C`. The same salt on every
// chain deterministically yields the same factory address — this is the
// whole point of the v0.5.0 release.
//
// `ENTRY_POINT_V07_ADDRESS` is the canonical EntryPoint v0.7 address,
// which is identical on every chain.
import { hexlify, zeroPad } from 'ethers/lib/utils'

// 32-byte salt for the v0.5.0 factory proxy deploy. `keccak256` of a
// stable human-readable string — the salt itself becomes part of the
// address on every chain, so changing it requires re-deploying the
// factory proxy across all chains.
const SALT_SEED = Buffer.from(hexlify(Buffer.from('mymultisig.app/v0.5.0')).slice(2).slice(0, 60), 'hex')

export default {
  FACTORY_SALT: zeroPad(SALT_SEED, 32),
  // OpenZeppelin's canonical minimal-CREATE2 deployer. Pre-funded on every
  // major EVM chain. See https://github.com/Arachnid/deterministic-deployer
  CANONICAL_CREATE2_DEPLOYER: '0x4e59b44847b379578588920cA78FbF26c0B4956C',
  // EntryPoint v0.7 canonical address — same on every chain.
  ENTRY_POINT_V07_ADDRESS: '0x0000000071727De22E5E9d8BDe0dFeC0CEB6a7d7'.toLowerCase(),
  // Default chain-agnostic key for tests; production deployments
  // generate a fresh random 32-byte value with `hexlify(crypto.randomBytes(32))`.
  CHAIN_AGNOSTIC_KEY_DEFAULT: zeroPad(
    Buffer.from(hexlify(Buffer.from('mymultisig.app/v0.5.0/chain-agnostic-key')).slice(2).slice(0, 60), 'hex'),
    32,
  ),
}

