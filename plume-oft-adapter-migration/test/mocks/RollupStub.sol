pragma solidity ^0.8.0;

import { IOwnable } from "../../../contracts/ethereum/bridge/IOwnable.sol";

contract RollupStub is IOwnable {
   address public owner;

    constructor(address _owner) {
        owner = _owner;
    }
}
