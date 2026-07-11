/**
 * scripts/verifyChainlist.ts
 *
 * Cross-checks hardhat.config.ts networks against chainlist.org to catch
 * deprecated or unsupported testnets early. Fetches the public chainlist JSON
 * once, indexes by chainId, then walks every external network declared in
 * hardhat.config.ts and reports:
 *   - ERRORS: chainId not present on chainlist, missing etherscan entry
 *   - WARNINGS: chain marked deprecated, configured RPC not in chainlist's
 *     public list (legitimate for private RPCs such as Alchemy/Infura/QuickNode)
 *
 * Run with:
 *   yarn verify-chainlist
 *   # or
 *   npx hardhat run scripts/verifyChainlist.ts
 *
 * Network failures are non-fatal: if chainlist.org is unreachable, the script
 * prints a warning and exits 0. Chainlist is treated as a hint, not a gate.
 */

import { config } from 'hardhat'
import * as https from 'https'

interface ChainlistEntry {
  chainId: number
  name: string
  status?: string
  rpc: Array<{ url: string; tracking?: string }>
}

interface ExternalNetwork {
  name: string
  chainId: number
  url: string
  forkingUrl?: string
}

const CHAINLIST_URL = 'https://chainlist.org/rpcs.json'
const REQUEST_TIMEOUT_MS = 8000

const LOCAL_NETWORKS = new Set(['hardhat', 'localhost', 'anvil', 'anvil9999'])

// chainId -> apiKey key used by @nomiclabs/hardhat-etherscan v3.
// Only the chains the project actually uses are listed; extend as needed.
const KNOWN_ETHERSCAN_CHAINS: Record<number, string> = {
  1: 'mainnet',
  11155111: 'sepolia',
  137: 'polygon',
  80002: 'polygonAmoy',
  56: 'bsc',
  97: 'bscTestnet',
  10: 'optimisticEthereum',
  11155420: 'optimisticSepolia',
  42161: 'arbitrumOne',
  421614: 'arbitrumSepolia',
}

const colors = {
  reset: '\x1b[0m',
  yellow: '\x1b[33m',
  red: '\x1b[31m',
  cyan: '\x1b[36m',
  green: '\x1b[32m',
}

const log = (color: string, tag: string, msg: string) =>
  console.log(`${color}${tag}${colors.reset}  ${msg}`)

const warn = (msg: string) => log(colors.yellow, 'WARN ', msg)
const error = (msg: string) => log(colors.red, 'ERROR', msg)
const info = (msg: string) => log(colors.cyan, 'INFO ', msg)
const ok = (msg: string) => log(colors.green, 'OK   ', msg)

function fetchChainlist(): Promise<ChainlistEntry[] | null> {
  return new Promise((resolve) => {
    let settled = false
    const settle = (value: ChainlistEntry[] | null) => {
      if (settled) return
      settled = true
      resolve(value)
    }

    const req = https.get(
      CHAINLIST_URL,
      { timeout: REQUEST_TIMEOUT_MS },
      (res) => {
        if (res.statusCode !== 200) {
          warn(`chainlist.org responded with HTTP ${res.statusCode}`)
          res.resume()
          settle(null)
          return
        }
        const chunks: Buffer[] = []
        res.on('data', (c: Buffer) => chunks.push(c))
        res.on('end', () => {
          try {
            settle(JSON.parse(Buffer.concat(chunks).toString('utf8')))
          } catch (e) {
            warn(`failed to parse chainlist JSON: ${(e as Error).message}`)
            settle(null)
          }
        })
        res.on('error', (e) => {
          warn(`chainlist response error: ${e.message}`)
          settle(null)
        })
      }
    )
    req.on('timeout', () => {
      warn(`chainlist.org request timed out after ${REQUEST_TIMEOUT_MS}ms`)
      req.destroy()
      settle(null)
    })
    req.on('error', (e) => {
      warn(`could not reach chainlist.org: ${e.message}`)
      settle(null)
    })
  })
}

function normalizeUrl(u: string): string {
  return u.replace(/\?.*$/, '').replace(/\/+$/, '').toLowerCase()
}

function externalNetworks(): ExternalNetwork[] {
  const networks = (config.networks || {}) as Record<string, any>
  return Object.entries(networks)
    .filter(([name, n]) => !LOCAL_NETWORKS.has(name) && n?.chainId !== undefined)
    .map(([name, n]) => ({
      name,
      chainId: n.chainId,
      url: typeof n.url === 'string' ? n.url : String(n.url ?? ''),
      forkingUrl: n.forking?.url,
    }))
}

function indexChainlist(list: ChainlistEntry[]): Map<number, ChainlistEntry[]> {
  const map = new Map<number, ChainlistEntry[]>()
  for (const entry of list) {
    if (typeof entry.chainId !== 'number') continue
    const arr = map.get(entry.chainId) ?? []
    arr.push(entry)
    map.set(entry.chainId, arr)
  }
  return map
}

function compare(
  networks: ExternalNetwork[],
  index: Map<number, ChainlistEntry[]>
): { errors: string[]; warnings: string[] } {
  const errors: string[] = []
  const warnings: string[] = []
  const seenBase = new Set<string>()

  for (const net of networks) {
    const isFork = net.name.endsWith('Fork')
    const baseName = isFork ? net.name.slice(0, -4) : net.name

    if (isFork) {
      const base = networks.find((n) => n.name === baseName)
      if (!base) {
        errors.push(
          `network "${net.name}" (chainId ${net.chainId}) has no matching non-Fork network "${baseName}"`
        )
        continue
      }
      if (net.forkingUrl && net.forkingUrl !== base.url) {
        warnings.push(
          `"${net.name}".forking.url differs from "${baseName}".url — verify both target the same chain`
        )
      }
      continue
    }

    if (seenBase.has(baseName)) continue
    seenBase.add(baseName)

    const matches = index.get(net.chainId) ?? []
    if (matches.length === 0) {
      errors.push(
        `network "${net.name}" (chainId ${net.chainId}) not found on chainlist.org — chain may not exist or be unsupported`
      )
      continue
    }

    // chainlist omits `status` on active entries and sets it to "deprecated"
    // (or similar) when retired. Only warn when status is explicitly set to
    // something other than "active" — missing field == active.
    const explicitlyDeprecated = matches.filter(
      (m) => m.status !== undefined && m.status !== 'active'
    )
    if (explicitlyDeprecated.length > 0) {
      const statuses = [...new Set(explicitlyDeprecated.map((m) => m.status as string))]
      warnings.push(
        `chainId ${net.chainId} (${net.name}) status on chainlist: ${statuses.join(', ')} — consider migrating`
      )
    }

    if (net.url && net.url !== 'undefined') {
      const chainRpcs = new Set(
        matches.flatMap((m) => (m.rpc ?? []).map((r) => normalizeUrl(r.url)))
      )
      const normalized = normalizeUrl(net.url)
      if (!chainRpcs.has(normalized)) {
        warnings.push(
          `"${net.name}" URL ${net.url} is not in chainlist.org's public RPC list — normal for private RPCs (Alchemy/Infura/QuickNode), but verify the URL is correct`
        )
      }
    }
  }

  return { errors, warnings }
}

function checkEtherscan(networks: ExternalNetwork[]): string[] {
  const errors: string[] = []
  const apiKey = (config.etherscan as any)?.apiKey as Record<string, string> | undefined
  if (!apiKey) return errors

  for (const net of networks) {
    if (net.name.endsWith('Fork')) continue
    // Only flag missing etherscan entries for networks the user has actually
    // configured (URL != 'undefined'). An unconfigured network is just noise.
    if (!net.url || net.url === 'undefined') continue

    const expectedKey = KNOWN_ETHERSCAN_CHAINS[net.chainId]
    if (!expectedKey) continue

    const keyValue = apiKey[expectedKey]
    if (!keyValue || keyValue === 'undefined') {
      errors.push(
        `network "${net.name}" (chainId ${net.chainId}) has no etherscan.apiKey.${expectedKey} entry — contract verification on ${expectedKey} will fail`
      )
    }
  }

  return errors
}

async function main() {
  console.log(`${colors.cyan}chainlist.org verifier${colors.reset}\n`)

  const networks = externalNetworks()
  if (networks.length === 0) {
    info('no external networks configured — nothing to verify')
    return
  }

  const list = await fetchChainlist()
  if (!list) {
    warn('skipped remote verification (chainlist.org unreachable)')
    return
  }

  const index = indexChainlist(list)
  const { errors, warnings } = compare(networks, index)
  const etherscanErrors = checkEtherscan(networks)

  for (const w of warnings) warn(w)
  for (const e of [...errors, ...etherscanErrors]) error(e)

  console.log()
  const liveCount = networks.filter((n) => !n.name.endsWith('Fork')).length
  if (errors.length === 0 && etherscanErrors.length === 0) {
    ok(`verified ${liveCount} networks against chainlist.org`)
  } else {
    error(
      `found ${errors.length + etherscanErrors.length} error(s) and ${warnings.length} warning(s)`
    )
  }

  process.exitCode = errors.length + etherscanErrors.length > 0 ? 1 : 0
}

main().catch((e) => {
  console.error(e)
  process.exitCode = 1
})