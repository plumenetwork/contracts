// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IPlumeStaking } from "./interfaces/IPlumeStaking.sol";
import { Owned } from "./Utils/Owned.sol";

/// @title StakerBucket
/// @notice Minimal per-bucket staking account controlled by stPlumeMinter (controller)
contract StakerBucket is Owned {

    IPlumeStaking public immutable plumeStaking;
    address public controller;

    event ControllerUpdated(address indexed oldController, address indexed newController);
    event BucketStake(uint16 indexed validatorId, uint256 amount);
    event BucketUnstake(uint16 indexed validatorId, uint256 amount);
    event BucketWithdraw(address indexed to, uint256 amount);
    event BucketRestake(uint16 indexed validatorId, uint256 amount);

    modifier onlyController() {
        require(msg.sender == controller, "Not controller");
        _;
    }

    constructor(address _plumeStaking, address _controller, address _owner) Owned(_owner) {
        require(_plumeStaking != address(0) && _controller != address(0), "Zero addr");
        plumeStaking = IPlumeStaking(_plumeStaking);
        controller = _controller;
    }

    function setController(address _controller) external onlyOwner {
        require(_controller != address(0), "Zero addr");
        emit ControllerUpdated(controller, _controller);
        controller = _controller;
    }

    /// @notice Stake ETH sitting in this bucket into a validator
    /// @dev Controller sends ETH to this function which is forwarded into stake()
    function stakeToValidator(uint16 validatorId) external payable onlyController returns (uint256 amountStaked) {
        require(msg.value > 0, "No value");
        amountStaked = plumeStaking.stake{ value: msg.value }(validatorId);
        emit BucketStake(validatorId, amountStaked);
    }

    /// @notice Request an unstake from a validator
    function requestUnstake(uint16 validatorId, uint256 amount) external onlyController returns (uint256 amountUnstaked) {
        amountUnstaked = plumeStaking.unstake(validatorId, amount);
        emit BucketUnstake(validatorId, amountUnstaked);
    }

    /// @notice Withdraw matured cooldowns to the controller
    function withdrawToController() external onlyController returns (uint256 amount) {
        uint256 balBefore = address(this).balance;
        plumeStaking.withdraw();
        uint256 balAfter = address(this).balance;
        amount = balAfter - balBefore;
        if (amount > 0) {
            (bool s,) = controller.call{ value: amount }("");
            require(s, "Forward failed");
            emit BucketWithdraw(controller, amount);
        }
    }

    /// @notice Restake cooled/parked funds to a validator
    function restakeToValidator(uint16 validatorId, uint256 amount) external onlyController returns (uint256) {
        plumeStaking.restake(validatorId, amount);
        emit BucketRestake(validatorId, amount);
        return amount;
    }

    receive() external payable {}
}


