// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @notice Interface for contracts processing orders for dShares
/// @author Dinari (https://github.com/dinaricrypto/sbt-contracts/blob/main/src/orders/IOrderProcessor.sol)
/// This interface provides a standard Order type and order lifecycle events
/// Orders are requested on-chain, processed off-chain, then fulfillment is submitted for on-chain settlement
interface IOrderProcessor {

    /// ------------------ Types ------------------ ///

    // Market or limit order
    enum OrderType {
        MARKET,
        LIMIT
    }

    // Time in force
    enum TIF {
        // Good until end of day
        DAY,
        // Good until cancelled
        GTC,
        // Immediate or cancel
        IOC,
        // Fill or kill
        FOK
    }

    // Order status enum
    enum OrderStatus {
        // Order has never existed
        NONE,
        // Order is active
        ACTIVE,
        // Order is completely filled
        FULFILLED,
        // Order is cancelled
        CANCELLED
    }

    struct Order {
        // Timestamp or other salt added to order hash for replay protection
        uint64 requestTimestamp;
        // Recipient of order fills
        address recipient;
        // Bridged asset token
        address assetToken;
        // Payment token
        address paymentToken;
        // Buy or sell
        bool sell;
        // Market or limit
        OrderType orderType;
        // Amount of asset token to be used for fills
        uint256 assetTokenQuantity;
        // Amount of payment token to be used for fills
        uint256 paymentTokenQuantity;
        // Price for limit orders in ether decimals
        uint256 price;
        // Time in force
        TIF tif;
    }

    struct OrderRequest {
        // Unique ID and hash of order data used to validate order details stored offchain
        uint256 orderId;
        // Signature expiration timestamp
        uint64 deadline;
    }

    struct Signature {
        // Signature expiration timestamp
        uint64 deadline;
        // Signature bytes (r, s, v)
        bytes signature;
    }

    struct FeeQuote {
        // Unique ID and hash of order data used to validate order details stored offchain
        uint256 orderId;
        // Requester of order
        address requester;
        // Fee amount in payment token
        uint256 fee;
        // Timestamp of fee quote
        uint64 timestamp;
        // Signature expiration timestamp
        uint64 deadline;
    }

    struct PricePoint {
        // Price specified with 18 decimals
        uint256 price;
        uint64 blocktime;
    }

    /// @dev Emitted order details and order ID for each order
    event OrderCreated(uint256 indexed id, address indexed requester, Order order, uint256 feesEscrowed);
    /// @dev Emitted for each fill
    event OrderFill(
        uint256 indexed id,
        address indexed paymentToken,
        address indexed assetToken,
        address requester,
        uint256 assetAmount,
        uint256 paymentAmount,
        uint256 feesTaken,
        bool sell
    );
    /// @dev Emitted when order is completely filled, terminal
    event OrderFulfilled(uint256 indexed id, address indexed requester);
    /// @dev Emitted when order cancellation is requested
    event CancelRequested(uint256 indexed id, address indexed requester);
    /// @dev Emitted when order is cancelled, terminal
    event OrderCancelled(uint256 indexed id, address indexed requester, string reason);

    /// ------------------ Getters ------------------ ///

    /// @notice Hash order data for validation and create unique order ID
    /// @param order Order data
    /// @dev EIP-712 typed data hash of order
    function hashOrder(
        Order calldata order
    ) external pure returns (uint256);

    /// @notice Status of a given order
    /// @param id Order ID
    function getOrderStatus(
        uint256 id
    ) external view returns (OrderStatus);

    /// @notice Get remaining order quantity to fill
    /// @param id Order ID
    function getUnfilledAmount(
        uint256 id
    ) external view returns (uint256);

    /// @notice Get received amount for an order
    /// @param id Order ID
    function getReceivedAmount(
        uint256 id
    ) external view returns (uint256);

    /// @notice Get fees in payment token escrowed for a buy order
    /// @param id Order ID
    function getFeesEscrowed(
        uint256 id
    ) external view returns (uint256);

    /// @notice Get cumulative payment token fees taken for an order
    /// @param id Order ID
    /// @dev Only valid for ACTIVE orders
    function getFeesTaken(
        uint256 id
    ) external view returns (uint256);

    /// @notice Reduces the precision allowed for the asset token quantity of an order
    /// @param token The address of the token
    function orderDecimalReduction(
        address token
    ) external view returns (uint8);

    /// @notice Get worst case fees for an order
    /// @param sell Sell order
    /// @param paymentToken Payment token for order
    /// @return flatFee Flat fee for order
    /// @return percentageFeeRate Percentage fee rate for order
    function getStandardFees(bool sell, address paymentToken) external view returns (uint256, uint24);

    /// @notice Get total standard fees for an order
    /// @param sell Sell order
    /// @param paymentToken Payment token for order
    /// @param paymentTokenQuantity Payment token quantity for order
    function totalStandardFee(
        bool sell,
        address paymentToken,
        uint256 paymentTokenQuantity
    ) external view returns (uint256);

    /// @notice Check if an account is locked from transferring tokens
    /// @param token Token to check
    /// @param account Account to check
    /// @dev Only used for payment tokens
    function isTransferLocked(address token, address account) external view returns (bool);

    /// @notice Get the latest fill price for a token pair
    /// @param assetToken Asset token
    /// @param paymentToken Payment token
    /// @dev price specified with 18 decimals
    function latestFillPrice(address assetToken, address paymentToken) external view returns (PricePoint memory);

    /// ------------------ Actions ------------------ ///

    /// @notice Lock tokens and initialize signed order
    /// @param order Order request to initialize
    /// @param orderSignature Signature and deadline for order
    /// @param feeQuote Fee quote for order
    /// @param feeQuoteSignature Signature for fee quote
    /// @return id Order id
    /// @dev Only callable by operator
    function createOrderWithSignature(
        Order calldata order,
        Signature calldata orderSignature,
        FeeQuote calldata feeQuote,
        bytes calldata feeQuoteSignature
    ) external returns (uint256);

    /// @notice Request an order
    /// @param order Order request to submit
    /// @param feeQuote Fee quote for order
    /// @param feeQuoteSignature Signature for fee quote
    /// @return id Order id
    /// @dev Emits OrderCreated event to be sent to fulfillment service (operator)
    function createOrder(
        Order calldata order,
        FeeQuote calldata feeQuote,
        bytes calldata feeQuoteSignature
    ) external returns (uint256);

    /// @notice Request an order with standard fees
    /// @param order Order request to submit
    /// @return id Order id
    /// @dev Emits OrderCreated event to be sent to fulfillment service (operator)
    function createOrderStandardFees(
        Order calldata order
    ) external returns (uint256);

    /// @notice Fill an order
    /// @param order Order request to fill
    /// @param fillAmount Amount of order token to fill
    /// @param receivedAmount Amount of received token
    /// @dev Only callable by operator
    function fillOrder(Order calldata order, uint256 fillAmount, uint256 receivedAmount, uint256 fees) external;

    /// @notice Request to cancel an order
    /// @param id Order id
    /// @dev Only callable by initial order requester
    /// @dev Emits CancelRequested event to be sent to fulfillment service (operator)
    function requestCancel(
        uint256 id
    ) external;

    /// @notice Cancel an order
    /// @param order Order request to cancel
    /// @param reason Reason for cancellation
    /// @dev Only callable by operator
    function cancelOrder(Order calldata order, string calldata reason) external;

}
