pragma solidity ^0.8.25;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { ComponentToken } from "../ComponentToken.sol";
import { IAggregateToken } from "../interfaces/IAggregateToken.sol";
import { IOrderProcessor } from "./external/IOrderProcessor.sol";

/**
 * @title DinariAdapterToken
 * @author Jake Timothy, Eugene Y. Q. Shen
 * @notice Implementation of the abstract ComponentToken that interfaces with external assets.
 * @dev Assets is USDC
 */
contract DinariAdapterToken is ComponentToken {

    // Storage

    /// @custom:storage-location erc7201:plume.storage.DinariAdapterToken
    struct DinariAdapterTokenStorage {
        /// @dev dShare token underlying component token
        address dshareToken;
        /// @dev Wrapped dShare token underlying component token
        address wrappedDshareToken;
        /// @dev Address of the Nest Staking contract
        address nestStakingContract;
        /// @dev Address of the dShares order contract
        IOrderProcessor externalOrderContract;
        /// @dev Mapping from request IDs to external request IDs
        mapping(uint256 requestId => uint256 externalId) requestMap;
        //
        mapping(uint256 externalId => uint256 amountIn) adjustedRequestAmounts;
    }

    // keccak256(abi.encode(uint256(keccak256("plume.storage.DinariAdapterToken")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant DINARI_ADAPTER_TOKEN_STORAGE_LOCATION =
        0x2a49a1f589de6263f42d4846b2f178279aaa9b9efbd070fd2367cbda9b826400;

    function _getDinariAdapterTokenStorage() private pure returns (DinariAdapterTokenStorage storage $) {
        assembly {
            $.slot := DINARI_ADAPTER_TOKEN_STORAGE_LOCATION
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
     * @notice Initialize the DinariAdapterToken
     * @param owner Address of the owner of the DinariAdapterToken
     * @param name Name of the DinariAdapterToken
     * @param symbol Symbol of the DinariAdapterToken
     * @param currencyToken CurrencyToken used to mint and burn the DinariAdapterToken
     * @param dshareToken dShare token underlying component token
     * @param decimals_ Number of decimals of the DinariAdapterToken
     * @param nestStakingContract Address of the Nest Staking contract
     * @param externalOrderContract Address of the dShares order contract
     */
    function initialize(
        address owner,
        string memory name,
        string memory symbol,
        address currencyToken,
        address dshareToken,
        address wrappedDshareToken,
        uint8 decimals_,
        address nestStakingContract,
        address externalOrderContract
    ) public initializer {
        super.initialize(owner, name, symbol, IERC20(currencyToken), decimals_);
        DinariAdapterTokenStorage storage $ = _getDinariAdapterTokenStorage();
        $.dshareToken = dshareToken;
        $.wrappedDshareToken = wrappedDshareToken;
        $.nestStakingContract = nestStakingContract;
        $.externalOrderContract = IOrderProcessor(externalOrderContract);
    }

    // Override Functions

    /// @inheritdoc IERC4626
    function convertToShares(uint256 assets) public view override(ComponentToken) returns (uint256 shares) {
        // Apply dshare price and wrapped conversion rate
        DinariAdapterTokenStorage storage $ = _getDinariAdapterTokenStorage();
        IOrderProcessor orderContract = $.externalOrderContract;
        address paymentToken = _getComponentTokenStorage().currencyToken;
        uint256 fees = orderContract.totalStandardFee(false, paymentToken, assets);
        IOrderProcessor.PricePoint memory price = orderContract.latestFillPrice($.dshareToken, paymentToken);
        return IERC4626($.wrappedDshareToken).convertToShares(((assets - fees) * price.price) / 1 ether);
    }

    /// @inheritdoc IERC4626
    function convertToAssets(uint256 shares) public view override(ComponentToken) returns (uint256 assets) {
        // Apply wrapped conversion rate and dshare price, subtract fees
        DinariAdapterTokenStorage storage $ = _getDinariAdapterTokenStorage();
        IOrderProcessor orderContract = $.externalOrderContract;
        address paymentToken = _getComponentTokenStorage().currencyToken;
        address dshareToken = $.dshareToken;
        IOrderProcessor.PricePoint memory price = orderContract.latestFillPrice(dshareToken, paymentToken);
        uint256 dshares = IERC4626($.wrappedDshareToken).convertToAssets(shares);
        // Round down to nearest supported decimal
        uint256 precisionReductionFactor = 10 ** orderContract.orderDecimalReduction(dshareToken);
        uint256 proceeds = ((dshares / precisionReductionFactor) * precisionReductionFactor * 1 ether) / price.price;
        uint256 fees = orderContract.totalStandardFee(true, paymentToken, proceeds);
        return proceeds - fees;
    }

    /// @inheritdoc IComponentToken
    function requestDeposit(
        uint256 assets,
        address controller,
        address owner
    ) public override(ComponentToken) returns (uint256 requestId) {
        DinariAdapterTokenStorage storage $ = _getDinariAdapterTokenStorage();
        address nestStakingContract = $.nestStakingContract;
        if (msg.sender != nestStakingContract) {
            revert Unauthorized(msg.sender, nestStakingContract);
        }
        requestId = super.requestBuy(assets);

        IOrderProcessor orderContract = $.externalOrderContract;
        address paymentToken = _getComponentTokenStorage().currencyToken;
        uint256 addedFees = orderContract.totalStandardFee(false, paymentToken, assets);
        // TODO: make more precise? This does not spend all money, same logic used in convertToShares
        uint256 paymentTokenQuantity = assets - addedFees;

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
        uint256 orderId = $.externalOrderContract.createOrderStandardFees(order);
        $.requestMap[requestId] = orderId;
        $.adjustedRequestAmounts[orderId] = paymentTokenQuantity;
    }

    function notifyBuy(uint256 externalId) public {
        // Restrict caller?
        DinariAdapterTokenStorage storage $ = _getDinariAdapterTokenStorage();

        IOrderProcessor orderContract = $.externalOrderContract;
        if (orderContract.getOrderStatus(externalId) != IOrderProcessor.OrderStatus.FULFILLED) {
            revert OrderNotFilled();
        }

        uint256 proceeds = orderContract.getReceivedAmount(externalId);
        address nestStakingContract = $.nestStakingContract;
        // TODO: handle partial fee refunds, verify assets amount
        uint256 totalSpent = $.adjustedRequestAmounts[externalId] + orderContract.getFeesTaken(externalId);
        super.notifyDeposit(totalSpent, proceeds, nestStakingContract);
    }

    /// @inheritdoc IComponentToken
    function deposit(
        uint256 assets,
        address receiver,
        address controller
    ) public override(ComponentToken) returns (uint256 shares) {
        AdapterTokenStorage storage $ = _getAdapterTokenStorage();
        if (msg.sender != address($.externalContract)) {
            revert Unauthorized(msg.sender, address($.externalContract));
        }
        if (receiver != address($.nestStakingContract)) {
            revert Unauthorized(receiver, address($.nestStakingContract));
        }
        return super.deposit(assets, receiver, controller);
    }

    /// @inheritdoc IComponentToken
    function requestRedeem(
        uint256 shares,
        address controller,
        address owner
    ) public override(ComponentToken) returns (uint256 requestId) {
        DinariAdapterTokenStorage storage $ = _getDinariAdapterTokenStorage();
        address nestStakingContract = $.nestStakingContract;
        if (msg.sender != nestStakingContract) {
            revert Unauthorized(msg.sender, nestStakingContract);
        }
        // TODO: should this be called with orderAmount instead?
        requestId = super.requestSell(shares);

        // Unwrap dshares
        address wrappedDshareToken = $.wrappedDshareToken;
        uint256 dshares = IERC4626(wrappedDshareToken).redeem(shares);
        // Round down to nearest supported decimal
        address dshareToken = $.dshareToken;
        uint256 precisionReductionFactor = 10 ** orderContract.orderDecimalReduction(dshareToken);
        uint256 orderAmount = (dshares / precisionReductionFactor) * precisionReductionFactor;
        // Rewrap dust
        uint256 dshareDust = dshares - orderAmount;
        if (dshareDust > 0) {
            IERC4626(wrappedDshareToken).deposit(dshareDust, address(this));
        }
        // Approve dshares
        IOrderProcessor orderContract = $.externalOrderContract;
        IERC20(dshareToken).approve(address(orderContract), orderAmount);
        // Sell
        IOrderProcessor.Order memory order = IOrderProcessor.Order({
            requestTimestamp: block.timestamp,
            recipient: address(this),
            assetToken: dshareToken,
            paymentToken: _getComponentTokenStorage().currencyToken,
            sell: true,
            orderType: IOrderProcessor.OrderType.MARKET,
            assetTokenQuantity: orderAmount,
            paymentTokenQuantity: 0,
            price: 0,
            tif: IOrderProcessor.TIF.DAY
        });
        uint256 orderId = orderContract.createOrderStandardFees(order);
        $.requestMap[requestId] = orderId;
        $.adjustedRequestAmounts[orderId] = shares;
    }

    function notifySell(uint256 externalId) public {
        // Restrict caller?
        DinariAdapterTokenStorage storage $ = _getDinariAdapterTokenStorage();

        IOrderProcessor orderContract = $.externalOrderContract;
        uint256 externalId = $.requestMap[requestId];
        if (orderContract.getOrderStatus(externalId) != IOrderProcessor.OrderStatus.FULFILLED) {
            revert OrderNotFilled();
        }

        uint256 proceeds = orderContract.getReceivedAmount(externalId);
        address nestStakingContract = $.nestStakingContract;
        super.notifyRedeem(proceeds, $.adjustedRequestAmounts[externalId], nestStakingContract);
    }

    /// @inheritdoc IComponentToken
    function redeem(
        uint256 shares,
        address receiver,
        address controller
    ) public override(ComponentToken) returns (uint256 assets) {
        AdapterTokenStorage storage $ = _getAdapterTokenStorage();
        if (msg.sender != address($.externalContract)) {
            revert Unauthorized(msg.sender, address($.externalContract));
        }
        if (receiver != address($.nestStakingContract)) {
            revert Unauthorized(receiver, address($.nestStakingContract));
        }
        return super.redeem(shares, receiver, controller);
    }

}
