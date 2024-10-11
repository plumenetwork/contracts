pragma solidity ^0.8.25;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { ComponentToken } from "../ComponentToken.sol";

/// @notice Example of an interface for the Nest Staking contract
interface IAggregateToken {

    /// @notice Notify the Nest Staking contract that a buy has been executed
    function notifyBuy(
        IERC20 currencyToken,
        IERC20 componentToken,
        uint256 currencyTokenAmount,
        uint256 componentTokenAmount
    ) external;
    /// @notice Notify the Nest Staking contract that a sell has been executed
    function notifySell(
        IERC20 currencyToken,
        IERC20 componentToken,
        uint256 currencyTokenAmount,
        uint256 componentTokenAmount
    ) external;

}

/// @notice Example of an interface for the external contract that manages the external asset
interface IExternalContract {

    /// @notice Notify the external contract that a buy has been requested
    function requestBuy(uint256 currencyTokenAmount, uint256 requestId) external;
    /// @notice Notify the external contract that a sell has been requested
    function requestSell(uint256 componentTokenAmount, uint256 requestId) external;

}

/**
 * @title DinariToken
 * @author Jake Timothy, Eugene Y. Q. Shen
 * @notice Implementation of the abstract ComponentToken that interfaces with external assets.
 */
contract DinariToken is ComponentToken {

    // Storage

    /// @custom:storage-location erc7201:plume.storage.DinariToken
    struct DinariTokenStorage {
        /// @dev Address of the Nest Staking contract
        IAggregateToken nestStakingContract;
        /// @dev Address of the external contract that manages the external asset
        IExternalContract externalContract;
        /// @dev Mapping from request IDs to external request UUIDs
        mapping(uint256 requestId => bytes16 externalUuid) requestMap;
    }

    // keccak256(abi.encode(uint256(keccak256("plume.storage.DinariToken")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant DINARI_TOKEN_STORAGE_LOCATION =
        0x8a42d16a5f4a9dd4fa20afc7735f15e9454454557ef7cacfda35654781bd3100;

    function _getDinariTokenStorage() private pure returns (DinariTokenStorage storage $) {
        assembly {
            $.slot := DINARI_TOKEN_STORAGE_LOCATION
        }
    }

    // Errors

    /**
     * @notice Indicates a failure because the caller is not the authorized caller
     * @param invalidCaller Address of the caller that is not the authorized caller
     * @param caller Address of the authorized caller
     */
    error Unauthorized(address invalidCaller, address caller);

    // Initializer

    /**
     * @notice Prevent the implementation contract from being initialized or reinitialized
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the DinariToken
     * @param owner Address of the owner of the DinariToken
     * @param name Name of the DinariToken
     * @param symbol Symbol of the DinariToken
     * @param currencyToken CurrencyToken used to mint and burn the DinariToken
     * @param decimals_ Number of decimals of the DinariToken
     * @param nestStakingContract Address of the Nest Staking contract
     * @param externalContract Address of the external contract that manages the external asset
     */
    function initialize(
        address owner,
        string memory name,
        string memory symbol,
        IERC20 currencyToken,
        uint8 decimals_,
        IAggregateToken nestStakingContract,
        IExternalContract externalContract
    ) public initializer {
        super.initialize(owner, name, symbol, currencyToken, decimals_);
        DinariTokenStorage storage $ = _getDinariTokenStorage();
        $.nestStakingContract = nestStakingContract;
        $.externalContract = externalContract;
    }

    // Override Functions

    /**
     * @notice Submit a request to send currencyTokenAmount of CurrencyToken to buy ComponentToken
     * @param currencyTokenAmount Amount of CurrencyToken to send
     * @return requestId Unique identifier for the buy request
     */
    function requestBuy(uint256 currencyTokenAmount) public override(ComponentToken) returns (uint256 requestId) {
        DinariTokenStorage storage $ = _getDinariTokenStorage();
        if (msg.sender != address($.nestStakingContract)) {
            revert Unauthorized(msg.sender, address($.nestStakingContract));
        }
        requestId = super.requestBuy(currencyTokenAmount);
        $.externalContract.requestBuy(currencyTokenAmount, requestId);
    }

    /**
     * @notice Submit a request to send componentTokenAmount of ComponentToken to sell for CurrencyToken
     * @param componentTokenAmount Amount of ComponentToken to send
     * @return requestId Unique identifier for the sell request
     */
    function requestSell(uint256 componentTokenAmount) public override(ComponentToken) returns (uint256 requestId) {
        DinariTokenStorage storage $ = _getDinariTokenStorage();
        if (msg.sender != address($.nestStakingContract)) {
            revert Unauthorized(msg.sender, address($.nestStakingContract));
        }
        requestId = super.requestSell(componentTokenAmount);
        $.externalContract.requestSell(componentTokenAmount, requestId);
    }

    /**
     * @notice Executes a request to buy ComponentToken with CurrencyToken
     * @param requestor Address of the user or smart contract that requested the buy
     * @param requestId Unique identifier for the request
     * @param currencyTokenAmount Amount of CurrencyToken to send
     * @param componentTokenAmount Amount of ComponentToken to receive
     */
    function executeBuy(
        address requestor,
        uint256 requestId,
        uint256 currencyTokenAmount,
        uint256 componentTokenAmount
    ) public override(ComponentToken) {
        DinariTokenStorage storage $ = _getDinariTokenStorage();
        if (msg.sender != address($.nestStakingContract)) {
            revert Unauthorized(requestor, address($.nestStakingContract));
        }
        if (msg.sender != address($.externalContract)) {
            revert Unauthorized(msg.sender, address($.externalContract));
        }
        super.executeBuy(address($.nestStakingContract), requestId, currencyTokenAmount, componentTokenAmount);
        $.nestStakingContract.notifyBuy(
            _getComponentTokenStorage().currencyToken, this, currencyTokenAmount, componentTokenAmount
        );
    }

    /**
     * @notice Executes a request to sell ComponentToken for CurrencyToken
     * @param requestor Address of the user or smart contract that requested the sell
     * @param requestId Unique identifier for the request
     * @param currencyTokenAmount Amount of CurrencyToken to receive
     * @param componentTokenAmount Amount of ComponentToken to send
     */
    function executeSell(
        address requestor,
        uint256 requestId,
        uint256 currencyTokenAmount,
        uint256 componentTokenAmount
    ) public override(ComponentToken) {
        DinariTokenStorage storage $ = _getDinariTokenStorage();
        if (requestor != address($.nestStakingContract)) {
            revert Unauthorized(requestor, address($.nestStakingContract));
        }
        if (msg.sender != address($.externalContract)) {
            revert Unauthorized(msg.sender, address($.externalContract));
        }
        super.executeSell(address($.nestStakingContract), requestId, currencyTokenAmount, componentTokenAmount);
        $.nestStakingContract.notifySell(
            _getComponentTokenStorage().currencyToken, this, currencyTokenAmount, componentTokenAmount
        );
    }

    // Admin Functions

    function distributeYield(address user, uint256 amount) external {
        DinariTokenStorage storage $ = _getDinariTokenStorage();
        if (msg.sender != address($.nestStakingContract)) {
            revert Unauthorized(msg.sender, address($.nestStakingContract));
        }

        ComponentTokenStorage storage cs = _getComponentTokenStorage();
        cs.currencyToken.transfer(user, amount);
        cs.yieldAccrued[user] += amount;
    }

}
