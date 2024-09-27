// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { ISmartWallet } from "./interfaces/ISmartWallet.sol";

/**
 * @title WalletFactory
 * @author Eugene Y. Q. Shen
 * @notice Factory contract for deploying and upgrading the SmartWallet implementation.
 *   The WalletFactory is deployed to 0x71482d5de04ea98af2df339a14e8e03be463516c.
 * @dev The WalletProxy calls the WalletFactory to get the address of the SmartWallet.
 *   The WalletFactory address must be fixed to make WalletProxy bytecode immutable.
 *   Only the owner can upgrade the SmartWallet by updating the implementation address.
 */
contract WalletFactory is Ownable {

    /// @notice Address of the current SmartWallet implementation
    ISmartWallet public smartWallet;

    /**
     * @notice Construct the WalletFactory
     * @param owner_ Address of the owner of the WalletFactory
     * @param smartWallet_ Initial SmartWallet implementation
     * @dev The owner of the WalletFactory should be set to Plume Governance once ready
     */
    constructor(address owner_, ISmartWallet smartWallet_) Ownable(owner_) {
        smartWallet = smartWallet_;
    }

    /**
     * @notice Upgrade the SmartWallet implementation
     * @dev Only the WalletFactory owner can upgrade the SmartWallet implementation
     * @param smartWallet_ New SmartWallet implementation
     */
    function upgrade(
        ISmartWallet smartWallet_
    ) public onlyOwner {
        smartWallet = smartWallet_;
    }

}
