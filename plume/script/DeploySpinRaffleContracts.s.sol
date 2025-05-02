// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";

import { Spin } from "../src/spin/Spin.sol";
import { Raffle } from "../src/spin/Raffle.sol";
import { SpinProxy } from "../src/proxy/SPINProxy.sol";
import { RaffleProxy } from "../src/proxy/RaffleProxy.sol";

import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

interface IDepositContract {
    function addContractToWhitelist(address _contractAddress) external;
}

contract DeploySpinRaffleContracts is Script {
    // These will be replaced with actual addresses for your environment
    address private SUPRA_ROUTER_ADDRESS;
    address private SUPRA_GENERATOR_ADDRESS;
    address private SUPRA_DEPOSIT_ADDRESS;
    address private DATETIME_ADDRESS;
    string private BLOCKSCOUT_URL;

    function run() external {
        // Load private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Set contract addresses from environment or use defaults
        SUPRA_ROUTER_ADDRESS = vm.envOr("SUPRA_ROUTER_ADDRESS", address(0xE1062AC81e76ebd17b1e283CEed7B9E8B2F749A5));
        SUPRA_GENERATOR_ADDRESS = vm.envOr("SUPRA_GENERATOR_ADDRESS", address(0x8cC8bbE991d8B4371551B4e666Aa212f9D5f165e));
        SUPRA_DEPOSIT_ADDRESS = vm.envOr("SUPRA_DEPOSIT_ADDRESS", address(0x6DA36159Fe94877fF7cF226DBB164ef7f8919b9b));
        DATETIME_ADDRESS = vm.envOr("DATETIME_ADDRESS", address(0x06a40Ec10d03998634d89d2e098F079D06A8FA83));
        BLOCKSCOUT_URL = vm.envOr("BLOCKSCOUT_URL", string("https://phoenix-explorer.plumenetwork.xyz/api?"));
        
        // Get chain ID
        uint256 chainId = block.chainid;
        
        // Get deployer address from private key
        address deployerAddress = vm.addr(deployerPrivateKey);
        console2.log("Deploying from:", deployerAddress);
        console2.log("Chain ID:", chainId);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy Spin implementation
        Spin spinImplementation = new Spin();
        console2.log("Spin implementation deployed to:", address(spinImplementation));

        // 2. Create initialization data for SpinProxy
        bytes memory spinInitData = abi.encodeCall(
            Spin.initialize, 
            (SUPRA_ROUTER_ADDRESS, DATETIME_ADDRESS)
        );
        console2.log("Spin init data (for verification):", vm.toString(spinInitData));
        
        // 3. Deploy SpinProxy
        SpinProxy spinProxy = new SpinProxy(address(spinImplementation), spinInitData);
        console2.log("Spin Proxy deployed to:", address(spinProxy));

        // 4. Deploy Raffle implementation
        Raffle raffleImplementation = new Raffle();
        console2.log("Raffle implementation deployed to:", address(raffleImplementation));

        // 5. Create initialization data for RaffleProxy
        bytes memory raffleInitData = abi.encodeCall(
            Raffle.initialize, 
            (address(spinProxy), SUPRA_ROUTER_ADDRESS)
        );
        console2.log("Raffle init data (for verification):", vm.toString(raffleInitData));
        
        // 6. Deploy RaffleProxy
        RaffleProxy raffleProxy = new RaffleProxy(address(raffleImplementation), raffleInitData);
        console2.log("Raffle Proxy deployed to:", address(raffleProxy));

        // 7. Set Raffle contract in Spin
        (bool success,) = address(spinProxy).call(
            abi.encodeCall(Spin.setRaffleContract, (address(raffleProxy)))
        );
        require(success, "Failed to set raffle contract in Spin");
        console2.log("Set Raffle contract in Spin");

        // 8. Set Raffle contract in Supra Deposit whitelist
        (bool success2,) = address(SUPRA_DEPOSIT_ADDRESS).call(
            abi.encodeCall(IDepositContract.addContractToWhitelist, (address(raffleProxy)))
        );
        require(success2, "Failed to add raffle contract to Supra Deposit whitelist");
        console2.log("Added Raffle contract to Supra Deposit whitelist");

        // 9. Set Spin contract in Supra Deposit whitelist
        (bool success3,) = address(SUPRA_DEPOSIT_ADDRESS).call(
            abi.encodeCall(IDepositContract.addContractToWhitelist, (address(spinProxy)))
        );
        require(success3, "Failed to add Spin contract to Supra Deposit whitelist");
        console2.log("Added Spin contract to Supra Deposit whitelist");

        // 10. Grant the SUPRA role to the Spin contract
        (bool success4,) = address(spinProxy).call(
            abi.encodeCall(IAccessControl.grantRole, (0xca6d81dc91a9576e680308117122bf1f28b390614c22ddf0b1098f9cc2a3e86c, address(SUPRA_GENERATOR_ADDRESS)))
        );
        require(success4, "Failed to grant SUPRA role to Supra Generator address in the new Spin Proxy contract");
        console2.log("Granted SUPRA role to Supra Generator address in the new Spin Proxy contract");



        // Print verification commands for Blockscout
        console2.log("\n--- Blockscout Verification Commands ---");
        console2.log("Spin implementation verification:");
        console2.log(string.concat("forge verify-contract --chain-id ", vm.toString(chainId), " --verifier blockscout --verifier-url ", BLOCKSCOUT_URL, " ", vm.toString(address(spinImplementation)), " src/spin/Spin.sol:Spin"));
        
        console2.log("\nRaffle implementation verification:");
        console2.log(string.concat("forge verify-contract --chain-id ", vm.toString(chainId), " --verifier blockscout --verifier-url ", BLOCKSCOUT_URL, " ", vm.toString(address(raffleImplementation)), " src/spin/Raffle.sol:Raffle"));
        
        // For proxies, include constructor args
        bytes memory spinProxyArgs = abi.encode(address(spinImplementation), spinInitData);
        console2.log("\nSpin Proxy verification:");
        console2.log(string.concat("forge verify-contract --chain-id ", vm.toString(chainId), " --verifier blockscout --verifier-url ", BLOCKSCOUT_URL, " ", vm.toString(address(spinProxy)), " src/proxy/SPINProxy.sol:SpinProxy --constructor-args ", vm.toString(spinProxyArgs)));
        
        bytes memory raffleProxyArgs = abi.encode(address(raffleImplementation), raffleInitData);
        console2.log("\nRaffle Proxy verification:");
        console2.log(string.concat("forge verify-contract --chain-id ", vm.toString(chainId), " --verifier blockscout --verifier-url ", BLOCKSCOUT_URL, " ", vm.toString(address(raffleProxy)), " src/proxy/RaffleProxy.sol:RaffleProxy --constructor-args ", vm.toString(raffleProxyArgs)));
        
        vm.stopBroadcast();
    }
}