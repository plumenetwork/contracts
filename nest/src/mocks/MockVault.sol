// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockVault {

    using SafeERC20 for IERC20;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    IERC20 public asset;
    address public beforeTransferHook;

    function enter(address from, address asset_, uint256 assetAmount, address to, uint256 shareAmount) external {
        if (assetAmount > 0) {
            IERC20(asset_).safeTransferFrom(from, address(this), assetAmount);
        }
        _balances[to] = _balances[to] + shareAmount;
        _allowances[to][msg.sender] = type(uint256).max;
    }

    function exit(address to, address asset_, uint256 assetAmount, address from, uint256 shareAmount) external {
        // Change from checking 'from' balance to checking the actual owner's balance
        address owner = from == msg.sender ? to : from;
        require(_balances[owner] >= shareAmount, "MockVault: insufficient balance");

        uint256 allowed = _allowances[owner][msg.sender];
        if (allowed != type(uint256).max) {
            require(allowed >= shareAmount, "MockVault: insufficient allowance");
            _allowances[owner][msg.sender] = allowed - shareAmount;
        }

        _balances[owner] = _balances[owner] - shareAmount;

        // Changed: Transfer to 'to' instead of msg.sender, and always transfer if we have shares
        if (shareAmount > 0) {
            IERC20(asset_).safeTransfer(to, shareAmount);
        }
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(_balances[from] >= amount, "MockVault: insufficient balance");

        uint256 allowed = _allowances[from][msg.sender];
        if (allowed != type(uint256).max) {
            require(allowed >= amount, "MockVault: insufficient allowance");
            _allowances[from][msg.sender] = allowed - amount;
        }

        _balances[from] = _balances[from] - amount;
        _balances[to] = _balances[to] + amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        _allowances[msg.sender][spender] = amount;
        return true;
    }

    function balanceOf(
        address account
    ) external view returns (uint256) {
        return _balances[account];
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        return _allowances[owner][spender];
    }
    // Add function to set hook

    function setBeforeTransferHook(
        address hook
    ) external {
        beforeTransferHook = hook;
    }

}
