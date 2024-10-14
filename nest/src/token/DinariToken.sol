pragma solidity ^0.8.25;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { ComponentToken } from "../ComponentToken.sol";
import { IOrderProcessor } from "./external/IOrderProcessor.sol";

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

/**
 * @title DinariToken
 * @author Jake Timothy, Eugene Y. Q. Shen
 * @notice Implementation of the abstract ComponentToken that interfaces with external assets.
 */
contract DinariToken is ComponentToken {
    // TODO: name - NestDinariVault?

    // Storage

    /// @custom:storage-location erc7201:plume.storage.DinariToken
    struct DinariTokenStorage {
        /// @dev dShare token underlying component token
        address dshareToken;
        /// @dev Address of the Nest Staking contract
        address nestStakingContract;
        /// @dev Address of the dShares order contract
        IOrderProcessor externalOrderContract;
        /// @dev Mapping from request IDs to external request IDs
        mapping(uint256 requestId => uint256 externalId) requestMap;
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

    error OrderNotFilled();

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
     * @param dshareToken dShare token underlying component token
     * @param decimals_ Number of decimals of the DinariToken
     * @param nestStakingContract Address of the Nest Staking contract
     * @param externalOrderContract Address of the dShares order contract
     */
    function initialize(
        address owner,
        string memory name,
        string memory symbol,
        address currencyToken,
        address dshareToken,
        uint8 decimals_,
        address nestStakingContract,
        address externalOrderContract
    ) public initializer {
        super.initialize(owner, name, symbol, IERC20(currencyToken), decimals_);
        DinariTokenStorage storage $ = _getDinariTokenStorage();
        $.dshareToken = dshareToken;
        $.nestStakingContract = nestStakingContract;
        $.externalOrderContract = IOrderProcessor(externalOrderContract);
    }

    // Override Functions

    /**
     * @notice Submit a request to send currencyTokenAmount of CurrencyToken to buy ComponentToken
     * @param currencyTokenAmount Amount of CurrencyToken to send
     * @return requestId Unique identifier for the buy request
     */
    function requestBuy(uint256 currencyTokenAmount) public override(ComponentToken) returns (uint256 requestId) {
        DinariTokenStorage storage $ = _getDinariTokenStorage();
        address nestStakingContract = $.nestStakingContract;
        if (msg.sender != nestStakingContract) {
            revert Unauthorized(msg.sender, nestStakingContract);
        }
        requestId = super.requestBuy(currencyTokenAmount);

        IOrderProcessor orderContract = $.externalOrderContract;
        address paymentToken = _getComponentTokenStorage().currencyToken;
        uint256 addedFees = orderContract.totalStandardFee(false, paymentToken, currencyTokenAmount);
        // Does not spend all currencyTokenAmount, collect unspent in executeBuy if needed
        uint256 paymentTokenQuantity = currencyTokenAmount - addedFees;
        // TODO: round down to nearest supported decimal

        IOrderProcessor.Order memory order = IOrderProcessor.Order({
            requestTimestamp: block.timestamp,
            recipient: address(this),
            assetToken: $.dshareToken,
            paymentToken: paymentToken,
            sell: false,
            orderType: IOrderProcessor.OrderType.MARKET,
            assetTokenQuantity: 0,
            paymentTokenQuantity: paymentTokenQuantity,
            price: 0,
            tif: IOrderProcessor.TIF.DAY
        });
        $.requestMap[requestId] = $.externalOrderContract.createOrderStandardFees(order);
    }

    /**
     * @notice Submit a request to send componentTokenAmount of ComponentToken to sell for CurrencyToken
     * @param componentTokenAmount Amount of ComponentToken to send
     * @return requestId Unique identifier for the sell request
     */
    function requestSell(uint256 componentTokenAmount) public override(ComponentToken) returns (uint256 requestId) {
        DinariTokenStorage storage $ = _getDinariTokenStorage();
        address nestStakingContract = $.nestStakingContract;
        if (msg.sender != nestStakingContract) {
            revert Unauthorized(msg.sender, nestStakingContract);
        }
        requestId = super.requestSell(componentTokenAmount);

        IOrderProcessor.Order memory order = IOrderProcessor.Order({
            requestTimestamp: block.timestamp,
            recipient: address(this),
            assetToken: $.dshareToken,
            paymentToken: _getComponentTokenStorage().currencyToken,
            sell: true,
            orderType: IOrderProcessor.OrderType.MARKET,
            assetTokenQuantity: componentTokenAmount,
            paymentTokenQuantity: 0,
            price: 0,
            tif: IOrderProcessor.TIF.DAY
        });
        $.requestMap[requestId] = $.externalOrderContract.createOrderStandardFees(order);
    }

    /**
     * @notice Executes a request to buy ComponentToken with CurrencyToken
     * @param requestor Address of the user or smart contract that requested the buy
     * @param requestId Unique identifier for the request
     * @param currencyTokenAmount Amount of CurrencyToken to send
     * @param componentTokenAmount Amount of ComponentToken to receive
     * @dev Dshare order fulfillment does not spend all tokens; called by external keeper
     */
    function executeBuy(
        address ,
        uint256 requestId,
        uint256 currencyTokenAmount,
        uint256 
    ) public override(ComponentToken) {
        // Restrict caller?
        DinariTokenStorage storage $ = _getDinariTokenStorage();

        IOrderProcessor orderContract = $.externalOrderContract;
        uint256 externalId = $.requestMap[requestId];
        if (orderContract.getOrderStatus(externalId) != IOrderProcessor.OrderStatus.FULFILLED) revert OrderNotFilled();

        // TODO: handle partial refunds
        uint256 proceeds = orderContract.getReceivedAmount(externalId);
        address nestStakingContract = $.nestStakingContract;
        super.executeBuy(nestStakingContract, requestId, currencyTokenAmount, proceeds);
        IAggregateToken(nestStakingContract).notifyBuy(
            _getComponentTokenStorage().currencyToken, this, currencyTokenAmount, proceeds
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
        address ,
        uint256 requestId,
        uint256 ,
        uint256 componentTokenAmount
    ) public override(ComponentToken) {
        // Restrict caller?
        DinariTokenStorage storage $ = _getDinariTokenStorage();

        IOrderProcessor orderContract = $.externalOrderContract;
        uint256 externalId = $.requestMap[requestId];
        if (orderContract.getOrderStatus(externalId) != IOrderProcessor.OrderStatus.FULFILLED) revert OrderNotFilled();

        uint256 proceeds = orderContract.getReceivedAmount(externalId);
        address nestStakingContract = $.nestStakingContract;
        super.executeSell(nestStakingContract, requestId, proceeds, componentTokenAmount);
        IAggregateToken(nestStakingContract).notifySell(
            _getComponentTokenStorage().currencyToken, this, proceeds, componentTokenAmount
        );
    }

    // Admin Functions

    function distributeYield(address user, uint256 amount) external {
        DinariTokenStorage storage $ = _getDinariTokenStorage();
        address nestStakingContract = $.nestStakingContract;
        if (msg.sender != nestStakingContract) {
            revert Unauthorized(msg.sender, nestStakingContract);
        }

        ComponentTokenStorage storage cs = _getComponentTokenStorage();
        cs.currencyToken.transfer(user, amount);
        cs.yieldAccrued[user] += amount;
    }

}
