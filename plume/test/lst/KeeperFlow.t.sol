// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Test, console2 } from "forge-std/Test.sol";
import { stPlumeMinter } from "../../src/lst/stPlumeMinter.sol";

interface IValidatorFacetView {
    struct ValidatorListData { uint16 id; uint256 totalStaked; uint256 commission; }
    function getValidatorsList() external view returns (ValidatorListData[] memory list);
}

contract KeeperFlowTest is Test {
    stPlumeMinter internal minter;
    IValidatorFacetView internal diamond;

    address internal MINTER_OWNER;
    address internal REBALANCER;
    address internal CLAIMER;
    address internal USER;

    function setUp() public {
        // Fork if RPC_URL is set
        string memory rpc = vm.envOr("RPC_URL", string(""));
        if (bytes(rpc).length > 0) {
            uint256 forkId = vm.createSelectFork(rpc);
            console2.log("Using fork", forkId);
        }
        address minterAddr = vm.envAddress("STPLUME_MINTER");
        address diamondAddr = vm.envAddress("DIAMOND_PROXY");
        minter = stPlumeMinter(minterAddr);
        diamond = IValidatorFacetView(diamondAddr);

        MINTER_OWNER = vm.envOr("MINTER_OWNER", address(0));
        REBALANCER = vm.envOr("REBALANCER", address(0));
        CLAIMER = vm.envOr("CLAIMER", address(0));
        USER = vm.envOr("USER", address(0));

        vm.label(minterAddr, "stPlumeMinter");
        vm.label(diamondAddr, "Diamond");
        if (MINTER_OWNER != address(0)) vm.label(MINTER_OWNER, "MinterOwner");
        if (REBALANCER != address(0)) vm.label(REBALANCER, "Rebalancer");
        if (CLAIMER != address(0)) vm.label(CLAIMER, "Claimer");
        if (USER != address(0)) vm.label(USER, "User");
    }

    function test_SyncValidatorsIfMissing() public {
        if (MINTER_OWNER == address(0)) { console2.log("skip: MINTER_OWNER not set"); return; }
        IValidatorFacetView.ValidatorListData[] memory list = diamond.getValidatorsList();
        console2.log("diamond validators", list.length);
        if (list.length == 0) return; // nothing to sync

        // Optimistically add first validator if minter doesn't have it
        uint16 vid = list[0].id;
        // Check existence in minter registry (linear search acceptable for test)
        bool found = false;
        uint256 cur = minter.numValidators();
        for (uint256 i = 0; i < cur; i++) {
            if (minter.getValidator(i) == vid) { found = true; break; }
        }
        if (!found) {
            vm.prank(MINTER_OWNER);
            minter.addValidator(minter.getValidatorStruct(vid));
            // Assert now present
            found = false; cur = minter.numValidators();
            for (uint256 j = 0; j < cur; j++) { if (minter.getValidator(j) == vid) { found = true; break; } }
            assertTrue(found, "validator not added to minter");
        }
    }

    function test_DeployBucketsAndViews() public {
        if (MINTER_OWNER == address(0)) { console2.log("skip: MINTER_OWNER not set"); return; }
        IValidatorFacetView.ValidatorListData[] memory list = diamond.getValidatorsList();
        if (list.length == 0) { console2.log("skip: no validators on diamond"); return; }
        uint16 vid = list[0].id;
        // Add 2 buckets if none
        (uint256 totalBuckets,,) = minter.getBucketAvailabilitySummary(vid);
        if (totalBuckets == 0) {
            vm.prank(MINTER_OWNER);
            minter.addBuckets(vid, 2);
        }
        (totalBuckets,,) = minter.getBucketAvailabilitySummary(vid);
        assertGt(totalBuckets, 0, "buckets not added");
        // Read buffer stats
        (uint256 buf,, uint256 unstaked,,) = minter.getBufferAndQueueStats();
        console2.log("buffer", buf, "unstakedTotal", unstaked);
    }

    function test_SweepAndFulfillFIFO() public {
        if (REBALANCER == address(0)) { console2.log("skip: REBALANCER not set"); return; }
        IValidatorFacetView.ValidatorListData[] memory list = diamond.getValidatorsList();
        if (list.length == 0) { console2.log("skip: no validators on diamond"); return; }
        uint16 vid = list[0].id;

        vm.prank(REBALANCER);
        minter.sweepMaturedBuckets(vid, 3);

        if (USER == address(0)) { console2.log("skip: USER not set"); return; }
        (uint256[] memory ids, , , , uint256 count) = minter.getReadyRequestsForUser(USER, 0, 5);
        if (count == 0) { console2.log("no ready requests; skipping fulfill"); return; }
        address[] memory users = new address[](count);
        uint256[] memory useIds = new uint256[](count);
        for (uint256 i = 0; i < count; i++) { users[i] = USER; useIds[i] = ids[i]; }

        vm.prank(REBALANCER);
        (uint256 processed, uint256 paid) = minter.fulfillRequests(users, useIds);
        console2.log("fulfilled", processed, "paid", paid);
        assertEq(processed, users.length, "not all processed");
    }

    function test_SweepAndFulfillProRata() public {
        if (REBALANCER == address(0)) { console2.log("skip: REBALANCER not set"); return; }
        IValidatorFacetView.ValidatorListData[] memory list = diamond.getValidatorsList();
        if (list.length == 0) { console2.log("skip: no validators on diamond"); return; }
        uint16 vid = list[0].id;
        vm.prank(REBALANCER);
        minter.sweepMaturedBuckets(vid, 2);

        if (USER == address(0)) { console2.log("skip: USER not set"); return; }
        (uint256[] memory ids, , , , uint256 count) = minter.getReadyRequestsForUser(USER, 0, 5);
        if (count == 0) { console2.log("no ready requests; skipping fulfill"); return; }
        address[] memory users = new address[](count);
        uint256[] memory useIds = new uint256[](count);
        for (uint256 i = 0; i < count; i++) { users[i] = USER; useIds[i] = ids[i]; }

        vm.prank(REBALANCER);
        (uint256 spent, uint256 processed, uint256 paid) = minter.fulfillProRata(users, useIds, 1 ether);
        console2.log("pro-rata spent", spent, "processed", processed, "paid", paid);
        assertGt(spent, 0, "pro-rata spent 0");
    }
}


