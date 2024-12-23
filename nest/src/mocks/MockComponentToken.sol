// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { IERC7575 } from "../interfaces/IERC7575.sol";
import { IComponentToken } from "../interfaces/IComponentToken.sol";

contract MockComponentToken is Initializable, ERC20Upgradeable, IComponentToken {
    IERC20 private _asset;
    string private _name;
    string private _symbol;
    mapping(address => uint256) private _pendingDeposits;
    mapping(address => uint256) private _claimableDeposits;
    mapping(address => uint256) private _pendingRedeems;
    mapping(address => uint256) private _claimableRedeems;
    mapping(bytes32 => mapping(address => bool)) private _roles;

    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    error ZeroAmount();
    error Unauthorized(address sender, address owner);



    function initialize(
        address owner,
        string memory name_,
        string memory symbol_,
        IERC20 asset_,
        bool asyncDeposit,
        bool asyncRedeem
    ) public initializer {
        _asset = asset_;
        _name = name_;
        _symbol = symbol_;
        _roles[DEFAULT_ADMIN_ROLE][owner] = true;
        _roles[ADMIN_ROLE][owner] = true;
        _roles[UPGRADER_ROLE][owner] = true;
    }

    function hasRole(bytes32 role, address account) public view returns (bool) {
        return _roles[role][account];
    }


    function asset() external view override returns (address) {
        return address(_asset);
    }

    function totalAssets() external view override returns (uint256) {
        return _asset.balanceOf(address(this));
    }

    function convertToShares(uint256 assets) public pure override returns (uint256) {
        return assets;
    }

    function convertToAssets(uint256 shares) public pure override returns (uint256) {
        return shares;
    }

    function requestDeposit(
        uint256 assets,
        address controller,
        address owner
    ) external override returns (uint256) {
        if (assets == 0) revert ZeroAmount();
        if (msg.sender != owner) revert Unauthorized(msg.sender, owner);
        
        _pendingDeposits[controller] = assets;
        emit DepositRequest(controller, owner, 0, msg.sender, assets);
        return 0;
    }

    function requestRedeem(
        uint256 shares,
        address controller,
        address owner
    ) external override returns (uint256) {
        if (shares == 0) revert ZeroAmount();
        if (msg.sender != owner) revert Unauthorized(msg.sender, owner);
        
        _pendingRedeems[controller] = shares;
        emit RedeemRequest(controller, owner, 0, msg.sender, shares);
        return 0;
    }

    function deposit(
        uint256 assets,
        address receiver,
        address controller
    ) external override returns (uint256) {
        return assets;
    }

    function redeem(
        uint256 shares,
        address receiver,
        address controller
    ) external override returns (uint256) {
        return shares;
    }

    function assetsOf(address owner) external view override returns (uint256) {
        return 0;
    }

    function pendingDepositRequest(
        uint256,
        address controller
    ) external view override returns (uint256) {
        return _pendingDeposits[controller];
    }

    function claimableDepositRequest(
        uint256,
        address controller
    ) external view override returns (uint256) {
        return _claimableDeposits[controller];
    }

    function pendingRedeemRequest(
        uint256,
        address controller
    ) external view override returns (uint256) {
        return _pendingRedeems[controller];
    }

    function claimableRedeemRequest(
        uint256,
        address controller
    ) external view override returns (uint256) {
        return _claimableRedeems[controller];
    }


  function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        return
            interfaceId == type(IERC20).interfaceId ||
            interfaceId == type(IAccessControl).interfaceId ||
            interfaceId == type(IERC7575).interfaceId ||
            interfaceId == type(IComponentToken).interfaceId ||
            interfaceId == type(IERC165).interfaceId;
    }

}