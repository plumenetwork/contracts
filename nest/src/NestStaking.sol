// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import { AggregateToken } from "./AggregateToken.sol";
import { IAggregateToken } from "./interfaces/IAggregateToken.sol";
import { AggregateTokenProxy } from "./proxy/AggregateTokenProxy.sol";

/**
 * @title NestStaking
 * @author Eugene Y. Q. Shen
 * @notice Contract for creating AggregateTokens
 */
contract NestStaking is Initializable, AccessControlUpgradeable, UUPSUpgradeable {

    // Constants

    /// @notice Role for the upgrader of the AggregateToken
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADE_ROLE");

    // Events

    /**
     * @notice Emitted when a new AggregateToken is created
     * @param owner Address of the owner of the AggregateToken
     * @param aggregateTokenProxy Address of the proxy of the new AggregateToken
     */
    event TokenCreated(address indexed owner, AggregateTokenProxy indexed aggregateTokenProxy);

    // Initializer

    /**
     * @notice Initialize the AggregateToken
     * @param owner Address of the owner of the AggregateToken
     */
    function initialize(address owner) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, owner);
        _grantRole(UPGRADER_ROLE, owner);
    }

    // Override Functions

    /**
     * @notice Revert when `msg.sender` is not authorized to upgrade the contract
     * @param newImplementation Address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) { }

    // User Functions

    /**
     * @notice Create a new AggregateToken
     * @param owner Address of the owner of the AggregateToken
     * @param name Name of the AggregateToken
     * @param symbol Symbol of the AggregateToken
     * @param currencyAddress Address of the CurrencyToken used to mint and burn the AggregateToken
     * @param decimals_ Number of decimals of the AggregateToken
     * @param askPrice Price at which users can buy the AggregateToken using CurrencyToken, times the base
     * @param bidPrice Price at which users can sell the AggregateToken to receive CurrencyToken, times the base
     * @param tokenURI URI of the AggregateToken metadata
     * @return aggregateTokenProxyAddress Address of the new AggregateTokenProxy
     */
    function createAggregateToken(
        address owner,
        string memory name,
        string memory symbol,
        address currencyAddress,
        uint8 decimals_,
        uint256 askPrice,
        uint256 bidPrice,
        string memory tokenURI
    ) public returns (address aggregateTokenProxyAddress) {
        AggregateToken aggregateToken = new AggregateToken();
        AggregateTokenProxy aggregateTokenProxy = new AggregateTokenProxy(
            address(aggregateToken),
            abi.encodeCall(
                AggregateToken.initialize,
                (owner, name, symbol, currencyAddress, decimals_, askPrice, bidPrice, tokenURI)
            )
        );

        emit TokenCreated(msg.sender, aggregateTokenProxy);

        return (address(aggregateTokenProxy));
    }

}
