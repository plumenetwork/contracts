// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "forge-std/Test.sol";

contract nYieldStakingTest is Test {

    function test_StorageSlot() public {
        // Calculate the storage slot
        bytes32 slot =
            keccak256(abi.encode(uint256(keccak256("plume.storage.nYieldStaking")) - 1)) & ~bytes32(uint256(0xff));

        // Log the results for verification
        console.logBytes32(keccak256("plume.storage.nYieldStaking"));
        console.log("Minus 1:");
        console.logBytes32(bytes32(uint256(keccak256("plume.storage.nYieldStaking")) - 1));
        console.log("Final slot:");
        console.logBytes32(slot);

        // Optional: Convert to uint256 for decimal representation
        console.log("Slot as uint256:", uint256(slot));
    }

}
