// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { AggregateToken } from "../src/AggregateToken.sol";
import { AggregateTokenProxy } from "../src/proxy/AggregateTokenProxy.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";

contract UpgradeNestContracts is Script {

    address private constant NEST_ADMIN_ADDRESS = 0xb015762405De8fD24d29A6e0799c12e0Ea81c1Ff;

    UUPSUpgradeable private constant AGGREGATE_TOKEN_PROXY =
        UUPSUpgradeable(payable(0x659619AEdf381c3739B0375082C2d61eC1fD8835));

    function run() external {
        vm.startBroadcast(NEST_ADMIN_ADDRESS);

        // Get private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console2.log("Deploying with address:", deployer);

        if (deployer == NEST_ADMIN_ADDRESS) {
            AggregateToken newAggregateTokenImpl = new AggregateToken();
            address newImplAddress = address(newAggregateTokenImpl);

            require(address(newAggregateTokenImpl).code.length > 0, "Implementation contract 0 byte code");

            console2.log("New AggregateToken Implementation deployed to:", address(newAggregateTokenImpl));

            AGGREGATE_TOKEN_PROXY.upgradeToAndCall(address(newAggregateTokenImpl), "");

            // Get implementation address after upgrade
            address implAddress = address(
                uint160(
                    uint256(
                        vm.load(
                            address(AGGREGATE_TOKEN_PROXY),
                            // ERC1967 IMPLEMENTATION storage slot
                            0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc
                        )
                    )
                )
            );

            require(implAddress == newImplAddress, "Implementation address mismatch");

            console2.log("Upgrade completed successfully");
        } else {
            console2.log("we need NEST_ADMIN_ADDRESS PK to upgrade AggregateToken, please try again with correct PK.");
        }

        vm.stopBroadcast();
    }

}
