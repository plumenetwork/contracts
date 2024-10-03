// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title SBTCStaking
 * @author Eugene Y. Q. Shen
 * @notice Pre-staking contract to provide security to Plume Mainnet
 */
contract SBTCStaking is AccessControlUpgradeable, UUPSUpgradeable {

    // Types

    using SafeERC20 for IERC20;

    /**
    * @notice State of a user that deposits into the SBTCStaking contract
    * @param amountSeconds Cumulative sum of the amount of SBTC staked by the user,
    *   multiplied by the number of seconds that the user has staked this amount for
    * @param amountStaked Total amount of SBTC staked by the user
    * @param lastUpdate Timestamp of the most recent update to amountSeconds
    */
    struct UserState {
        uint256 amountSeconds;
        uint256 amountStaked;
        uint256 lastUpdate;
    }

    // Storage

    /// @custom:storage-location erc7201:plume.storage.SBTCStaking
    struct SBTCStakingStorage {
        /// @dev SBTC token contract address
        IERC20 sbtc;
        /// @dev Total amount of SBTC staked in the SBTCStaking contract
        uint256 totalAmountStaked;
        /// @dev List of users who have staked into the SBTCStaking contract
        address[] users;
        /// @dev Mapping of users to their state in the SBTCStaking contract
        mapping(address user => UserState userState) userStates;
    }

    // keccak256(abi.encode(uint256(keccak256("plume.storage.SBTCStaking")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant SBTC_STAKING_STORAGE_LOCATION =
        0xe6f69a0161187dc57c8cc7752ede708d62bb1a432a5a93aebf5ce3f284fb0a00;

    function _getSBTCStakingStorage() private pure returns (SBTCStakingStorage storage $) {
        assembly {
            $.slot := SBTC_STAKING_STORAGE_LOCATION
        }
    }

    // Constants

    /// @notice Role for the admin of the SBTCStaking contract
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    /// @notice Role for the upgrader of the SBTCStaking contract
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    // Events

    /**
     * @notice Emitted when a user stakes SBTC into the SBTCStaking contract
     * @param user Address of the user who staked SBTC
     * @param amount Amount of SBTC staked
     * @param timestamp Timestamp of the stake
     */
    event Staked(
        address indexed user,
        uint256 amount,
        uint256 timestamp
    );

    // Initializer

    /**
     * @notice Prevent the implementation contract from being initialized or reinitialized
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the SBTCStaking contract
     * @param owner Address of the owner of the SBTCStaking contract
     * @param sbtc SBTC token contract address
     */
    function initialize(
        address owner,
        IERC20 sbtc
    ) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, owner);
        _grantRole(ADMIN_ROLE, owner);
        _grantRole(UPGRADER_ROLE, owner);

        _getSBTCStakingStorage().sbtc = sbtc;
    }

    // Override Functions

    /**
     * @notice Revert when `msg.sender` is not authorized to upgrade the contract
     * @param newImplementation Address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) { }

    // User Functions

    /**
     * @notice Stake SBTC into the SBTCStaking contract
     * @param amount Amount of SBTC to stake
     */
    function stake(uint256 amount) external {
        SBTCStakingStorage storage $ = _getSBTCStakingStorage();

        $.sbtc.safeTransferFrom(msg.sender, address(this), amount);

        uint256 timestamp = block.timestamp;
        UserState storage userState = $.userStates[msg.sender];
        if (userState.lastUpdate == 0) {
            $.users.push(msg.sender);
        }
        userState.amountSeconds += userState.amountStaked * (timestamp - userState.lastUpdate);
        userState.amountStaked += amount;
        userState.lastUpdate = timestamp;
        $.totalAmountStaked += amount;

        emit Staked(msg.sender, amount, timestamp);
    }

    // Getter View Functions

    /// @notice SBTC token contract address
    function getSBTC() external view returns (IERC20) {
        return _getSBTCStakingStorage().sbtc;
    }

    /// @notice Total amount of SBTC staked in the SBTCStaking contract
    function getTotalAmountStaked() external view returns (uint256) {
        return _getSBTCStakingStorage().totalAmountStaked;
    }

    /// @notice List of users who have staked into the SBTCStaking contract
    function getUsers() external view returns (address[] memory) {
        return _getSBTCStakingStorage().users;
    }

    /// @notice State of a user who has staked into the SBTCStaking contract
    function getUserState(address user) external view returns (UserState memory) {
        return _getSBTCStakingStorage().userStates[user];
    }
}