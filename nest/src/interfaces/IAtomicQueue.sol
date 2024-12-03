// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IAtomicQueue
 * @notice Interface for AtomicQueue contract that allows users to create requests to exchange
 *         one ERC20 token for another at a specified price.
 * @author crispymangoes
 */
interface IAtomicQueue {

    // ========================================= STRUCTS =========================================

    struct AtomicRequest {
        uint64 deadline;
        uint88 atomicPrice;
        uint96 offerAmount;
        bool inSolve;
    }

    struct SolveMetaData {
        address user;
        uint8 flags;
        uint256 assetsToOffer;
        uint256 assetsForWant;
    }

    struct VerboseSolveMetaData {
        address user;
        bool deadlineExceeded;
        bool zeroOfferAmount;
        bool insufficientOfferBalance;
        bool insufficientOfferAllowance;
        uint256 assetsToOffer;
        uint256 assetsForWant;
    }

    // ========================================= EVENTS =========================================

    event AtomicRequestUpdated(
        address indexed user,
        address indexed offerToken,
        address indexed wantToken,
        uint256 amount,
        uint256 deadline,
        uint256 minPrice,
        uint256 timestamp
    );

    event AtomicRequestFulfilled(
        address indexed user,
        address indexed offerToken,
        address indexed wantToken,
        uint256 offerAmountSpent,
        uint256 wantAmountReceived,
        uint256 timestamp
    );

    event Paused();
    event Unpaused();

    // ========================================= ERRORS =========================================

    error AtomicQueue__UserRepeated(address user);
    error AtomicQueue__RequestDeadlineExceeded(address user);
    error AtomicQueue__UserNotInSolve(address user);
    error AtomicQueue__ZeroOfferAmount(address user);
    error AtomicQueue__SafeRequestOfferAmountGreaterThanOfferBalance(uint256 offerAmount, uint256 offerBalance);
    error AtomicQueue__SafeRequestDeadlineExceeded(uint256 deadline);
    error AtomicQueue__SafeRequestInsufficientOfferAllowance(uint256 offerAmount, uint256 offerAllowance);
    error AtomicQueue__SafeRequestOfferAmountZero();
    error AtomicQueue__SafeRequestDiscountTooLarge();
    error AtomicQueue__SafeRequestAccountantOfferMismatch();
    error AtomicQueue__SafeRequestCannotCastToUint88();
    error AtomicQueue__Paused();

    // ========================================= CONSTANTS =========================================

    function MAX_DISCOUNT() external view returns (uint256);

    // ========================================= STATE VARIABLES =========================================

    function userAtomicRequest(address user, IERC20 offer, IERC20 want) external view returns (AtomicRequest memory);
    function isPaused() external view returns (bool);

    // ========================================= ADMIN FUNCTIONS =========================================

    function pause() external;
    function unpause() external;

    // ========================================= USER FUNCTIONS =========================================

    function getUserAtomicRequest(
        address user,
        IERC20 offer,
        IERC20 want
    ) external view returns (AtomicRequest memory);

    function isAtomicRequestValid(
        IERC20 offer,
        address user,
        AtomicRequest calldata userRequest
    ) external view returns (bool);

    function updateAtomicRequest(IERC20 offer, IERC20 want, AtomicRequest memory userRequest) external;

    // ========================================= SOLVER FUNCTIONS =========================================

    function solve(
        IERC20 offer,
        IERC20 want,
        address[] calldata users,
        bytes calldata runData,
        address solver
    ) external;

    function viewSolveMetaData(
        IERC20 offer,
        IERC20 want,
        address[] calldata users
    ) external view returns (SolveMetaData[] memory metaData, uint256 totalAssetsForWant, uint256 totalAssetsToOffer);

    function viewVerboseSolveMetaData(
        IERC20 offer,
        IERC20 want,
        address[] calldata users
    )
        external
        view
        returns (VerboseSolveMetaData[] memory metaData, uint256 totalAssetsForWant, uint256 totalAssetsToOffer);

}
