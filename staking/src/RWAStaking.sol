// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract RWAStaking is AccessControlUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;
    struct UserState {
        uint256 amountSeconds;
        uint256 amountStaked;
        uint256 lastUpdate;
    }

    /// @custom:storage-location erc7201:plume.storage.RWAStaking
    struct RWAStakingStorage {
        uint256 totalAmountStaked;
        address[] users;
        mapping(address user => UserState userState) userStates;
        IERC20[] stablecoins;
        mapping(IERC20 stablecoin => bool allowed) allowedStablecoins;
    }

    // keccak256(abi.encode(uint256(keccak256("plume.storage.RWAStaking")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant RWA_STAKING_STORAGE_LOCATION =
        0x985cf34339f517022bb48b1ce402d8af12b040d0d5b3c991a00533cf3bab8800;
    function _getRWAStakingStorage() private pure returns (RWAStakingStorage storage $) {
        assembly {
            $.slot := RWA_STAKING_STORAGE_LOCATION
        }
    }

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    event Staked(address indexed user, uint256 amount, uint256 timestamp);
    error AlreadyAllowedStablecoin(IERC20 stablecoin);
    error NotAllowedStablecoin(IERC20 stablecoin);

    constructor() {
        _disableInitializers();
    }

    function initialize(address owner) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, owner);
        _grantRole(ADMIN_ROLE, owner);
        _grantRole(UPGRADER_ROLE, owner);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) { }

    // Admin Functions

    function allowStablecoin(IERC20 stablecoin) external onlyRole(ADMIN_ROLE) {
        RWAStakingStorage storage $ = _getRWAStakingStorage();
        if ($.allowedStablecoins[stablecoin]) {
            revert AlreadyAllowedStablecoin(stablecoin);
        }
        $.stablecoins.push(stablecoin);
        $.allowedStablecoins[stablecoin] = true;
    }

    // User Functions

    function stake(uint256 amount, IERC20 stablecoin) external {
        RWAStakingStorage storage $ = _getRWAStakingStorage();
        if (!$.allowedStablecoins[stablecoin]) {
            revert NotAllowedStablecoin(stablecoin);
        }

        stablecoin.safeTransferFrom(msg.sender, address(this), amount);
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

    function getTotalAmountStaked() external view returns (uint256) {
        return _getRWAStakingStorage().totalAmountStaked;
    }
    function getUsers() external view returns (address[] memory) {
        return _getRWAStakingStorage().users;
    }
    function getUserState(address user) external view returns (UserState memory) {
        return _getRWAStakingStorage().userStates[user];
    }
    function getAllowedStablecoins() external view returns (IERC20[] memory) {
        return _getRWAStakingStorage().stablecoins;
    }
    function isAllowedStablecoin(IERC20 stablecoin) external view returns (bool) {
        return _getRWAStakingStorage().allowedStablecoins[stablecoin];
    }

}
