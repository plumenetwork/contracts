// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IAssetToken} from "../interfaces/IAssetToken.sol";
import {IAssetVault} from "../interfaces/IAssetVault.sol";
import {ISmartWallet} from "../interfaces/ISmartWallet.sol";
import {console} from "forge-std/console.sol";

/**
 * @title AssetVault
 * @author Eugene Y. Q. Shen
 * @notice Smart wallet extension on Plume that allows users to lock yield-bearing assets
 *   in a vault, then take the yield distributed to those locked yield-bearing assets
 *   and manage the redistribution of that yield to multiple beneficiaries.
 */
contract AssetVault is IAssetVault {
    // Types

    /**
     * @notice Yield of some amount that expires at some time
     * @dev Can be used to represent both yield allowances and yield distributions
     */
    struct Yield {
        /// @dev Amount of AssetTokens that are locked for this yield, must always be positive
        uint256 amount;
        /// @dev Timestamp at which the yield expires
        uint256 expiration;
    }

    /// @notice Item in a linked list of yield distributions
    struct YieldDistributionListItem {
        /// @dev Address of the beneficiary of the yield distribution
        address beneficiary;
        /// @dev Yield represented by the yield distribution
        Yield yield;
        /// @dev Next YieldDistributionListItem in the linked list
        YieldDistributionListItem[] next; // Use array to avoid recursive struct definition error
    }

    // Storage

    /// @custom:storage-location erc7201:plume.storage.AssetVault
    struct AssetVaultStorage {
        /// @dev Mapping of yield allowances for each AssetToken and beneficiary
        mapping(IAssetToken assetToken => mapping(address beneficiary => Yield allowance)) yieldAllowances;
        /// @dev Mapping of the yield distribution list for each AssetToken
        mapping(IAssetToken assetToken => YieldDistributionListItem distribution) yieldDistributions;
    }

    // keccak256(abi.encode(uint256(keccak256("plume.storage.AssetVault")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ASSET_VAULT_STORAGE_LOCATION =
        0x8705cfd43fb7e30ae97a9cbbffbf82f7d6cb80ad243d5fc52988024cb47c5700;

    function _getAssetVaultStorage()
        private
        pure
        returns (AssetVaultStorage storage $)
    {
        assembly {
            $.slot := ASSET_VAULT_STORAGE_LOCATION
        }
    }

    // Constants

    /// @notice Address of the user smart wallet that contains this AssetVault extension
    address public immutable wallet;

    /**
     * @dev Maximum amount of gas used in each iteration of the loops.
     *   We keep iterating until we have less than this much gas left,
     *   then we stop the loop so that we do not reach the gas limit.
     */
    uint256 private constant MAX_GAS_PER_ITERATION = 50_000;

    // Events

    /**
     * @notice Emitted when the user wallet updates a yield allowance
     * @param assetToken AssetToken from which the yield is to be redistributed
     * @param beneficiary Address of the beneficiary of the yield allowance
     * @param amount Amount of AssetTokens that are locked for this yield
     * @param expiration Timestamp at which the yield expires
     */
    event YieldAllowanceUpdated(
        IAssetToken indexed assetToken,
        address indexed beneficiary,
        uint256 amount,
        uint256 expiration
    );

    /**
     * @notice Emitted when the user wallet redistributes yield to the beneficiaries
     * @param assetToken AssetToken from which the yield was redistributed
     * @param beneficiary Address of the beneficiary that received the yield redistribution
     * @param currencyToken Token in which the yield was redistributed
     * @param yieldShare Amount of CurrencyToken that was redistributed to the beneficiary
     */
    event YieldRedistributed(
        IAssetToken indexed assetToken,
        address indexed beneficiary,
        IERC20 indexed currencyToken,
        uint256 yieldShare
    );

    /**
     * @notice Emitted when a beneficiary accepts a yield allowance and creates a new yield distribution
     * @param assetToken AssetToken from which the yield is to be redistributed
     * @param beneficiary Address of the beneficiary of the yield distribution
     * @param amount Amount of AssetTokens that are locked for this yield
     * @param expiration Timestamp at which the yield expires
     */
    event YieldDistributionCreated(
        IAssetToken indexed assetToken,
        address indexed beneficiary,
        uint256 amount,
        uint256 expiration
    );

    /**
     * @notice Emitted when a beneficiary renounces their yield distributions
     * @param assetToken AssetToken from which the yield is to be redistributed
     * @param beneficiary Address of the beneficiary of the yield distribution
     * @param amount Amount of AssetTokens that are renounced from the yield distributions of the beneficiary
     */
    event YieldDistributionRenounced(
        IAssetToken indexed assetToken,
        address indexed beneficiary,
        uint256 amount
    );

    /**
     * @notice Emitted when anyone clears expired yield distributions from the linked list
     * @param assetToken AssetToken from which the yield is to be redistributed
     * @param amountCleared Amount of AssetTokens that were cleared from the yield distributions
     */
    event YieldDistributionsCleared(
        IAssetToken indexed assetToken,
        uint256 amountCleared
    );

    // Errors

    /// @notice Indicates a failure because the given address is 0x0
    error ZeroAddress();

    /// @notice Indicates a failure because the given amount is 0
    error ZeroAmount();

    /**
     * @notice Indicates a failure because the given expiration timestamp is too old
     * @param expiration Expiration timestamp that was too old
     * @param currentTimestamp Current block.timestamp
     */
    error InvalidExpiration(uint256 expiration, uint256 currentTimestamp);

    /**
     * @notice Indicates a failure because the given expiration does not match the actual one
     * @param invalidExpiration Expiration timestamp that does not match the actual expiration
     * @param expiration Actual expiration timestamp at which the yield expires
     */
    error MismatchedExpiration(uint256 invalidExpiration, uint256 expiration);

    /**
     * @notice Indicates a failure because the beneficiary does not have enough yield allowances
     * @param assetToken AssetToken from which the yield is to be redistributed
     * @param beneficiary Address of the beneficiary of the yield allowance
     * @param allowanceAmount Amount of assetTokens included in this yield allowance
     * @param amount Amount of assetTokens that the beneficiary tried to accept the yield of
     */
    error InsufficientYieldAllowance(
        IAssetToken assetToken,
        address beneficiary,
        uint256 allowanceAmount,
        uint256 amount
    );

    /**
     * @notice Indicates a failure because the user wallet does not have enough AssetTokens
     * @param assetToken AssetToken for which a new yield distribution is to be made
     * @param amount Amount of assetTokens that the user wallet tried to add to the distribution
     */
    error InsufficientBalance(IAssetToken assetToken, uint256 amount);

    /**
     * @notice Indicates a failure because the beneficiary does not have enough yield distributions
     * @param assetToken AssetToken from which the yield is to be redistributed
     * @param beneficiary Address of the beneficiary of the yield distributions
     * @param amount Amount of assetTokens included in all of their yield distributions
     * @param amountRenounced Amount of assetTokens that the beneficiary tried to renounce the yield of
     */
    error InsufficientYieldDistributions(
        IAssetToken assetToken,
        address beneficiary,
        uint256 amount,
        uint256 amountRenounced
    );

    /**
     * @notice Indicates a failure because the caller is not the user wallet
     * @param invalidUser Address of the caller who tried to call a wallet-only function
     */
    error UnauthorizedCall(address invalidUser);

    // Modifiers

    /// @notice Only the user wallet can call this function
    modifier onlyWallet() {
        if (msg.sender != wallet) {
            revert UnauthorizedCall(msg.sender);
        }
        _;
    }

    // Constructor

    /**
     * @notice Construct the AssetVault extension
     * @dev The sender of the transaction creates an AssetVault for themselves,
     *   and their address is saved as the public immutable variable `wallet`.
     */
    constructor() {
        wallet = msg.sender;
    }

    // User Wallet Functions

    /**
     * @notice Update the yield allowance of the given beneficiary
     * @dev Only the user wallet can update yield allowances for tokens in their own AssetVault
     * @param assetToken AssetToken from which the yield is to be redistributed
     * @param beneficiary Address of the beneficiary of the yield allowance
     * @param amount Amount of assetTokens to be locked for this yield allowance
     * @param expiration Timestamp at which the yield expires
     */
    function updateYieldAllowance(
        IAssetToken assetToken,
        address beneficiary,
        uint256 amount,
        uint256 expiration
    ) external onlyWallet {
        if (address(assetToken) == address(0) || beneficiary == address(0)) {
            revert ZeroAddress();
        }
        if (amount == 0) {
            revert ZeroAmount();
        }
        if (expiration <= block.timestamp) {
            revert InvalidExpiration(expiration, block.timestamp);
        }

        Yield storage allowance = _getAssetVaultStorage().yieldAllowances[
            assetToken
        ][beneficiary];
        allowance.amount = amount;
        allowance.expiration = expiration;

        emit YieldAllowanceUpdated(assetToken, beneficiary, amount, expiration);
    }

    /**
     * @notice Redistribute yield to the beneficiaries of the AssetToken, using yield distributions
     * @dev Only the user wallet can initiate the yield redistribution. The yield redistributed
     *   to each beneficiary is rounded down, and any remaining CurrencyToken are kept in the vault.
     * @param assetToken AssetToken from which the yield is to be redistributed
     * @param currencyToken Token in which the yield is to be redistributed
     * @param currencyTokenAmount Amount of CurrencyToken to redistribute
     */

    function redistributeYield(
        IAssetToken assetToken,
        IERC20 currencyToken,
        uint256 currencyTokenAmount
    ) external onlyWallet {
        console.log(
            "Redistributing yield. Currency token amount:",
            currencyTokenAmount
        );
        if (currencyTokenAmount == 0) {
            console.log("Currency token amount is 0, exiting function");
            return;
        }

        uint256 amountTotal = assetToken.balanceOf(address(this));
        console.log("Total amount of AssetTokens in AssetVault:", amountTotal);

        YieldDistributionListItem storage distribution = _getAssetVaultStorage()
            .yieldDistributions[assetToken];

        if (distribution.beneficiary == address(0)) {
            console.log("No yield distributions found");
            return;
        }

        uint256 totalDistributed = 0;
        while (true) {
            console.log(
                "Current distribution beneficiary:",
                distribution.beneficiary
            );
            console.log(
                "Current distribution amount:",
                distribution.yield.amount
            );
            console.log(
                "Current distribution expiration:",
                distribution.yield.expiration
            );
            console.log("Current block timestamp:", block.timestamp);

            if (distribution.yield.expiration > block.timestamp) {
                uint256 yieldShare = (currencyTokenAmount *
                    distribution.yield.amount) / amountTotal;
                console.log("Calculated yield share:", yieldShare);

                if (yieldShare > 0) {
                    console.log(
                        "Transferring yield to beneficiary:",
                        distribution.beneficiary
                    );
                    console.log("Yield amount:", yieldShare);
                    ISmartWallet(wallet).transferYield(
                        assetToken,
                        distribution.beneficiary,
                        currencyToken,
                        yieldShare
                    );
                    emit YieldRedistributed(
                        assetToken,
                        distribution.beneficiary,
                        currencyToken,
                        yieldShare
                    );
                    totalDistributed += yieldShare;

                    // Check beneficiary balance after transfer
                    uint256 beneficiaryBalance = currencyToken.balanceOf(
                        distribution.beneficiary
                    );
                    console.log(
                        "Beneficiary balance after transfer:",
                        beneficiaryBalance
                    );
                } else {
                    console.log("Yield share is 0, skipping transfer");
                }
            } else {
                console.log("Distribution has expired");
            }

            if (distribution.next.length == 0) {
                console.log("No more distributions, exiting loop");
                break;
            }
            distribution = distribution.next[0];
        }

        console.log("Total yield distributed:", totalDistributed);
    }

    // Permissionless Functions

    /**
     * @notice Get the number of AssetTokens that are currently locked in the AssetVault
     * @param assetToken AssetToken from which the yield is to be redistributed
     */
    function getBalanceLocked(
        IAssetToken assetToken
    ) external view returns (uint256 balanceLocked) {
        // Iterate through the list and sum up the locked balance across all yield distributions
        YieldDistributionListItem storage distribution = _getAssetVaultStorage()
            .yieldDistributions[assetToken];
        while (true) {
            if (distribution.yield.expiration > block.timestamp) {
                balanceLocked += distribution.yield.amount;
            }
            if (distribution.next.length > 0) {
                distribution = distribution.next[0];
            } else {
                break;
            }
        }

        return balanceLocked;
    }

    /**
     * @notice Accept the yield allowance and create a new yield distribution
     * @dev The beneficiary must call this function to accept the yield allowance
     * @param assetToken AssetToken from which the yield is to be redistributed
     * @param amount Amount of AssetTokens included in this yield allowance
     * @param expiration Timestamp at which the yield expires
     */
    function acceptYieldAllowance(
        IAssetToken assetToken,
        uint256 amount,
        uint256 expiration
    ) external {
        AssetVaultStorage storage $ = _getAssetVaultStorage();
        address beneficiary = msg.sender;
        Yield storage allowance = $.yieldAllowances[assetToken][beneficiary];

        if (amount == 0) {
            revert ZeroAmount();
        }
        if (expiration <= block.timestamp) {
            revert InvalidExpiration(expiration, block.timestamp);
        }
        if (allowance.expiration != expiration) {
            revert MismatchedExpiration(allowance.expiration, expiration);
        }
        if (allowance.amount < amount) {
            revert InsufficientYieldAllowance(
                assetToken,
                beneficiary,
                allowance.amount,
                amount
            );
        }
        if (assetToken.getBalanceAvailable(address(this)) < amount) {
            revert InsufficientBalance(assetToken, amount);
        }

        allowance.amount -= amount;

        YieldDistributionListItem storage distributionHead = $
            .yieldDistributions[assetToken];
        YieldDistributionListItem
            storage currentDistribution = distributionHead;

        // If the list is empty or the first item is expired, update the head
        if (
            currentDistribution.beneficiary == address(0) ||
            currentDistribution.yield.expiration <= block.timestamp
        ) {
            distributionHead.beneficiary = beneficiary;
            distributionHead.yield.amount = amount;
            distributionHead.yield.expiration = expiration;
        } else {
            // Find the correct position to insert or update
            while (currentDistribution.next.length > 0) {
                if (
                    currentDistribution.beneficiary == beneficiary &&
                    currentDistribution.yield.expiration == expiration
                ) {
                    currentDistribution.yield.amount += amount;
                    break;
                }
                currentDistribution = currentDistribution.next[0];
            }

            // If we didn't find an existing distribution, add a new one
            if (
                currentDistribution.beneficiary != beneficiary ||
                currentDistribution.yield.expiration != expiration
            ) {
                currentDistribution.next.push();
                YieldDistributionListItem
                    storage newDistribution = currentDistribution.next[0];
                newDistribution.beneficiary = beneficiary;
                newDistribution.yield.amount = amount;
                newDistribution.yield.expiration = expiration;
            }
        }

        console.log("Accepted yield allowance for beneficiary:", beneficiary);
        console.log("Amount:", amount);
        console.log("Expiration:", expiration);

        emit YieldDistributionCreated(
            assetToken,
            beneficiary,
            amount,
            expiration
        );
    }

    function getYieldDistributions(
        IAssetToken assetToken
    )
        external
        view
        returns (
            address[] memory beneficiaries,
            uint256[] memory amounts,
            uint256[] memory expirations
        )
    {
        YieldDistributionListItem storage distribution = _getAssetVaultStorage()
            .yieldDistributions[assetToken];
        uint256 count = 0;
        YieldDistributionListItem storage current = distribution;
        while (true) {
            if (current.beneficiary != address(0)) {
                count++;
            }
            if (current.next.length == 0) break;
            current = current.next[0];
        }

        beneficiaries = new address[](count);
        amounts = new uint256[](count);
        expirations = new uint256[](count);

        current = distribution;
        uint256 index = 0;
        while (true) {
            if (current.beneficiary != address(0)) {
                beneficiaries[index] = current.beneficiary;
                amounts[index] = current.yield.amount;
                expirations[index] = current.yield.expiration;
                index++;
            }
            if (current.next.length == 0) break;
            current = current.next[0];
        }
    }

    /**
     * @notice Renounce the given amount of AssetTokens from the beneficiary's yield distributions
     * @dev The beneficiary must call this function to reduce the size of their yield distributions.
     *   If there are too many yield distributions to process, the function will stop to avoid
     *   reaching the gas limit, and the beneficiary must call the function again to renounce more.
     * @param assetToken AssetToken from which the yield is to be redistributed
     * @param amount Amount of AssetTokens to renounce from from the yield distribution
     * @param expiration Timestamp at which the yield expires
     */
    function renounceYieldDistribution(
        IAssetToken assetToken,
        uint256 amount,
        uint256 expiration
    ) external returns (uint256 amountRenounced) {
        console.log("renounceYieldDistribution1");
        YieldDistributionListItem storage distribution = _getAssetVaultStorage()
            .yieldDistributions[assetToken];
        address beneficiary = msg.sender;
        uint256 amountLeft = amount;
        console.log("renounceYieldDistribution2");
        // Iterate through the list and subtract the amount from the beneficiary's yield distributions
        uint256 amountLocked = distribution.yield.amount;
        while (amountLocked > 0) {
            console.log("renounceYieldDistribution3");

            if (
                distribution.beneficiary == beneficiary &&
                distribution.yield.expiration == expiration
            ) {
                console.log("renounceYieldDistribution4");

                // If the entire yield distribution is to be renounced, then set its timestamp
                // to be in the past so it is cleared on the next run of `clearYieldDistributions`
                if (amountLeft >= amountLocked) {
                    console.log("renounceYieldDistribution4.1");

                    amountLeft -= amountLocked;
                    console.log("renounceYieldDistribution4.2");
                    console.log(
                        "distribution.yield.expiration",
                        distribution.yield.expiration
                    );
                    console.log("block.timestamp", block.timestamp - 1 days);
                    //console.log("1.days",1 days);

                    distribution.yield.expiration = block.timestamp - 1 days;
                    console.log("renounceYieldDistribution4.2.2");

                    if (amountLeft == 0) {
                        console.log("renounceYieldDistribution4.2.3");

                        break;
                    }
                    console.log("renounceYieldDistribution4.3");
                } else {
                    console.log("renounceYieldDistribution4.4");
                    distribution.yield.amount -= amountLeft;
                    console.log("renounceYieldDistribution4.5");
                    amountLeft = 0;
                    break;
                }
            }
            console.log("renounceYieldDistribution5");

            if (gasleft() < MAX_GAS_PER_ITERATION) {
                emit YieldDistributionRenounced(
                    assetToken,
                    beneficiary,
                    amount - amountLeft
                );
                return amount - amountLeft;
            }
            distribution = distribution.next[0];
            amountLocked = distribution.yield.amount;
            console.log("renounceYieldDistribution6");
        }
        console.log("renounceYieldDistribution7");

        if (amountLeft > 0) {
            revert InsufficientYieldDistributions(
                assetToken,
                beneficiary,
                amount - amountLeft,
                amount
            );
        }
        console.log("renounceYieldDistribution8");

        emit YieldDistributionRenounced(assetToken, beneficiary, amount);
        return amount;
    }

    /**
     * @notice Clear expired yield distributions from the linked list
     * @dev Anyone can call this function to free up unused storage for gas refunds.
     *   If there are too many yield distributions to process, the function will stop to avoid
     *   reaching the gas limit, and the caller must call the function again to clear more.
     * @param assetToken AssetToken from which the yield is to be redistributed
     */

    function clearYieldDistributions(IAssetToken assetToken) external {
        uint256 amountCleared = 0;
        AssetVaultStorage storage s = _getAssetVaultStorage();
        YieldDistributionListItem storage head = s.yieldDistributions[
            assetToken
        ];

        // Check if the list is empty
        if (head.beneficiary == address(0) && head.yield.amount == 0) {
            emit YieldDistributionsCleared(assetToken, 0);
            return;
        }

        while (head.yield.amount > 0) {
            if (head.yield.expiration <= block.timestamp) {
                amountCleared += head.yield.amount;
                if (head.next.length > 0) {
                    YieldDistributionListItem storage nextItem = head.next[0];
                    head.beneficiary = nextItem.beneficiary;
                    head.yield = nextItem.yield;
                    head.next = nextItem.next;
                } else {
                    // If there's no next item, clear the current one and break
                    head.beneficiary = address(0);
                    head.yield.amount = 0;
                    head.yield.expiration = 0;
                    break;
                }
            } else {
                // If the current item is not expired, move to the next one
                if (head.next.length > 0) {
                    head = head.next[0];
                } else {
                    break;
                }
            }

            if (gasleft() < MAX_GAS_PER_ITERATION) {
                break;
            }
        }

        emit YieldDistributionsCleared(assetToken, amountCleared);
    }
}
