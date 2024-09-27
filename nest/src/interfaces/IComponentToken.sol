// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IClaimableYieldToken {
    /// this token has a whitelist and only whitelisted people can call buy and offer
    /// NEV tells Credbull please give me the yield you told me i had, in $pUSD
    function claimYield(address user) external returns (uint256 currencyTokenAmount);
    function totalYield() external view returns (uint256 amount);
    function claimedYield() external view returns (uint256 amount);
    function unclaimedYield() external view returns (uint256 amount);
    function totalYield(address user) external view returns (uint256 amount);
    function claimedYield(address user) external view returns (uint256 amount);
    function unclaimedYield(address user) external view returns (uint256 amount);
}

interface IComponentToken {

    /// NEV tells Credbull I want to buy $CBL using $pUSD, they take the $pUSD and mint $CBL for me - all synchronous
    function buy(IERC20 currencyToken, uint256 currencyTokenAmount) external returns (uint256 componentTokenAmount);

    /// NEV tells Credbull I want to sell this much $CBL, they tell me they will give me this much $pUSD
    function offer(IERC20 currencyToken, uint256 componentTokenAmount) external returns (uint256 currencyTokenAmount);
}

interface IAggregateToken is IComponentToken {

    /// The vault that caontains this tells NEV I want to buy $NEV using $pUSD, they take the $pUSD and mint $NEV for me - all synchronous
    function buy(IERC20 currencyToken, uint256 currencyTokenAmount) external returns (uint256 componentTokenAmount);

    /// The vault that caontains this tells NEV I want to buy $NEV using $pUSD, they take the $pUSD and mint $NEV for me - all synchronous
    function sell(IERC20 currencyToken, uint256 currencyTokenAmount) external returns (uint256 componentTokenAmount);

    /// Cicada this will call componentToken.buy
    function buyComponentToken(IComponentToken componentToken, uint256 currencyTokenAmount) external;

    /// Cicada this will call componentToken.offer
    function offerComponentToken(IComponentToken componentToken, uint256 componentTokenAmount) external;

    /// Credbull tells NEV I have the $pUSD for you, they give NEV the $pUSD and burn the $CBL from NEV
    // we can check that this is only being called by a componentToken
    function sellComponentToken(IERC20 currencyToken, IERC20 componentToken, uint256 componentTokenAmount) external returns (uint256 currencyTokenAmount);

    /// Credbull tells NEV I have $pUSD yield for you and gives it to NEV
    function depositYield(IERC20 currencyToken, uint256 currencyTokenAmount) external;
}
