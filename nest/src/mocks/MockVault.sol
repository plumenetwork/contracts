// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ERC1155Holder } from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC721Holder } from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import { Auth, Authority } from "@solmate/auth/Auth.sol";

import { IBoringVault } from "../interfaces/IBoringVault.sol";

contract MockVault is ERC20, Auth, ERC721Holder, ERC1155Holder, IBoringVault {

    using SafeERC20 for IERC20;

    // token => account => balance
    mapping(address => mapping(address => uint256)) private _balances;

    mapping(address => mapping(address => mapping(address => uint256))) private _allowances;

    IERC20 public asset;
    IERC20 public immutable usdc;
    IERC20 public immutable usdt;
    address public beforeTransferHook;

    constructor(
        address _owner,
        string memory _name,
        string memory _symbol,
        address _usdc
    ) ERC20(_name, _symbol) Auth(_owner, Authority(address(0))) {
        usdc = IERC20(_usdc);
    }

    function enter(address from, address asset_, uint256 assetAmount, address to, uint256 shareAmount) external {
        if (assetAmount > 0) {
            IERC20(asset_).safeTransferFrom(from, address(this), assetAmount);
        }
        _balances[asset_][to] += shareAmount;
        _allowances[asset_][to][msg.sender] = type(uint256).max;
    }

    function exit(address to, address asset_, uint256 assetAmount, address from, uint256 shareAmount) external {
        // Change from checking 'from' balance to checking the actual owner's balance
        address owner = from == msg.sender ? to : from;
        require(_balances[asset_][owner] >= shareAmount, "MockVault: insufficient balance");

        uint256 allowed = _allowances[asset_][owner][msg.sender];
        if (allowed != type(uint256).max) {
            require(allowed >= shareAmount, "MockVault: insufficient allowance");
            _allowances[asset_][owner][msg.sender] = allowed - shareAmount;
        }

        _balances[asset_][owner] -= shareAmount;

        // Changed: Transfer to 'to' instead of msg.sender, and always transfer if we have shares
        if (shareAmount > 0) {
            IERC20(asset_).safeTransfer(to, shareAmount);
        }
    }

    function transferFrom(address asset_, address from, address to, uint256 amount) external returns (bool) {
        require(_balances[asset_][from] >= amount, "MockVault: insufficient balance");

        uint256 allowed = _allowances[asset_][from][msg.sender];
        if (allowed != type(uint256).max) {
            require(allowed >= amount, "MockVault: insufficient allowance");
            _allowances[asset_][from][msg.sender] = allowed - amount;
        }

        _balances[asset_][from] -= amount;
        _balances[asset_][to] += amount;
        return true;
    }

    function approve(address asset_, address spender, uint256 amount) external returns (bool) {
        _allowances[asset_][msg.sender][spender] = amount;
        return true;
    }

    function balanceOf(
        address account
    ) public view virtual override(ERC20, IERC20) returns (uint256) {
        // Return total balance across all assets
        return _balances[address(usdc)][account] + _balances[address(usdt)][account];
    }

    function totalSupply() public view virtual override(ERC20, IERC20) returns (uint256) {
        // Return total supply across all assets
        return _balances[address(usdc)][address(this)] + _balances[address(usdt)][address(this)];
    }

    function decimals() public pure virtual override(ERC20, IERC20Metadata) returns (uint8) {
        return 6;
    }

    function tokenBalance(address token, address account) external view returns (uint256) {
        return _balances[token][account];
    }

    function setBalance(address token, uint256 amount) external {
        _balances[token][address(this)] = amount;
    }

    function allowance(address asset_, address owner, address spender) external view returns (uint256) {
        return _allowances[asset_][owner][spender];
    }

    function setBeforeTransferHook(
        address hook
    ) external {
        beforeTransferHook = hook;
    }

}
