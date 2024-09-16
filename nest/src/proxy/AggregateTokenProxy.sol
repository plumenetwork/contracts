// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title AggregateTokenProxy
 * @author Eugene Y. Q. Shen
 * @notice Proxy contract for the AggregateToken
 */
contract AggregateTokenProxy is ERC1967Proxy {

    bytes32 private constant PROXY_NAME = keccak256("AggregateTokenProxy");

    constructor(address logic, bytes memory data) ERC1967Proxy(logic, data) { }

}
