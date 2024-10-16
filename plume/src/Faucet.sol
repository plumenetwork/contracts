// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IERC20Metadata } from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ERC20Pausable } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";

/**
 * @title Faucet
 * @author Eugene Y. Q. Shen
 * @notice Contract that mints tokens to users that submit a signed message from the owner
 */
contract Faucet is Initializable, UUPSUpgradeable {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    // Storage

    /// @custom:storage-location erc7201:plume.storage.Faucet
    struct FaucetStorage {
        /// @dev Address of the owner of the Faucet
        address owner;
        /// @dev Amount of tokens to mint to each user per faucet call
        mapping(address tokenAddress => uint256 dripAmount) dripAmounts;
        /// @dev Mapping of token names to their addresses
        mapping(string tokenName => address tokenAddress) tokens;
        /// @dev True if the nonce has been used; false otherwise
        mapping(bytes32 nonce => bool used) usedNonces;
    }

    // keccak256(abi.encode(uint256(keccak256("plume.storage.Faucet")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant FAUCET_STORAGE_LOCATION =
        0xba213a20809c9d49f5b31f993c1d71bca94443a1b2f0e23907f4ad1f30c71500;

    function _getFaucetStorage() internal pure returns (FaucetStorage storage $) {
        assembly {
            $.slot := FAUCET_STORAGE_LOCATION
        }
    }

    // Constants

    /// @notice Magic constant to represent the address of the gas token on Plume
    address public constant ETH_ADDRESS = address(1);

    // Events

    /**
     * @notice Emitted when the recipient has received tokens from the faucet
     * @param recipient Address of the recipient
     * @param amount Amount of tokens received
     * @param token Name of the token received
     */
    event TokenSent(address indexed recipient, uint256 amount, string tokenName);

    /**
     * @notice Emitted when the owner withdraws tokens from the faucet
     * @param recipient Address of the recipient
     * @param amount Amount of tokens received
     * @param token Name of the token received
     */
    event Withdrawn(address indexed recipient, uint256 amount, string tokenName);

    /**
     * @notice Emitted when the owner of the faucet changes
     * @param oldOwner Address of the old owner
     * @param newOwner Address of the new owner
     */
    event OwnerChanged(address indexed oldOwner, address indexed newOwner);

    // Errors

    /// @notice Indicates a failure because the initialization parameters are invalid
    error InvalidInitialization();

    /**
     * @notice Indicates a failure because the sender is not authorized to perform the action
     * @param sender Address of the sender that is not authorized
     * @param authorizedUser Address of the authorized user who can perform the action
     */
    error Unauthorized(address sender, address authorizedUser);

    /**
     * @notice Indicates a failure because the faucet does not have enough tokens
     * @param asset Asset used to mint and burn the ComponentToken
     * @param user Address of the user who is selling the assets
     * @param assets Amount of assets required in the failed transfer
     */
    error InsufficientBalance(IERC20 asset, address user, uint256 assets);

    // Modifiers

    /// @notice Only the owner can call this function
    modifier onlyOwner() {
        if (msg.sender != _getFaucetStorage().owner) {
            revert Unauthorized(msg.sender, _getFaucetStorage().owner);
        }
        _;
    }

    // Initializer

    /**
     * @notice Prevent the implementation contract from being initialized or reinitialized
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the Faucet
     * @param owner Address of the owner of the Faucet
     * @param tokenNames Names of the tokens to add to the faucet
     * @param tokenAddresses Addresses of the tokens to add to the faucet
     */
    function initialize(
        address owner,
        string[] memory tokenNames,
        address[] memory tokenAddresses
    ) public initializer {
        if (owner == address(0) || tokenNames.length == 0 || tokenNames.length != tokenAddresses.length) {
            revert InvalidInitialization();
        }

        __UUPSUpgradeable_init();

        ComponentTokenStorage storage $ = _getFaucetStorage();
        $.owner = owner;

        bytes32 ethHash = keccak256(abi.encodePacked("ETH"));
        uint256 length = tokenNames.length;
        for (uint256 i = 0; i < length; ++i) {
            if (keccak256(bytes(tokenNames[i])) == ethHash) {
                $.tokens[tokenNames[i]] = ETH_ADDRESS;
                $.dripAmounts[ETH_ADDRESS] = 0.001 ether;
            } else {
                $.tokens[tokenNames[i]] = tokenAddresses[i];
                $.dripAmounts[tokenAddresses[i]] = 1e9; // $1000 USDT (6 decimals)
            }
        }
    }

    // Override Functions

    /**
     * @notice Revert when `msg.sender` is not authorized to upgrade the contract
     * @param newImplementation Address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override(UUPSUpgradeable) onlyOwner {}

    // Fallback Functions

    receive() external payable {}
}
