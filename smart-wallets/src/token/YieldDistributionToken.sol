// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IYieldDistributionToken } from "../interfaces/IYieldDistributionToken.sol";

/**
 * @title YieldDistributionToken
 * @author ...
 * @notice ERC20 token that receives yield deposits and distributes yield
 *   to token holders proportionally based on how long they have held the token
 */
abstract contract YieldDistributionToken is ERC20, Ownable, IYieldDistributionToken {

    // Types

    /**
     * @notice Balance of one user at one point in time
     * @param amount Amount of YieldDistributionTokens held by the user at that time
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
        mapping(uint256 => Balance) balances;
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
        mapping(uint256 => Deposit) deposits;
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
        mapping(address => BalanceHistory) balanceHistory;
        /// @dev Total amount of yield that has ever been accrued by each user
        mapping(address => uint256) yieldAccrued;
        /// @dev Total amount of yield that has ever been withdrawn by each user
        mapping(address => uint256) yieldWithdrawn;
        /// @dev Mapping of DEX addresses
        mapping(address => bool) isDEX;
        /// @dev Mapping of DEX addresses to maker addresses for pending orders
        mapping(address => mapping(address => address)) dexToMakerAddress;
        /// @dev Tokens held on DEXs on behalf of each maker
        mapping(address => uint256) tokensHeldOnDEXs;
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

    // remove this, for debug purposes
    event Debug(string message, uint256 value);


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
     * @dev Invariant: the user has at most one balance at each timestamp
     * @param from Address to transfer tokens from
     * @param to Address to transfer tokens to
     * @param value Amount of tokens to transfer
     */
    function _update(address from, address to, uint256 value) internal virtual override {
        YieldDistributionTokenStorage storage $ = _getYieldDistributionTokenStorage();

        // Accrue yield before the transfer
        if (from != address(0)) {
            accrueYield(from);
        }
        if (to != address(0)) {
            accrueYield(to);
        }

        // Adjust balances if transferring to a DEX
        if (from != address(0) && $.isDEX[to]) {
            // Register the maker
            $.dexToMakerAddress[to][address(this)] = from;

            // Adjust maker's tokensHeldOnDEXs balance
            _adjustMakerBalance(from, value, true);
        }

        // Adjust balances if transferring from a DEX
        if ($.isDEX[from]) {
            // Get the maker
            address maker = $.dexToMakerAddress[from][address(this)];

            // Adjust maker's tokensHeldOnDEXs balance
            _adjustMakerBalance(maker, value, false);
        }

        // Perform the transfer
        super._update(from, to, value);

        // Update balance histories
        if (from != address(0)) {
            _updateBalanceHistory(from);
        }
        if (to != address(0)) {
            _updateBalanceHistory(to);
        }
    }

    function _adjustMakerBalance(address maker, uint256 amount, bool increase) internal {
        YieldDistributionTokenStorage storage $ = _getYieldDistributionTokenStorage();

        // Accrue yield for the maker before adjusting balance
        accrueYield(maker);

        if (increase) {
            $.tokensHeldOnDEXs[maker] += amount;
        } else {
            require($.tokensHeldOnDEXs[maker] >= amount, "Insufficient tokens held on DEXs");
            $.tokensHeldOnDEXs[maker] -= amount;
        }

        // Update the maker's balance history
        _updateBalanceHistory(maker);
    }

    // Helper function to update balance history
    function _updateBalanceHistory(address user) private {
        YieldDistributionTokenStorage storage $ = _getYieldDistributionTokenStorage();
        BalanceHistory storage balanceHistory = $.balanceHistory[user];
        uint256 balance = balanceOf(user);

        // Include tokens held on DEXs if the user is a maker
        uint256 tokensOnDEXs = $.tokensHeldOnDEXs[user];
        balance += tokensOnDEXs;

        uint256 timestamp = block.timestamp;
        uint256 lastTimestamp = balanceHistory.lastTimestamp;

        if (timestamp == lastTimestamp) {
            balanceHistory.balances[timestamp].amount = balance;
        } else {
            balanceHistory.balances[timestamp] = Balance(balance, lastTimestamp);
            balanceHistory.lastTimestamp = timestamp;
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

    // Getter View Functions

    /// @notice CurrencyToken in which the yield is deposited and denominated
    function getCurrencyToken() external view returns (IERC20) {
        return _getYieldDistributionTokenStorage().currencyToken;
    }

    /// @notice URI for the YieldDistributionToken metadata
    function getTokenURI() external view returns (string memory) {
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

    uint256 totalSupply_ = totalSupply();
    if (totalSupply_ == 0) {
        revert("Cannot deposit yield when total supply is zero");
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
            $.depositHistory.deposits[timestamp] = Deposit(currencyTokenAmount, totalSupply(), lastTimestamp);
            $.depositHistory.lastTimestamp = timestamp;
        }

        if (!$.currencyToken.transferFrom(msg.sender, address(this), currencyTokenAmount)) {
            revert TransferFailed(msg.sender, currencyTokenAmount);
        }
        emit Deposited(msg.sender, timestamp, currencyTokenAmount);
    }

    // Functions to manage DEXs and maker orders

    /**
     * @notice Register a DEX address
     * @dev Only the owner can call this function
     * @param dexAddress Address of the DEX to register
     */
    function registerDEX(address dexAddress) external onlyOwner {
        YieldDistributionTokenStorage storage $ = _getYieldDistributionTokenStorage();
        $.isDEX[dexAddress] = true;
    }

    /**
     * @notice Unregister a DEX address
     * @dev Only the owner can call this function
     * @param dexAddress Address of the DEX to unregister
     */
    function unregisterDEX(address dexAddress) external onlyOwner {
        YieldDistributionTokenStorage storage $ = _getYieldDistributionTokenStorage();
        $.isDEX[dexAddress] = false;
    }

    /**
     * @notice Register a maker's pending order on a DEX
     * @dev Only registered DEXs can call this function
     * @param maker Address of the maker
     * @param amount Amount of tokens in the order
     */
    function registerMakerOrder(address maker, uint256 amount) external {
        YieldDistributionTokenStorage storage $ = _getYieldDistributionTokenStorage();
        require($.isDEX[msg.sender], "Caller is not a registered DEX");
        $.dexToMakerAddress[msg.sender][address(this)] = maker;
        _transfer(maker, msg.sender, amount);
    }

    /**
     * @notice Unregister a maker's completed or cancelled order on a DEX
     * @dev Only registered DEXs can call this function
     * @param maker Address of the maker
     * @param amount Amount of tokens to return (if any)
     */
function unregisterMakerOrder(address maker, uint256 amount) external {
    YieldDistributionTokenStorage storage $ = _getYieldDistributionTokenStorage();
    require($.isDEX[msg.sender], "Caller is not a registered DEX");
    if (amount > 0) {
        _transfer(msg.sender, maker, amount);
    }
    $.dexToMakerAddress[msg.sender][address(this)] = address(0);
}

    function isDexAddressWhitelisted(address addr) public view returns (bool) {
        YieldDistributionTokenStorage storage $ = _getYieldDistributionTokenStorage();
        return $.isDEX[addr];
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

        if (depositTimestamp == block.timestamp) {
            return;
        }

        if (balanceTimestamp == 0) {
            return;
        }

        Deposit storage deposit = depositHistory.deposits[depositTimestamp];
        Balance storage balance = balanceHistory.balances[balanceTimestamp];
        uint256 previousBalanceTimestamp = balance.previousTimestamp;
        Balance storage previousBalance = balanceHistory.balances[previousBalanceTimestamp];

        while (depositTimestamp < previousBalanceTimestamp) {
            balanceTimestamp = previousBalanceTimestamp;
            balance = previousBalance;
            previousBalanceTimestamp = balance.previousTimestamp;
            previousBalance = balanceHistory.balances[previousBalanceTimestamp];
        }

        uint256 preserveBalanceTimestamp;
        if (balanceTimestamp < depositTimestamp) {
            balanceHistory.lastTimestamp = depositTimestamp;
            balanceHistory.balances[depositTimestamp].amount = balance.amount;
            delete balanceHistory.balances[depositTimestamp].previousTimestamp;
        } else if (balanceTimestamp > depositTimestamp) {
            if (previousBalanceTimestamp != 0) {
                balance.previousTimestamp = depositTimestamp;
                balanceHistory.balances[depositTimestamp].amount = previousBalance.amount;
                delete balanceHistory.balances[depositTimestamp].previousTimestamp;
            }
            balance = previousBalance;
            balanceTimestamp = previousBalanceTimestamp;
        } else {
            preserveBalanceTimestamp = balanceTimestamp;
        }

        uint256 yieldAccrued = 0;
        uint256 depositAmount = deposit.currencyTokenAmount;
        while (depositAmount > 0 && balanceTimestamp > 0) {
            uint256 previousDepositTimestamp = deposit.previousTimestamp;
            uint256 timeBetweenDeposits = depositTimestamp - previousDepositTimestamp;

            // Log deposit totalSupply and timeBetweenDeposits
            emit Debug("deposit.totalSupply", deposit.totalSupply);
            emit Debug("timeBetweenDeposits", timeBetweenDeposits);

            if (previousDepositTimestamp >= balanceTimestamp) {
                            // Log balance.amount
            emit Debug("balance.amount", balance.amount);
            // Check for division by zero
            if (deposit.totalSupply == 0) {
                emit Debug("Division by zero error: deposit.totalSupply is zero", deposit.totalSupply);
            }
            yieldAccrued += _BASE * depositAmount * balance.amount / deposit.totalSupply;

            } else {
                            // Log balance.amount and time intervals
    
            // Check for division by zero
            if (deposit.totalSupply == 0 || timeBetweenDeposits == 0) {
                emit Debug("Division by zero error", 0);
                emit Debug("deposit.totalSupply", deposit.totalSupply);
                emit Debug("timeBetweenDeposits", timeBetweenDeposits);
            }

                uint256 nextBalanceTimestamp = depositTimestamp;

        emit Debug("balance.amount", balance.amount);
            emit Debug("nextBalanceTimestamp - balanceTimestamp", nextBalanceTimestamp - balanceTimestamp);




                while (balanceTimestamp >= previousDepositTimestamp) {
                    yieldAccrued += _BASE * depositAmount * balance.amount * (nextBalanceTimestamp - balanceTimestamp)
                        / deposit.totalSupply / timeBetweenDeposits;

                    nextBalanceTimestamp = balanceTimestamp;
                    balanceTimestamp = balance.previousTimestamp;
                    balance = balanceHistory.balances[balanceTimestamp];

                    if (nextBalanceTimestamp != preserveBalanceTimestamp) {
                        delete balanceHistory.balances[nextBalanceTimestamp].amount;
                        delete balanceHistory.balances[nextBalanceTimestamp].previousTimestamp;
                    }
                }

                yieldAccrued += _BASE * depositAmount * balance.amount
                    * (nextBalanceTimestamp - previousDepositTimestamp) / deposit.totalSupply / timeBetweenDeposits;
            }

            depositTimestamp = previousDepositTimestamp;
            deposit = depositHistory.deposits[depositTimestamp];
            depositAmount = deposit.currencyTokenAmount;
        }

        if ($.isDEX[user]) {
            // Redirect yield to the maker
            address maker = $.dexToMakerAddress[user][address(this)];
            $.yieldAccrued[maker] += yieldAccrued / _BASE;
            emit YieldAccrued(maker, yieldAccrued / _BASE);
        } else {
            // Regular yield accrual
            $.yieldAccrued[user] += yieldAccrued / _BASE;
            emit YieldAccrued(user, yieldAccrued / _BASE);
        }
    }


        /**
     * @notice Getter function to access tokensHeldOnDEXs for a user
     * @param user Address of the user
     * @return amount of tokens held on DEXs on behalf of the user
     */
    function tokensHeldOnDEXs(address user) public view returns (uint256) {
        YieldDistributionTokenStorage storage $ = _getYieldDistributionTokenStorage();
        return $.tokensHeldOnDEXs[user];
    }
}
