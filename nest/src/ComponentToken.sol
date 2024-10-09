// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IComponentToken } from "./interfaces/IComponentToken.sol";

/**
 * @title ComponentToken
 * @author Eugene Y. Q. Shen
 * @notice Abstract contract that implements the IComponentToken interface and can be extended
 *   with a concrete implementation that interfaces with an external real-world asset.
 */
abstract contract ComponentToken is
    Initializable,
    ERC20Upgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    IComponentToken
{

    // Storage

    /// @notice Represents a request to buy or sell ComponentToken using CurrencyToken
    struct Request {
        /// @dev Unique identifier for the request
        uint256 requestId;
        /// @dev CurrencyTokenAmount for a buy; ComponentTokenAmount for a sell
        uint256 amount;
        /// @dev Address of the user or smart contract who requested the buy or sell
        address requestor;
        /// @dev True for a buy request; false for a sell request
        bool isBuy;
        /// @dev True if the request has been executed; false otherwise
        bool isExecuted;
    }

    /// @custom:storage-location erc7201:plume.storage.ComponentToken
    struct ComponentTokenStorage {
        /// @dev CurrencyToken used to mint and burn the ComponentToken
        IERC20 currencyToken;
        /// @dev Number of decimals of the ComponentToken
        uint8 decimals;
        /// @dev Version of the ComponentToken interface
        uint256 version;
        /// @dev Requests to buy or sell ComponentToken using CurrencyToken
        Request[] requests;
        /// @dev Total amount of yield that has ever been accrued by all users
        uint256 totalYieldAccrued;
        /// @dev Total amount of yield that has ever been withdrawn by all users
        uint256 totalYieldWithdrawn;
        /// @dev Total amount of yield that has ever been accrued by each user
        mapping(address user => uint256 currencyTokenAmount) yieldAccrued;
        /// @dev Total amount of yield that has ever been withdrawn by each user
        mapping(address user => uint256 currencyTokenAmount) yieldWithdrawn;
    }

    // keccak256(abi.encode(uint256(keccak256("plume.storage.ComponentToken")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant COMPONENT_TOKEN_STORAGE_LOCATION =
        0x40f2ca4cf3a525ed9b1b2649f0f850db77540accc558be58ba47f8638359e800;

    function _getComponentTokenStorage() internal pure returns (ComponentTokenStorage storage $) {
        assembly {
            $.slot := COMPONENT_TOKEN_STORAGE_LOCATION
        }
    }

    // Constants

    /// @notice Role for the admin of the ComponentToken
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    /// @notice Role for the upgrader of the ComponentToken
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    // Events

    /**
     * @notice Emitted when a user requests to buy ComponentToken using CurrencyToken
     * @param user Address of the user who requested to buy the ComponentToken
     * @param currencyToken CurrencyToken to be used to buy the ComponentToken
     * @param currencyTokenAmount Amount of CurrencyToken offered to be paid
     */
    event BuyRequested(address indexed user, IERC20 indexed currencyToken, uint256 currencyTokenAmount);

    /**
     * @notice Emitted when a user requests to sell ComponentToken to receive CurrencyToken
     * @param user Address of the user who requested to sell the ComponentToken
     * @param currencyToken CurrencyToken to be received in exchange for the ComponentToken
     * @param componentTokenAmount Amount of ComponentToken offered to be sold
     */
    event SellRequested(address indexed user, IERC20 indexed currencyToken, uint256 componentTokenAmount);

    /**
     * @notice Emitted when a user buys ComponentToken using CurrencyToken
     * @param user Address of the user who bought the ComponentToken
     * @param currencyToken CurrencyToken used to buy the ComponentToken
     * @param currencyTokenAmount Amount of CurrencyToken paid
     * @param componentTokenAmount Amount of ComponentToken received
     */
    event BuyExecuted(
        address indexed user, IERC20 indexed currencyToken, uint256 currencyTokenAmount, uint256 componentTokenAmount
    );

    /**
     * @notice Emitted when a user sells ComponentToken to receive CurrencyToken
     * @param user Address of the user who sold the ComponentToken
     * @param currencyToken CurrencyToken received in exchange for the ComponentToken
     * @param currencyTokenAmount Amount of CurrencyToken received
     * @param componentTokenAmount Amount of ComponentToken sold
     */
    event SellExecuted(
        address indexed user, IERC20 indexed currencyToken, uint256 currencyTokenAmount, uint256 componentTokenAmount
    );

    /**
     * @notice Emitted when anyone claims yield that has accrued to a user
     * @param user Address of the user who receives the claimed yield
     * @param currencyToken CurrencyToken used to denominate the claimed yield
     * @param amount Amount of CurrencyToken claimed as yield
     */
    event YieldClaimed(address indexed user, IERC20 indexed currencyToken, uint256 amount);

    // Errors

    /**
     * @notice Indicates a failure because the given request ID is invalid
     * @param invalidRequestId Request ID that is invalid
     * @param errorType Type of error that occurred
     *   0: Request ID does not exist
     *   1: Request amount does not match the amount the user is trying to execute
     *   2: Requestor is not the user trying to execute the request
     *   3: Request is not a buy request, but the user is trying to execute a buy
     *   4: Request is not a sell request, but the user is trying to execute a sell
     *   5: Request has already been executed
     */
    error InvalidRequest(uint256 invalidRequestId, uint256 errorType);

    /**
     * @notice Indicates a failure because the given version is not higher than the current version
     * @param invalidVersion Invalid version that is not higher than the current version
     * @param version Current version of the ComponentToken
     */
    error InvalidVersion(uint256 invalidVersion, uint256 version);

    /**
     * @notice Indicates a failure because the user does not have enough CurrencyToken
     * @param currencyToken CurrencyToken used to mint and burn the ComponentToken
     * @param user Address of the user who is selling the CurrencyToken
     * @param amount Amount of CurrencyToken required in the failed transfer
     */
    error InsufficientBalance(IERC20 currencyToken, address user, uint256 amount);

    // Initializer

    /**
     * @notice Prevent the implementation contract from being initialized or reinitialized
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the ComponentToken
     * @param owner Address of the owner of the ComponentToken
     * @param name Name of the ComponentToken
     * @param symbol Symbol of the ComponentToken
     * @param currencyToken CurrencyToken used to mint and burn the ComponentToken
     * @param decimals_ Number of decimals of the ComponentToken
     */
    function initialize(
        address owner,
        string memory name,
        string memory symbol,
        IERC20 currencyToken,
        uint8 decimals_
    ) public initializer {
        __ERC20_init(name, symbol);
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, owner);
        _grantRole(ADMIN_ROLE, owner);
        _grantRole(UPGRADER_ROLE, owner);

        ComponentTokenStorage storage $ = _getComponentTokenStorage();
        $.currencyToken = currencyToken;
        $.decimals = decimals_;
    }

    // Override Functions

    /**
     * @notice Revert when `msg.sender` is not authorized to upgrade the contract
     * @param newImplementation Address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override(UUPSUpgradeable) onlyRole(UPGRADER_ROLE) { }

    /// @notice Number of decimals of the ComponentToken
    function decimals() public view override returns (uint8) {
        return _getComponentTokenStorage().decimals;
    }

    // User Functions

    /**
     * @notice Submit a request to send currencyTokenAmount of CurrencyToken to buy ComponentToken
     * @param currencyTokenAmount Amount of CurrencyToken to send
     * @return requestId Unique identifier for the buy request
     */
    function requestBuy(uint256 currencyTokenAmount) public virtual returns (uint256 requestId) {
        ComponentTokenStorage storage $ = _getComponentTokenStorage();
        IERC20 currencyToken = $.currencyToken;
        requestId = $.requests.length;

        if (!currencyToken.transferFrom(msg.sender, address(this), currencyTokenAmount)) {
            revert InsufficientBalance(currencyToken, msg.sender, currencyTokenAmount);
        }
        $.requests.push(Request(requestId, currencyTokenAmount, msg.sender, true, false));

        emit BuyRequested(msg.sender, currencyToken, currencyTokenAmount);
    }

    /**
     * @notice Submit a request to send componentTokenAmount of ComponentToken to sell for CurrencyToken
     * @param componentTokenAmount Amount of ComponentToken to send
     * @return requestId Unique identifier for the sell request
     */
    function requestSell(uint256 componentTokenAmount) public virtual returns (uint256 requestId) {
        ComponentTokenStorage storage $ = _getComponentTokenStorage();
        IERC20 currencyToken = $.currencyToken;
        requestId = $.requests.length;

        _burn(msg.sender, componentTokenAmount);
        $.requests.push(Request(requestId, componentTokenAmount, msg.sender, false, false));

        emit SellRequested(msg.sender, currencyToken, componentTokenAmount);
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
    ) public virtual {
        ComponentTokenStorage storage $ = _getComponentTokenStorage();
        if (requestId >= $.requests.length) {
            revert InvalidRequest(requestId, 0);
        }

        IERC20 currencyToken = $.currencyToken;
        Request storage request = $.requests[requestId];
        if (request.amount != currencyTokenAmount) {
            revert InvalidRequest(requestId, 1);
        }
        if (request.requestor != requestor) {
            revert InvalidRequest(requestId, 2);
        }
        if (!request.isBuy) {
            revert InvalidRequest(requestId, 3);
        }
        if (request.isExecuted) {
            revert InvalidRequest(requestId, 5);
        }

        _mint(requestor, componentTokenAmount);
        request.isExecuted = true;

        emit BuyExecuted(requestor, currencyToken, currencyTokenAmount, componentTokenAmount);
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
    ) public virtual {
        ComponentTokenStorage storage $ = _getComponentTokenStorage();
        if (requestId >= $.requests.length) {
            revert InvalidRequest(requestId, 0);
        }

        IERC20 currencyToken = $.currencyToken;
        Request storage request = $.requests[requestId];
        if (request.amount != componentTokenAmount) {
            revert InvalidRequest(requestId, 1);
        }
        if (request.requestor != requestor) {
            revert InvalidRequest(requestId, 2);
        }
        if (request.isBuy) {
            revert InvalidRequest(requestId, 4);
        }
        if (request.isExecuted) {
            revert InvalidRequest(requestId, 5);
        }

        if (!currencyToken.transfer(requestor, currencyTokenAmount)) {
            revert InsufficientBalance(currencyToken, requestor, currencyTokenAmount);
        }
        request.isExecuted = true;

        emit SellExecuted(requestor, currencyToken, currencyTokenAmount, componentTokenAmount);
    }

    /**
     * @notice Claim all the remaining yield that has been accrued to a user
     * @dev Anyone can call this function to claim yield for any user
     * @param user Address of the user to claim yield for
     * @return amount Amount of CurrencyToken claimed as yield
     */
    function claimYield(address user) external returns (uint256 amount) {
        ComponentTokenStorage storage $ = _getComponentTokenStorage();
        IERC20 currencyToken = $.currencyToken;

        amount = unclaimedYield(user);
        currencyToken.transfer(user, amount);
        $.yieldWithdrawn[user] += amount;
        $.totalYieldWithdrawn += amount;

        emit YieldClaimed(user, currencyToken, amount);
    }

    // Admin Setter Functions

    /**
     * @notice Set the version of the ComponentToken
     * @dev Only the owner can call this setter
     * @param version New version of the ComponentToken
     */
    function setVersion(uint256 version) external onlyRole(ADMIN_ROLE) {
        ComponentTokenStorage storage $ = _getComponentTokenStorage();
        if (version <= $.version) {
            revert InvalidVersion(version, $.version);
        }
        $.version = version;
    }

    /**
     * @notice Set the CurrencyToken used to mint and burn the ComponentToken
     * @dev Only the owner can call this setter
     * @param currencyToken New CurrencyToken
     */
    function setCurrencyToken(IERC20 currencyToken) external onlyRole(ADMIN_ROLE) {
        _getComponentTokenStorage().currencyToken = currencyToken;
    }

    // Getter View Functions

    /// @notice Returns the version of the ComponentToken interface
    function getVersion() external view returns (uint256) {
        return _getComponentTokenStorage().version;
    }

    /// @notice CurrencyToken used to buy and sell the ComponentToken
    function getCurrencyToken() public view returns (IERC20) {
        return _getComponentTokenStorage().currencyToken;
    }

    /// @notice Total yield distributed to the ComponentToken for all users
    function totalYield() public view returns (uint256 amount) {
        return _getComponentTokenStorage().totalYieldAccrued;
    }

    /// @notice Claimed yield across the ComponentToken for all users
    function claimedYield() public view returns (uint256 amount) {
        return _getComponentTokenStorage().totalYieldWithdrawn;
    }

    /// @notice Unclaimed yield across the ComponentToken for all users
    function unclaimedYield() public view returns (uint256 amount) {
        ComponentTokenStorage storage $ = _getComponentTokenStorage();
        return $.totalYieldAccrued - $.totalYieldWithdrawn;
    }

    /**
     * @notice Total yield distributed to a specific user
     * @param user Address of the user for which to get the total yield
     * @return amount Total yield distributed to the user
     */
    function totalYield(address user) public view returns (uint256 amount) {
        return _getComponentTokenStorage().yieldAccrued[user];
    }

    /**
     * @notice Amount of yield that a specific user has claimed
     * @param user Address of the user for which to get the claimed yield
     * @return amount Amount of yield that the user has claimed
     */
    function claimedYield(address user) public view returns (uint256 amount) {
        return _getComponentTokenStorage().yieldWithdrawn[user];
    }

    /**
     * @notice Amount of yield that a specific user has not yet claimed
     * @param user Address of the user for which to get the unclaimed yield
     * @return amount Amount of yield that the user has not yet claimed
     */
    function unclaimedYield(address user) public view returns (uint256 amount) {
        ComponentTokenStorage storage $ = _getComponentTokenStorage();
        return $.yieldAccrued[user] - $.yieldWithdrawn[user];
    }

}
