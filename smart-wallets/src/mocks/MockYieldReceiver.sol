// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IAssetToken } from "../interfaces/IAssetToken.sol";
import { IYieldReceiver } from "../interfaces/IYieldReceiver.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockYieldReceiver is IYieldReceiver {

    // small hack to be excluded from coverage report
    function test() public { }

    function receiveYield(IAssetToken assetToken, IERC20 currencyToken, uint256 amount) external override {
        // Implementation can be empty for testing
    }

}
