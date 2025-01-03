// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { Auth, Authority } from "@solmate/auth/Auth.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { FixedPointMathLib } from "@solmate/utils/FixedPointMathLib.sol";

import { AtomicQueue } from "@boringvault/src/atomic-queue/AtomicQueue.sol";

import { IAtomicQueue } from "../interfaces/IAtomicQueue.sol";
import { NestBoringVaultModule } from "./NestBoringVaultModule.sol";

/**
 * @title NestAtomicQueue
 * @notice AtomicQueue implementation for the Nest vault
 * @dev An AtomicQueue that only allows withdraws into a single `asset` that is
 * configured.
 */
contract NestAtomicQueue is Initializable, NestBoringVaultModule, AtomicQueue {

    using SafeCast for uint256;
    using FixedPointMathLib for uint256;

    // Public State

    // Constants
    uint256 public constant REQUEST_ID = 0;

    // Public State
    uint256 public deadlinePeriod;
    uint256 public pricePercentage; // Must be 4 decimals i.e. 9999 = 99.99%
    IAtomicQueue public atomicQueue;

    // Events

    event RequestRedeem(uint256 shares, address controller, address owner);

    constructor(
        address _owner
    ) {
        _disableInitializers();
    }

    function initialize(
        address _vault,
        address _accountant,
        IERC20 _asset,
        uint256 _deadlinePeriod,
        uint256 _pricePercentage
    ) public initializer {
        __NestBoringVaultModule_init(_vault, _accountant, _asset);
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
    ) public virtual override returns (uint256 requestId) {
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

        atomicQueue.updateAtomicRequest(IERC20(address(vaultContract)), assetToken, request);

        emit RequestRedeem(shares, controller, owner);

        return REQUEST_ID;
    }

    /**
     * @notice Fulfill a request to buy shares by minting shares to the receiver
     * @param assets Amount of `asset` that was deposited by `requestDeposit`
     * @param receiver Address to receive the shares
     * @param controller Controller of the request
     */
    function deposit(
        uint256 assets,
        address receiver,
        address controller
    ) public virtual override returns (uint256 shares) {
        revert Unimplemented();
    }

}
