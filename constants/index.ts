export default {
  FIGLET_NAME: `
  .88b  d88. db    db .88b  d88. db    db db      d888888b d888888b .d8888. d888888b  d888b  
  88'YbdP\`88 \`8b  d8' 88'YbdP\`88 88    88 88      \`~~88~~'   \`88'   88'  YP   \`88'   88' Y8b 
  88  88  88  \`8bd8'  88  88  88 88    88 88         88       88    \`8bo.      88    88      
  88  88  88    88    88  88  88 88    88 88         88       88      \`Y8b.    88    88  ooo 
  88  88  88    88    88  88  88 88b  d88 88booo.    88      .88.   db   8D   .88.   88. ~8~ 
  YP  YP  YP    YP    YP  YP  YP ~Y8888P' Y88888P    YP    Y888888P \`8888Y' Y888888P  Y888P  
`,
  CONTRACT_FACTORY_NAME: 'MyMultiSigFactory',
  CONTRACT_FACTORY_VERSION: '0.2.0',
  CONTRACT_NAME: 'MyMultiSig',
  /// @notice EIP-712 version string for the BASE `MyMultiSig` wallet. The
  ///         v0.4.0 `MyMultiSigExtended` is built on top of this contract and
  ///         bumps its `version()` getter to `'0.4.0'` for wallet-side
  ///         introspection, but the signed-payload's EIP-712 domain MUST
  ///         continue to match the wallet's `version()` exactly. Test
  ///         helpers read this constant when signing for the base wallet and
  ///         `CONTRACT_VERSION_EXTENDED` for Extended wallets.
  CONTRACT_VERSION: '0.3.0',
  CONTRACT_NAME_EXTENDED: 'MyMultiSigExtended',
  /// @notice EIP-712 version string for the `MyMultiSigExtended` v0.4.0
  ///         wallet. Matches the wallet's `version()` getter.
  CONTRACT_VERSION_EXTENDED: '0.4.0',
  DEFAULT_THRESHOLD: 2,
  DEFAULT_GAS: 75000,
  DEFAULT_ALLOW_ONLY_OWNER: true,
}
