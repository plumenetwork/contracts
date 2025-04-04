// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title RoycoMarketHelperProxy
 * @dev This contract extends ERC1967Proxy for RoycoNestMarketHelper.
 * It provides a custom proxy that is specifically for the RoycoNestMarketHelper contract.
 * It follows the same pattern as ERC1967Proxy but can be extended for custom functionality.
 */
contract RoycoMarketHelperProxy is ERC1967Proxy {

    bytes32 public constant PROXY_NAME = keccak256("RoycoMarketHelperProxy");

    /**
     * @dev Initializes the upgradeable proxy with an initial implementation and data.
     *
     * @param implementation Address of the initial implementation.
     * @param _data Data to send as msg.data to the implementation to initialize the proxied contract.
     * It should include the signature and the parameters of the function to be called, as described in
     * https://solidity.readthedocs.io/en/v0.4.24/abi-spec.html#function-selector-and-argument-encoding.
     * This parameter is optional, if no data is given the initialization call to proxied contract will be skipped.
     */
    constructor(address implementation, bytes memory _data) ERC1967Proxy(implementation, _data) { }

    /**
     * @dev Returns the current implementation address.
     * Exposed for testing and verification purposes.
     */
    function getImplementation() external view returns (address) {
        return _implementation();
    }

    receive() external payable { }

}
