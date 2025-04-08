// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {
    ArrayLengthMismatch,
    EmptyArray,
    InvalidAmount,
    InvalidRewardRateCheckpoint,
    NativeTransferFailed,
    RewardRateExceedsMax,
    TokenAlreadyExists,
    TokenDoesNotExist,
    ValidatorDoesNotExist,
    ValidatorInactive,
    ZeroAddress
} from "../lib/PlumeErrors.sol";
import {
    MaxRewardRateUpdated,
    RewardClaimed,
    RewardClaimedFromValidator,
    RewardRateCheckpointCreated,
    RewardRatesSet,
    RewardTokenAdded,
    RewardTokenRemoved,
    RewardsAdded,
    Staked
} from "../lib/PlumeEvents.sol";
import { PlumeStakingStorage } from "../lib/PlumeStakingStorage.sol";
import { OwnableStorage } from "@solidstate/access/ownable/OwnableStorage.sol";
import { DiamondBaseStorage } from "@solidstate/proxy/diamond/base/DiamondBaseStorage.sol";

// Import the new library
import { PlumeRewardLogic } from "../lib/PlumeRewardLogic.sol";

import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

using PlumeRewardLogic for PlumeStakingStorage.Layout;

/**
 * @title RewardsFacet
 * @notice Facet handling reward token management, rate setting, reward calculation, and claiming.
 */
contract RewardsFacet is
    ReentrancyGuardUpgradeable // Removed AccessControlUpgradeable
{

    using SafeERC20 for IERC20;
    using Address for address payable;

    // --- Constants ---
    address internal constant PLUME = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    uint256 internal constant REWARD_PRECISION = 1e18;
    uint256 internal constant BASE = 1e18;
    uint256 internal constant MAX_REWARD_RATE = 3171 * 1e9;

    // --- Storage Access ---
    bytes32 internal constant PLUME_STORAGE_POSITION = keccak256("plume.storage.PlumeStaking");

    function plumeStorage() internal pure returns (PlumeStakingStorage.Layout storage $) {
        bytes32 position = PLUME_STORAGE_POSITION;
        assembly {
            $.slot := position
        }
    }

    modifier onlyOwner() {
        require(msg.sender == OwnableStorage.layout().owner, "Must be owner");
        _;
    }

    // --- Internal View Function (_earned) ---
    // NOTE: The implementation of _earned here now depends on the library's
    // calculateRewardsWithCheckpoints for consistency, but it's still needed
    // as the public view entry point.
    function _earned(address user, address token, uint16 validatorId) internal view returns (uint256 rewards) {
        PlumeStakingStorage.Layout storage $ = plumeStorage();
        uint256 userStakedAmount = $.userValidatorStakes[user][validatorId].staked;
        if (userStakedAmount == 0) {
            // If no stake, only return previously calculated rewards stored in userRewards
            return $.userRewards[user][validatorId][token];
        }
        // Call the library function to calculate the current pending reward delta
        (uint256 userRewardDelta,) = PlumeRewardLogic.calculateRewardsWithCheckpoints(
            $, user, token, validatorId, userStakedAmount, $.validators[validatorId].commission
        );
        // Add the delta to any previously stored (but unclaimed) rewards
        rewards = $.userRewards[user][validatorId][token] + userRewardDelta;
        return rewards;
    }

    // --- Admin Functions ---
    function addRewardToken(
        address token
    ) external onlyOwner {
        PlumeStakingStorage.Layout storage $ = plumeStorage();
        if (token == address(0)) {
            revert ZeroAddress("token");
        }
        if (_isRewardToken(token)) {
            revert TokenAlreadyExists();
        }
        $.rewardTokens.push(token);
        for (uint256 i = 0; i < $.validatorIds.length; i++) {
            $.validatorLastUpdateTimes[$.validatorIds[i]][token] = block.timestamp;
        }
        emit RewardTokenAdded(token);
    }

    function removeRewardToken(
        address token
    ) external onlyOwner {
        PlumeStakingStorage.Layout storage $ = plumeStorage();
        uint256 tokenIndex = _getTokenIndex(token);
        if (tokenIndex >= $.rewardTokens.length) {
            revert TokenDoesNotExist(token);
        }
        // Update rewards using the library before removing
        for (uint256 i = 0; i < $.validatorIds.length; i++) {
            // Needs to update the cumulative index, not user rewards
            PlumeRewardLogic.updateRewardPerTokenForValidator($, token, $.validatorIds[i]);
        }
        $.rewardRates[token] = 0;
        $.rewardTokens[tokenIndex] = $.rewardTokens[$.rewardTokens.length - 1];
        $.rewardTokens.pop();
        delete $.maxRewardRates[token];
        emit RewardTokenRemoved(token);
    }

    function setRewardRates(address[] calldata tokens, uint256[] calldata rewardRates_) external onlyOwner {
        PlumeStakingStorage.Layout storage $ = plumeStorage();
        if (tokens.length == 0) {
            revert EmptyArray();
        }
        if (tokens.length != rewardRates_.length) {
            revert ArrayLengthMismatch();
        }
        uint16[] memory validatorIds = $.validatorIds;
        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            uint256 rate = rewardRates_[i];
            if (!_isRewardToken(token)) {
                revert TokenDoesNotExist(token);
            }
            uint256 maxRate = $.maxRewardRates[token] > 0 ? $.maxRewardRates[token] : MAX_REWARD_RATE;
            if (rate > maxRate) {
                revert RewardRateExceedsMax();
            }
            for (uint256 j = 0; j < validatorIds.length; j++) {
                uint16 validatorId = validatorIds[j];
                PlumeRewardLogic.updateRewardPerTokenForValidator($, token, validatorId);
                PlumeRewardLogic.createRewardRateCheckpoint($, token, validatorId, rate); // Use library
            }
            $.rewardRates[token] = rate;
        }
        emit RewardRatesSet(tokens, rewardRates_);
    }

    function setMaxRewardRate(address token, uint256 newMaxRate) external onlyOwner {
        PlumeStakingStorage.Layout storage $ = plumeStorage();
        if (!_isRewardToken(token)) {
            revert TokenDoesNotExist(token);
        }
        if ($.rewardRates[token] > newMaxRate) {
            revert RewardRateExceedsMax();
        }
        $.maxRewardRates[token] = newMaxRate;
        emit MaxRewardRateUpdated(token, newMaxRate);
    }

    function addRewards(address token, uint256 amount) external payable onlyOwner {
        PlumeStakingStorage.Layout storage $ = plumeStorage();
        if (!_isRewardToken(token)) {
            revert TokenDoesNotExist(token);
        }
        uint16[] memory validatorIds = $.validatorIds;
        for (uint256 i = 0; i < validatorIds.length; i++) {
            // Use library function to update validator cumulative index
            PlumeRewardLogic.updateRewardPerTokenForValidator($, token, validatorIds[i]);
        }
        if (token == PLUME) {
            if (msg.value != amount) {
                revert InvalidAmount(msg.value);
            }
        } else {
            if (msg.value > 0) {
                revert InvalidAmount(msg.value);
            }
            // address(this) is the Diamond Proxy
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }
        $.rewardsAvailable[token] += amount;
        emit RewardsAdded(token, amount);
    }

    // --- User Claim Functions ---
    function claim(
        address token
    ) external nonReentrant returns (uint256 totalAmount) {
        PlumeStakingStorage.Layout storage $ = plumeStorage();
        if (!_isRewardToken(token)) {
            revert TokenDoesNotExist(token);
        }
        uint16[] memory userValidators = $.userValidators[msg.sender];
        totalAmount = 0;
        for (uint256 i = 0; i < userValidators.length; i++) {
            uint16 validatorId = userValidators[i];
            uint256 amount = _claimWithValidator(token, validatorId);
            totalAmount += amount;
        }
        if (totalAmount > 0) {
            emit RewardClaimed(msg.sender, token, totalAmount);
        }
        return totalAmount;
    }

    function claim(address token, uint16 validatorId) external nonReentrant returns (uint256 amount) {
        amount = _claimWithValidator(token, validatorId);
        if (amount > 0) {
            emit RewardClaimed(msg.sender, token, amount);
        }
        return amount;
    }

    function _claimWithValidator(address token, uint16 validatorId) internal returns (uint256 amount) {
        // Uses library
        PlumeStakingStorage.Layout storage $ = plumeStorage();
        if (!$.validatorExists[validatorId]) {
            revert ValidatorDoesNotExist(validatorId);
        }
        // Use library function to update user's rewards *before* claiming
        PlumeRewardLogic.updateRewardsForValidator($, msg.sender, validatorId);
        amount = $.userRewards[msg.sender][validatorId][token];
        if (amount > 0) {
            $.userRewards[msg.sender][validatorId][token] = 0;
            if ($.totalClaimableByToken[token] >= amount) {
                $.totalClaimableByToken[token] -= amount;
            } else {
                $.totalClaimableByToken[token] = 0;
            }
            if (token != PLUME) {
                IERC20(token).safeTransfer(msg.sender, amount);
            } else {
                (bool success,) = payable(msg.sender).call{ value: amount }("");
                if (!success) {
                    revert NativeTransferFailed();
                }
            }
            emit RewardClaimedFromValidator(msg.sender, token, validatorId, amount);
        }
        return amount;
    }

    function claimAll() external nonReentrant returns (uint256 totalValue) {
        PlumeStakingStorage.Layout storage $ = plumeStorage();
        address[] memory tokens = $.rewardTokens;
        uint16[] memory userValidators = $.userValidators[msg.sender];
        totalValue = 0;
        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            uint256 tokenTotalAmount = 0;
            if (!_isRewardToken(token)) {
                continue;
            }
            for (uint256 j = 0; j < userValidators.length; j++) {
                uint16 validatorId = userValidators[j];
                uint256 amount = _claimWithValidator(token, validatorId);
                tokenTotalAmount += amount;
            }
            if (tokenTotalAmount > 0) {
                emit RewardClaimed(msg.sender, token, tokenTotalAmount);
            }
            totalValue += tokenTotalAmount;
        }
        return totalValue;
    }

    function restakeRewards(
        uint16 validatorId
    ) external nonReentrant returns (uint256 stakedAmount) {
        PlumeStakingStorage.Layout storage $ = plumeStorage();
        if (!$.validatorExists[validatorId]) {
            revert ValidatorDoesNotExist(validatorId);
        }
        PlumeStakingStorage.ValidatorInfo storage targetValidator = $.validators[validatorId];
        if (!targetValidator.active) {
            revert ValidatorInactive(validatorId);
        }
        address token = PLUME;
        if (!_isRewardToken(token)) {
            revert TokenDoesNotExist(token);
        }
        _updateRewards(msg.sender);
        uint16[] memory userValidators = $.userValidators[msg.sender];
        stakedAmount = 0;
        for (uint256 i = 0; i < userValidators.length; i++) {
            uint16 sourceValidatorId = userValidators[i];
            uint256 validatorRewards = $.userRewards[msg.sender][sourceValidatorId][token];
            if (validatorRewards > 0) {
                $.userRewards[msg.sender][sourceValidatorId][token] = 0;
                stakedAmount += validatorRewards;
                if ($.totalClaimableByToken[token] >= validatorRewards) {
                    $.totalClaimableByToken[token] -= validatorRewards;
                } else {
                    $.totalClaimableByToken[token] = 0;
                }
                emit RewardClaimedFromValidator(msg.sender, token, sourceValidatorId, validatorRewards);
            }
        }
        if (stakedAmount > 0) {
            PlumeStakingStorage.StakeInfo storage targetValidatorInfo = $.userValidatorStakes[msg.sender][validatorId];
            PlumeStakingStorage.StakeInfo storage globalInfo = $.stakeInfo[msg.sender];
            // Update rewards for the *target* validator before staking
            PlumeRewardLogic.updateRewardsForValidator($, msg.sender, validatorId);
            bool firstTimeStaking = targetValidatorInfo.staked == 0;
            targetValidatorInfo.staked += stakedAmount;
            globalInfo.staked += stakedAmount;
            targetValidator.delegatedAmount += stakedAmount;
            $.validatorTotalStaked[validatorId] += stakedAmount;
            $.totalStaked += stakedAmount;
            // Delegatecall to ValidatorFacet
            (bool success,) = address(this).delegatecall(
                abi.encodeWithSelector(
                    bytes4(keccak256("_addStakerToValidator(address,uint16)")), msg.sender, validatorId
                )
            );
            require(success, "RewardsFacet: _addStakerToValidator delegatecall failed");
            if (firstTimeStaking) {
                $.userValidatorStakeStartTime[msg.sender][validatorId] = block.timestamp;
            }
            // Update rewards *again* after staking to set the correct baseline
            PlumeRewardLogic.updateRewardsForValidator($, msg.sender, validatorId);
            emit Staked(msg.sender, validatorId, stakedAmount, 0, 0, stakedAmount);
        }
        return stakedAmount;
    }

    // --- View Functions (now call internal _earned) ---
    function earned(address user, address token) external view returns (uint256 rewards) {
        PlumeStakingStorage.Layout storage $ = plumeStorage();
        if (!_isRewardToken(token)) {
            return 0;
        }
        uint16[] memory userValidators = $.userValidators[user];
        rewards = 0;
        for (uint256 i = 0; i < userValidators.length; i++) {
            // Now calls the internal _earned which is defined above
            rewards += _earned(user, token, userValidators[i]);
        }
        return rewards;
    }

    function getClaimableReward(address user, address token) external view returns (uint256 amount) {
        // Explicitly call earned via this.
        return this.earned(user, token);
    }

    function getRewardTokens() external view returns (address[] memory tokens, uint256[] memory rates) {
        PlumeStakingStorage.Layout storage $ = plumeStorage();
        uint256 length = $.rewardTokens.length;
        tokens = new address[](length);
        rates = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            address currentToken = $.rewardTokens[i];
            tokens[i] = currentToken;
            rates[i] = $.rewardRates[currentToken];
        }
    }

    function getMaxRewardRate(
        address token
    ) external view returns (uint256) {
        PlumeStakingStorage.Layout storage $ = plumeStorage();
        uint256 maxRate = $.maxRewardRates[token];
        return maxRate > 0 ? maxRate : MAX_REWARD_RATE;
    }

    function tokenRewardInfo(
        address token
    ) external view returns (uint256 rate, uint256 available) {
        PlumeStakingStorage.Layout storage $ = plumeStorage();
        return ($.rewardRates[token], $.rewardsAvailable[token]);
    }

    // --- Checkpoint View Functions ---

    function getRewardRateCheckpointCount(
        address token
    ) external view returns (uint256) {
        return plumeStorage().rewardRateCheckpoints[token].length;
    }

    function getValidatorRewardRateCheckpointCount(uint16 validatorId, address token) external view returns (uint256) {
        return plumeStorage().validatorRewardRateCheckpoints[validatorId][token].length;
    }

    function getRewardRateCheckpoint(
        address token,
        uint256 index
    ) external view returns (uint256 timestamp, uint256 rate, uint256 cumulativeIndex) {
        PlumeStakingStorage.RateCheckpoint[] storage checkpoints = plumeStorage().rewardRateCheckpoints[token];
        if (index >= checkpoints.length) {
            revert InvalidRewardRateCheckpoint(token, index);
        }
        PlumeStakingStorage.RateCheckpoint storage checkpoint = checkpoints[index];
        return (checkpoint.timestamp, checkpoint.rate, checkpoint.cumulativeIndex);
    }

    function getValidatorRewardRateCheckpoint(
        uint16 validatorId,
        address token,
        uint256 index
    ) external view returns (uint256 timestamp, uint256 rate, uint256 cumulativeIndex) {
        PlumeStakingStorage.RateCheckpoint[] storage checkpoints =
            plumeStorage().validatorRewardRateCheckpoints[validatorId][token];
        if (index >= checkpoints.length) {
            revert InvalidRewardRateCheckpoint(token, index);
        }
        PlumeStakingStorage.RateCheckpoint storage checkpoint = checkpoints[index];
        return (checkpoint.timestamp, checkpoint.rate, checkpoint.cumulativeIndex);
    }

    function getUserLastCheckpointIndex(
        address user,
        uint16 validatorId,
        address token
    ) external view returns (uint256) {
        return plumeStorage().userLastCheckpointIndex[user][validatorId][token];
    }

    // --- Internal Helper Functions ---

    function _isRewardToken(
        address token
    ) internal view returns (bool) {
        return _getTokenIndex(token) < plumeStorage().rewardTokens.length;
    }

    function _getTokenIndex(
        address token
    ) internal view returns (uint256) {
        address[] memory tokens = plumeStorage().rewardTokens;
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == token) {
                return i;
            }
        }
        return tokens.length;
    }

    function _updateRewards(
        address user
    ) internal {
        PlumeStakingStorage.Layout storage $ = plumeStorage();
        uint16[] memory userValidators = $.userValidators[user];
        for (uint256 i = 0; i < userValidators.length; i++) {
            // Calls the library function now
            PlumeRewardLogic.updateRewardsForValidator($, user, userValidators[i]);
        }
    }

    // Placeholder internal function used by delegatecall
    // function _addStakerToValidator(address /* staker */, uint16 /* validatorId */) internal pure {}

}
