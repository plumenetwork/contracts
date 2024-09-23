// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IYieldDistributionToken } from "./IYieldDistributionToken.sol";
import { IYieldReceiver } from "./IYieldReceiver.sol";

interface IYieldToken is IYieldDistributionToken, IYieldReceiver {

    function requestYield(address from) external;

}
