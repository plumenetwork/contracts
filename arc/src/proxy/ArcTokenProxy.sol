// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title ArcTokenProxy
 * @author Plume Network
 * @notice Proxy contract for ArcToken
 */
contract ArcTokenProxy is ERC1967Proxy {

    /// @notice Name of the proxy, used to ensure each named proxy has unique bytecode
    bytes32 public constant PROXY_NAME = keccak256("ArcTokenProxy");

    constructor(address logic, bytes memory data) ERC1967Proxy(logic, data) { }

    /// @dev Allows the proxy to receive ETH
    receive() external payable {
        // Empty function body allows receiving ETH
    }

}
