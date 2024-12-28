// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IRWAStaking {

    // Structs
    struct UserState {
        uint256 amountSeconds;
        uint256 amountStaked;
        uint256 lastUpdate;
    }

    // Events
    event AdminWithdrawn(address indexed user, IERC20 indexed stablecoin, uint256 amount);
    event Withdrawn(address indexed user, IERC20 indexed stablecoin, uint256 amount);
    event Staked(address indexed user, IERC20 indexed stablecoin, uint256 amount);
    event Paused();
    event Unpaused();

    // Admin Functions
    function initialize(TimelockController timelock, address owner) external;
    function reinitialize(address multisig, TimelockController timelock) external;
    function setMultisig(
        address multisig
    ) external;
    function allowStablecoin(
        IERC20 stablecoin
    ) external;
    function adminWithdraw() external;
    function pause() external;
    function unpause() external;

    // User Functions
    function stake(uint256 amount, IERC20 stablecoin) external;
    function withdraw(uint256 amount, IERC20 stablecoin) external;

    // View Functions
    function ADMIN_ROLE() external pure returns (bytes32);
    function getTotalAmountStaked() external view returns (uint256);
    function getUsers() external view returns (address[] memory);
    function getUserState(
        address user
    ) external view returns (uint256 amountSeconds, uint256 amountStaked, uint256 lastUpdate);
    function getUserStablecoinAmounts(address user, IERC20 stablecoin) external view returns (uint256);
    function getAllowedStablecoins() external view returns (IERC20[] memory);
    function isAllowedStablecoin(
        IERC20 stablecoin
    ) external view returns (bool);
    function getEndTime() external view returns (uint256);
    function isPaused() external view returns (bool);
    function getMultisig() external view returns (address);
    function getTimelock() external view returns (TimelockController);

}
