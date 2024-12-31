// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import { IRWAStaking } from "../src/interfaces/IRWAStaking.sol";
import { AggregateToken } from "../src/AggregateToken.sol";
import { IAggregateToken } from "../src/interfaces/IAggregateToken.sol";
import { AggregateToken } from "../src/AggregateToken.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SimulateMigration is Test {
    // Ethereum mainnet addresses (for reading state)
    address constant RWA_STAKING = address(0xdbd03D676e1cf3c3b656972F88eD21784372AcAB);
    address constant ADMIN = address(0xDE1509CC56D740997c70E1661BA687e950B4a241);

    // Plume mainnet addresses
    address constant PLUME_RECEIVER = address(0x04354e44ed31022716e77eC6320C04Eda153010c);
    address constant PLUME_USDC = address(0x3938A812c54304fEffD266C7E2E70B48F9475aD6); // Add Plume USDC address
    //address constant PLUME_USDT = address(0x...); // Add Plume USDT address
    address constant PLUME_NRWA = address(0x81537d879ACc8a290a1846635a0cAA908f8ca3a6); // Add new RWA token address
    address constant PLUME_NRWA_IMPLEMENTATION = address(0x8d463B454937c0165537Bb1983F5A6CEaFe5aaF6); // Add new RWA token address

    IRWAStaking rwaStaking;
    AggregateToken nRWA;



    function run() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
        rwaStaking = IRWAStaking(RWA_STAKING);
        
        // Get user data from Ethereum mainnet
        address[] memory users = rwaStaking.getUsers();
        uint256[] memory amounts = new uint256[](users.length);
        
        for (uint256 i = 0; i < users.length; i++) {
            (, uint256 amountStaked,) = rwaStaking.getUserState(users[i]);
            amounts[i] = amountStaked;
        }

        // Switch to Plume mainnet
        vm.createSelectFork(vm.envString("PLUME_RPC_URL"));

        // Deploy new AggregateToken to get the bytecode
        AggregateToken implementation = new AggregateToken();
        vm.etch(PLUME_NRWA_IMPLEMENTATION, address(implementation).code);
        nRWA = AggregateToken(PLUME_NRWA);

        // Deal bridged tokens to PLUME_RECEIVER
        deal(PLUME_USDC, PLUME_RECEIVER, 17_049_395 * 1e6);  // 17,049,395 USDC
        //deal(PLUME_USDT, PLUME_RECEIVER, 11_713_501 * 1e6);  // 11,713,501 USDT

        console2.log("\n=== Starting Plume Migration ===");
        console2.log("Total users to migrate:", users.length);
        console2.log("USDC balance:", IERC20(PLUME_USDC).balanceOf(PLUME_RECEIVER) / 1e6, "USDC");
        //console2.log("USDT balance:", IERC20(PLUME_USDT).balanceOf(PLUME_RECEIVER) / 1e6, "USDT");
        
        
        // Start migration process
        vm.startPrank(PLUME_RECEIVER);

        uint256 startGas = gasleft();
        uint256 batchSize = 100; // Can be adjusted based on testing

        for (uint256 i = 0; i < users.length; i += batchSize) {
            uint256 currentBatchSize = min(batchSize, users.length - i);
            address[] memory batchUsers = sliceArray(users, i, currentBatchSize);
            uint256[] memory batchAmounts = sliceArray(amounts, i, currentBatchSize);

            // Mint new RWA tokens to users
            for (uint256 j = 0; j < currentBatchSize; j++) {
                // mint(shares, receiver, controller)
                nRWA.mint(
                    batchAmounts[j],     // shares
                    batchUsers[j],       // receiver
                    PLUME_RECEIVER       // controller
                );
            }

            console2.log("Migrated batch", i / batchSize + 1);
            console2.log("with", currentBatchSize, "users");
        }

        uint256 gasUsed = startGas - gasleft();
        vm.stopPrank();

        // Print migration results
        console2.log("\n=== Migration Complete ===");
        console2.log("Total gas used:", gasUsed);
        console2.log("Average gas per user:", gasUsed / users.length);
        console2.log("Total cost in ETH:", gasUsed * tx.gasprice * 1000 / 1e18 / 1000.0, "ETH");
        
        // Verify migration
        verifyMigration(users, amounts);
    }

    function verifyMigration(
        address[] memory users,
        uint256[] memory originalAmounts
    ) internal view {
        console2.log("\n=== Verifying Migration ===");
        bool success = true;

        for (uint256 i = 0; i < users.length; i++) {
            uint256 newBalance = nRWA.balanceOf(users[i]);
            if (newBalance != originalAmounts[i]) {
                console2.log("Migration mismatch for user:", users[i]);
                console2.log("Expected:", originalAmounts[i]);
                console2.log("Got:", newBalance);
                success = false;
            }
        }

        if (success) {
            console2.log("Migration verified successfully!");
        } else {
            console2.log("Migration verification failed!");
        }
    }

    // Helper functions
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function sliceArray(
        address[] memory arr,
        uint256 start,
        uint256 length
    ) internal pure returns (address[] memory) {
        address[] memory result = new address[](length);
        for (uint256 i = 0; i < length; i++) {
            result[i] = arr[start + i];
        }
        return result;
    }

    function sliceArray(
        uint256[] memory arr,
        uint256 start,
        uint256 length
    ) internal pure returns (uint256[] memory) {
        uint256[] memory result = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            result[i] = arr[start + i];
        }
        return result;
    }
}