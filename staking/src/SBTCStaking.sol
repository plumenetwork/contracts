// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract SBTCStaking is AccessControlUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;
    struct UserState {
        uint256 amountSeconds;
        uint256 amountStaked;
        uint256 lastUpdate;
    }

    /// @custom:storage-location erc7201:plume.storage.SBTCStaking
    struct SBTCStakingStorage {
        IERC20 sbtc;
        uint256 totalAmountStaked;
        address[] users;
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

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    event Staked(address indexed user, uint256 amount, uint256 timestamp);

    constructor() {
        _disableInitializers();
    }

    function initialize(address owner, IERC20 sbtc) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, owner);
        _grantRole(ADMIN_ROLE, owner);
        _grantRole(UPGRADER_ROLE, owner);

        _getSBTCStakingStorage().sbtc = sbtc;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) { }

    // User Functions

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

    // View Functions

    function getSBTC() external view returns (IERC20) {
        return _getSBTCStakingStorage().sbtc;
    }
    function getTotalAmountStaked() external view returns (uint256) {
        return _getSBTCStakingStorage().totalAmountStaked;
    }
    function getUsers() external view returns (address[] memory) {
        return _getSBTCStakingStorage().users;
    }
    function getUserState(address user) external view returns (UserState memory) {
        return _getSBTCStakingStorage().userStates[user];
    }

}
