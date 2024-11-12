// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import { AggregateToken } from "./AggregateToken.sol";
import { IAggregateToken } from "./interfaces/IAggregateToken.sol";
import { IComponentToken } from "./interfaces/IAggregateToken.sol";
import { AggregateTokenProxy } from "./proxy/AggregateTokenProxy.sol";

/**
 * @title NestStaking
 * @author Eugene Y. Q. Shen
 * @notice Contract for creating AggregateTokens
 */
contract NestStaking is Initializable, AccessControlUpgradeable, UUPSUpgradeable {

    // Storage

    /// @custom:storage-location erc7201:plume.storage.NestStaking
    struct NestStakingStorage {
        /// @dev List of featured AggregateTokens
        IAggregateToken[] featuredList;
        /// @dev Mapping of featured AggregateTokens
        mapping(IAggregateToken aggregateToken => bool featured) isFeatured;
    }

    // keccak256(abi.encode(uint256(keccak256("plume.storage.NestStaking")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant NEST_STAKING_STORAGE_LOCATION =
        0x0f4543a2739af6ee2144908062c013c82b6c29235b82220f7f0fb21e08428f00;

    function _getNestStakingStorage() private pure returns (NestStakingStorage storage $) {
        assembly {
            $.slot := NEST_STAKING_STORAGE_LOCATION
        }
    }

    // Constants

    /// @notice Role for the admin of the Nest Staking protocol
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    /// @notice Role for the upgrader of the Nest Staking protocol
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    // Events

    /**
     * @notice Emitted when a new AggregateToken is created
     * @param owner Address of the owner of the new AggregateToken
     * @param aggregateToken AggregateToken that is newly created
     */
    event TokenCreated(address indexed owner, IAggregateToken aggregateToken);

    /**
     * @notice Emitted when an AggregateToken is featured
     * @param aggregateToken AggregateToken that is featured
     */
    event TokenFeatured(IAggregateToken aggregateToken);

    /**
     * @notice Emitted when an AggregateToken is unfeatured
     * @param aggregateToken AggregateToken that is unfeatured
     */
    event TokenUnfeatured(IAggregateToken aggregateToken);

    // Errors

    /**
     * @notice Indicates a failure because the AggregateToken is already featured
     * @param aggregateToken AggregateToken that is already featured
     */
    error TokenAlreadyFeatured(IAggregateToken aggregateToken);

    /**
     * @notice Indicates a failure because the AggregateToken is not featured
     * @param aggregateToken AggregateToken that is not featured
     */
    error TokenNotFeatured(IAggregateToken aggregateToken);

    // Initializer

    /**
     * @notice Prevent the implementation contract from being initialized or reinitialized
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the Nest Staking protocol
     * @param owner Address of the owner of Nest Staking
     */
    function initialize(
        address owner
    ) public initializer {
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
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(UPGRADER_ROLE) { }

    // Admin Functions

    /**
     * @notice Add an AggregateToken to the featured list
     * @dev Only the owner can call this function
     * @param aggregateToken AggregateToken to be featured
     */
    function featureToken(
        IAggregateToken aggregateToken
    ) external onlyRole(ADMIN_ROLE) {
        NestStakingStorage storage $ = _getNestStakingStorage();
        if ($.isFeatured[aggregateToken]) {
            revert TokenAlreadyFeatured(aggregateToken);
        }
        $.featuredList.push(aggregateToken);
        $.isFeatured[aggregateToken] = true;
        emit TokenFeatured(aggregateToken);
    }

    /**
     * @notice Remove an AggregateToken from the featured list
     * @dev Only the owner can call this function
     * @param aggregateToken AggregateToken to be unfeatured
     */
    function unfeatureToken(
        IAggregateToken aggregateToken
    ) external onlyRole(ADMIN_ROLE) {
        NestStakingStorage storage $ = _getNestStakingStorage();
        if (!$.isFeatured[aggregateToken]) {
            revert TokenNotFeatured(aggregateToken);
        }
        IAggregateToken[] storage featuredList = $.featuredList;
        uint256 length = featuredList.length;
        for (uint256 i = 0; i < length; ++i) {
            if (featuredList[i] == aggregateToken) {
                featuredList[i] = featuredList[length - 1];
                featuredList.pop();
                break;
            }
        }
        $.isFeatured[aggregateToken] = false;
        emit TokenUnfeatured(aggregateToken);
    }

    // User Functions

    /**
     * @notice Create a new AggregateToken
     * @param owner Address of the owner of the AggregateToken
     * @param name Name of the AggregateToken
     * @param symbol Symbol of the AggregateToken
     * @param currencyToken CurrencyToken used to mint and burn the AggregateToken
     * @param decimals_ Number of decimals of the AggregateToken
     * @param askPrice Price at which users can buy the AggregateToken using CurrencyToken, times the base
     * @param bidPrice Price at which users can sell the AggregateToken to receive CurrencyToken, times the base
     * @param tokenURI URI of the AggregateToken metadata
     * @return aggregateToken AggregateToken that is newly created
     */
    function createAggregateToken(
        address owner,
        string memory name,
        string memory symbol,
        IComponentToken currencyToken,
        uint8 decimals_,
        uint256 askPrice,
        uint256 bidPrice,
        string memory tokenURI
    ) public returns (IAggregateToken aggregateToken) {
        NestStakingStorage storage $ = _getNestStakingStorage();

        IAggregateToken aggregateTokenImplementation = new AggregateToken();
        AggregateTokenProxy aggregateTokenProxy = new AggregateTokenProxy(
            address(aggregateTokenImplementation),
            abi.encodeCall(
                AggregateToken.initialize, (owner, name, symbol, currencyToken, askPrice, bidPrice)
            )
        );



        aggregateToken = IAggregateToken(address(aggregateTokenProxy));
        $.featuredList.push(aggregateToken);
        $.isFeatured[aggregateToken] = true;
        emit TokenFeatured(aggregateToken);
        emit TokenCreated(msg.sender, aggregateToken);
    }

    // Getter View Functions

    /// @notice List of featured AggregateTokens
    function getFeaturedList() external view returns (IAggregateToken[] memory) {
        return _getNestStakingStorage().featuredList;
    }

    /**
     * @notice Check if the aggregateToken is featured
     * @param aggregateToken AggregateToken to check
     * @return featured Boolean indicating if the AggregateToken is featured
     */
    function isFeatured(
        IAggregateToken aggregateToken
    ) external view returns (bool featured) {
        return _getNestStakingStorage().isFeatured[aggregateToken];
    }

}
