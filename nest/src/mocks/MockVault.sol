// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IBoringVault } from "../interfaces/IBoringVault.sol";
import { BeforeTransferHook } from "@boringvault/src/interfaces/BeforeTransferHook.sol";
import { ERC1155Holder } from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import { ERC721Holder } from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import { Auth, Authority } from "@solmate/auth/Auth.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";

contract MockVault is IBoringVault, Auth, ERC721Holder, ERC1155Holder {

    using SafeTransferLib for ERC20;

    // State variables
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    BeforeTransferHook public hook;

    // Events
    event DebugCall(string functionName, bytes data);
    event Enter(address indexed from, address indexed asset, uint256 amount, address indexed to, uint256 shares);
    event Exit(address indexed to, address indexed asset, uint256 amount, address indexed from, uint256 shares);

    constructor(
        address _owner,
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) Auth(_owner, Authority(address(0))) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    function approve(address spender, uint256 amount) public returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) public returns (bool) {
        _callBeforeTransfer(msg.sender);
        return _transfer(msg.sender, to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public returns (bool) {
        _callBeforeTransfer(from);
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            require(allowed >= amount, "MockVault: insufficient allowance");
            allowance[from][msg.sender] = allowed - amount;
        }
        return _transfer(from, to, amount);
    }

    function _transfer(address from, address to, uint256 amount) internal returns (bool) {
        require(from != address(0), "MockVault: transfer from zero address");
        require(to != address(0), "MockVault: transfer to zero address");
        require(balanceOf[from] >= amount, "MockVault: insufficient balance");

        balanceOf[from] -= amount;
        balanceOf[to] += amount;

        emit Transfer(from, to, amount);
        return true;
    }

    function _mint(address to, uint256 amount) internal {
        require(to != address(0), "MockVault: mint to zero address");
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function _burn(address from, uint256 amount) internal {
        require(from != address(0), "MockVault: burn from zero address");
        require(balanceOf[from] >= amount, "MockVault: insufficient balance");
        totalSupply -= amount;
        balanceOf[from] -= amount;
        emit Transfer(from, address(0), amount);
    }

    function enter(
        address from,
        address asset,
        uint256 assetAmount,
        address to,
        uint256 shareAmount
    ) external override requiresAuth {
        emit DebugCall("enter", abi.encode(from, asset, assetAmount, to, shareAmount));

        if (assetAmount > 0) {
            ERC20(asset).safeTransferFrom(from, address(this), assetAmount);
        }

        _mint(to, shareAmount);

        emit Enter(from, asset, assetAmount, to, shareAmount);
    }

    function exit(
        address to,
        address asset,
        uint256 assetAmount,
        address from,
        uint256 shareAmount
    ) external override requiresAuth {
        emit DebugCall("exit", abi.encode(to, asset, assetAmount, from, shareAmount));

        _burn(from, shareAmount);

        if (assetAmount > 0) {
            ERC20(asset).safeTransfer(to, assetAmount);
        }

        emit Exit(to, address(asset), assetAmount, from, shareAmount);
    }

    function setBeforeTransferHook(
        address _hook
    ) external requiresAuth {
        hook = BeforeTransferHook(_hook);
    }

    function _callBeforeTransfer(
        address from
    ) internal view {
        if (address(hook) != address(0)) {
            hook.beforeTransfer(from);
        }
    }

    receive() external payable { }

}
