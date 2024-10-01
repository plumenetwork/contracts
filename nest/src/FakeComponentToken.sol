// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IComponentToken } from "./interfaces/IComponentToken.sol";

/**
 * @title FakeComponentToken
 * @author Eugene Y. Q. Shen
 * @notice Fake example of a ComponentToken that could be used in an AggregateToken when testing.
 * Users can buy and sell one FakeComponentToken by exchanging it with one CurrencyToken at any time.
 */
contract FakeComponentToken is
    Initializable,
    ERC20Upgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    IComponentToken
{

    // Storage

    /// @custom:storage-location erc7201:plume.storage.FakeComponentToken
    struct FakeComponentTokenStorage {
        /// @dev CurrencyToken used to mint and burn the FakeComponentToken
        IERC20 currencyToken;
        /// @dev Number of decimals of the FakeComponentToken
        uint8 decimals;
        /// @dev Version of the FakeComponentToken
        uint256 version;
        /// @dev Total amount of yield that has ever been accrued by all users
        uint256 totalYieldAccrued;
        /// @dev Total amount of yield that has ever been withdrawn by all users
        uint256 totalYieldWithdrawn;
        /// @dev Total amount of yield that has ever been accrued by each user
        mapping(address user => uint256 currencyTokenAmount) yieldAccrued;
        /// @dev Total amount of yield that has ever been withdrawn by each user
        mapping(address user => uint256 currencyTokenAmount) yieldWithdrawn;
    }

    // keccak256(abi.encode(uint256(keccak256("plume.storage.FakeComponentToken")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant FAKE_COMPONENT_TOKEN_STORAGE_LOCATION =
        0x2c4e9dd7fc35b7006b8a84e1ac11ecc9e53a0dd5c8824b364abab355c5037600;

    function _getFakeComponentTokenStorage() private pure returns (FakeComponentTokenStorage storage $) {
        assembly {
            $.slot := FAKE_COMPONENT_TOKEN_STORAGE_LOCATION
        }
    }

    // Constants

    /// @notice Role for the upgrader of the FakeComponentToken
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    // Events

    /**
     * @notice Emitted when a user buys FakeComponentToken using CurrencyToken
     * @param user Address of the user who bought the FakeComponentToken
     * @param currencyToken CurrencyToken used to buy the FakeComponentToken
     * @param currencyTokenAmount Amount of CurrencyToken paid
     * @param componentTokenAmount Amount of FakeComponentToken received
     */
    event ComponentTokenBought(
        address indexed user, IERC20 indexed currencyToken, uint256 currencyTokenAmount, uint256 componentTokenAmount
    );

    /**
     * @notice Emitted when a user sells FakeComponentToken to receive CurrencyToken
     * @param user Address of the user who sold the FakeComponentToken
     * @param currencyToken CurrencyToken received in exchange for the FakeComponentToken
     * @param currencyTokenAmount Amount of CurrencyToken received
     * @param componentTokenAmount Amount of FakeComponentToken sold
     */
    event ComponentTokenSold(
        address indexed user, IERC20 indexed currencyToken, uint256 currencyTokenAmount, uint256 componentTokenAmount
    );

    // Errors

    /**
     * @notice Indicates a failure because the given version is not higher than the current version
     * @param invalidVersion Invalid version that is not higher than the current version
     * @param version Current version of the FakeComponentToken
     */
    error InvalidVersion(uint256 invalidVersion, uint256 version);

    /**
     * @notice Indicates a failure because the given CurrencyToken does not match actual CurrencyToken
     * @param invalidCurrencyToken CurrencyToken that does not match the actual CurrencyToken
     * @param currencyToken Actual CurrencyToken used to mint and burn the FakeComponentToken
     */
    error InvalidCurrencyToken(IERC20 invalidCurrencyToken, IERC20 currencyToken);

    /**
     * @notice Indicates a failure because the FakeComponentToken does not have enough CurrencyToken
     * @param currencyToken CurrencyToken used to mint and burn the FakeComponentToken
     * @param amount Amount of CurrencyToken required in the failed transfer
     */
    error CurrencyTokenInsufficientBalance(IERC20 currencyToken, uint256 amount);

    /**
     * @notice Indicates a failure because the user does not have enough CurrencyToken
     * @param currencyToken CurrencyToken used to mint and burn the FakeComponentToken
     * @param user Address of the user who is selling the CurrencyToken
     * @param amount Amount of CurrencyToken required in the failed transfer
     */
    error UserCurrencyTokenInsufficientBalance(IERC20 currencyToken, address user, uint256 amount);

    // Initializer

    /**
     * @notice Prevent the implementation contract from being initialized or reinitialized
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the FakeComponentToken
     * @param owner Address of the owner of the FakeComponentToken
     * @param name Name of the FakeComponentToken
     * @param symbol Symbol of the FakeComponentToken
     * @param currencyToken CurrencyToken used to mint and burn the FakeComponentToken
     * @param decimals_ Number of decimals of the FakeComponentToken
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
        _grantRole(UPGRADER_ROLE, owner);

        FakeComponentTokenStorage storage $ = _getFakeComponentTokenStorage();
        $.currencyToken = currencyToken;
        $.decimals = decimals_;
    }

    // Override Functions

    /**
     * @notice Revert when `msg.sender` is not authorized to upgrade the contract
     * @param newImplementation Address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) { }

    /// @notice Number of decimals of the FakeComponentToken
    function decimals() public view override returns (uint8) {
        return _getFakeComponentTokenStorage().decimals;
    }

    // User Functions
    
    function requestBuy(uint256 currencyTokenAmount) external returns (uint256 requestId) {}
    function requestSell(uint256 currencyTokenAmount) external returns (uint256 requestId) {}

    /**
     * @notice Executes a request to buy ComponentToken with CurrencyToken
     * @param requestor Address of the user or smart contract that requested the buy
     * @param requestId Unique identifier for the request
     * @param currencyTokenAmount Amount of CurrencyToken to send
     * @param componentTokenAmount Amount of ComponentToken to receive
     */
    function executeBuy(address requestor, uint256 requestId, uint256 currencyTokenAmount, uint256 componentTokenAmount) public {
        IERC20 currencyToken = _getFakeComponentTokenStorage().currencyToken;
        uint256 amount = currencyTokenAmount;
        if (!currencyToken.transferFrom(msg.sender, address(this), amount)) {
            revert UserCurrencyTokenInsufficientBalance(currencyToken, msg.sender, amount);
        }

        _mint(msg.sender, amount);
        emit ComponentTokenBought(msg.sender, currencyToken, amount, amount);
        componentTokenAmount = amount;
    }

    /**
     * @notice Executes a request to sell ComponentToken for CurrencyToken
     * @param requestor Address of the user or smart contract that requested the sell
     * @param requestId Unique identifier for the request
     * @param currencyTokenAmount Amount of CurrencyToken to receive
     * @param componentTokenAmount Amount of ComponentToken to send
     */
    function executeSell(address requestor, uint256 requestId, uint256 currencyTokenAmount, uint256 componentTokenAmount) public {
        IERC20 currencyToken = _getFakeComponentTokenStorage().currencyToken;
        uint256 amount = currencyTokenAmount;
        if (!currencyToken.transfer(msg.sender, amount)) {
            revert CurrencyTokenInsufficientBalance(currencyToken, amount);
        }

        _burn(msg.sender, amount);
        emit ComponentTokenSold(msg.sender, currencyToken, amount, amount);
        componentTokenAmount = amount;
    }

    /**
     * @notice Claim yield for the given user
     * @dev Anyone can call this function to claim yield for any user
     * @param user Address of the user for which to claim yield
     */
    function claimYield(address user) external returns (uint256 amount) {
        FakeComponentTokenStorage storage $ = _getFakeComponentTokenStorage();
        amount = unclaimedYield(user);
        $.currencyToken.transfer(user, amount);
        $.yieldWithdrawn[user] += amount;
        $.totalYieldWithdrawn += amount;
    }

    /**
     * @notice Accrue yield for the given user
     * @dev Anyone can call this function to accrue yield for any user
     * @param user Address of the user for which to accrue yield
     */
    function accrueYield(address user, uint256 amount) external {
        FakeComponentTokenStorage storage $ = _getFakeComponentTokenStorage();
        $.yieldAccrued[user] += amount;
        $.totalYieldAccrued += amount;
    }

    // Admin Setter Functions

    /**
     * @notice Set the version of the FakeComponentToken
     * @dev Only the owner can call this setter
     * @param version New version of the FakeComponentToken
     */
    function setVersion(uint256 version) external onlyRole(DEFAULT_ADMIN_ROLE) {
        FakeComponentTokenStorage storage $ = _getFakeComponentTokenStorage();
        if (version <= $.version) {
            revert InvalidVersion(version, $.version);
        }
        $.version = version;
    }

    /**
     * @notice Set the CurrencyToken used to mint and burn the FakeComponentToken
     * @dev Only the owner can call this setter
     * @param currencyToken New CurrencyToken
     */
    function setCurrencyToken(IERC20 currencyToken) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _getFakeComponentTokenStorage().currencyToken = currencyToken;
    }

    // Getter View Functions

    /// @notice Version of the FakeComponentToken
    function getVersion() external view returns (uint256) {
        return _getFakeComponentTokenStorage().version;
    }

    /// @notice CurrencyToken used to mint and burn the FakeComponentToken
    function getCurrencyToken() external view returns (IERC20) {
        return _getFakeComponentTokenStorage().currencyToken;
    }

    /// @notice Total yield distributed to all FakeComponentTokens for all users
    function totalYield() external view returns (uint256 amount) {
        return _getFakeComponentTokenStorage().totalYieldAccrued;
    }

    /// @notice Claimed yield across all FakeComponentTokens for all users
    function claimedYield() external view returns (uint256 amount) {
        return _getFakeComponentTokenStorage().totalYieldWithdrawn;
    }

    /// @notice Unclaimed yield across all FakeComponentTokens for all users
    function unclaimedYield() external view returns (uint256 amount) {
        FakeComponentTokenStorage storage $ = _getFakeComponentTokenStorage();
        return $.totalYieldAccrued - $.totalYieldWithdrawn;
    }

    /**
     * @notice Total yield distributed to a specific user
     * @param user Address of the user for which to get the total yield
     * @return amount Total yield distributed to the user
     */
    function totalYield(address user) external view returns (uint256 amount) {
        return _getFakeComponentTokenStorage().yieldAccrued[user];
    }

    /**
     * @notice Amount of yield that a specific user has claimed
     * @param user Address of the user for which to get the claimed yield
     * @return amount Amount of yield that the user has claimed
     */
    function claimedYield(address user) external view returns (uint256 amount) {
        return _getFakeComponentTokenStorage().yieldWithdrawn[user];
    }

    /**
     * @notice Amount of yield that a specific user has not yet claimed
     * @param user Address of the user for which to get the unclaimed yield
     * @return amount Amount of yield that the user has not yet claimed
     */
    function unclaimedYield(address user) public view returns (uint256 amount) {
        FakeComponentTokenStorage storage $ = _getFakeComponentTokenStorage();
        return $.yieldAccrued[user] - $.yieldWithdrawn[user];
    }

}
