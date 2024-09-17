// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { SmartWallet } from "../SmartWallet.sol";
import { IAssetToken } from "../interfaces/IAssetToken.sol";
import { YieldDistributionToken } from "./YieldDistributionToken.sol";

/**
 * @title AssetToken
 * @author Eugene Y. Q. Shen
 * @notice ERC20 token that represents a tokenized real world asset
 *   and distributes yield proportionally to token holders
 */
contract AssetToken is YieldDistributionToken, IAssetToken {

    // Storage

    /// @custom:storage-location erc7201:plume.storage.AssetToken
    struct AssetTokenStorage {
        /// @dev Total value of all circulating AssetTokens
        uint256 totalValue;
        /// @dev Boolean to enable whitelist for the AssetToken
        bool isWhitelistEnabled;
        /// @dev Whitelist of users that are allowed to hold AssetTokens
        address[] whitelist;
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

    event AddressAddedToWhitelist(address indexed _address);
    event AddressRemovedFromWhitelist(address indexed _address);

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

    // Constructor

    /**
     * @notice Construct the AssetToken
     * @param owner Address of the owner of the AssetToken
     * @param name Name of the AssetToken
     * @param symbol Symbol of the AssetToken
     * @param currencyToken Token in which the yield is deposited and denominated
     * @param decimals_ Number of decimals of the AssetToken
     * @param initialSupply Initial supply of the AssetToken
     * @param totalValue_ Total value of all circulating AssetTokens
     * @param tokenURI_ URI of the AssetToken metadata
     */
    constructor(
        address owner,
        string memory name,
        string memory symbol,
        ERC20 currencyToken,
        uint8 decimals_,
        uint256 initialSupply,
        uint256 totalValue_,
        string memory tokenURI_
    ) YieldDistributionToken(owner, name, symbol, currencyToken, decimals_, tokenURI_) {
        _getAssetTokenStorage().totalValue = totalValue_;
        _mint(owner, initialSupply);
    }

    // Override Functions

    /**
     * @notice Update the balance of `from` and `to` after token transfer
     * @dev Require that the available balance of `from` is greater than `value`
     * @param from Address to transfer tokens from
     * @param to Address to transfer tokens to
     * @param value Amount of tokens to transfer
     */
    function _update(address from, address to, uint256 value) internal override(YieldDistributionToken) {
        AssetTokenStorage storage $ = _getAssetTokenStorage();
        if ($.isWhitelistEnabled) {
            if (!$.isWhitelisted[from]) {
                revert Unauthorized(from);
            }
            if (!$.isWhitelisted[to]) {
                revert Unauthorized(to);
            }
        }

        if (from != address(0)) {
            if (getBalanceAvailable(from) < value) {
                revert InsufficientBalance(from);
            }
        }

        super._update(from, to, value);
    }

    // Admin Functions

    function addToWhitelist(address user) external onlyOwner {
        AssetTokenStorage storage $ = _getAssetTokenStorage();
        require(user != address(0), "Invalid address");
        if ($.isWhitelistEnabled) {
            require(!$.isWhitelisted[user], "Address is already whitelisted");
            $.isWhitelisted[user] = true;
            $.whitelist.push(user);
            emit AddressAddedToWhitelist(user);
        }
    }

    function removeFromWhitelist(address user) external onlyOwner {
        AssetTokenStorage storage $ = _getAssetTokenStorage();
        if (!$.isWhitelistEnabled) {
            return;
        }
        require($.isWhitelisted[user], "Address is not whitelisted");

        for (uint256 i = 0; i < $.whitelist.length; i++) {
            if ($.whitelist[i] == user) {
                $.whitelist[i] = $.whitelist[$.whitelist.length - 1];
                $.whitelist.pop();
                break;
            }
        }

        $.isWhitelisted[user] = false;

        emit AddressRemovedFromWhitelist(user);
    }

    function enableWhitelist() external onlyOwner {
        _getAssetTokenStorage().isWhitelistEnabled = true;
    }

    function isAddressWhitelisted(address user) public view returns (bool) {
        return _getAssetTokenStorage().isWhitelisted[user];
    }

    /**
     * @notice Mint new tokens
     * @param user The user to mint tokens to
     * @param value The amount of tokens to mint
     */
    function mint(address user, uint256 value) public onlyOwner {
        _mint(user, value);
    }

    /**
     * @notice Deposit yield
     * @param timestamp The timestamp of the deposit
     * @param amount The amount of yield to deposit
     */
    function depositYield(uint256 timestamp, uint256 amount) external onlyOwner {
        uint256 lastDepositTimestamp = _getYieldDistributionTokenStorage().depositHistory.lastTimestamp;

        // To prevent adding to a previous deposit where yield has already been distributed
        require(
            lastDepositTimestamp < timestamp,
            "AssetToken: timestamp must be greater than the previous deposit timestamp"
        );

        _depositYield(timestamp, amount);
    }

    // Getter View Functions

    /**
     * @notice Get the available balance of an user
     * @dev The available balance is the balance minus the locked balance
     * @param user The user to get the balance of
     * @return balanceAvailable The available balance of the user
     */
    function getBalanceAvailable(address user) public view returns (uint256 balanceAvailable) {
        return balanceOf(user) - SmartWallet(payable(user)).getBalanceLocked(ERC20(this));
    }

    function getPricePerToken() public view returns (uint256) {
        return _getAssetTokenStorage().totalValue / totalSupply();
    }

    // Get the total yield (unclaimed + claimed)
    function totalYield() public view returns (uint256) {
        // TODO loop through yield deposit history
        return 0;
    }

    // Get unclaimed yield for all users
    function unclaimedYield() public view returns (uint256) {
        return totalYield() - claimedYield();
    }

    // Get claimed yield for all users
    function claimedYield() public view returns (uint256) {
        AssetTokenStorage storage $ = _getAssetTokenStorage();
        // TODO delete this function, it breaks when we delete from whitelist
        uint256 totalClaimed = 0;
        for (uint256 i = 0; i < $.whitelist.length; i++) {
            totalClaimed += _getYieldDistributionTokenStorage().yieldWithdrawn[$.whitelist[i]];
        }
        return totalClaimed;
    }

    // Get user-specific total yield (unclaimed + claimed)
    function totalYield(address user) external view returns (uint256) {
        return unclaimedYield(user) + claimedYield(user);
    }

    // Get unclaimed yield for a specific user
    function unclaimedYield(address user) public view returns (uint256) {
        return _getYieldDistributionTokenStorage().yieldAccrued[user]
            - _getYieldDistributionTokenStorage().yieldWithdrawn[user];
    }

    // Get claimed yield for a specific user
    function claimedYield(address user) public view returns (uint256) {
        return _getYieldDistributionTokenStorage().yieldWithdrawn[user];
    }
}
