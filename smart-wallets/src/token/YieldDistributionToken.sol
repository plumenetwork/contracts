// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IYieldDistributionToken } from "../interfaces/IYieldDistributionToken.sol";

/**
 * @title YieldDistributionToken
 * @author Eugene Y. Q. Shen
 * @notice ERC20 token that receives yield deposits and distributes yield
 *   to token holders proportionally based on how long they have held the token
 */
abstract contract YieldDistributionToken is ERC20, Ownable, IYieldDistributionToken {

    // Types

    /**
     * @notice State of a holder of the YieldDistributionToken
     * @param amount Amount of YieldDistributionTokens currently held by the user
     * @param amountSeconds Cumulative sum of the amount of YieldDistributionTokens held by
     *   the user, multiplied by the number of seconds that the user has had each balance for
     * @param yieldAccrued Total amount of yield that has ever been accrued to the user
     * @param yieldWithdrawn Total amount of yield that has ever been withdrawn by the user
     * @param lastBalanceTimestamp Timestamp of the most recent balance update for the user
     * @param lastDepositAmountSeconds AmountSeconds of the user at the time of the
     *   most recent deposit that was successfully processed by calling accrueYield
     */
    struct UserState {
        uint256 amount;
        uint256 amountSeconds;
        uint256 yieldAccrued;
        uint256 yieldWithdrawn;
        uint256 lastBalanceTimestamp;
        uint256 lastDepositAmountSeconds;
    }

    /**
     * @notice Amount of yield deposited into the YieldDistributionToken at one point in time
     * @param currencyTokenAmount Amount of CurrencyToken deposited as yield
     * @param totalAmountSeconds Sum of amountSeconds for all users at that time
     * @param previousTimestamp Timestamp of the previous deposit
     */
    struct Deposit {
        uint256 currencyTokenAmount;
        uint256 totalAmountSeconds;
        uint256 previousTimestamp;
    }

    /**
     * @notice Linked list of deposits into the YieldDistributionToken
     * @dev Invariant: the YieldDistributionToken has at most one deposit at each timestamp
     *   i.e. depositHistory[timestamp].previousTimestamp < timestamp
     * @param lastTimestamp Timestamp of the most recent deposit
     * @param deposits Mapping of timestamps to deposits
     */
    struct DepositHistory {
        uint256 lastTimestamp;
        mapping(uint256 timestamp => Deposit deposit) deposits;
    }

    // Storage

    /// @custom:storage-location erc7201:plume.storage.YieldDistributionToken
    struct YieldDistributionTokenStorage {
        /// @dev CurrencyToken in which the yield is deposited and denominated
        IERC20 currencyToken;
        /// @dev Current sum of all amountSeconds for all users
        uint256 totalAmountSeconds;
        /// @dev Timestamp of the last change in totalSupply()
        uint256 lastSupplyTimestamp;
        // uint8 decimals and uint8 registeredDEXCount are packed together in the same slot.
        // We add a uint240 __gap to fill the rest of this slot, which allows for future upgrades without changing the
        // storage layout.
        /// @dev Number of decimals of the YieldDistributionToken
        uint8 decimals;
        /// @dev Counter for the number of registered DEXes
        uint8 registeredDEXCount;
        /// @dev Padding to fill the slot
        uint240 __gap;
        /// @dev Registered DEX addresses
        address[] registeredDEXes;
        /// @dev URI for the YieldDistributionToken metadata
        string tokenURI;
        /// @dev History of deposits into the YieldDistributionToken
        DepositHistory depositHistory;
        /// @dev State for each user
        mapping(address user => UserState userState) userStates;
        /// @dev Mapping to track registered DEX addresses
        mapping(address => bool) isDEX;
        /// @dev Mapping to track tokens in open orders for each user on each DEX
        mapping(address user => mapping(address dex => uint256 amount)) tokensInOpenOrders;
        /// @dev Mapping to track total tokens held on all DEXes for each user
        mapping(address user => uint256 totalTokensOnDEXs) tokensHeldOnDEXs;
        /// @dev Mapping to  store index of each DEX to avoid looping in unregisterDex
        mapping(address => uint256) dexIndex;
    }

    // keccak256(abi.encode(uint256(keccak256("plume.storage.YieldDistributionToken")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant YIELD_DISTRIBUTION_TOKEN_STORAGE_LOCATION =
        0x3d2d7d9da47f1055055838ecd982d8a93d7044b5f93759fc6e1ef3269bbc7000;

    function _getYieldDistributionTokenStorage() internal pure returns (YieldDistributionTokenStorage storage $) {
        assembly {
            $.slot := YIELD_DISTRIBUTION_TOKEN_STORAGE_LOCATION
        }
    }

    // Constants

    // Base that is used to divide all price inputs in order to represent e.g. 1.000001 as 1000001e12
    uint256 private constant _BASE = 1e18;

    // Events

    /**
     * @notice Emitted when yield is deposited into the YieldDistributionToken
     * @param user Address of the user who deposited the yield
     * @param timestamp Timestamp of the deposit
     * @param currencyTokenAmount Amount of CurrencyToken deposited as yield
     */
    event Deposited(address indexed user, uint256 timestamp, uint256 currencyTokenAmount);

    /**
     * @notice Emitted when yield is claimed by a user
     * @param user Address of the user who claimed the yield
     * @param currencyTokenAmount Amount of CurrencyToken claimed as yield
     */
    event YieldClaimed(address indexed user, uint256 currencyTokenAmount);

    /**
     * @notice Emitted when yield is accrued to a user
     * @param user Address of the user who accrued the yield
     * @param currencyTokenAmount Amount of CurrencyToken accrued as yield
     */
    event YieldAccrued(address indexed user, uint256 currencyTokenAmount);

    /**
     * @notice Emitted when yield is accrued to a user for DEX tokens
     * @param user Address of the user who accrued the yield
     * @param currencyTokenAmount Amount of CurrencyToken accrued as yield
     */
    event YieldAccruedForDEXTokens(address indexed user, uint256 currencyTokenAmount);

    /**
     * @notice Emitted when a DEX is registered
     * @param dex Address of the user who accrued the yield
     */
    event DEXRegistered(address indexed dex);

    /**
     * @notice Emitted when a DEX is unregistered
     * @param dex Address of the user who accrued the yield
     */
    event DEXUnregistered(address indexed dex);

    // Errors

    /**
     * @notice Indicates a failure because the transfer of CurrencyToken failed
     * @param user Address of the user who tried to transfer CurrencyToken
     * @param currencyTokenAmount Amount of CurrencyToken that failed to transfer
     */
    error TransferFailed(address user, uint256 currencyTokenAmount);

    /// @notice Error thrown when a non-registered DEX attempts to perform a DEX-specific operation
    error NotRegisteredDEX();

    /// @notice Error thrown when attempting to unregister more tokens than are currently in open orders for a user on a
    /// DEX
    error InsufficientTokensInOpenOrders();

    /// @notice Error thrown when attempting to register a DEX that is already registered
    error DEXAlreadyRegistered();

    /// @notice Error thrown when attempting to unregister a DEX that is not currently registered
    error DEXNotRegistered();

    // do we want to limit maximum Dexs?
    /// @notice Error thrown when attempting to register a new DEX when the maximum number of DEXes has already been
    /// reached
    //error MaximumDEXesReached();

    // Constructor

    /**
     * @notice Construct the YieldDistributionToken
     * @param owner Address of the owner of the YieldDistributionToken
     * @param name Name of the YieldDistributionToken
     * @param symbol Symbol of the YieldDistributionToken
     * @param currencyToken Token in which the yield is deposited and denominated
     * @param decimals_ Number of decimals of the YieldDistributionToken
     * @param tokenURI URI of the YieldDistributionToken metadata
     */
    constructor(
        address owner,
        string memory name,
        string memory symbol,
        IERC20 currencyToken,
        uint8 decimals_,
        string memory tokenURI
    ) ERC20(name, symbol) Ownable(owner) {
        YieldDistributionTokenStorage storage $ = _getYieldDistributionTokenStorage();
        $.currencyToken = currencyToken;
        $.decimals = decimals_;
        $.tokenURI = tokenURI;
        $.depositHistory.lastTimestamp = block.timestamp;
        _updateSupply();
    }

    // Virtual Functions

    /// @notice Request to receive yield from the given SmartWallet
    function requestYield(address from) external virtual override(IYieldDistributionToken);

    // Override Functions

    /// @notice Number of decimals of the YieldDistributionToken
    function decimals() public view override returns (uint8) {
        return _getYieldDistributionTokenStorage().decimals;
    }

    /**
     * @notice Update the balance of `from` and `to` after token transfer and accrue yield
     * @param from Address to transfer tokens from
     * @param to Address to transfer tokens to
     * @param value Amount of tokens to transfer
     */
    function _update(address from, address to, uint256 value) internal virtual override {
        YieldDistributionTokenStorage storage $ = _getYieldDistributionTokenStorage();
        uint256 timestamp = block.timestamp;
        super._update(from, to, value);

        _updateSupply();

        if (from != address(0)) {
            accrueYield(from);
            UserState memory fromState = $.userStates[from];
            fromState.amountSeconds += fromState.amount * (timestamp - fromState.lastBalanceTimestamp);
            fromState.amount = balanceOf(from);
            fromState.lastBalanceTimestamp = timestamp;
            $.userStates[from] = fromState;

            // Adjust balances if transferring to a DEX
            if ($.isDEX[to]) {
                _adjustUserDEXBalance(from, to, value, true);
            }
        }

        if (to != address(0)) {
            accrueYield(to);
            UserState memory toState = $.userStates[to];
            toState.amountSeconds += toState.amount * (timestamp - toState.lastBalanceTimestamp);
            toState.amount = balanceOf(to);
            toState.lastBalanceTimestamp = timestamp;
            $.userStates[to] = toState;

            // Adjust balances if transferring from a DEX
            if ($.isDEX[from]) {
                _adjustUserDEXBalance(to, from, value, false);
            }
        }
    }

    // Internal Functions

    /// @notice Update the totalAmountSeconds and lastSupplyTimestamp when supply or time changes
    function _updateSupply() internal {
        YieldDistributionTokenStorage storage $ = _getYieldDistributionTokenStorage();
        uint256 timestamp = block.timestamp;
        if (timestamp > $.lastSupplyTimestamp) {
            $.totalAmountSeconds += totalSupply() * (timestamp - $.lastSupplyTimestamp);
            $.lastSupplyTimestamp = timestamp;
        }
    }

    /**
     * @notice Deposit yield into the YieldDistributionToken
     * @dev The sender must have approved the CurrencyToken to spend the given amount
     * @param currencyTokenAmount Amount of CurrencyToken to deposit as yield
     */
    function _depositYield(uint256 currencyTokenAmount) internal {
        if (currencyTokenAmount == 0) {
            return;
        }

        YieldDistributionTokenStorage storage $ = _getYieldDistributionTokenStorage();
        uint256 lastTimestamp = $.depositHistory.lastTimestamp;
        uint256 timestamp = block.timestamp;

        _updateSupply();

        // If the deposit is in the same block as the last one, add to the previous deposit
        //  Otherwise, append a new deposit to the token deposit history
        Deposit memory deposit = $.depositHistory.deposits[timestamp];
        deposit.currencyTokenAmount += currencyTokenAmount;
        deposit.totalAmountSeconds = $.totalAmountSeconds;
        if (timestamp != lastTimestamp) {
            deposit.previousTimestamp = lastTimestamp;
            $.depositHistory.lastTimestamp = timestamp;
        }
        $.depositHistory.deposits[timestamp] = deposit;

        if (!$.currencyToken.transferFrom(msg.sender, address(this), currencyTokenAmount)) {
            revert TransferFailed(msg.sender, currencyTokenAmount);
        }
        emit Deposited(msg.sender, timestamp, currencyTokenAmount);
    }

    /**
     * @notice Adjusts the balance of tokens held on a DEX for a user
     * @dev This function is called when tokens are transferred to or from a DEX
     * @param user Address of the user whose balance is being adjusted
     * @param dex Address of the DEX where the tokens are held
     * @param amount Amount of tokens to adjust
     * @param increase Boolean indicating whether to increase (true) or decrease (false) the balance
     */
    function _adjustUserDEXBalance(address user, address dex, uint256 amount, bool increase) internal {
        YieldDistributionTokenStorage storage $ = _getYieldDistributionTokenStorage();
        if (increase) {
            $.tokensInOpenOrders[user][dex] += amount;
            $.tokensHeldOnDEXs[user] += amount;
        } else {
            $.tokensInOpenOrders[user][dex] -= amount;
            $.tokensHeldOnDEXs[user] -= amount;
        }
    }

    // Admin Setter Functions

    /**
     * @notice Set the URI for the YieldDistributionToken metadata
     * @dev Only the owner can call this setter
     * @param tokenURI New token URI
     */
    function setTokenURI(string memory tokenURI) external onlyOwner {
        _getYieldDistributionTokenStorage().tokenURI = tokenURI;
    }

    /**
     * @notice Register a DEX address
     * @dev Only the owner can call this function
     * @param dexAddress Address of the DEX to register
     */
    function registerDEX(address dexAddress) external onlyOwner {
        YieldDistributionTokenStorage storage $ = _getYieldDistributionTokenStorage();
        if ($.isDEX[dexAddress]) {
            revert DEXAlreadyRegistered();
        }

        // Should we limit registeredDexs?
        /*
        if ($.registeredDEXCount >= 10) {
            revert MaximumDEXesReached();
        }
        */

        $.isDEX[dexAddress] = true;
        $.dexIndex[dexAddress] = $.registeredDEXes.length;
        $.registeredDEXes.push(dexAddress);
        $.registeredDEXCount++;
        emit DEXRegistered(dexAddress);
    }

    /**
     * @notice Unregister a DEX address
     * @dev Only the owner can call this function
     * @param dexAddress Address of the DEX to unregister
     */
    function unregisterDEX(address dexAddress) external onlyOwner {
        YieldDistributionTokenStorage storage $ = _getYieldDistributionTokenStorage();
        if (!$.isDEX[dexAddress]) {
            revert DEXNotRegistered();
        }

        uint256 index = $.dexIndex[dexAddress];
        uint256 lastIndex = $.registeredDEXes.length - 1;

        if (index != lastIndex) {
            address lastDex = $.registeredDEXes[lastIndex];
            $.registeredDEXes[index] = lastDex;
            $.dexIndex[lastDex] = index;
        }

        $.registeredDEXes.pop();
        delete $.isDEX[dexAddress];
        delete $.dexIndex[dexAddress];
        $.registeredDEXCount--;

        emit DEXUnregistered(dexAddress);
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

    /**
     * @notice Checks if an address is a registered DEX
     * @param addr Address to check
     * @return bool True if the address is a registered DEX, false otherwise
     */
    function isDEXRegistered(address addr) external view returns (bool) {
        return _getYieldDistributionTokenStorage().isDEX[addr];
    }

    /**
     * @notice Gets the amount of tokens a user has in open orders on a specific DEX
     * @param user Address of the user
     * @param dex Address of the DEX
     * @return uint256 Amount of tokens in open orders
     */
    function tokensInOpenOrdersOnDEX(address user, address dex) public view returns (uint256) {
        return _getYieldDistributionTokenStorage().tokensInOpenOrders[user][dex];
    }

    /**
     * @notice Gets the total amount of tokens a user has held on all DEXes
     * @param user Address of the user
     * @return uint256 Total amount of tokens held on all DEXes
     */
    function totalTokensHeldOnDEXs(address user) public view returns (uint256) {
        return _getYieldDistributionTokenStorage().tokensHeldOnDEXs[user];
    }

    // Permissionless Functions

    /**
     * @notice Claim all the remaining yield that has been accrued to a user
     * @dev Anyone can call this function to claim yield for any user
     * @param user Address of the user to claim yield for
     * @return currencyToken CurrencyToken in which the yield is deposited and denominated
     * @return currencyTokenAmount Amount of CurrencyToken claimed as yield
     */
    function claimYield(address user) public returns (IERC20 currencyToken, uint256 currencyTokenAmount) {
        YieldDistributionTokenStorage storage $ = _getYieldDistributionTokenStorage();
        currencyToken = $.currencyToken;

        accrueYield(user);

        UserState storage userState = $.userStates[user];
        uint256 amountAccrued = userState.yieldAccrued;
        currencyTokenAmount = amountAccrued - userState.yieldWithdrawn;
        if (currencyTokenAmount != 0) {
            userState.yieldWithdrawn = amountAccrued;
            if (!currencyToken.transfer(user, currencyTokenAmount)) {
                revert TransferFailed(user, currencyTokenAmount);
            }
            emit YieldClaimed(user, currencyTokenAmount);
        }
    }

    /**
     * @notice Accrue yield to a user, which can later be claimed
     * @dev Anyone can call this function to accrue yield to any user.
     *   The function does not do anything if it is called in the same block that a deposit is made.
     *   This function accrues all the yield up until the most recent deposit and updates the user state.
     * @param user Address of the user to accrue yield to
     */
    function accrueYield(address user) public {
        YieldDistributionTokenStorage storage $ = _getYieldDistributionTokenStorage();
        DepositHistory storage depositHistory = $.depositHistory;
        UserState memory userState = $.userStates[user];
        uint256 depositTimestamp = depositHistory.lastTimestamp;
        uint256 lastBalanceTimestamp = userState.lastBalanceTimestamp;

        // Check if the user has any tokens on DEXs
        uint256 tokensOnDEXs = $.tokensHeldOnDEXs[user];
        uint256 totalUserTokens = userState.amount + tokensOnDEXs;


        /**
         * There is a race condition in the current implementation that occurs when
         * we deposit yield, then accrue yield for some users, then deposit more yield
         * in the same block. The users whose yield was accrued in this block would
         * not receive the yield from the second deposit. Therefore, we do not accrue
         * anything when the deposit timestamp is the same as the current block timestamp.
         * Users can call `accrueYield` again on the next block.
         */
        if (
            depositTimestamp == block.timestamp
            // If the user has never had any balances, then there is no yield to accrue
            || lastBalanceTimestamp == 0
            // If this deposit is before the user's last balance update, then they already accrued yield
            || depositTimestamp < lastBalanceTimestamp
        ) {
            return;
        }

        // Iterate through depositHistory and accrue yield for the user at each deposit timestamp
        Deposit storage deposit = depositHistory.deposits[depositTimestamp];
        uint256 yieldAccrued = 0;
        uint256 amountSeconds = userState.amountSeconds;
        uint256 depositAmount = deposit.currencyTokenAmount;
        while (depositAmount > 0 && depositTimestamp > lastBalanceTimestamp) {
            uint256 previousDepositTimestamp = deposit.previousTimestamp;
            uint256 intervalTotalAmountSeconds =
                deposit.totalAmountSeconds - depositHistory.deposits[previousDepositTimestamp].totalAmountSeconds;
            if (previousDepositTimestamp > lastBalanceTimestamp) {
                /**
                 * There can be a sequence of deposits made while the user balance remains the same throughout.
                 * Subtract the amountSeconds in this interval to get the total amountSeconds at the previous deposit.
                 */
                uint256 intervalAmountSeconds = totalUserTokens * (depositTimestamp - previousDepositTimestamp);
                amountSeconds -= intervalAmountSeconds;
                yieldAccrued += _BASE * depositAmount * intervalAmountSeconds / intervalTotalAmountSeconds;
            } else {
                /**
                 * At the very end, there can be a sequence of balance updates made right after
                 * the most recent previously processed deposit and before any other deposits.
                 */
                yieldAccrued += _BASE * depositAmount * (amountSeconds - userState.lastDepositAmountSeconds)
                    / intervalTotalAmountSeconds;
            }
            depositTimestamp = previousDepositTimestamp;
            deposit = depositHistory.deposits[depositTimestamp];
            depositAmount = deposit.currencyTokenAmount;
        }

        userState.lastDepositAmountSeconds = userState.amountSeconds;
        userState.amountSeconds += totalUserTokens * (depositHistory.lastTimestamp - lastBalanceTimestamp);
        userState.lastBalanceTimestamp = depositHistory.lastTimestamp;

        uint256 newYield = yieldAccrued / _BASE;



        if (totalUserTokens > 0) {
            // Calculate total yield for the user, including tokens on DEXs
            userState.yieldAccrued += newYield;
            $.userStates[user] = userState;

            // Emit an event for the total yield accrued
            emit YieldAccrued(user, newYield);

            // If user has tokens on DEXs, emit an additional event to track this
            if (tokensOnDEXs > 0) {
                uint256 yieldForDEXTokens = (newYield * tokensOnDEXs) / totalUserTokens;
                emit YieldAccrued(user, yieldForDEXTokens);
            }
        }
    }

    /**
     * @notice Registers an open order for a user on a DEX
     * @dev Can only be called by a registered DEX
     * @param user Address of the user placing the order
     * @param amount Amount of tokens in the order
     */
    function registerOpenOrder(address user, uint256 amount) external {
        YieldDistributionTokenStorage storage $ = _getYieldDistributionTokenStorage();
        if (!$.isDEX[msg.sender]) {
            revert NotRegisteredDEX();
        }
        _adjustUserDEXBalance(user, msg.sender, amount, true);
    }

    /**
     * @notice Unregisters an open order for a user on a DEX
     * @dev Can only be called by a registered DEX
     * @param user Address of the user whose order is being unregistered
     * @param amount Amount of tokens to unregister
     */
    function unregisterOpenOrder(address user, uint256 amount) external {
        YieldDistributionTokenStorage storage $ = _getYieldDistributionTokenStorage();
        if (!$.isDEX[msg.sender]) {
            revert NotRegisteredDEX();
        }
        if ($.tokensInOpenOrders[user][msg.sender] < amount) {
            revert InsufficientTokensInOpenOrders();
        }
        _adjustUserDEXBalance(user, msg.sender, amount, false);
    }

}
