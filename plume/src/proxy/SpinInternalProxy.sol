// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title SpinInternalProxy
 * @author Eugene Y. Q. Shen
 * @notice Proxy contract for Faucet
 */
contract SpinInternalProxy is ERC1967Proxy {

    /// @notice Indicates a failure because transferring ETH to the proxy is unsupported
    error ETHTransferUnsupported();

    /// @notice Name of the proxy, used to ensure each named proxy has unique bytecode
    bytes32 public constant PROXY_NAME = keccak256("SpinInternalProxy");

    constructor(address logic, bytes memory data) ERC1967Proxy(logic, data) { }

    receive() external payable { }

}
