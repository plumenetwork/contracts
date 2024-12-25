// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IComponentToken } from "../interfaces/IComponentToken.sol";

import { IAtomicQueue } from "../interfaces/IAtomicQueue.sol";
import { NestBoringVaultModule } from "./NestBoringVaultModule.sol";
import { AtomicQueue } from "@boringvault/src/atomic-queue/AtomicQueue.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { Auth, Authority } from "@solmate/auth/Auth.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { FixedPointMathLib } from "@solmate/utils/FixedPointMathLib.sol";

/**
 * @title NestAtomicQueue
 * @notice AtomicQueue implementation for the Nest vault
 * @dev An AtomicQueue that only allows withdraws into a single `asset` that is
 * configured.
 */
contract NestAtomicQueue is NestBoringVaultModule, AtomicQueue {

    using SafeCast for uint256;
    using FixedPointMathLib for uint256;

    // Public State

    // Constants
    uint256 public constant REQUEST_ID = 0;

    // Public State
    uint256 public deadlinePeriod;
    uint256 public pricePercentage; // Must be 4 decimals i.e. 9999 = 99.99%
    IAtomicQueue public immutable atomicQueue;
    // Events

    event RequestRedeem(uint256 shares, address controller, address owner);

    constructor(
        address _owner,
        address _vault,
        address _accountant,
        IERC20 _asset,
        uint256 _deadlinePeriod,
        uint256 _pricePercentage
    )
        Auth(_owner, Authority(address(0))) // Initialize Auth
        NestBoringVaultModule(_owner, _vault, _accountant, _asset)
        AtomicQueue() // AtomicQueue inherits from Auth, so we don't pass parameters here
    {
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
                accountantContract.getRateInQuote(ERC20(address(assetToken))).mulDivDown(pricePercentage, 10_000)
            ),
            offerAmount: uint96(shares),
            inSolve: false
        });

        //updateAtomicRequest(IERC20(address(vaultContract)), assetToken, request);
        atomicQueue.updateAtomicRequest(IERC20(address(vaultContract)), assetToken, request);

        emit RequestRedeem(shares, controller, owner);

        return REQUEST_ID;
    }

  function redeem(
        uint256 shares,
        address receiver,
        address controller
    ) public override returns (uint256 assets) {
        if (shares == 0) {
            revert ZeroAmount();
        }
        if (msg.sender != controller) {
            revert Unauthorized(msg.sender, controller);
        }

        // Get the atomic request for this asset pair
        IAtomicQueue.AtomicRequest memory request = atomicQueue.getAtomicRequest(IERC20(address(vaultContract)), assetToken);
        
        if (request.inSolve) {
            revert AtomicQueue.RequestInSolve();
        }

        if (block.timestamp > request.deadline) {
            revert AtomicQueue.RequestExpired();
        }

        // Verify the shares match the request
        if (shares != request.offerAmount) {
            revert AtomicQueue.InvalidRedeemAmount(shares, request.offerAmount);
        }

        // Calculate assets to receive based on atomic price
        assets = uint256(request.offerAmount).mulDivDown(request.atomicPrice, 10 ** decimals);
        
        // Clear the request
        AtomicQueue.deleteAtomicRequest(IERC20(address(vaultContract)), assetToken);
        
        // Transfer assets to receiver
        SafeERC20.safeTransfer(IERC20(asset()), receiver, assets);

        emit Withdraw(controller, receiver, controller, assets, shares);
        return assets;
    }


    function deposit(uint256 assets, address receiver, address controller) public override returns (uint256) {
        revert Unimplemented();
    }

}
