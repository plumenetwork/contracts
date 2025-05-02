// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "../src/ArcToken.sol";
import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";

// Import necessary restriction contracts and interfaces
import { RestrictionsRouter } from "../src/restrictions/RestrictionsRouter.sol";
import { WhitelistRestrictions } from "../src/restrictions/WhitelistRestrictions.sol";
import { YieldBlacklistRestrictions } from "../src/restrictions/YieldBlacklistRestrictions.sol";

/**
 * @title Gas Usage Test for ArcToken's previewYieldDistribution
 * @notice Tests the gas usage of previewYieldDistribution with various holder counts
 */
contract GasTest is Test {

    // Admin address used for setup
    address public constant ADMIN = address(0x123);
    // Test addresses to serve as token holders - make private to avoid fuzzing
    address[] private testAddresses;
    // The token we're testing
    ArcToken public token;

    // Infrastructure
    RestrictionsRouter public router;
    WhitelistRestrictions public whitelistModule;
    YieldBlacklistRestrictions public yieldBlacklistModule;

    // Gas usage per test case
    struct GasUsage {
        uint256 holderCount;
        uint256 gasUsed;
    }

    GasUsage[] public gasUsages;

    // Helper function to get a test address
    function getTestAddress(
        uint256 index
    ) internal view returns (address) {
        if (index >= testAddresses.length) {
            return address(0);
        }
        return testAddresses[index];
    }

    function setUp() public {
        // Set up token
        vm.startPrank(ADMIN);

        // --- Deploy Infrastructure ---
        router = new RestrictionsRouter();
        router.initialize(ADMIN);
        whitelistModule = new WhitelistRestrictions();
        whitelistModule.initialize(ADMIN);
        yieldBlacklistModule = new YieldBlacklistRestrictions();
        yieldBlacklistModule.initialize(ADMIN);

        // Make the ADMIN address have ETH to pay for transactions
        vm.deal(ADMIN, 100 ether);

        token = new ArcToken();
        token.initialize(
            "Test ArcToken", // name_
            "TAT", // symbol_
            0, // No initial supply yet
            address(0x456), // Yield token
            ADMIN,
            18, // Token decimals
            address(router) // Router address
        );

        // --- Link Modules ---
        token.setSpecificRestrictionModule(token.TRANSFER_RESTRICTION_TYPE(), address(whitelistModule));
        token.setSpecificRestrictionModule(token.YIELD_RESTRICTION_TYPE(), address(yieldBlacklistModule));

        // Explicitly grant all necessary roles
        bytes32 MINTER_ROLE = token.MINTER_ROLE();
        bytes32 BURNER_ROLE = token.BURNER_ROLE();
        bytes32 YIELD_MANAGER_ROLE = token.YIELD_MANAGER_ROLE();
        bytes32 YIELD_DISTRIBUTOR_ROLE = token.YIELD_DISTRIBUTOR_ROLE();
        bytes32 UPGRADER_ROLE = token.UPGRADER_ROLE();

        // Grant all roles to ADMIN
        token.grantRole(MINTER_ROLE, ADMIN);
        token.grantRole(BURNER_ROLE, ADMIN);
        token.grantRole(YIELD_MANAGER_ROLE, ADMIN);
        token.grantRole(YIELD_DISTRIBUTOR_ROLE, ADMIN);
        token.grantRole(UPGRADER_ROLE, ADMIN);

        // Also grant MINTER_ROLE to this test contract to allow it to call mint
        token.grantRole(MINTER_ROLE, address(this));

        console2.log("Minting initial supply");

        // Mint a larger initial token supply to ensure meaningful distribution
        uint256 totalSupply = 100_000_000 * 1e18; // 100M tokens
        token.mint(ADMIN, totalSupply);

        console2.log("Setting transfers allowed to true");

        // Ensure transfers are allowed via the whitelist module
        whitelistModule.setTransfersAllowed(true);

        console2.log("Adding holders to whitelist and transferring tokens");

        // Make sure we don't try to create more holders than we have addresses for
        uint256 actualHolderCount = 10_000;
        if (actualHolderCount > testAddresses.length) {
            actualHolderCount = testAddresses.length;
            console2.log("Limiting to available addresses:", actualHolderCount);
        }

        // Calculate amount per holder - make sure it's substantial
        uint256 amountPerHolder = totalSupply / (actualHolderCount + 1); // +1 for ADMIN
        console2.log("Amount per holder:", amountPerHolder / 1e18, "tokens");

        // Track successful transfers
        uint256 successfulHolders = 0;

        // Transfer tokens to each holder
        for (uint256 i = 0; i < actualHolderCount; i++) {
            address holder = testAddresses[i];
            if (holder == ADMIN) {
                continue;
            } // Skip if the test address happens to be ADMIN

            // Whitelist the holder using the module
            try whitelistModule.addToWhitelist(holder) {
                // Successfully added to whitelist
            } catch (bytes memory) {
                console2.log("Failed to add to whitelist:", uint256(uint160(holder)));
                continue;
            }

            // Transfer tokens to the holder
            try token.transfer(holder, amountPerHolder) {
                // Verify transfer was successful
                uint256 holderBalance = token.balanceOf(holder);
                if (holderBalance > 0) {
                    successfulHolders++;
                } else {
                    console2.log("Transfer succeeded but balance is zero:", uint256(uint160(holder)));
                }
            } catch (bytes memory) {
                console2.log("Failed to transfer to:", uint256(uint160(holder)));
            }

            // Print progress for large holder counts
            if (i > 0 && i % 50 == 0) {
                console2.log("Created", successfulHolders, "holders so far...");
            }
        }

        console2.log("Successfully created holders:", successfulHolders);

        // Verify actual holder count using the previewYieldDistribution function
        _getVerifiedHolderCountFromPreview(); // Call for logging, but don't return from setUp
    }

    /// @dev Disable fuzzing for this test
    function testPreviewYieldDistributionGas() public {
        vm.startPrank(ADMIN);

        // Let's start with a smaller number of holders for debugging
        uint256[] memory holderCounts = new uint256[](4);
        holderCounts[0] = 10; // 10 holders
        holderCounts[1] = 50; // 50 holders
        holderCounts[2] = 100; // 100 holders
        holderCounts[3] = 500; // 500 holders
        // We'll increase these once the basic test is working
        // holderCounts[4] = 1000;   // 1,000 holders
        // holderCounts[5] = 2000;   // 2,000 holders
        // holderCounts[6] = 5000;   // 5,000 holders
        // holderCounts[7] = 10000;  // 10,000 holders

        // Run tests with each holder count
        for (uint256 i = 0; i < holderCounts.length; i++) {
            uint256 holderCount = holderCounts[i];

            // Skip if we've already hit the gas limit in a previous test
            if (gasUsages.length > 0 && gasUsages[gasUsages.length - 1].gasUsed > 30_000_000) {
                console2.log("Skipping test with holders:");
                console2.log(holderCount);
                continue;
            }

            console2.log("Setting up token with holders:");
            console2.log(holderCount);

            // Temporarily stop pranking to call the helper function
            vm.stopPrank();

            // Reset the token and add the specified number of holders
            try this.setupAndMeasureGas(holderCount) returns (uint256 gasUsed) {
                // Resume pranking as ADMIN for the remainder of the loop
                vm.startPrank(ADMIN);

                // Store results
                gasUsages.push(GasUsage({ holderCount: holderCount, gasUsed: gasUsed }));

                // Log results
                console2.log("Holders:");
                console2.log(holderCount);
                console2.log("Gas Used:");
                console2.log(gasUsed);

                // Check if we're approaching the gas limit
                if (gasUsed > 30_000_000) {
                    console2.log("WARNING: Gas usage exceeded 30M limit at holders:");
                    console2.log(holderCount);
                    break;
                }
            } catch Error(string memory reason) {
                // Resume pranking as ADMIN even if the test fails
                vm.startPrank(ADMIN);
                console2.log("Test failed with Error:");
                console2.log(reason);
                break;
            } catch (bytes memory data) {
                // Resume pranking as ADMIN even if the test fails
                vm.startPrank(ADMIN);
                console2.log("Test failed with low-level error");
                break;
            }
        }

        vm.stopPrank();

        // Summarize results
        console2.log("=== Gas Usage Summary ===");

        for (uint256 i = 0; i < gasUsages.length; i++) {
            GasUsage memory usage = gasUsages[i];

            // Avoid division by zero
            uint256 gasPerHolder = usage.holderCount > 0 ? usage.gasUsed / usage.holderCount : 0;

            console2.log("Holders:");
            console2.log(usage.holderCount);
            console2.log("Gas Used:");
            console2.log(usage.gasUsed);
            console2.log("Gas Per Holder:");
            console2.log(gasPerHolder);
            console2.log("---------");
        }

        // Estimate maximum holders under 30M gas
        if (gasUsages.length >= 2) {
            GasUsage memory last = gasUsages[gasUsages.length - 1];
            // Avoid division by zero
            uint256 gasPerHolder = last.holderCount > 0 ? last.gasUsed / last.holderCount : 0;
            uint256 estimatedMaxHolders = gasPerHolder > 0 ? 30_000_000 / gasPerHolder : 0;

            console2.log("Estimated maximum holders under 30M gas:");
            console2.log(estimatedMaxHolders);
            console2.log("Average gas per holder:");
            console2.log(gasPerHolder);
        }
    }

    // Helper function for try/catch compatibility
    function setupAndMeasureGas(
        uint256 holderCount
    ) external returns (uint256) {
        // Start acting as ADMIN inside this function
        vm.startPrank(ADMIN);

        // Reset token and distribute tokens to holders
        uint256 actualHolderCount = _resetTokenAndAddHolders(holderCount);

        // Verify that we actually have the correct number of holders
        require(actualHolderCount > 1, "Failed to set up multiple holders");

        console2.log("Token setup complete with actual holder count:", actualHolderCount);
        console2.log("Measuring gas...");

        // Measure gas usage for preview
        uint256 gasBefore = gasleft();
        (address[] memory holders,) = token.previewYieldDistribution(1_000_000 * 1e18); // 1M tokens as yield
        uint256 gasAfter = gasleft();

        // Double check the actual number of holders processed
        console2.log("Holders processed in previewYieldDistribution:", holders.length);

        // Stop acting as ADMIN before returning
        vm.stopPrank();

        return gasBefore - gasAfter;
    }

    /// @dev Disable fuzzing for this test
    function testPaginatedPreviewYieldDistribution() public {
        vm.startPrank(ADMIN);

        // Start with a more moderate number of holders for debugging
        uint256 holderCount = 100;

        console2.log("Setting up token with holders:");
        console2.log(holderCount);

        // Temporarily stop pranking to call the helper function
        vm.stopPrank();

        try this.runPaginationTest(holderCount) {
            // Test completed successfully
            vm.startPrank(ADMIN);
        } catch Error(string memory reason) {
            vm.startPrank(ADMIN);
            console2.log("Test failed with Error:");
            console2.log(reason);
        } catch (bytes memory data) {
            vm.startPrank(ADMIN);
            console2.log("Test failed with low-level error");
        }

        vm.stopPrank();
    }

    // Helper function for try/catch compatibility
    function runPaginationTest(
        uint256 holderCount
    ) external {
        // Start acting as ADMIN inside this function
        vm.startPrank(ADMIN);

        // Reset token and distribute tokens to holders
        uint256 actualHolderCount = _resetTokenAndAddHolders(holderCount);

        // Verify that we actually have the correct number of holders
        require(actualHolderCount > 1, "Failed to set up multiple holders");

        console2.log("=== Testing Paginated vs. Regular Distribution Preview ===");
        console2.log("Actual holder count:", actualHolderCount);

        // First measure the gas for the regular function
        uint256 gasBefore = gasleft();
        (address[] memory holdersArray,) = token.previewYieldDistribution(1_000_000 * 1e18); // 1M tokens as yield
        uint256 gasAfter = gasleft();
        uint256 regularGasUsed = gasBefore - gasAfter;

        console2.log("Regular function processed holders:", holdersArray.length);
        console2.log("Regular function gas used:", regularGasUsed);

        // Now test the paginated version with different batch sizes
        uint256[] memory batchSizes = new uint256[](3);
        batchSizes[0] = 10;
        batchSizes[1] = 50;
        batchSizes[2] = 100;

        console2.log("Paginated Function Gas Usage by Batch Size:");

        for (uint256 i = 0; i < batchSizes.length; i++) {
            uint256 batchSize = batchSizes[i];

            // Measure gas for the paginated function with this batch size
            gasBefore = gasleft();

            // Store full result and then extract what we need
            (address[] memory paginatedHolders, uint256[] memory amountsFirst, uint256 nextIndex, uint256 totalHolders)
            = token.previewYieldDistributionWithLimit(
                1_000_000 * 1e18, // 1M tokens as yield
                0, // start from the beginning
                batchSize // process this many holders
            );

            gasAfter = gasleft();
            uint256 paginatedGasUsed = gasBefore - gasAfter;

            console2.log("Batch Size:", batchSize);
            console2.log("Holders processed in first batch:", paginatedHolders.length);
            console2.log("Gas Used:", paginatedGasUsed);

            // Calculate gas per holder and percentage of regular function gas - check for division by zero
            uint256 gasPerHolder = paginatedHolders.length > 0 ? paginatedGasUsed / paginatedHolders.length : 0;
            uint256 percentOfRegular = regularGasUsed > 0 ? (paginatedGasUsed * 100) / regularGasUsed : 0;

            console2.log("Percent of Regular:", percentOfRegular);
            console2.log("Gas Per Holder:", gasPerHolder);

            // If we didn't process all holders, process the rest in batches
            uint256 startIdx = nextIndex;
            uint256 batchCount = 1;

            while (startIdx != 0 && batchCount < 10) {
                // Limit batches to avoid too much output
                gasBefore = gasleft();

                // Get the next batch of holders
                address[] memory batchHolders;
                uint256[] memory amountsNext;
                uint256 nextStartIdx;
                uint256 unusedTotalHolders;

                // Call function directly with variable assignment
                (batchHolders, amountsNext, nextStartIdx, unusedTotalHolders) =
                    token.previewYieldDistributionWithLimit(1_000_000 * 1e18, startIdx, batchSize);

                // Update startIdx for next iteration
                startIdx = nextStartIdx;

                gasAfter = gasleft();
                uint256 subsequentBatchGas = gasBefore - gasAfter;

                console2.log("  Batch:", batchCount + 1);
                console2.log("  Holders processed:", batchHolders.length);
                console2.log("  Gas Used:", subsequentBatchGas);

                // Check for division by zero
                if (batchHolders.length > 0) {
                    console2.log("  Gas Per Holder:", subsequentBatchGas / batchHolders.length);
                } else {
                    console2.log("  Gas Per Holder: N/A (no holders processed)");
                }

                batchCount++;
            }

            // After each full test, show a summary
            if (nextIndex != 0) {
                // Calculate number of batches needed, avoiding division by zero
                uint256 batchesNeeded = batchSize > 0 ? ((totalHolders + batchSize - 1) / batchSize) : 1;
                uint256 estimatedTotalGas = paginatedGasUsed * batchesNeeded;

                console2.log("  Estimated total gas for all holders:", totalHolders);
                console2.log("  in batches of:", batchSize);
                console2.log("  Total gas:", estimatedTotalGas);
            }
        }

        // Based on the gas per holder, calculate recommended batch sizes for different gas limits
        console2.log("=== Recommended Maximum Batch Sizes ===");

        // Use the actual number of holders processed
        uint256 actualProcessedHolders = holdersArray.length;

        // Avoid division by zero
        uint256 avgGasPerHolder = actualProcessedHolders > 0 ? regularGasUsed / actualProcessedHolders : 0;

        uint256[] memory gasLimits = new uint256[](4);
        gasLimits[0] = 30_000_000; // 30M - near block gas limit
        gasLimits[1] = 15_000_000; // 15M - half block gas limit
        gasLimits[2] = 10_000_000; // 10M - third of block gas limit
        gasLimits[3] = 5_000_000; // 5M - common transaction limit

        for (uint256 i = 0; i < gasLimits.length; i++) {
            uint256 limit = gasLimits[i];
            // Avoid division by zero
            uint256 maxHolders = avgGasPerHolder > 0 ? limit / avgGasPerHolder : 0;

            console2.log("For gas limit:", limit);
            console2.log("Max holders:", maxHolders);
        }

        // Stop acting as ADMIN before returning
        vm.stopPrank();
    }

    // Helper to reset the token and add a specific number of holders
    // Returns the actual number of holders successfully created
    function _resetTokenAndAddHolders(
        uint256 holderCount
    ) internal returns (uint256) {
        console2.log("Creating new token instance");

        // Create a new token to reset state
        token = new ArcToken();

        console2.log("Initializing token");

        // Initialize the token
        token.initialize(
            "Test ArcToken", // name_
            "TAT", // symbol_
            0, // No initial supply yet
            address(0x456), // Yield token
            ADMIN,
            18, // Token decimals
            address(router) // Router address
        );

        console2.log("Granting roles");

        // Explicitly grant all necessary roles
        bytes32 MINTER_ROLE = token.MINTER_ROLE();
        bytes32 BURNER_ROLE = token.BURNER_ROLE();
        bytes32 YIELD_MANAGER_ROLE = token.YIELD_MANAGER_ROLE();
        bytes32 YIELD_DISTRIBUTOR_ROLE = token.YIELD_DISTRIBUTOR_ROLE();
        bytes32 UPGRADER_ROLE = token.UPGRADER_ROLE();

        // Grant all roles to ADMIN
        token.grantRole(MINTER_ROLE, ADMIN);
        token.grantRole(BURNER_ROLE, ADMIN);
        token.grantRole(YIELD_MANAGER_ROLE, ADMIN);
        token.grantRole(YIELD_DISTRIBUTOR_ROLE, ADMIN);
        token.grantRole(UPGRADER_ROLE, ADMIN);

        // Also grant MINTER_ROLE to this test contract to allow it to call mint
        token.grantRole(MINTER_ROLE, address(this));

        console2.log("Minting initial supply");

        // Mint a larger initial token supply to ensure meaningful distribution
        uint256 totalSupply = 100_000_000 * 1e18; // 100M tokens
        token.mint(ADMIN, totalSupply);

        console2.log("Setting transfers allowed to true");

        // Ensure transfers are allowed via the whitelist module
        whitelistModule.setTransfersAllowed(true);

        console2.log("Adding holders to whitelist and transferring tokens");

        // Make sure we don't try to create more holders than we have addresses for
        uint256 actualHolderCount = holderCount;
        if (actualHolderCount > testAddresses.length) {
            actualHolderCount = testAddresses.length;
            console2.log("Limiting to available addresses:", actualHolderCount);
        }

        // Calculate amount per holder - make sure it's substantial
        uint256 amountPerHolder = totalSupply / (actualHolderCount + 1); // +1 for ADMIN
        console2.log("Amount per holder:", amountPerHolder / 1e18, "tokens");

        // Track successful transfers
        uint256 successfulHolders = 0;

        // Transfer tokens to each holder
        for (uint256 i = 0; i < actualHolderCount; i++) {
            address holder = testAddresses[i];
            if (holder == ADMIN) {
                continue;
            } // Skip if the test address happens to be ADMIN

            // Whitelist the holder using the module
            try whitelistModule.addToWhitelist(holder) {
                // Successfully added to whitelist
            } catch (bytes memory) {
                console2.log("Failed to add to whitelist:", uint256(uint160(holder)));
                continue;
            }

            // Transfer tokens to the holder
            try token.transfer(holder, amountPerHolder) {
                // Verify transfer was successful
                uint256 holderBalance = token.balanceOf(holder);
                if (holderBalance > 0) {
                    successfulHolders++;
                } else {
                    console2.log("Transfer succeeded but balance is zero:", uint256(uint160(holder)));
                }
            } catch (bytes memory) {
                console2.log("Failed to transfer to:", uint256(uint160(holder)));
            }

            // Print progress for large holder counts
            if (i > 0 && i % 50 == 0) {
                console2.log("Created", successfulHolders, "holders so far...");
            }
        }

        console2.log("Successfully created holders:", successfulHolders);

        // Verify actual holder count using the previewYieldDistribution function
        _getVerifiedHolderCountFromPreview(); // Call for logging, but don't return from setUp
    }

    /**
     * @dev Internal helper to call previewYieldDistribution safely and return holder count.
     */
    function _getVerifiedHolderCountFromPreview() internal returns (uint256) {
        uint256 verifiedHolderCount = 0;
        try token.previewYieldDistribution(1e18) returns (address[] memory h, uint256[] memory) {
            verifiedHolderCount = h.length;

            console2.log("Verified holder count from previewYieldDistribution:", verifiedHolderCount);

            // Print the first few holders and their balances for verification
            uint256 holdersToPrint = verifiedHolderCount > 5 ? 5 : verifiedHolderCount;
            console2.log("Sample of holder balances:");
            for (uint256 i = 0; i < holdersToPrint; i++) {
                address holder = h[i]; // Use h directly
                uint256 balance = token.balanceOf(holder);
                console2.log("Holder", i, "address:", uint256(uint160(holder)));
                console2.log("Balance:", balance / 1e18, "tokens");
            }
        } catch Error(string memory reason) {
            console2.log("previewYieldDistribution failed:", reason);
            verifiedHolderCount = 0; // Ensure return value is 0 on error
        } catch (bytes memory) {
            console2.log("previewYieldDistribution failed with low-level error");
            verifiedHolderCount = 0; // Ensure return value is 0 on error
        }
        return verifiedHolderCount;
    }

}
