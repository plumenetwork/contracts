// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title YieldTokenProxy
 * @author Eugene Y. Q. Shen, Alp Guneysel
 * @notice Proxy contract for YieldToken
 */
contract YieldTokenProxy is ERC1967Proxy {

    /// @notice Indicates a failure because transferring ETH to the proxy is unsupported
    error ETHTransferUnsupported();

    /// @notice Name of the proxy, used to ensure each named proxy has unique bytecode
    bytes32 public constant PROXY_NAME = keccak256("YieldTokenProxy");

    constructor(address logic, bytes memory data) ERC1967Proxy(logic, data) { }

    /// @dev Fallback function to silence compiler warnings
    receive() external payable {
        revert ETHTransferUnsupported();
    }

}
