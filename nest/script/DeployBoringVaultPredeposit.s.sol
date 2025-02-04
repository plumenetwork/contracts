// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";
import { Script } from "forge-std/Script.sol";

import { BoringVaultPredeposit } from "../src/BoringVaultPredeposit.sol";

import { IBoringVault } from "../src/interfaces/IBoringVault.sol";
import { ITeller } from "../src/interfaces/ITeller.sol";

contract DeployBoringVaultPredeposit is Script {

    // Configuration
    address private constant ADMIN = address(0xC0A7a3AD0e5A53cEF42AB622381D0b27969c4ab5);
    address private constant TIMELOCK = address(0xC0A7a3AD0e5A53cEF42AB622381D0b27969c4ab5);

    //nYield Teller
    address private constant TELLER = address(0x92A735f600175FE9bA350a915572a86F68EBBE66);
    //nYield Vault
    address private constant VAULT = address(0x892DFf5257B39f7afB7803dd7C81E8ECDB6af3E8);

    // Using nYIELD as salt
    bytes32 private constant SALT = keccak256("nYIELD");

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy implementation
        BoringVaultPredeposit implementation = new BoringVaultPredeposit();

        // Configure vault parameters
        BoringVaultPredeposit.BoringVault memory vaultConfig =
            BoringVaultPredeposit.BoringVault({ teller: ITeller(TELLER), vault: IBoringVault(VAULT) });

        // Initialize implementation
        implementation.initialize(TimelockController(TIMELOCK), ADMIN, vaultConfig, SALT);

        vm.stopBroadcast();

        // Log deployments
        console2.log("BoringVaultPredeposit implementation deployed to:", address(implementation));
    }

}
