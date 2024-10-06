// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { WalletUtils } from "../../src/WalletUtils.sol";
import { console } from "forge-std/console.sol";

contract WalletUtilsHarness is WalletUtils {

    function onlyWalletFunction() public onlyWallet { }

    function callOnlyWalletFunction() public {
        this.onlyWalletFunction();
    }

    function exposed_isContract(address addr) external view returns (bool hasCode) {
        return isContract(addr);
    }

}
