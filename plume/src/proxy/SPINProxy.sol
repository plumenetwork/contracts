// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title SpinProxy
 * @author Eugene Y. Q. Shen, Alp Guneysel
 * @notice Proxy contract for Faucet
 */
contract SpinProxy is ERC1967Proxy {

    /// @notice Name of the proxy, used to ensure each named proxy has unique bytecode
    bytes32 public constant PROXY_NAME = keccak256("SpinProxy");

    constructor(address logic, bytes memory data) ERC1967Proxy(logic, data) { }

    /// @dev Fallback function to allow receiving Ether.
    receive() external payable { }

}
