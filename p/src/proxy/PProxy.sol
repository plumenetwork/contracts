// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title PProxy
 * @author Eugene Y. Q. Shen
 * @notice Proxy contract for P
 */
contract PProxy is ERC1967Proxy {

    bytes32 private constant PROXY_NAME = keccak256("PProxy");

    constructor(address logic, bytes memory data) ERC1967Proxy(logic, data) { }

}
