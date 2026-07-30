// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title MockERC20
 */

import '@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol';

contract MockProxyAdmin is ProxyAdmin {
  // OZ v5 added an `initialOwner` parameter to Ownable (which ProxyAdmin
  // extends); pass a placeholder so the mock compiles.
  constructor() ProxyAdmin(msg.sender) {}
}
