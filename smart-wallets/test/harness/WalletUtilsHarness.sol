// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { WalletUtils } from "../../src/WalletUtils.sol";

contract WalletUtilsHarness is WalletUtils {

    function onlyWalletFunction() public onlyWallet { }

    function callOnlyWalletFunction() public {
        this.onlyWalletFunction();
    }

}
