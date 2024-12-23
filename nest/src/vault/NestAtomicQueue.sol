// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IComponentToken } from "../interfaces/IComponentToken.sol";

import { NestBoringVaultModule } from "./NestBoringVaultModule.sol";
import { AtomicQueue } from "@nucleus-boring-vault/base/AtomicQueue.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
/**
 * @title NestAtomicQueue
 * @notice AtomicQueue implementation for the Nest vault
 * @dev An AtomicQueue that only allows withdraws into a single `asset` that is
 * configured.
 */

contract NestAtomicQueue is NestBoringVaultModule, AtomicQueue {

    using SafeCast for uint256;

    // Constants

    uint256 public constant REQUEST_ID = 0;

    // Public State

    address public vault;
    address public accountant;
    uint256 public decimals; // Always set to vault decimals
    IERC20 public asset;
    uint256 public deadlinePeriod;
    uint256 public pricePercentage; // Must be 4 decimals i.e. 9999 = 99.99%

    // Errors

    error Unimplemented();

    /**
     * @notice Transfer shares from the owner into the vault and submit a request to redeem assets
     * @param shares Amount of shares to redeem
     * @param controller Controller of the request
     * @param owner Source of the shares to redeem
     * @return requestId Discriminator between non-fungible requests
     */
    function requestRedeem(uint256 shares, address controller, address owner) public returns (uint256 requestId) {
        if (owner != msg.sender) {
            revert InvalidOwner();
        }

        if (controller != msg.sender) {
            revert InvalidController();
        }

        // Create and submit atomic request
        IAtomicQueue.AtomicRequest memory request = IAtomicQueue.AtomicRequest({
            deadline: block.timestamp + deadlinePeriod,
            atomicPrice: accountant.getRateInQuote(asset).mulDivDown(pricePercentage, 10_000).toUint88(), // Price per
                // share in terms of asset
            offerAmount: uint96(shares),
            inSolve: false
        });

        updateAtomicRequest(IERC20(vault), asset, request);

        emit RequestRedeem(shares, controller, owner);

        return REQUEST_ID;
    }

}
