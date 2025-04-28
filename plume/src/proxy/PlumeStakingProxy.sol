// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title PlumeStakingProxy
 * @author Eugene Y. Q. Shen, Alp  Guneysel
 * @notice Proxy contract for PlumeStaking
 */
contract PlumeStakingProxy is ERC1967Proxy {

    /// @notice Name of the proxy, used to ensure each named proxy has unique bytecode
    bytes32 public constant PROXY_NAME = keccak256("PlumeStakingProxy");

    constructor(address logic, bytes memory data) ERC1967Proxy(logic, data) { }

    // Allow the proxy to receive ETH.
    receive() external payable { }

}
