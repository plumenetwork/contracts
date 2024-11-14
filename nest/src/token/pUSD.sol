// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { ERC4626Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";

import { IComponentToken } from "../interfaces/IComponentToken.sol";
import { IVault } from "../interfaces/IVault.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";

import { ComponentToken } from "../ComponentToken.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title pUSD
 * @author Eugene Y. Q. Shen, Alp Guneysel
 * @notice Unified Plume USD stablecoin
 */
contract pUSD is Initializable, ERC20Upgradeable, AccessControlUpgradeable, UUPSUpgradeable, ComponentToken {

    using SafeERC20 for IERC20;
    // ========== STORAGE ==========
    /// @custom:storage-location erc7201:plume.storage.pUSD

    struct pUSDStorage {
        IVault vault;
        uint8 tokenDecimals;
        string tokenName;
        string tokenSymbol;
    }

    // keccak256(abi.encode(uint256(keccak256("plume.storage.pUSD")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant PUSD_STORAGE_LOCATION = 0x54ae4f9578cdf7faaee986bff2a08b358f01b852b4da3af4f67309dae312ee00;

    function _getpUSDStorage() private pure returns (pUSDStorage storage $) {
        bytes32 position = PUSD_STORAGE_LOCATION;
        assembly {
            $.slot := position
        }
    }

    // ========== EVENTS ==========
    event VaultChanged(address oldVault, address newVault);

    // ========== ROLES ==========
    bytes32 public constant VAULT_ADMIN_ROLE = keccak256("VAULT_ADMIN_ROLE");

    /**
     * @notice Prevent the implementation contract from being initialized or reinitialized
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize pUSD
     * @param owner Address of the owner of pUSD
     * @param asset_ Address of the underlying asset
     * @param vault_ Address of the Boring Vault
     */
    // Changed to _initialize to avoid double initialization

    function initialize(address owner, IERC20 asset_, address vault_) public initializer {
        super.initialize(owner, "Plume USD", "pUSD", asset_, false, false);

        pUSDStorage storage $ = _getpUSDStorage();
        $.vault = IVault(vault_);

        _grantRole(VAULT_ADMIN_ROLE, owner);
    }

    // ========== ADMIN FUNCTIONS ==========
    function setVault(
        address newVault
    ) external onlyRole(VAULT_ADMIN_ROLE) {
        pUSDStorage storage $ = _getpUSDStorage();
        address oldVault = address($.vault);
        $.vault = IVault(newVault);
        emit VaultChanged(oldVault, newVault);
    }

    // ========== VIEW FUNCTIONS ==========
    function vault() external view returns (address) {
        return address(_getpUSDStorage().vault);
    }

    // ========== COMPONENT TOKEN INTEGRATION ==========
    function deposit(
        uint256 assets,
        address receiver,
        address controller
    ) public virtual override returns (uint256 shares) {
        // Calculate shares to mint
        shares = previewDeposit(assets);

        // Transfer assets from depositor
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), assets);

        // Mint shares to receiver
        _mint(receiver, shares);

        // Approve and deposit assets into vault
        IERC20(asset()).approve(address(_getpUSDStorage().vault), assets);
        _getpUSDStorage().vault.enter(address(this), address(asset()), assets, receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function redeem(
        uint256 shares,
        address receiver,
        address controller
    ) public virtual override returns (uint256 assets) {
        // Calculate the assets amount using previewRedeem
        assets = previewRedeem(shares);

        // Check that the controller has enough shares
        require(_getpUSDStorage().vault.balanceOf(controller) >= shares, "ERC20: insufficient balance");

        // Handle the share burning before vault exit
        if (controller != msg.sender) {
            _spendAllowance(controller, msg.sender, shares);
        }
        _burn(controller, shares);

        // Get assets from vault and send directly to receiver
        _getpUSDStorage().vault.exit(receiver, address(asset()), assets, controller, shares);

        emit Withdraw(msg.sender, receiver, controller, assets, shares);
    }

    // ========== ERC20 OVERRIDES ==========
    function transfer(address to, uint256 amount) public virtual override(ERC20Upgradeable, IERC20) returns (bool) {
        // Since balances are tracked in the vault, we only need to update the vault's records
        return _getpUSDStorage().vault.transferFrom(msg.sender, to, amount);
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual override(ERC20Upgradeable, IERC20) returns (bool) {
        // Handle allowance in the token contract
        if (from != msg.sender) {
            uint256 currentAllowance = allowance(from, msg.sender);
            if (currentAllowance != type(uint256).max) {
                require(currentAllowance >= amount, "ERC20: insufficient allowance");
                unchecked {
                    _approve(from, msg.sender, currentAllowance - amount);
                }
            }
        }

        // Delegate the actual transfer to the vault
        return _getpUSDStorage().vault.transferFrom(from, to, amount);
    }

    function balanceOf(
        address account
    ) public view override(IERC20, ERC20Upgradeable) returns (uint256) {
        return _getpUSDStorage().vault.balanceOf(account);
    }

    // ========== METADATA OVERRIDES ==========

    function decimals() public pure override(ERC4626Upgradeable, ERC20Upgradeable, IERC20Metadata) returns (uint8) {
        return 6;
    }

    function name() public pure override(ERC20Upgradeable, IERC20Metadata) returns (string memory) {
        return "Plume USD";
    }

    function symbol() public pure override(ERC20Upgradeable, IERC20Metadata) returns (string memory) {
        return "pUSD";
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(AccessControlUpgradeable, ComponentToken) returns (bool) {
        return interfaceId == type(IERC20).interfaceId || interfaceId == type(IAccessControl).interfaceId
            || super.supportsInterface(interfaceId);
    }

}
