// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title PlumePreStaking
 * @author Eugene Y. Q. Shen
 * @notice Proxy contract for RWAStaking
 */
contract BoringVaultPredepositProxy is ERC1967Proxy {

    /// @notice Name of the proxy, used to ensure each named proxy has unique bytecode
    bytes32 public constant PROXY_NAME = keccak256("BoringVaultPredepositProxy");

    constructor(address logic, bytes memory data) ERC1967Proxy(logic, data) { }

    /// @dev Fallback function to silence compiler warnings
    function test() public virtual { }

    /// @dev Allow receiving ETH for bridge fees
    receive() external payable { }

}
