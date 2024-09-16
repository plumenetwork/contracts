// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title NestStakingProxy
 * @author Eugene Y. Q. Shen
 * @notice Proxy contract for the NestStakingProxy
 */
contract NestStakingProxy is ERC1967Proxy {

    constructor(address logic, bytes memory data) ERC1967Proxy(logic, data) { }

}
