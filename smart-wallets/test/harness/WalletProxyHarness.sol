// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { WalletFactory } from "../../src/WalletFactory.sol";
import { WalletProxy } from "../../src/WalletProxy.sol";

contract WalletProxyHarness is WalletProxy {

    constructor(
        WalletFactory walletFactory_
    ) WalletProxy(walletFactory_) { }

    function exposed_implementation() external view returns (address impl) {
        return _implementation();
    }

}
