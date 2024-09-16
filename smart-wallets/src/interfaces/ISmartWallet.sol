// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ISignedOperations } from "./ISignedOperations.sol";

interface ISmartWallet is ISignedOperations {

    function upgrade(address userWallet) external;

}
