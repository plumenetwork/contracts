// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IAtomicQueue } from "../interfaces/IAtomicQueue.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";

contract MockAtomicQueue is IAtomicQueue {

    bool private _paused;

    // State variables
    mapping(address => mapping(ERC20 => mapping(ERC20 => AtomicRequest))) private _userAtomicRequest;
    uint256 private _mockRate;
    uint256 private constant _MAX_DISCOUNT = 0.01e6;

    constructor() {
        _mockRate = 1e18; // Default 1:1 rate
    }

    // Add missing interface function
    function MAX_DISCOUNT() external pure returns (uint256) {
        return _MAX_DISCOUNT;
    }

    // Admin functions
    function setPaused(
        bool paused
    ) internal {
        _paused = paused;
        if (paused) {
            emit Paused();
        } else {
            emit Unpaused();
        }
    }

    function userAtomicRequest(address user, ERC20 offer, ERC20 want) external view returns (AtomicRequest memory) {
        return _userAtomicRequest[user][offer][want];
    }

    function setMockRate(
        uint256 rate
    ) external {
        _mockRate = rate;
    }

    // View functions
    function isPaused() external view returns (bool) {
        return _paused;
    }

    function getRate() external view returns (uint256) {
        return _mockRate;
    }

    // Core functions
    function updateAtomicRequest(ERC20 offer, ERC20 want, AtomicRequest memory userRequest) external {
        require(!_paused, "AtomicQueue: paused");
        _userAtomicRequest[msg.sender][offer][want] = userRequest;
        emit AtomicRequestUpdated(
            msg.sender,
            address(offer),
            address(want),
            userRequest.offerAmount,
            userRequest.deadline,
            userRequest.atomicPrice,
            block.timestamp
        );
    }

    function getUserAtomicRequest(address user, ERC20 offer, ERC20 want) external view returns (AtomicRequest memory) {
        return _userAtomicRequest[user][offer][want];
    }

    function pause() external {
        setPaused(true);
    }

    function unpause() external {
        setPaused(false);
    }

    function isAtomicRequestValid(
        ERC20 offer,
        address user,
        AtomicRequest calldata userRequest
    ) external view returns (bool) {
        return true; // Mock implementation
    }

    function solve(
        ERC20 offer,
        ERC20 want,
        address[] calldata users,
        bytes calldata runData,
        address solver
    ) external {
        // Mock implementation
    }

    function viewSolveMetaData(
        ERC20 offer,
        ERC20 want,
        address[] calldata users
    ) external view returns (SolveMetaData[] memory metaData, uint256 totalAssetsForWant, uint256 totalAssetsToOffer) {
        // Mock implementation
    }

    function viewVerboseSolveMetaData(
        ERC20 offer,
        ERC20 want,
        address[] calldata users
    )
        external
        view
        returns (VerboseSolveMetaData[] memory metaData, uint256 totalAssetsForWant, uint256 totalAssetsToOffer)
    {
        // Mock implementation
    }

}
