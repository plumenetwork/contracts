// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { WalletUtils } from "../WalletUtils.sol";
import { IAssetToken } from "../interfaces/IAssetToken.sol";
import { ISmartWallet } from "../interfaces/ISmartWallet.sol";
import { IYieldDistributionToken } from "../interfaces/IYieldDistributionToken.sol";
import { Deposit, UserState } from "./Types.sol";
import { YieldDistributionToken } from "./YieldDistributionToken.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title AssetToken
 * @author Eugene Y. Q. Shen, Alp Guneysel
 * @notice ERC20 token that represents a tokenized real world asset
 *   and distributes yield proportionally to token holders
 */
contract AssetToken is
    Initializable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    WalletUtils,
    YieldDistributionToken,
    IAssetToken
{

    // Storage

    /// @custom:storage-location erc7201:plume.storage.AssetToken
    struct AssetTokenStorage {
        /// @dev Total value of all circulating AssetTokens
        uint256 totalValue;
        /// @dev Boolean to enable whitelist for the AssetToken
        bool isWhitelistEnabled;
        /// @dev Mapping of whitelisted users
        mapping(address user => bool whitelisted) isWhitelisted;
    }

    // keccak256(abi.encode(uint256(keccak256("plume.storage.AssetToken")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ASSET_TOKEN_STORAGE_LOCATION =
        0x726dfad64e66a3008dc13dfa01e6342ee01974bb72e1b2f461563ca13356d800;

    function _getAssetTokenStorage() private pure returns (AssetTokenStorage storage $) {
        assembly {
            $.slot := ASSET_TOKEN_STORAGE_LOCATION
        }
    }

    // Events

    /**
     * @notice Emitted when a user is added to the whitelist
     * @param user Address of the user that is added to the whitelist
     */
    event AddressAddedToWhitelist(address indexed user);

    /**
     * @notice Emitted when a user is removed from the whitelist
     * @param user Address of the user that is removed from the whitelist
     */
    event AddressRemovedFromWhitelist(address indexed user);

    // Errors

    /**
     * @notice Indicates a failure because the user is not whitelisted
     * @param user Address of the user that is not whitelisted
     */
    error Unauthorized(address user);

    /**
     * @notice Indicates a failure because the user has insufficient balance
     * @param user Address of the user that has insufficient balance
     */
    error InsufficientBalance(address user);

    /// @notice Indicates a failure because the given address is 0x0
    error InvalidAddress();

    /**
     * @notice Indicates a failure because the user is already whitelisted
     * @param user Address of the user that is already whitelisted
     */
    error AddressAlreadyWhitelisted(address user);

    /**
     * @notice Indicates a failure because the user is not whitelisted
     * @param user Address of the user that is not whitelisted
     */
    error AddressNotWhitelisted(address user);

    /**
     * @notice Indicates holder status change event
     * @param holder Address of Holder
     * @param isHolder true when becomes holder, false when stops being holder
     */
    event HolderStatusChanged(address indexed holder, bool isHolder);

    // Constructor

    constructor() {
        _disableInitializers();
    }
    /**
     * @notice Construct the AssetToken
     * @param owner Address of the owner of the AssetToken
     * @param name Name of the AssetToken
     * @param symbol Symbol of the AssetToken
     * @param currencyToken Token in which the yield is deposited and denominated
     * @param decimals_ Number of decimals of the AssetToken
     * @param tokenURI_ URI of the AssetToken metadata
     * @param initialSupply Initial supply of the AssetToken
     * @param totalValue_ Total value of all circulating AssetTokens
     * @param isWhitelistEnabled_ Boolean to enable whitelist for the AssetToken
     */

    function initialize(
        address owner,
        string memory name,
        string memory symbol,
        IERC20 currencyToken,
        uint8 decimals_,
        string memory tokenURI_,
        uint256 initialSupply,
        uint256 totalValue_,
        bool isWhitelistEnabled_
    ) public initializer {
        if (address(currencyToken) == address(0)) {
            revert InvalidAddress();
        }
        __YieldDistributionToken_init(owner, name, symbol, currencyToken, decimals_, tokenURI_);

        AssetTokenStorage storage $ = _getAssetTokenStorage();
        $.totalValue = totalValue_;
        $.isWhitelistEnabled = isWhitelistEnabled_;

        // need to whitelist owner, otherwise reverts in _update
        if ($.isWhitelistEnabled) {
            // Whitelist the owner
            if (owner == address(0)) {
                revert InvalidAddress();
            }
            $.isWhitelisted[owner] = true;
            emit AddressAddedToWhitelist(owner);
        }

        _mint(owner, initialSupply);
    }

    /**
     * @notice Reinitialize the AssetToken with updated parameters
     * @dev This function can be called multiple times, but only by the owner and with increasing version numbers
     * @param version Version number for the reinitialization
     * @param newName Optional new name for the token (empty string to keep current)
     * @param newSymbol Optional new symbol for the token (empty string to keep current)
     * @param newTokenURI Optional new token URI (empty string to keep current)
     * @param newCurrencyToken Optional new currency token (address(0) to keep current)
     * @param newDecimals Optional new decimals (0 to keep current)
     * @param newTotalValue Optional new total value (0 to keep current)
     * @param newWhitelistEnabled Optional new whitelist enabled setting
     */
    function reinitialize(
        uint8 version,
        string memory newName,
        string memory newSymbol,
        string memory newTokenURI,
        address newCurrencyToken,
        uint8 newDecimals,
        uint256 newTotalValue,
        bool newWhitelistEnabled
    ) public reinitializer(version) onlyRole(ADMIN_ROLE) {
        // Reinitialize YieldDistributionToken
        __YieldDistributionToken_reinitialize(
            version, newName, newSymbol, IERC20(newCurrencyToken), newDecimals, newTokenURI
        );

        AssetTokenStorage storage $ = _getAssetTokenStorage();

        // Update total value if provided
        if (newTotalValue > 0) {
            $.totalValue = newTotalValue;
        }

        // Update whitelist setting
        $.isWhitelistEnabled = newWhitelistEnabled;
    }

    // Override Functions

    /**
     * @notice Update the balance of `from` and `to` after token transfer and accrue yield
     * @dev Require that both parties are whitelisted and `from` has enough tokens
     * @param from Address to transfer tokens from
     * @param to Address to transfer tokens to
     * @param value Amount of tokens to transfer
     */
    function _update(address from, address to, uint256 value) internal override(YieldDistributionToken) {
        AssetTokenStorage storage $ = _getAssetTokenStorage();
        if ($.isWhitelistEnabled) {
            if (from != address(0) && !$.isWhitelisted[from]) {
                revert Unauthorized(from);
            }
            if (to != address(0) && !$.isWhitelisted[to]) {
                revert Unauthorized(to);
            }
        }

        if (from != address(0)) {
            if (getBalanceAvailable(from) < value) {
                revert InsufficientBalance(from);
            }

            if (balanceOf(from) == value) {
                // Will have zero balance after transfer
                emit HolderStatusChanged(from, false);
            }
        }

        if (to != address(0)) {
            // Check if to address will become a new holder
            if (balanceOf(to) == 0) {
                // Currently has zero balance
                emit HolderStatusChanged(to, true);
            }
        }

        super._update(from, to, value);
    }

    // Admin Functions

    /**
     * @notice Revert when `msg.sender` is not authorized to upgrade the contract
     * @param newImplementation Address of the new implementation
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal virtual override(UUPSUpgradeable) onlyRole(UPGRADER_ROLE) { }

    /**
     * @notice Update the total value of all circulating AssetTokens
     * @dev Only the owner can call this function
     */
    function setTotalValue(
        uint256 totalValue
    ) external onlyRole(ADMIN_ROLE) {
        _getAssetTokenStorage().totalValue = totalValue;
    }

    /**
     * @notice Add a user to the whitelist
     * @dev Only the owner can call this function
     * @param user Address of the user to add to the whitelist
     */
    function addToWhitelist(
        address user
    ) external onlyRole(ADMIN_ROLE) {
        if (user == address(0)) {
            revert InvalidAddress();
        }

        AssetTokenStorage storage $ = _getAssetTokenStorage();
        if ($.isWhitelistEnabled) {
            if ($.isWhitelisted[user]) {
                revert AddressAlreadyWhitelisted(user);
            }
            $.isWhitelisted[user] = true;
            emit AddressAddedToWhitelist(user);
        }
    }

    /**
     * @notice Remove a user from the whitelist
     * @dev Only the owner can call this function
     * @param user Address of the user to remove from the whitelist
     */
    function removeFromWhitelist(
        address user
    ) external onlyRole(ADMIN_ROLE) {
        if (user == address(0)) {
            revert InvalidAddress();
        }

        AssetTokenStorage storage $ = _getAssetTokenStorage();
        if ($.isWhitelistEnabled) {
            if (!$.isWhitelisted[user]) {
                revert AddressNotWhitelisted(user);
            }
            $.isWhitelisted[user] = false;
            emit AddressRemovedFromWhitelist(user);
        }
    }

    /**
     * @notice Mint new AssetTokens to the user
     * @dev Only the owner can call this function
     * @param user Address of the user to mint AssetTokens to
     * @param assetTokenAmount Amount of AssetTokens to mint
     */
    function mint(address user, uint256 assetTokenAmount) external onlyRole(ADMIN_ROLE) {
        _mint(user, assetTokenAmount);
    }

    /**
     * @notice Deposit yield into the AssetToken
     * @dev Only the owner can call this function, and the owner must have
     *   approved the CurrencyToken to spend the given amount
     * @param currencyTokenAmount Amount of CurrencyToken to deposit as yield
     */
    function depositYield(
        uint256 currencyTokenAmount
    ) external onlyRole(ADMIN_ROLE) nonReentrant {
        _depositYield(currencyTokenAmount);
    }

    // Permissionless Functions

    /**
     * @notice Make the SmartWallet redistribute yield from this token
     * @dev The Solidity compiler adds a check that the target address has `extcodesize > 0`
     *   and otherwise reverts for high-level calls, so we have to use a low-level call here
     * @param from Address of the SmartWallet to request the yield from
     */
    function requestYield(
        address from
    ) external override(YieldDistributionToken, IYieldDistributionToken) nonReentrant {
        // Have to override both until updated in https://github.com/ethereum/solidity/issues/12665
        (bool success,) = from.call(abi.encodeWithSelector(ISmartWallet.claimAndRedistributeYield.selector, this));
        if (!success) {
            revert SmartWalletCallFailed(from);
        }
    }

    // Getter View Functions

    /// @notice Total value of all circulating AssetTokens
    function getTotalValue() external view returns (uint256) {
        return _getAssetTokenStorage().totalValue;
    }

    /// @notice Returns whether the whitelist is enabled for this token
    function isWhitelistEnabled() public view returns (bool) {
        return _getAssetTokenStorage().isWhitelistEnabled;
    }

    /**
     * @notice Check if the user is whitelisted
     * @param user Address of the user to check
     * @return isWhitelisted Boolean indicating if the user is whitelisted
     */
    function isAddressWhitelisted(
        address user
    ) external view returns (bool isWhitelisted) {
        return _getAssetTokenStorage().isWhitelisted[user];
    }

    /// @notice Price of an AssetToken based on its total value and total supply
    function getPricePerToken() external view returns (uint256) {
        return _getAssetTokenStorage().totalValue / totalSupply();
    }

    /**
     * @notice Get the available unlocked AssetToken balance of a user
     * @dev The Solidity compiler adds a check that the target address has `extcodesize > 0`
     *   and otherwise reverts for high-level calls, so we have to use a low-level call here
     * @param user Address of the user to get the available balance of
     * @return balanceAvailable Available unlocked AssetToken balance of the user
     */
    function getBalanceAvailable(
        address user
    ) public view returns (uint256 balanceAvailable) {
        (bool success, bytes memory data) =
            user.staticcall(abi.encodeWithSelector(ISmartWallet.getBalanceLocked.selector, this));
        if (!success) {
            revert SmartWalletCallFailed(user);
        }

        balanceAvailable = balanceOf(user);
        if (data.length > 0) {
            uint256 lockedBalance = abi.decode(data, (uint256));
            balanceAvailable -= lockedBalance;
        }
    }

    function getYieldCalculationState(
        address user
    )
        external
        view
        returns (
            uint256 userBalance,
            uint256 lastUpdateTimestamp,
            uint256 timeSinceLastUpdate,
            uint256 userAmountSeconds,
            uint256 yieldPerTokenStored,
            uint256 userYieldPerTokenPaid,
            uint256 yieldDifference,
            uint256 currentRewards,
            uint256 contractBalance
        )
    {
        YieldDistributionTokenStorage storage $ = _getYieldDistributionTokenStorage();

        userBalance = balanceOf(user);
        lastUpdateTimestamp = $.lastUpdate[user];
        timeSinceLastUpdate = block.timestamp - lastUpdateTimestamp;
        userAmountSeconds = userBalance * timeSinceLastUpdate;
        yieldPerTokenStored = $.yieldPerTokenStored;
        userYieldPerTokenPaid = $.userYieldPerTokenPaid[user];
        yieldDifference = yieldPerTokenStored - userYieldPerTokenPaid;
        currentRewards = $.rewards[user];
        contractBalance = $.currencyToken.balanceOf(address(this));
    }

    function getGlobalState()
        external
        view
        returns (
            uint256 totalSupply_,
            uint256 totalAmountSeconds_,
            uint256 lastSupplyUpdate_,
            uint256 lastDepositTimestamp_,
            uint256 yieldPerTokenStored_
        )
    {
        YieldDistributionTokenStorage storage $ = _getYieldDistributionTokenStorage();

        totalSupply_ = totalSupply();
        totalAmountSeconds_ = $.totalAmountSeconds;
        lastSupplyUpdate_ = $.lastSupplyUpdate;
        lastDepositTimestamp_ = $.lastDepositTimestamp;
        yieldPerTokenStored_ = $.yieldPerTokenStored;
    }

}
