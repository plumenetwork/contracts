// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title FakeComponentTokenProxy
 * @author Eugene Y. Q. Shen
 * @notice Proxy contract for the FakeComponentToken
 */
contract FakeComponentTokenProxy is ERC1967Proxy {

    constructor(address logic, bytes memory data) ERC1967Proxy(logic, data) { }

}
