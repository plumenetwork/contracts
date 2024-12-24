// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IComponentToken } from "../interfaces/IComponentToken.sol";

import { IAtomicQueue } from "../interfaces/IAtomicQueue.sol";
import { NestBoringVaultModule } from "./NestBoringVaultModule.sol";
import { AtomicQueue } from "@boringvault/src/atomic-queue/AtomicQueue.sol";

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

    // Public State

    // Constants
    uint256 public constant REQUEST_ID = 0;

    // Public State
    uint256 public deadlinePeriod;
    uint256 public pricePercentage; // Must be 4 decimals i.e. 9999 = 99.99%

    // Events
    event RequestRedeem(uint256 shares, address controller, address owner);

    constructor(
        address _owner,
        address _vault,
        address _accountant,
        IERC20 _asset,
        uint256 _deadlinePeriod,
        uint256 _pricePercentage
    ) NestBoringVaultModule(_owner, _vault, _accountant, _asset) {
        deadlinePeriod = _deadlinePeriod;
        pricePercentage = _pricePercentage;
    }

    /**
     * @notice Transfer shares from the owner into the vault and submit a request to redeem assets
     * @param shares Amount of shares to redeem
     * @param controller Controller of the request
     * @param owner Source of the shares to redeem
     * @return requestId Discriminator between non-fungible requests
     */
    function requestRedeem(
        uint256 shares,
        address controller,
        address owner
    ) public override returns (uint256 requestId) {
        if (owner != msg.sender) {
            revert InvalidOwner();
        }

        if (controller != msg.sender) {
            revert InvalidController();
        }

        // Create and submit atomic request
        IAtomicQueue.AtomicRequest memory request = IAtomicQueue.AtomicRequest({
            deadline: uint64(block.timestamp + deadlinePeriod),
            atomicPrice: uint88(
                accountantContract.getRateInQuote(IERC20(address(assetToken))).mulDivDown(pricePercentage, 10_000)
            ),
            offerAmount: uint96(shares),
            inSolve: false
        });

        super.updateAtomicRequest(IERC20(address(vaultContract)), assetToken, request);

        emit RequestRedeem(shares, controller, owner);

        return REQUEST_ID;
    }

    function deposit(uint256 assets, address receiver, address controller) public override returns (uint256) {
        revert Unimplemented();
    }

}
