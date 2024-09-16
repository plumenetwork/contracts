// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IYieldDistributionToken
 * @author Eugene Y. Q. Shen
 * @notice Interface for the Yield Distribution
 */
interface IYieldDistributionToken is IERC20 {

    /**
     * @notice Claim yield for the token holder
     * @dev sender is the token holder
     * @return currency The token that was yielded
     * @return amount The amount of tokens that was yielded
     */
    function claimYield() external returns (address currency, uint256 amount);

}
