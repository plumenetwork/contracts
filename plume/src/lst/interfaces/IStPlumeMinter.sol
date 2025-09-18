// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import { IPlumeStaking } from "./IPlumeStaking.sol";
import { PlumeStakingStorage } from "./PlumeStakingStorage.sol";
import { IstPlumeRewards } from "./IstPlumeRewards.sol";

/// @title IstPlumeMinter - Interface for stPlumeMinter contract
/// @notice Interface for the stPlumeMinter contract which extends frxETHMinter with staking capabilities
interface IstPlumeMinter {
    // Constants and Public Variables
    function REDEMPTION_FEE() external view returns (uint256);
    function INSTANT_REDEMPTION_FEE() external view returns (uint256);
    function withHoldEth() external view returns (uint256);
    function minStake() external view returns (uint256);
    function maxValidatorPercentage(uint16 validatorId) external view returns (uint256);
    function withdrawalQueueThreshold() external view returns (uint256);
    function batchUnstakeInterval() external view returns (uint256);
    function stPlumeRewards() external view returns (IstPlumeRewards);
    function currentWithheldETH() external view returns (uint256);
    function totalInstantUnstaked() external view returns (uint256);

    // External Functions
    function submitForValidator(uint16 validatorId) external payable;
    function getNextValidator(uint256 depositAmount, uint16 validatorId) external view returns (uint256 validatorId_, uint256 capacity_);
    function rebalance() external;
    function unstake(uint256 amount) external returns (uint256 amountUnstaked);
    function unstakeFromValidator(uint256 amount, uint16 validatorId) external returns (uint256 amountUnstaked);
    function restake(uint16 validatorId) external returns (uint256 amountRestaked);
    function unstakeGov(uint16 validatorId, uint256 amount) external returns (uint256 amountRestaked);
    function withdrawGov() external returns (uint256 amountWithdrawn);
    function stakeWitheld(uint256 amount) external returns (uint256 amountRestaked);
    function stakeWitheldForValidator(uint256 amount, uint16 validatorId) external returns (uint256 amountRestaked);
    function withdrawFee() external returns (uint256 amount);
    function withdraw(address recipient, uint256 id) external returns (uint256 amount);
    function getClaimableReward() external returns (uint256 amount);
    function claim(uint16 validatorId) external returns (uint256 amount);
    function loadRewards() external payable returns (uint256 amount);
    function claimAll() external returns (uint256[] memory amounts);
    function unstakeRewards() external returns (uint256 yield);
    function processBatchUnstake() external;
    
    // Admin functions
    function setFees(uint256 newInstantFee, uint256 newStandardFee) external;
    function setMinStake(uint256 _minStake) external;
    function setMaxValidatorPercentage(uint256 _validatorId, uint256 _maxPercentage) external;
    function setBatchUnstakeParams(uint256 _threshold, uint256 _interval) external;
    function setNativeToken(address _nativeToken) external;
    function setStPlumeRewards(address _stPlumeRewards) external;
    function addWithHoldFee() external payable;
}