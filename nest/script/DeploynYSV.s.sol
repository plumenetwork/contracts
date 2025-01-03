// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";

import { nYSVProxy } from "../src/proxy/nYSVProxy.sol";
import { nYSV } from "../src/token/nYSV.sol";

contract DeploynYSV is Script {

    address private constant NEST_ADMIN_ADDRESS = 0xC0A7a3AD0e5A53cEF42AB622381D0b27969c4ab5;
    address private constant USDC_ADDRESS = 0x3938A812c54304fEffD266C7E2E70B48F9475aD6;

    address private constant VAULT_TOKEN = 0x4dA57055E62D8c5a7fD3832868DcF3817b99C959;
    address private constant ATOMIC_QUEUE = 0x7f69e1A09472EEb7a5dA7552bD59Ca022c341193;
    address private constant TELLER_ADDRESS = 0x28295bD42bB21690E2f30AE04BCd5F019cDC8D4e;
    address private constant LENS_ADDRESS = 0x3D2021776e385601857E7b7649de955525E21d23;
    address private constant ACCOUNTANT_ADDRESS = 0xD9c3cBfA7dDa0A78a6ea45b09182A33a7C1B3251;
    address private constant ENDPOINT_ADDRESS = 0x6F475642a6e85809B1c36Fa62763669b1b48DD5B;

    function run() external {
        vm.startBroadcast(NEST_ADMIN_ADDRESS);

        // Deploy nYSVToken implementation
        // Deploy with correct constructor parameters
        nYSV nYSVToken = new nYSV(NEST_ADMIN_ADDRESS, VAULT_TOKEN, ACCOUNTANT_ADDRESS, ENDPOINT_ADDRESS);
        console2.log("nYSV implementation deployed to:", address(nYSVToken));

        // Deploy pUSD proxy
        ERC1967Proxy nYSVProxyContract = new nYSVProxy(
            address(nYSVToken),
            abi.encodeCall(
                nYSV.initialize,
                (
                    VAULT_TOKEN,
                    ACCOUNTANT_ADDRESS,
                    IERC20(USDC_ADDRESS),
                    9900, // minimumMintPercentage
                    1 days, // deadlinePeriod
                    9900 // pricePercentage
                )
            )
        );

        console2.log("nYSV proxy deployed to:", address(nYSVProxyContract));

        vm.stopBroadcast();
    }

}
