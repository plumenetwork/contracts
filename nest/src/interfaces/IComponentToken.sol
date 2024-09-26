// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IComponentToken } from "./IComponentToken.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IYieldDistributionToken is IERC20 {
    /// @notice CurrencyToken in which yield is denominated and distributed
    function getCurrencyToken() external returns (IERC20 currencyToken);

    /**
     * @notice Claim yield for the given user
     * @dev Anyone can call this function to claim yield for any user
     * @param user Address of the user for which to claim yield
     * @return currencyToken CurrencyToken in which yield is denominated and distributed
     * @return currencyTokenAmount Amount of yield claimed by the user
     */
    function claimYield(address user) external returns (IERC20 currencyToken, uint256 currencyTokenAmount);

    function accrueYield(address user) external;
    function requestYield(address from) external;
}

interface IComponentToken is IYieldDistributionToken {

    /**
     * @notice Buy FakeComponentToken using CurrencyToken
     * @dev The user must approve the contract to spend the CurrencyToken
     * @param currencyToken CurrencyToken used to buy the FakeComponentToken
     * @param currencyTokenAmount Amount of CurrencyToken to pay to receive the same amount of FakeComponentToken
     * @return componentTokenAmount Amount of FakeComponentToken received
     */
    function buy(IERC20 currencyToken, uint256 currencyTokenAmount) external returns (uint256 componentTokenAmount);

    /**
     * @notice Sell FakeComponentToken to receive CurrencyToken
     * @param currencyToken CurrencyToken received in exchange for the FakeComponentToken
     * @param currencyTokenAmount Amount of CurrencyToken to receive in exchange for the FakeComponentToken
     * @return componentTokenAmount Amount of FakeComponentToken sold
     */
    function sell(IERC20 currencyToken, uint256 currencyTokenAmount) external returns (uint256 componentTokenAmount);

    /// @notice Version of the FakeComponentToken
    function getVersion() external view returns (uint256 version);

    /// @notice Total yield distributed to all FakeComponentTokens for all users
    function totalYield() external view returns (uint256 currencyTokenAmount);

    /// @notice Claimed yield across all FakeComponentTokens for all users
    function claimedYield() external view returns (uint256 currencyTokenAmount);

    /// @notice Unclaimed yield across all FakeComponentTokens for all users
    function unclaimedYield() external view returns (uint256 currencyTokenAmount);

    /**
     * @notice Total yield distributed to a specific user
     * @param user Address of the user for which to get the total yield
     * @return currencyTokenAmount Total yield distributed to the user
     */
    function totalYield(address user) external view returns (uint256 currencyTokenAmount);

    /**
     * @notice Amount of yield that a specific user has claimed
     * @param user Address of the user for which to get the claimed yield
     * @return currencyTokenAmount Amount of yield that the user has claimed
     */
    function claimedYield(address user) external view returns (uint256 currencyTokenAmount);

    /**
     * @notice Amount of yield that a specific user has not yet claimed
     * @param user Address of the user for which to get the unclaimed yield
     * @return currencyTokenAmount Amount of yield that the user has not yet claimed
     */
    function unclaimedYield(address user) external view returns (uint256 currencyTokenAmount);

}
