// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IYieldDistributionToken } from "../interfaces/IYieldDistributionToken.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title YieldDistributionToken
 * @author Eugene Y. Q. Shen, Alp Guneysel
 * @notice ERC20 token that receives yield deposits and distributes yield
 *   to token holders proportionally based on how long they have held the token
 */
abstract contract YieldDistributionToken is
    Initializable,
    ERC20Upgradeable,
    AccessControlUpgradeable,
    IYieldDistributionToken
{

    using Math for uint256;
    using SafeERC20 for IERC20;

    // Storage

    /// @custom:storage-location erc7201:plume.storage.YieldDistributionToken
    struct YieldDistributionTokenStorage {
        /// @dev CurrencyToken in which the yield is deposited and denominated
        IERC20 currencyToken;
        /// @dev Number of decimals of the YieldDistributionToken
        uint8 decimals;
        /// @dev URI for the YieldDistributionToken metadata
        string tokenURI;
        /// @dev Current sum of all amountSeconds for all users
        uint256 totalAmountSeconds;
        /// @dev Timestamp of the last change in totalSupply()
        uint256 lastSupplyUpdate;
        /// @dev lastDepositTimestamp
        uint256 lastDepositTimestamp;
        /// @dev yieldPerTokenStored
        uint256 yieldPerTokenStored;
        /// @dev userYieldPerTokenPaid
        mapping(address => uint256) userYieldPerTokenPaid;
        /// @dev rewards
        mapping(address => uint256) rewards;
        /// @dev State for each user
        mapping(address user => uint256) lastUpdate;
    }

    // keccak256(abi.encode(uint256(keccak256("plume.storage.YieldDistributionToken")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant YIELD_DISTRIBUTION_TOKEN_STORAGE_LOCATION =
        0x3d2d7d9da47f1055055838ecd982d8a93d7044b5f93759fc6e1ef3269bbc7000;

    /// @notice Role for the admin of the ComponentToken
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    /// @notice Role for the upgrader of the ComponentToken
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    function _getYieldDistributionTokenStorage() internal pure returns (YieldDistributionTokenStorage storage $) {
        assembly {
            $.slot := YIELD_DISTRIBUTION_TOKEN_STORAGE_LOCATION
        }
    }

    // Constants

    // Base that is used to divide all price inputs in order to represent e.g. 1.000001 as 1000001e12
    uint256 private constant _BASE = 1e18;

    // Scale that is used to multiply yield deposits for increased precision
    uint256 private constant SCALE = 1e36;

    // Constructor

    /**
     * @notice Prevent the implementation contract from being initialized or reinitialized
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the YieldDistributionToken with basic parameters and storage
     * @dev This function should only be called once during initialization
     * @param owner Address thaxt will receive initial ownership rights
     * @param name Token name for ERC20 metadata
     * @param symbol Token symbol for ERC20 metadata
     * @param currencyToken The ERC20 token used for yield distributions
     * @param decimals_ Number of decimals for token amounts (e.g., 18 for full precision)
     * @param tokenURI_ URI pointing to token metadata (can be updated later by owner)
     * @custom:security onlyInitializing - Function can only be called during initialization
     */
    function __YieldDistributionToken_init(
        address owner,
        string memory name,
        string memory symbol,
        IERC20 currencyToken,
        uint8 decimals_,
        string memory tokenURI_
    ) internal onlyInitializing {
        __ERC20_init(name, symbol);

        _grantRole(DEFAULT_ADMIN_ROLE, owner);
        _grantRole(ADMIN_ROLE, owner);
        _grantRole(UPGRADER_ROLE, owner);

        YieldDistributionTokenStorage storage $ = _getYieldDistributionTokenStorage();
        $.currencyToken = currencyToken;
        $.decimals = decimals_;
        $.tokenURI = tokenURI_;
        $.lastDepositTimestamp = block.timestamp;
        $.lastSupplyUpdate = block.timestamp;
        $.yieldPerTokenStored = 0;
    }

    function __YieldDistributionToken_reinit(
        string memory newName,
        string memory newSymbol,
        string memory newTokenURI
    ) internal {
        // Update name and symbol if provided
        if (bytes(newName).length > 0 || bytes(newSymbol).length > 0) {
            string memory updatedName = bytes(newName).length > 0 ? newName : name();
            string memory updatedSymbol = bytes(newSymbol).length > 0 ? newSymbol : symbol();
            __ERC20_init(updatedName, updatedSymbol);
        }

        // Update tokenURI if provided
        if (bytes(newTokenURI).length > 0) {
            _getYieldDistributionTokenStorage().tokenURI = newTokenURI;
        }
    }

    /**
     * @notice Reinitialize the YieldDistributionToken with updated parameters
     * @dev This function can be called multiple times, but only by the owner and with increasing version numbers
     * @param version Version number for the reinitialization
     * @param newName Optional new name for the token (empty string to keep current)
     * @param newSymbol Optional new symbol for the token (empty string to keep current)
     * @param newCurrencyToken Optional new currency token (address(0) to keep current)
     * @param newDecimals Optional new decimals (0 to keep current)
     * @param newTokenURI Optional new token URI (empty string to keep current)
     */
    function __YieldDistributionToken_reinitialize(
        uint8 version,
        string memory newName,
        string memory newSymbol,
        IERC20 newCurrencyToken,
        uint8 newDecimals,
        string memory newTokenURI
    ) internal reinitializer(version) {
        YieldDistributionTokenStorage storage $ = _getYieldDistributionTokenStorage();

        // Update currency token if provided
        if (address(newCurrencyToken) != address(0)) {
            // Ensure there's no pending yield before changing currency token
            if ($.yieldPerTokenStored > 0) {
                revert("Cannot change currency token with pending yield");
            }
            $.currencyToken = newCurrencyToken;
        }

        // Update decimals if provided
        if (newDecimals > 0) {
            $.decimals = newDecimals;
        }

        // Update tokenURI if provided
        if (bytes(newTokenURI).length > 0) {
            $.tokenURI = newTokenURI;
        }
    }

    // Virtual Functions

    /// @notice Request to receive yield from the given SmartWallet
    function requestYield(
        address from
    ) external virtual override(IYieldDistributionToken);

    // Override Functions

    /// @notice Number of decimals of the YieldDistributionToken
    function decimals() public view virtual override returns (uint8) {
        return _getYieldDistributionTokenStorage().decimals;
    }

    /**
     * @notice Update the balance of `from` and `to` after token transfer and accrue yield
     * @param from Address to transfer tokens from
     * @param to Address to transfer tokens to
     * @param value Amount of tokens to transfer
     */
    // Users only accrue yield based on their userYieldPerTokenPaid
    // When a user first receives tokens, their userYieldPerTokenPaid is set to the current yieldPerTokenStored
    // This naturally prevents them from claiming any yield from before they held tokens
    function _update(address from, address to, uint256 value) internal virtual override {
        _updateGlobalAmountSeconds();

        if (from != address(0)) {
            accrueYield(from);
        }

        if (to != address(0)) {
            YieldDistributionTokenStorage storage $ = _getYieldDistributionTokenStorage();
            // Initialize lastUpdate for new token holders
            if (balanceOf(to) == 0 && $.lastUpdate[to] == 0) {
                $.lastUpdate[to] = block.timestamp;
                $.userYieldPerTokenPaid[to] = $.yieldPerTokenStored;
            }
            accrueYield(to);
        }

        super._update(from, to, value);
    }

    // Internal Functions

    /// @notice Update the totalAmountSeconds and lastSupplyUpdate when supply or time changes
    function _updateGlobalAmountSeconds() internal {
        YieldDistributionTokenStorage storage $ = _getYieldDistributionTokenStorage();
        uint256 timestamp = block.timestamp;
        if (timestamp > $.lastSupplyUpdate) {
            $.totalAmountSeconds += totalSupply() * (timestamp - $.lastSupplyUpdate);
            $.lastSupplyUpdate = timestamp;
        }
    }

    /**
     * @notice Deposit yield into the YieldDistributionToken
     * @dev The sender must have approved the CurrencyToken to spend the given amount
     * @param currencyTokenAmount Amount of CurrencyToken to deposit as yield
     */
    function _depositYield(
        uint256 currencyTokenAmount
    ) internal {
        if (currencyTokenAmount == 0) {
            return;
        }

        YieldDistributionTokenStorage storage $ = _getYieldDistributionTokenStorage();

        if (block.timestamp == $.lastDepositTimestamp) {
            revert DepositSameBlock();
        }

        _updateGlobalAmountSeconds();

        uint256 currentSupply = totalSupply();
        if (currentSupply > 0) {
            // Use current supply if totalAmountSeconds is 0
            uint256 divisor = $.totalAmountSeconds > 0 ? $.totalAmountSeconds : currentSupply;
            $.yieldPerTokenStored += currencyTokenAmount.mulDiv(SCALE, divisor);
        }

        $.lastDepositTimestamp = block.timestamp;
        $.currencyToken.safeTransferFrom(_msgSender(), address(this), currencyTokenAmount);
        emit Deposited(_msgSender(), currencyTokenAmount);
    }

    // Admin Setter Functions

    /**
     * @notice Set the URI for the YieldDistributionToken metadata
     * @dev Only the owner can call this setter
     * @param tokenURI New token URI
     */
    function setTokenURI(
        string memory tokenURI
    ) external onlyRole(ADMIN_ROLE) {
        _getYieldDistributionTokenStorage().tokenURI = tokenURI;
    }

    // Getter View Functions

    /// @notice CurrencyToken in which the yield is deposited and denominated
    function getCurrencyToken() external view returns (IERC20) {
        return _getYieldDistributionTokenStorage().currencyToken;
    }

    /// @notice URI for the YieldDistributionToken metadata
    function getTokenURI() external view returns (string memory) {
        return _getYieldDistributionTokenStorage().tokenURI;
    }

    /// @notice State of a holder of the YieldDistributionToken
    function getUserState(
        address account
    ) external view returns (uint256 lastUpdate) {
        return _getYieldDistributionTokenStorage().lastUpdate[account];
    }

    // Permissionless Functions

    //TODO: why are we returning currencyToken?
    /**
     * @notice Claim all the remaining yield that has been accrued to a user
     * @dev Anyone can call this function to claim yield for any user
     * @param user Address of the user to claim yield for
     * @return currencyToken CurrencyToken in which the yield is deposited and denominated
     * @return currencyTokenAmount Amount of CurrencyToken claimed as yield
     */
    function claimYield(
        address user
    ) public returns (IERC20 currencyToken, uint256 currencyTokenAmount) {
        YieldDistributionTokenStorage storage $ = _getYieldDistributionTokenStorage();
        currencyToken = $.currencyToken;

        accrueYield(user);

        currencyTokenAmount = $.rewards[user];

        if (currencyTokenAmount > 0) {
            // Reset rewards before transfer to prevent reentrancy
            $.rewards[user] = 0;
            currencyToken.safeTransfer(user, currencyTokenAmount);
            emit YieldClaimed(user, currencyTokenAmount);
        }
    }

    function pendingYield(
        address user
    ) external view returns (uint256) {
        YieldDistributionTokenStorage storage $ = _getYieldDistributionTokenStorage();

        uint256 userAmountSeconds = balanceOf(user) * (block.timestamp - $.lastUpdate[user]);
        uint256 pendingDelta = userAmountSeconds.mulDiv($.yieldPerTokenStored - $.userYieldPerTokenPaid[user], SCALE);

        return $.rewards[user] + pendingDelta;
    }

    /**
     * @notice Accrue yield to a user, which can later be claimed
     * @dev Anyone can call this function to accrue yield to any user.
     *   The function does not do anything if it is called in the same block that a deposit is made.
     *   This function accrues all the yield up until the most recent deposit and updates the user state.
     * @param user Address of the user to accrue yield to
     */
    function accrueYield(
        address user
    ) public {
        YieldDistributionTokenStorage storage $ = _getYieldDistributionTokenStorage();

        _updateGlobalAmountSeconds();
        _updateUserYield(user);
    }

    function _updateUserYield(
        address user
    ) internal {
        YieldDistributionTokenStorage storage $ = _getYieldDistributionTokenStorage();

        uint256 userAmountSeconds = balanceOf(user) * (block.timestamp - $.lastUpdate[user]);
        if (userAmountSeconds > 0) {
            uint256 yieldDelta = userAmountSeconds.mulDiv($.yieldPerTokenStored - $.userYieldPerTokenPaid[user], SCALE);
            $.rewards[user] += yieldDelta;
            // Emit event with the delta amount instead of total rewards
            emit YieldAccrued(user, yieldDelta);
        }

        $.userYieldPerTokenPaid[user] = $.yieldPerTokenStored;
        $.lastUpdate[user] = block.timestamp;
    }

}
