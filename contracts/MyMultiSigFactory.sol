// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';

import './abstracts/MyMultiSigFactorable.sol';
import './MyMultiSigExtended.sol';

contract MyMultiSigFactory is MyMultiSigFactorable, Initializable {
  function initialize() external initializer {}
}
