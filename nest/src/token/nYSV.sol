// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { ERC4626Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";

import { NestAtomicQueue } from "../vault/NestAtomicQueue.sol";

import { NestBoringVaultModule } from "../vault/NestBoringVaultModule.sol";
import { NestTeller } from "../vault/NestTeller.sol";

/**
 * @title nYSV
 * @author Eugene Y. Q. Shen, Alp Guneysel
 * @notice Unified Plume Yield Stables Vault
 */
contract nYSV is Initializable, ERC20Upgradeable, NestAtomicQueue, NestTeller {

    /**
     * @notice Prevent the implementation contract from being initialized or reinitialized
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor(
        address _owner,
        address _vault,
        address _accountant,
        address _endpoint
    ) NestTeller(_owner, _vault, _accountant, _endpoint) NestAtomicQueue(_owner) {
        _disableInitializers();
    }

    /**
     * @notice Initialize nYSV
     * @param _vault Address of the BoringVault
     * @param _accountant Address of the accountant
     * @param _asset Address of the underlying asset
     * @param _minimumMintPercentage Minimum mint percentage (4 decimals)
     * @param _deadlinePeriod Period for atomic queue deadlines
     * @param _pricePercentage Price percentage for atomic queue (4 decimals)
     */
    function initialize(
        address _vault,
        address _accountant,
        IERC20 _asset,
        uint256 _minimumMintPercentage,
        uint256 _deadlinePeriod,
        uint256 _pricePercentage
    ) public initializer {
        __ERC20_init("Nest Yield Stable Vault", "nYSV");
        __NestBoringVaultModule_init(_vault, _accountant, _asset);

        // Set minimumMintPercentage
        if (_minimumMintPercentage == 0 || _minimumMintPercentage > 10_000) {
            revert InvalidMinimumMintPercentage();
        }
        minimumMintPercentage = _minimumMintPercentage;

        // Set atomic queue parameters
        deadlinePeriod = _deadlinePeriod;
        pricePercentage = _pricePercentage;
    }

    // ========== METADATA OVERRIDES ==========

    /**
     * @notice Get the name of the token
     * @return Name of the token
     */
    function name() public pure override(ERC20Upgradeable) returns (string memory) {
        return "Nest Yield Stable Vault";
    }

    /**
     * @notice Get the symbol of the token
     * @return Symbol of the token
     */
    function symbol() public pure override(ERC20Upgradeable) returns (string memory) {
        return "nYSV";
    }

    // Override conflicting functions
    function deposit(
        uint256 assets,
        address receiver,
        address controller
    ) public override(NestAtomicQueue, NestTeller) returns (uint256) {
        return NestTeller.deposit(assets, receiver, controller);
    }

    function requestDeposit(
        uint256 assets,
        address controller,
        address owner
    ) public override(NestTeller, NestBoringVaultModule) returns (uint256) {
        return NestTeller.requestDeposit(assets, controller, owner);
    }

    function requestRedeem(
        uint256 shares,
        address controller,
        address owner
    ) public override(NestAtomicQueue, NestTeller) returns (uint256) {
        return NestAtomicQueue.requestRedeem(shares, controller, owner);
    }

    // Add overrides for ERC20 functions
    function balanceOf(
        address account
    ) public view override(ERC20Upgradeable, NestBoringVaultModule) returns (uint256) {
        return ERC20Upgradeable.balanceOf(account);
    }

    function totalSupply() public view override(ERC20Upgradeable, NestBoringVaultModule) returns (uint256) {
        return ERC20Upgradeable.totalSupply();
    }

    // For decimals, we need to change the inheritance or rename one of them
    // Let's override it to use ERC20Upgradeable's implementation
    function decimals() public view override(ERC20Upgradeable) returns (uint8) {
        return ERC20Upgradeable.decimals();
    }

}
