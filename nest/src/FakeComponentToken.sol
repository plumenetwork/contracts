// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { AccessControlUpgradeable } from "openzeppelin-contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { Initializable } from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ERC20Upgradeable } from "openzeppelin-contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import { IComponentToken } from "./interfaces/IComponentToken.sol";

/**
 * @title FakeComponentToken
 * @author Eugene Y. Q. Shen
 * @notice Fake example of a ComponentToken that could be used in an AggregateToken when testing.
 * Users can buy and sell one FakeComponentToken by exchanging it with one CurrencyToken at any time.
 * @custom:oz-upgrades-from FakeComponentToken
 */
contract FakeComponentToken is Initializable, AccessControlUpgradeable, UUPSUpgradeable, ERC20Upgradeable {

    // Storage

    /// @custom:storage-location erc7201:plume.storage.FakeComponentToken
    struct FakeComponentTokenStorage {
        /// @dev CurrencyToken used to mint and burn the FakeComponentToken
        IERC20 currencyToken;
        /// @dev Number of decimals of the FakeComponentToken
        uint8 decimals;
    }

    // keccak256(abi.encode(uint256(keccak256("plume.storage.FakeComponentToken")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant FAKE_COMPONENT_TOKEN_STORAGE_LOCATION =
        0x2c4e9dd7fc35b7006b8a84e1ac11ecc9e53a0dd5c8824b364abab355c5037600;

    function _getFakeComponentTokenStorage() private pure returns (FakeComponentTokenStorage storage $) {
        assembly {
            $.slot := FAKE_COMPONENT_TOKEN_STORAGE_LOCATION
        }
    }

    // Constants

    /// @notice Role for the upgrader of the FakeComponentToken
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADE_ROLE");

    // Base at which we do all calculations to minimize rounding losses
    uint256 private constant _BASE = 1e18;

    // Events

    /**
     * @notice Emitted when a user buys FakeComponentToken using CurrencyToken
     * @param user Address of the user who bought the FakeComponentToken
     * @param currencyToken CurrencyToken used to buy the FakeComponentToken
     * @param currencyTokenAmount Amount of CurrencyToken paid
     * @param componentTokenAmount Amount of FakeComponentToken received
     */
    event ComponentTokenBought(
        address indexed user, IERC20 indexed currencyToken, uint256 currencyTokenAmount, uint256 componentTokenAmount
    );

    /**
     * @notice Emitted when a user sells FakeComponentToken to receive CurrencyToken
     * @param user Address of the user who sold the FakeComponentToken
     * @param currencyToken CurrencyToken received in exchange for the FakeComponentToken
     * @param currencyTokenAmount Amount of CurrencyToken received
     * @param componentTokenAmount Amount of FakeComponentToken sold
     */
    event ComponentTokenSold(
        address indexed user, IERC20 indexed currencyToken, uint256 currencyTokenAmount, uint256 componentTokenAmount
    );

    // Errors

    /**
     * @notice Indicates a failure because the given CurrencyToken does not match actual CurrencyToken
     * @param invalidCurrencyToken CurrencyToken that does not match the actual CurrencyToken
     * @param currencyToken Actual CurrencyToken used to mint and burn the FakeComponentToken
     */
    error InvalidCurrencyToken(IERC20 invalidCurrencyToken, IERC20 currencyToken);

    /**
     * @notice Indicates a failure because the FakeComponentToken does not have enough CurrencyToken
     * @param currencyToken CurrencyToken used to mint and burn the FakeComponentToken
     * @param amount Amount of CurrencyToken required in the failed transfer
     */
    error CurrencyTokenInsufficientBalance(IERC20 currencyToken, uint256 amount);

    /**
     * @notice Indicates a failure because the user does not have enough CurrencyToken
     * @param currencyToken CurrencyToken used to mint and burn the FakeComponentToken
     * @param user Address of the user who is selling the CurrencyToken
     * @param amount Amount of CurrencyToken required in the failed transfer
     */
    error UserCurrencyTokenInsufficientBalance(IERC20 currencyToken, address user, uint256 amount);

    // Initializer

    /**
     * @notice Initialize the FakeComponentToken
     * @param owner Address of the owner of the FakeComponentToken
     * @param name Name of the FakeComponentToken
     * @param symbol Symbol of the FakeComponentToken
     * @param currencyToken CurrencyToken used to mint and burn the FakeComponentToken
     * @param decimals_ Number of decimals of the FakeComponentToken
     */
    function initialize(
        address owner,
        string memory name,
        string memory symbol,
        IERC20 currencyToken,
        uint8 decimals_
    ) public initializer {
        __ERC20_init(name, symbol);
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, owner);
        _grantRole(UPGRADER_ROLE, owner);

        FakeComponentTokenStorage storage $ = _getFakeComponentTokenStorage();
        $.currencyToken = currencyToken;
        $.decimals = decimals_;
    }

    // Override Functions

    /**
     * @notice Revert when `msg.sender` is not authorized to upgrade the contract
     * @param newImplementation Address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) { }

    /// @notice Number of decimals of the FakeComponentToken
    function decimals() public view override returns (uint8) {
        FakeComponentTokenStorage storage $ = _getFakeComponentTokenStorage();
        return $.decimals;
    }

    // User Functions

    /**
     * @notice Buy FakeComponentToken using CurrencyToken
     * @dev The user must approve the contract to spend the CurrencyToken
     * @param currencyToken_ CurrencyToken used to buy the FakeComponentToken
     * @param amount Amount of FakeComponentToken to buy using the same amount of CurrencyToken
     */
    function buy(IERC20 currencyToken_, uint256 amount) public {
        FakeComponentTokenStorage storage $ = _getFakeComponentTokenStorage();
        IERC20 currencyToken = $.currencyToken;

        if (currencyToken_ != currencyToken) {
            revert InvalidCurrencyToken(currencyToken_, currencyToken);
        }
        if (!currencyToken.transferFrom(msg.sender, address(this), amount)) {
            revert UserCurrencyTokenInsufficientBalance(currencyToken, msg.sender, amount);
        }

        _mint(msg.sender, amount);

        emit ComponentTokenBought(msg.sender, currencyToken, amount, amount);
    }

    /**
     * @notice Sell FakeComponentToken to receive CurrencyToken
     * @param currencyToken_ CurrencyToken received in exchange for the FakeComponentToken
     * @param amount Amount of FakeComponentToken to sell to receive the same amount of CurrencyToken
     */
    function sell(IERC20 currencyToken_, uint256 amount) public {
        FakeComponentTokenStorage storage $ = _getFakeComponentTokenStorage();
        IERC20 currencyToken = $.currencyToken;

        if (currencyToken_ != currencyToken) {
            revert InvalidCurrencyToken(currencyToken_, currencyToken);
        }
        if (!currencyToken.transfer(msg.sender, amount)) {
            revert CurrencyTokenInsufficientBalance(currencyToken, amount);
        }

        _burn(msg.sender, amount);

        emit ComponentTokenSold(msg.sender, currencyToken, amount, amount);
    }

    // Admin Functions

    /**
     * @notice Set the CurrencyToken used to mint and burn the FakeComponentToken
     * @param currencyAddress Address of the CurrencyToken
     */
    function setCurrencyToken(IERC20 currencyAddress) public onlyRole(DEFAULT_ADMIN_ROLE) {
        FakeComponentTokenStorage storage $ = _getFakeComponentTokenStorage();
        $.currencyToken = currencyAddress;
    }

    // View Functions

    /// @notice CurrencyToken used to mint and burn the FakeComponentToken
    function getCurrencyToken() public view returns (IERC20) {
        FakeComponentTokenStorage storage $ = _getFakeComponentTokenStorage();
        return $.currencyToken;
    }

}