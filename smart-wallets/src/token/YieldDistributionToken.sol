// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IYieldDistributionToken } from "../interfaces/IYieldDistributionToken.sol";

/**
 * @title YieldDistributionToken
 * @author Eugene Y. Q. Shen
 * @notice ERC20 token that represents TODO
 */
abstract contract YieldDistributionToken is ERC20, IYieldDistributionToken {

    // Types

    /**
     * @notice Balance of one user at one point in time
     * @param amount Amount of tokens held by the user at that time
     * @param previousTimestamp Timestamp of the previous balance for that user
     */
    struct Balance {
        uint256 amount;
        uint256 previousTimestamp;
    }

    /**
     * @notice Linked list of balances for one user
     * @dev Invariant: the user has at most one balance at each timestamp,
     *   i.e. balanceHistory[timestamp].previousTimestamp < timestamp.
     *   Invariant: there is at most one balance whose timestamp is older or equal
     *   to than the most recent deposit whose yield was accrued to each user.
     * @param lastTimestamp Timestamp of the last balance for that user
     * @param balances Mapping of timestamps to balances
     */
    struct BalanceHistory {
        uint256 lastTimestamp;
        mapping(uint256 timestamp => Balance balance) balances;
    }

    /**
     * @notice Amount of yield deposited into the YieldDistributionToken at one point in time
     * @param currencyTokenAmount Amount of CurrencyToken deposited as yield
     * @param totalSupply Total supply of the YieldDistributionToken at that time
     * @param previousTimestamp Timestamp of the previous deposit
     */
    struct Deposit {
        uint256 currencyTokenAmount;
        uint256 totalSupply;
        uint256 previousTimestamp;
    }

    /**
     * @notice Linked list of deposits into the YieldDistributionToken
     * @dev Invariant: the YieldDistributionToken has at most one deposit at each timestamp
     *   i.e. depositHistory[timestamp].previousTimestamp < timestamp
     * @param lastTimestamp Timestamp of the last deposit
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
        /// @dev Number of decimals of the YieldDistributionToken
        uint8 decimals;
        /// @dev URI for the YieldDistributionToken metadata
        string tokenURI;
        /// @dev History of deposits into the YieldDistributionToken
        DepositHistory depositHistory;
        /// @dev History of balances for each user
        mapping(address user => BalanceHistory balanceHistory) balanceHistory;
        /// @dev Total amount of yield that has ever been accrued by each user
        mapping(address user => uint256 currencyTokenAmount) yieldAccrued;
        /// @dev Total amount of yield that has ever been withdrawn by each user
        mapping(address user => uint256 currencyTokenAmount) yieldWithdrawn;
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

    // Errors

    /**
     * @notice Indicates a failure because the given timestamp is in the future
     * @param timestamp Timestamp that was in the future
     * @param currentTimestamp Current block.timestamp
     */
    error InvalidTimestamp(uint256 timestamp, uint256 currentTimestamp);

    /// @notice Indicates a failure because the given amount is 0
    error ZeroAmount();

    /**
     * @notice Indicates a failure because the given deposit timestamp is less than the last one
     * @param timestamp Deposit timestamp that was too old
     * @param lastTimestamp Last deposit timestamp
     */
    error InvalidDepositTimestamp(uint256 timestamp, uint256 lastTimestamp);

    /**
     * @notice Indicates a failure because the transfer of CurrencyToken failed
     * @param user Address of the user who tried to transfer CurrencyToken
     * @param currencyTokenAmount Amount of CurrencyToken that failed to transfer
     */
    error TransferFailed(address user, uint256 currencyTokenAmount);

    // Constructor

    /**
     * @notice Construct the YieldDistributionToken
     * @param name Name of the YieldDistributionToken
     * @param symbol Symbol of the YieldDistributionToken
     * @param currencyToken Token in which the yield is deposited and denominated
     * @param decimals_ Number of decimals of the YieldDistributionToken
     * @param tokenURI URI of the YieldDistributionToken metadata
     */
    constructor(string memory name, string memory symbol, ERC20 currencyToken, uint8 decimals_, string memory tokenURI) ERC20(name, symbol) {
        YieldDistributionTokenStorage storage $ = _getYieldDistributionTokenStorage();
        $.currencyToken = currencyToken;
        $.decimals = decimals_;
        $.tokenURI = tokenURI;
        $.depositHistory.lastTimestamp = block.timestamp;
    }

    // Override Functions

    /// @notice Number of decimals of the YieldDistributionToken
    function decimals() public view override returns (uint8) {
        return _getYieldDistributionTokenStorage().decimals;
    }

    /**
     * @notice Update the balance of `from` and `to` after token transfer and accrue yield
     * @dev Invariant: the user has at most one balance at each timestamp
     * @param from Address to transfer tokens from
     * @param to Address to transfer tokens to
     * @param value Amount of tokens to transfer
     */
    function _update(address from, address to, uint256 value) internal virtual override {
        YieldDistributionTokenStorage storage $ = _getYieldDistributionTokenStorage();
        uint256 timestamp = block.timestamp;
        super._update(from, to, value);

        // If the token is not being minted, then accrue yield to the sender
        //   and append a new balance to the sender balance history
        if (from != address(0)) {
            accrueYield(from);

            BalanceHistory storage fromBalanceHistory = $.balanceHistory[from];
            uint256 balance = balanceOf(from);
            uint256 lastTimestamp = fromBalanceHistory.lastTimestamp;

            if (timestamp == lastTimestamp) {
                fromBalanceHistory.balances[timestamp].amount = balance;
            } else {
                fromBalanceHistory.balances[timestamp] = Balance(balance, lastTimestamp);
                fromBalanceHistory.lastTimestamp = timestamp;
            }
        }

        // If the token is not being burned, then accrue yield to the receiver
        //   and append a new balance to the receiver balance history
        if (to != address(0)) {
            accrueYield(to);

            BalanceHistory storage toBalanceHistory = $.balanceHistory[to];
            uint256 balance = balanceOf(to);
            uint256 lastTimestamp = toBalanceHistory.lastTimestamp;

            if (timestamp == lastTimestamp) {
                toBalanceHistory.balances[timestamp].amount = balance;
            } else {
                toBalanceHistory.balances[timestamp] = Balance(balance, lastTimestamp);
                toBalanceHistory.lastTimestamp = timestamp;
            }
        }
    }

    // Admin Setter Functions

    /**
     * @notice Set the URI for the YieldDistributionToken metadata
     * @dev Only the owner can call this setter
     * @param tokenURI New token URI
     */
    function setTokenURI(string memory tokenURI) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _getYieldDistributionTokenStorage().tokenURI = tokenURI;
    }

    // Getter View Functions

    /// @notice CurrencyToken in which the yield is deposited and denominated
    function getCurrencyToken() public view returns (IERC20) {
        return _getYieldDistributionTokenStorage().currencyToken;
    }

    /// @notice URI for the YieldDistributionToken metadata
    function getTokenURI() public view returns (string memory) {
        return _getYieldDistributionTokenStorage().tokenURI;
    }

    // Internal Functions

    /**
     * @notice Deposit yield into the YieldDistributionToken
     * @dev The sender must have approved the CurrencyToken to spend the given amount
     * @param timestamp Timestamp of the deposit, must not be less than the previous deposit timestamp
     * @param currencyTokenAmount Amount of CurrencyToken to deposit as yield
     */
    function _depositYield(uint256 timestamp, uint256 currencyTokenAmount) internal {
        if (timestamp > block.timestamp) {
            revert InvalidTimestamp(timestamp, block.timestamp);
        }
        if (currencyTokenAmount == 0) {
            revert ZeroAmount();
        }

        YieldDistributionTokenStorage storage $ = _getYieldDistributionTokenStorage();
        uint256 lastTimestamp = $.depositHistory.lastTimestamp;

        if (timestamp < lastTimestamp) {
            revert InvalidDepositTimestamp(timestamp, lastTimestamp);
        }

        // If the deposit is in the same block as the last one, add to the previous deposit
        //  Otherwise, append a new deposit to the token deposit history
        if (timestamp == lastTimestamp) {
            $.depositHistory.deposits[timestamp].currencyTokenAmount += currencyTokenAmount;
        } else {
            $.depositHistory[timestamp] = Deposit(currencyTokenAmount, totalSupply(), lastTimestamp);
            $.depositHistory.lastTimestamp = timestamp;
        }

        if (!$.currencyToken.transferFrom(msg.sender, address(this), currencyTokenAmount)) {
            revert TransferFailed(msg.sender, currencyTokenAmount);
        }
        emit Deposited(msg.sender, timestamp, currencyTokenAmount);
    }

    // Permissionless Functions

    /**
     * @notice Claim all the remaining yield that has been accrued to a user
     * @dev Anyone can call this function to claim yield for any user
     * @param user Address of the user to claim yield for
     * @return currencyToken CurrencyToken in which the yield is deposited and denominated
     * @return currencyTokenAmount Amount of CurrencyToken claimed as yield
     */
    function claimYield(address user) public returns (ERC20 currencyToken, uint256 currencyTokenAmount) {
        YieldDistributionTokenStorage storage $ = _getYieldDistributionTokenStorage();
        currencyToken = $.currencyToken;

        accrueYield(user);

        uint256 amountAccrued = $.yieldAccrued[user];
        currencyTokenAmount = amountAccrued - $.yieldWithdrawn[user];
        if (currencyTokenAmount != 0) {
            $.yieldWithdrawn[user] = amountAccrued;
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
     *   This function accrues all the yield up until the most recent deposit and creates
     *   a new balance at that deposit timestamp. All balances before that are then deleted.
     * @param user Address of the user to accrue yield to
     */
    function accrueYield(address user) public {
        YieldDistributionTokenStorage storage $ = _getYieldDistributionTokenStorage();
        DepositHistory storage depositHistory = $.depositHistory;
        BalanceHistory storage balanceHistory = $.balanceHistory[user];
        uint256 depositTimestamp = depositHistory.lastTimestamp;
        uint256 balanceTimestamp = balanceHistory.lastTimestamp;

        /**
         * There is a race condition in the current implementation that occurs when
         * we deposit yield, then accrue yield for some users, then deposit more yield
         * in the same block. The users whose yield was accrued in this block would
         * not receive the yield from the second deposit. Therefore, we do not accrue
         * anything when the deposit timestamp is the same as the current block timestamp.
         * Users can call `accrueYield` again on the next block.
         */
        if (depositTimestamp == block.timestamp) {
            return;
        }

        // If the user has never had any balances, then there is no yield to accrue
        if (balanceTimestamp == 0) {
            return;
        }

        Deposit storage deposit = depositHistory.deposits[depositTimestamp];
        Balance storage balance = balanceHistory.balances[balanceTimestamp];
        uint256 previousBalanceTimestamp = balance.previousBalanceTimestamp;
        Balance storage previousBalance = balanceHistory.balances[previousBalanceTimestamp];

        // Iterate through the balanceHistory list until depositTimestamp >= previousBalanceTimestamp
        while (depositTimestamp < previousBalanceTimestamp) {
            balanceTimestamp = previousBalanceTimestamp;
            balance = previousBalance;
            previousBalanceTimestamp = balance.previousBalanceTimestamp;
            previousBalance = balanceHistory.balances[previousBalanceTimestamp];
        }

        /**
         * At this point, either:
         *   (a) depositTimestamp >= balanceTimestamp > previousBalanceTimestamp
         *   (b) balanceTimestamp > depositTimestamp >= previousBalanceTimestamp
         * Create a new balance at the moment of depositTimestamp, whose amount is
         *   either case (a) balance.amount or case (b) previousBalance.amount.
         *   Then ignore the most recent balance in case (b) because it is in the future.
         */
        uint256 preserveBalanceTimestamp;
        if (balanceTimestamp < depositTimestamp) {
            balanceHistory.lastTimestamp = depositTimestamp;
            balanceHistory.balances[depositTimestamp].amount = balance.amount;
            delete balanceHistory.balances[depositTimestamp].previousBalanceTimestamp;
        } else if (balanceTimestamp > depositTimestamp) {
            if (previousBalanceTimestamp != 0) {
                balance.previousTimestamp = depositTimestamp;
                balanceHistory.balances[depositTimestamp].amount = previousBalance.amount;
                delete balanceHistory.balances[depositTimestamp].previousBalanceTimestamp;
            }
            balance = previousBalance;
            balanceTimestamp = previousBalanceTimestamp;
        } else {
            // Do not delete this balance if its timestamp is the same as the deposit timestamp
            preserveBalanceTimestamp = balanceTimestamp;
        }

        /**
         * At this point: depositTimestamp >= balanceTimestamp
         * We will keep this as an invariant throughout the rest of the function.
         * Double while loop: in the outer while loop, we iterate through the depositHistory list and
         *   calculate the yield to be accrued to the user based on their balance at that time.
         *   This outer loop ends after we go through all deposits or all of the user's balance history.
         */
        uint256 yieldAccrued = 0;
        uint256 depositAmount = deposit.amount;
        while (depositAmount > 0 && balanceTimestamp > 0) {
            uint256 previousDepositTimestamp = deposit.previousDepositTimestamp;
            uint256 timeBetweenDeposits = depositTimestamp - previousDepositTimestamp;

            /**
             * If the balance of the user remained unchanged between both deposits,
             *   then we can easily calculate the yield proportional to the balance.
             */
            if (previousDepositTimestamp >= balanceTimestamp) {
                yieldAccrued += _BASE * depositAmount * balance.amount / deposit.totalSupply;
            } else {
                /**
                 * If the balance of the user changed between the deposits, then we need to iterate through
                 *   the balanceHistory list and calculate the prorated yield that accrued to the user.
                 *   The prorated yield is the proportion of tokens the user holds (balance.amount /
                 * deposit.totalSupply)
                 *   multiplied by the time interval ((nextBalanceTimestamp - balanceTimestamp) / timeBetweenDeposits).
                 */
                uint256 nextBalanceTimestamp = depositTimestamp;
                while (balanceTimestamp >= previousDepositTimestamp) {
                    yieldAccrued += _BASE * depositAmount * balance.amount * (nextBalanceTimestamp - balanceTimestamp)
                        / deposit.totalSupply / timeBetweenDeposits;

                    nextBalanceTimestamp = balanceTimestamp;
                    balanceTimestamp = balance.previousBalanceTimestamp;
                    balance = balanceHistory.balances[balanceTimestamp];

                    /**
                     * Delete the old balance since it has already been processed by some deposit,
                     *   unless the timestamp is the same as the deposit timestamp, in which case
                     *   we need to preserve the balance for the next iteration.
                     */
                    if (nextBalanceTimestamp != preserveBalanceTimestamp) {
                        delete balanceHistory.balances[nextBalanceTimestamp].amount;
                        delete balanceHistory.balances[nextBalanceTimestamp].previousBalanceTimestamp;
                    }
                }

                /**
                 * At this point: nextBalanceTimestamp >= previousDepositTimestamp > balanceTimestamp
                 * Accrue yield from previousDepositTimestamp up until nextBalanceTimestamp
                 */
                yieldAccrued += _BASE * depositAmount * balance.amount
                    * (nextBalanceTimestamp - previousDepositTimestamp) / deposit.totalSupply / timeBetweenDeposits;
            }

            depositTimestamp = previousDepositTimestamp;
            deposit = depositHistory.deposits[depositTimestamp];
            depositAmount = deposit.amount;
        }

        $.yieldAccrued[user] += yieldAccrued / _BASE;
        emit YieldAccrued(user, yieldAccrued / _BASE);
    }
}
