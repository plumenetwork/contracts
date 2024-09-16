// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { IYieldDistributionToken } from "../interfaces/IYieldDistributionToken.sol";

import { SmartWallet } from "../SmartWallet/SmartWallet.sol";

abstract contract YieldDistributionToken is ERC20, IYieldDistributionToken {

    struct BalanceSnapshot {
        uint256 amount;
        // Reverse linked list
        uint256 previousBalanceTimestamp;
    }

    struct WalletBalanceHistory {
        uint256 lastBalanceTimestamp;
        mapping(uint256 timestamp => BalanceSnapshot) balances;
    }

    struct YieldDeposit {
        uint256 amount;
        uint256 totalSupply;
        // Reverse linked list
        uint256 previousDepositTimestamp;
    }

    struct DepositHistory {
        uint256 lastDepositTimestamp;
        mapping(uint256 timestamp => YieldDeposit) deposits;
    }

    /// @custom:storage-location erc7201:plume.storage.SmartWallet
    struct YieldDistributionStorage {
        IERC20 yieldCurrency;
        DepositHistory depositHistory;
        mapping(address => WalletBalanceHistory) balanceHistory;
        mapping(address => uint256) yieldAccrued;
        mapping(address => uint256) yieldWithdrawn;
    }

    // keccak256(abi.encode(uint256(keccak256("plume.storage.YieldDistributionToken")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant YIELD_DISTRIBUTION_TOKEN_STORAGE_LOCATION =
        0x3d2d7d9da47f1055055838ecd982d8a93d7044b5f93759fc6e1ef3269bbc7000;

    function _getYieldDistributionStorage() internal pure returns (YieldDistributionStorage storage $) {
        assembly {
            $.slot := YIELD_DISTRIBUTION_TOKEN_STORAGE_LOCATION
        }
    }

    uint256 private constant PRECISION = 1e18;

    constructor(string memory name, string memory symbol, address yieldCurrency) ERC20(name, symbol) {
        _getYieldDistributionStorage().yieldCurrency = IERC20(yieldCurrency);
        _getYieldDistributionStorage().depositHistory.lastDepositTimestamp = block.timestamp;
    }

    /**
     * @notice Deposit yield
     * @param timestamp The timestamp of the deposit
     * @param amount The amount of yield to deposit
     */
    function _depositYield(uint256 timestamp, uint256 amount) internal {
        require(amount > 0, "YieldDistributionExample: amount must be greater than 0");

        uint256 lastDepositTimestamp = _getYieldDistributionStorage().depositHistory.lastDepositTimestamp;

        require(
            lastDepositTimestamp <= timestamp,
            "YieldDistributionExample: timestamp cannot be less than the previous timestamp"
        );
        require(
            timestamp <= block.timestamp,
            "YieldDistributionExample: timestamp must be less than or equal to the current block timestamp"
        );

        // Allow multiple deposits in the same block
        if (lastDepositTimestamp == timestamp) {
            _getYieldDistributionStorage().depositHistory.deposits[timestamp].amount += amount;
            return;
        }

        YieldDeposit storage newDeposit = _getYieldDistributionStorage().depositHistory.deposits[timestamp];
        newDeposit.previousDepositTimestamp = lastDepositTimestamp;
        newDeposit.amount = amount;
        newDeposit.totalSupply = totalSupply();

        _getYieldDistributionStorage().depositHistory.lastDepositTimestamp = timestamp;

        _getYieldDistributionStorage().yieldCurrency.transferFrom(msg.sender, address(this), amount);
    }

    /**
     * @notice Process yield for an account
     * @param tokenHolder The account to process yield for
     */
    function processYield(address tokenHolder) public {
        DepositHistory storage depositHistory = _getYieldDistributionStorage().depositHistory;
        WalletBalanceHistory storage balanceHistory = _getYieldDistributionStorage().balanceHistory[tokenHolder];

        uint256 depositTimestamp = depositHistory.lastDepositTimestamp;

        /* Avoid a race condition where we deposit yield,
        then process yield for some users, then deposit yield again in the same block.
        This would cause those users to miss out on the second deposit
        because they would have already been marked as receiving the yield from that timestamp. */
        if (depositTimestamp == block.timestamp) {
            return;
        }

        uint256 balanceTimestamp = balanceHistory.lastBalanceTimestamp;

        if (balanceTimestamp == 0) {
            return;
        }

        YieldDeposit storage deposit = depositHistory.deposits[depositTimestamp];
        BalanceSnapshot storage balance = balanceHistory.balances[balanceTimestamp];
        uint256 previousBalanceTimestamp = balance.previousBalanceTimestamp;
        BalanceSnapshot storage previousBalance = balanceHistory.balances[previousBalanceTimestamp];

        // Skipping balances newer than the last deposit
        while (previousBalanceTimestamp > depositTimestamp) {
            balance = previousBalance;
            balanceTimestamp = previousBalanceTimestamp;
            previousBalanceTimestamp = balance.previousBalanceTimestamp;
            previousBalance = balanceHistory.balances[previousBalanceTimestamp];
        }

        // NOW balanceTimestamp > depositTimestamp >= previousBalanceTimestamp
        // OR depositTimestamp >= balanceTimestamp > previousBalanceTimestamp

        uint256 preserveBalanceTimestamp;

        // Trimming everything prior to the last deposit from the balance history
        if (balanceTimestamp > depositTimestamp) {
            if (previousBalanceTimestamp != 0) {
                balance.previousBalanceTimestamp = depositTimestamp;
                balanceHistory.balances[depositTimestamp].amount = previousBalance.amount;
                delete balanceHistory.balances[depositTimestamp].previousBalanceTimestamp;
            }

            balance = previousBalance;
            balanceTimestamp = previousBalanceTimestamp;
        } else if (balanceTimestamp < depositTimestamp) {
            balanceHistory.lastBalanceTimestamp = depositTimestamp;
            balanceHistory.balances[depositTimestamp].amount = balance.amount;
            delete balanceHistory.balances[depositTimestamp].previousBalanceTimestamp;
        } else {
            preserveBalanceTimestamp = balanceTimestamp;
        }

        // NOW depositTimestamp >= balanceTimestamp

        uint256 yieldAmount = 0;
        uint256 depositAmount = deposit.amount;

        // Looping through the deposits and balance history
        while (balanceTimestamp != 0 && depositAmount != 0) {
            uint256 previousDepositTimestamp = deposit.previousDepositTimestamp;
            uint256 timeSpan = depositTimestamp - previousDepositTimestamp;
            uint256 snapshotAmount;

            // if didn't transfer token for the full deposit period
            if (previousDepositTimestamp >= balanceTimestamp) {
                snapshotAmount = PRECISION * depositAmount * balance.amount / deposit.totalSupply;
                yieldAmount += snapshotAmount;
            } else {
                uint256 followingTimestamp = depositTimestamp;

                while (balanceTimestamp > previousDepositTimestamp) {
                    snapshotAmount = PRECISION * depositAmount * balance.amount
                        * (followingTimestamp - balanceTimestamp) / deposit.totalSupply / timeSpan;
                    yieldAmount += snapshotAmount;

                    followingTimestamp = balanceTimestamp;

                    balanceTimestamp = balance.previousBalanceTimestamp;
                    balance = balanceHistory.balances[balanceTimestamp];

                    if (followingTimestamp != preserveBalanceTimestamp) {
                        delete balanceHistory.balances[followingTimestamp].amount;
                        delete balanceHistory.balances[followingTimestamp].previousBalanceTimestamp;
                    }
                }

                // handling the the interval between last balance and the previous deposit
                snapshotAmount = PRECISION * depositAmount * balance.amount
                    * (followingTimestamp - previousDepositTimestamp) / deposit.totalSupply / timeSpan;
                yieldAmount += snapshotAmount;
            }

            deposit = depositHistory.deposits[previousDepositTimestamp];
            depositTimestamp = previousDepositTimestamp;
            depositAmount = deposit.amount;
        }

        _getYieldDistributionStorage().yieldAccrued[tokenHolder] += yieldAmount / PRECISION;
    }

    /**
     * @notice Claim yield
     * @dev This function must be called by the token holder
     * @return currency The yield currency token address
     * @return amount The amount of yield claimed
     */
    function claimYield() public returns (address currency, uint256 amount) {
        address tokenHolder = msg.sender;
        IERC20 yieldCurrency = _getYieldDistributionStorage().yieldCurrency;

        processYield(tokenHolder);

        uint256 accruedAmount = _getYieldDistributionStorage().yieldAccrued[tokenHolder];
        amount = accruedAmount - _getYieldDistributionStorage().yieldWithdrawn[tokenHolder];

        if (amount == 0) {
            return (address(yieldCurrency), 0);
        }

        _getYieldDistributionStorage().yieldWithdrawn[tokenHolder] = accruedAmount;

        yieldCurrency.transfer(tokenHolder, amount);

        return (address(yieldCurrency), amount);
    }

    /**
     * @notice Update the balance of an account
     * @dev Internal function of IERC20 implementation
     * @param from The account to update the balance from
     * @param to The account to update the balance to
     * @param amount The amount to update the balance by
     */
    function _update(address from, address to, uint256 amount) internal virtual override {
        super._update(from, to, amount);

        uint256 timestamp = block.timestamp;

        if (from != address(0)) {
            processYield(from);

            uint256 previousBalanceTimestamp = _getYieldDistributionStorage().balanceHistory[from].lastBalanceTimestamp;
            uint256 balance = balanceOf(from);

            if (previousBalanceTimestamp == timestamp) {
                _getYieldDistributionStorage().balanceHistory[from].balances[timestamp].amount = balance;
            } else {
                _getYieldDistributionStorage().balanceHistory[from].balances[timestamp] =
                    BalanceSnapshot(balance, previousBalanceTimestamp);
                _getYieldDistributionStorage().balanceHistory[from].lastBalanceTimestamp = timestamp;
            }
        }

        if (to != address(0)) {
            processYield(to);

            uint256 previousBalanceTimestamp = _getYieldDistributionStorage().balanceHistory[to].lastBalanceTimestamp;
            uint256 balance = balanceOf(to);

            if (previousBalanceTimestamp == timestamp) {
                _getYieldDistributionStorage().balanceHistory[to].balances[timestamp].amount = balance;
            } else {
                _getYieldDistributionStorage().balanceHistory[to].balances[timestamp] =
                    BalanceSnapshot(balance, previousBalanceTimestamp);
                _getYieldDistributionStorage().balanceHistory[to].lastBalanceTimestamp = timestamp;
            }
        }
    }

}
