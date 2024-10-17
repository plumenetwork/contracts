// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { IYieldDistributionToken } from "../interfaces/IYieldDistributionToken.sol";
import { Deposit, UserState } from "./Types.sol";

// Suggestions:
// - move structs to Types.sol file
// - move errors, events to interface
// - move storage related structs to YieldDistributionTokenStorage.sol library

/**
 * @title YieldDistributionToken
 * @author Eugene Y. Q. Shen
 * @notice ERC20 token that receives yield deposits and distributes yield
 *   to token holders proportionally based on how long they have held the token
 */
abstract contract YieldDistributionToken is ERC20, Ownable, IYieldDistributionToken {

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
        /// @dev State for each user
        mapping(address user => UserState userState) userStates;
         /// @dev Mapping to track registered DEX addresses
        mapping(address => bool) isDEX;
        /// @dev Mapping to associate DEX addresses with maker addresses
        mapping(address => mapping(address => address)) dexToMakerAddress;
        /// @dev Mapping to track tokens held on DEXs for each user
        mapping(address => uint256) tokensHeldOnDEXs;
        Deposit[] deposits;
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

    // Scale that is used to multiply yield deposits for increased precision
    uint256 private constant SCALE = 1e36;

    // Events

    /**
     * @notice Emitted when yield is deposited into the YieldDistributionToken
     * @param user Address of the user who deposited the yield
     * @param currencyTokenAmount Amount of CurrencyToken deposited as yield
     */
    event Deposited(address indexed user, uint256 currencyTokenAmount);

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
     * @notice Indicates a failure because the transfer of CurrencyToken failed
     * @param user Address of the user who tried to transfer CurrencyToken
     * @param currencyTokenAmount Amount of CurrencyToken that failed to transfer
     */
    error TransferFailed(address user, uint256 currencyTokenAmount);

    /// @notice Indicates a failure because a yield deposit is made in the same block as the last one
    error DepositSameBlock();

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
        _updateGlobalAmountSeconds();
        $.deposits.push(
            Deposit({ scaledCurrencyTokenPerAmountSecond: 0, totalAmountSeconds: 0, timestamp: block.timestamp })
        );
    }


    // Virtual Functions

    /// @notice Request to receive yield from the given SmartWallet
    function requestYield(
        address from
    ) external virtual override(IYieldDistributionToken);

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
        _updateGlobalAmountSeconds();

        if (from != address(0)) {
            accrueYield(from);

            // Adjust balances if transferring to a DEX
            if ($.isDEX[to]) {
                $.dexToMakerAddress[to][address(this)] = from;
                _adjustMakerBalance(from, value, true);
            }



            
        }

        if (to != address(0)) {

            // conditions checks that this is the first time a user receives tokens
            // if so, the lastDepositIndex is set to index of the last deposit in deposits array
            // to avoid needlessly accruing yield for previous deposits which the user has no claim to
            if ($.userStates[to].lastDepositIndex == 0 && balanceOf(to) == 0) {
                $.userStates[to].lastDepositIndex = $.deposits.length - 1;
            }

            accrueYield(to);


    
            // Adjust balances if transferring from a DEX
            if ($.isDEX[from]) {
                address maker = $.dexToMakerAddress[from][address(this)];
                _adjustMakerBalance(maker, value, false);
            }

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

    /// @notice Update the amountSeconds for a user
    /// @param account Address of the user to update the amountSeconds for
    function _updateUserAmountSeconds(
        address account
    ) internal {
        UserState storage userState = _getYieldDistributionTokenStorage().userStates[account];
        userState.amountSeconds += balanceOf(account) * (block.timestamp - userState.lastUpdate);
        userState.lastUpdate = block.timestamp;
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

        uint256 previousDepositIndex = $.deposits.length - 1;
        if (block.timestamp == $.deposits[previousDepositIndex].timestamp) {
            revert DepositSameBlock();
        }

        _updateGlobalAmountSeconds();

        $.deposits.push(
            Deposit({
                scaledCurrencyTokenPerAmountSecond: currencyTokenAmount.mulDiv(
                    SCALE, ($.totalAmountSeconds - $.deposits[previousDepositIndex].totalAmountSeconds)
                ),
                totalAmountSeconds: $.totalAmountSeconds,
                timestamp: block.timestamp
            })
        );

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
    ) external onlyOwner {
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
    ) external view returns (UserState memory) {
        return _getYieldDistributionTokenStorage().userStates[account];
    }

    /// @notice Deposit at a given index
    function getDeposit(
        uint256 index
    ) external view returns (Deposit memory) {
        return _getYieldDistributionTokenStorage().deposits[index];
    }

    /// @notice All deposits made into the YieldDistributionToken
    function getDeposits() external view returns (Deposit[] memory) {
        return _getYieldDistributionTokenStorage().deposits;
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

        UserState storage userState = $.userStates[user];
        uint256 amountAccrued = userState.yieldAccrued;
        currencyTokenAmount = amountAccrued - userState.yieldWithdrawn;

        if (currencyTokenAmount != 0) {
            userState.yieldWithdrawn = amountAccrued;
            currencyToken.safeTransfer(user, currencyTokenAmount);
            emit YieldClaimed(user, currencyTokenAmount);
        }
    }

    /**
     * @notice Accrue yield to a user, which can later be claimed
     * @dev Anyone can call this function to accrue yield to any user.
     *   This function accrues all the yield up until the most recent deposit and updates the user state.
     * @param user Address of the user to accrue yield to
     */
    function accrueYield(
        address user
    ) public {
        YieldDistributionTokenStorage storage $ = _getYieldDistributionTokenStorage();
        UserState memory userState = $.userStates[user];

        uint256 currentDepositIndex = $.deposits.length - 1;
        uint256 lastDepositIndex = userState.lastDepositIndex;
        uint256 amountSecondsAccrued;

        if (lastDepositIndex != currentDepositIndex) {
            Deposit memory deposit;

            // all the deposits up to and including the lastDepositIndex of the user have had their yield accrued, if any
            // the loop iterates through all the remaining deposits and accrues yield from them, if any should be accrued
            // all variables in `userState` are updated until `lastDepositIndex`
            while (lastDepositIndex != currentDepositIndex) {
                ++lastDepositIndex;

                deposit = $.deposits[lastDepositIndex];

                amountSecondsAccrued = balanceOf(user) * (deposit.timestamp - userState.lastUpdate);

                userState.amountSeconds += amountSecondsAccrued;

                if (userState.amountSeconds > userState.amountSecondsDeduction) {
                    userState.yieldAccrued += deposit.scaledCurrencyTokenPerAmountSecond.mulDiv(
                        userState.amountSeconds - userState.amountSecondsDeduction, SCALE
                    );

                    // the `amountSecondsDeduction` is updated to the value of `amountSeconds`
                    // of the last yield accrual - therefore for the current yield accrual, it is updated
                    // to the current value of `amountSeconds`, along with `lastUpdate` and `lastDepositIndex`
                    // to avoid double counting yield
                    userState.amountSecondsDeduction = userState.amountSeconds;
                    userState.lastUpdate = deposit.timestamp;
                    userState.lastDepositIndex = lastDepositIndex;
                }


                // if amountSecondsAccrued is 0, then the either the balance of the user has been 0 for the entire deposit
                // of the deposit timestamp is equal to the users last update, meaning yield has already been accrued
                // the check ensures that the process terminates early if there are no more deposits from which to accrue yield
                if (amountSecondsAccrued == 0) {
                    userState.lastDepositIndex = currentDepositIndex;
                    break;
                }

                if (gasleft() < 100_000) {
                    break;
                }
            }

            // at this stage, the `userState` along with any accrued rewards, has been updated until the current deposit index
            $.userStates[user] = userState;

            if ($.isDEX[user]) {
                // Redirect yield to the maker
                address maker = $.dexToMakerAddress[user][address(this)];
                $.userStates[maker].yieldAccrued += userState.yieldAccrued;
                emit YieldAccrued(maker, userState.yieldAccrued);
            } else {
                // Regular yield accrual
                emit YieldAccrued(user, userState.yieldAccrued);
            }




            // TODO: do we emit the portion of yield accrued from this action, or the entirey of the yield accrued?
            //emit YieldAccrued(user, userState.yieldAccrued);
        }

        _updateUserAmountSeconds(user);
    }


    /**
     * @notice Register a DEX address
     * @dev Only the owner can call this function
     * @param dexAddress Address of the DEX to register
     */
    function registerDEX(address dexAddress) external onlyOwner {
        _getYieldDistributionTokenStorage().isDEX[dexAddress] = true;
    }

    /**
     * @notice Unregister a DEX address
     * @dev Only the owner can call this function
     * @param dexAddress Address of the DEX to unregister
     */
    function unregisterDEX(address dexAddress) external onlyOwner {
        _getYieldDistributionTokenStorage().isDEX[dexAddress] = false;
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
    $.tokensHeldOnDEXs[maker] += amount;
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
    require($.tokensHeldOnDEXs[maker] >= amount, "Insufficient tokens held on DEX");
    $.tokensHeldOnDEXs[maker] -= amount;
    if ($.tokensHeldOnDEXs[maker] == 0) {
        $.dexToMakerAddress[msg.sender][address(this)] = address(0);
    }
}


    /**
     * @notice Check if an address is a registered DEX
     * @param addr Address to check
     * @return bool True if the address is a registered DEX, false otherwise
     */
    function isDexAddressWhitelisted(address addr) public view returns (bool) {
        return _getYieldDistributionTokenStorage().isDEX[addr];
    }

    /**
     * @notice Get the amount of tokens held on DEXs for a user
     * @param user Address of the user
     * @return amount of tokens held on DEXs on behalf of the user
     */
    function tokensHeldOnDEXs(address user) public view returns (uint256) {
        return _getYieldDistributionTokenStorage().tokensHeldOnDEXs[user];
    }


        function _adjustMakerBalance(address maker, uint256 amount, bool increase) internal {
        YieldDistributionTokenStorage storage $ = _getYieldDistributionTokenStorage();
        if (increase) {
            $.tokensHeldOnDEXs[maker] += amount;
        } else {
            require($.tokensHeldOnDEXs[maker] >= amount, "Insufficient tokens held on DEXs");
            $.tokensHeldOnDEXs[maker] -= amount;
        }
    }

}