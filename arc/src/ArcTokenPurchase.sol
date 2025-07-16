// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "./ArcToken.sol";
import "./ArcTokenFactory.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/**
 * @title ArcTokenPurchase
 * @author Eugene Y. Q. Shen, Alp Guneysel
 * @notice Handles token sales and storefront configuration for ArcTokens.
 *         The contract holds the tokens being sold and the purchase currency received.
 * @dev Manages purchase process and storefront metadata, upgradeable via UUPS pattern.
 *      Requires ArcTokens to be transferred to this contract before enabling sale.
 *      Assumes tokenPrice is denominated in purchaseToken units for the number of base units
 *      corresponding to 1 full ArcToken (e.g., 1e18 for 18 decimals).
 */
contract ArcTokenPurchase is Initializable, AccessControlUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    using EnumerableSet for EnumerableSet.AddressSet;

    struct TokenInfo {
        bool isEnabled;
        uint256 tokenPrice;
        uint256 totalAmountForSale;
        uint256 amountSold;
    }

    struct StorefrontConfig {
        string domain;
        string title;
        string description;
        string ogImageUrl;
        string accentColor;
        string backgroundColor;
        string companyLogoUrl;
        bool showPlumeBadge;
    }

    /// @custom:storage-location erc7201:arc.purchase.storage
    struct PurchaseStorage {
        // The token used for purchasing ArcTokens (e.g., USDC)
        IERC20 purchaseToken;
        // The factory that created the tokens
        address tokenFactory;
        // Mappings
        mapping(address => TokenInfo) tokenInfo;
        mapping(address => StorefrontConfig) storefrontConfigs;
        mapping(string => address) domainToAddress;
        // Set of tokens currently enabled for sale
        EnumerableSet.AddressSet enabledTokens;
    }

    // Calculate unique storage slot
    bytes32 private constant PURCHASE_STORAGE_LOCATION = keccak256("arc.purchase.storage");

    function _getPurchaseStorage() private pure returns (PurchaseStorage storage ps) {
        bytes32 position = PURCHASE_STORAGE_LOCATION;
        assembly {
            ps.slot := position
        }
    }

    // Events
    event PurchaseMade(address indexed buyer, address indexed tokenContract, uint256 amount, uint256 pricePaid);
    event TokenSaleEnabled(address indexed tokenContract, uint256 numberOfTokens, uint256 tokenPrice);
    event TokenSaleDisabled(address indexed tokenContract);
    event StorefrontConfigSet(address indexed tokenContract, string domain);
    event PurchaseTokenUpdated(address indexed newPurchaseToken);
    event TokenFactoryUpdated(address indexed newFactory);

    // -------------- Custom Errors --------------
    error PurchaseTokenNotSet();
    error PurchaseAmountTooLow();
    error TooLittleReceived();
    error NotEnoughTokensForSale();
    error ContractBalanceInsufficient();
    error PurchaseTransferFailed();
    error TokenTransferFailed();
    error InvalidPurchaseTokenAddress();
    error TokenPriceMustBePositive();
    error NumberOfTokensMustBePositive();
    error ContractMissingRequiredTokens();
    error NotTokenAdmin(address caller, address token);
    error DomainCannotBeEmpty();
    error DomainAlreadyInUse(string domain);
    error NoConfigForDomain(string domain);
    error CannotWithdrawToZeroAddress();
    error AmountMustBePositive();
    error InsufficientUnsoldTokens();
    error ArcTokenWithdrawalFailed();
    error PurchaseTokenWithdrawalFailed();
    error TokenNotEnabled(); // Replaces "Token is not enabled for purchase"
    error ZeroAmount(); // Added for consistency if needed
    error TokenFactoryNotSet();
    error TokenNotCreatedByFactory();
    error CannotChangePurchaseTokenWithActiveSales();

    /**
     * @dev Initializes the contract and sets up admin role
     * @param admin Address to be granted admin role
     * @param factory Address of the ArcTokenFactory
     */
    function initialize(address admin, address factory) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);

        if (factory == address(0)) {
            revert TokenFactoryNotSet();
        }
        _getPurchaseStorage().tokenFactory = factory;
    }

    /**
     * @dev Modifier to ensure only token admin can call certain functions
     */
    modifier onlyTokenAdmin(
        address _tokenContract
    ) {
        address adminRoleHolder = msg.sender;
        bytes32 adminRole = ArcToken(_tokenContract).ADMIN_ROLE();
        if (!ArcToken(_tokenContract).hasRole(adminRole, adminRoleHolder)) {
            revert NotTokenAdmin(adminRoleHolder, _tokenContract);
        }
        _;
    }

    /**
     * @dev Enables token for sale
     * @param _tokenContract Address of the ArcToken contract
     * @param _numberOfTokens Number of tokens available for sale
     * @param _tokenPrice Price per token in purchase token units
     */
    function enableToken(
        address _tokenContract,
        uint256 _numberOfTokens,
        uint256 _tokenPrice
    ) external onlyTokenAdmin(_tokenContract) {
        if (_tokenPrice == 0) {
            revert TokenPriceMustBePositive();
        }
        if (_numberOfTokens == 0) {
            revert NumberOfTokensMustBePositive();
        }

        PurchaseStorage storage ps = _getPurchaseStorage();
        if (ps.tokenFactory == address(0)) {
            revert TokenFactoryNotSet();
        }

        // Verify token was created by the factory
        address implementation = ArcTokenFactory(ps.tokenFactory)
            .getTokenImplementation(_tokenContract);
        if (implementation == address(0)) {
            revert TokenNotCreatedByFactory();
        }

        if (
            ArcToken(_tokenContract).balanceOf(address(this)) < _numberOfTokens
        ) {
            revert ContractMissingRequiredTokens();
        }

        ps.tokenInfo[_tokenContract] =
            TokenInfo({ isEnabled: true, tokenPrice: _tokenPrice, totalAmountForSale: _numberOfTokens, amountSold: 0 });

        ps.enabledTokens.add(_tokenContract);

        emit TokenSaleEnabled(_tokenContract, _numberOfTokens, _tokenPrice);
    }

    /**
     * @dev Disables a token for sale.
     * @param _tokenContract Address of the ArcToken contract to disable.
     */
    function disableToken(address _tokenContract) external onlyTokenAdmin(_tokenContract) {
        PurchaseStorage storage ps = _getPurchaseStorage();
        TokenInfo storage info = ps.tokenInfo[_tokenContract];

        if (!info.isEnabled) {
            revert TokenNotEnabled();
        }

        info.isEnabled = false;
        ps.enabledTokens.remove(_tokenContract);

        emit TokenSaleDisabled(_tokenContract);
    }

    /**
     * @dev Set token factory address
     * @param factoryAddress Address of the ArcTokenFactory
     */
    function setTokenFactory(
        address factoryAddress
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (factoryAddress == address(0)) {
            revert TokenFactoryNotSet();
        }
        _getPurchaseStorage().tokenFactory = factoryAddress;
        emit TokenFactoryUpdated(factoryAddress);
    }

    /**
     * @dev Purchase tokens using the purchase token.
     *      Requires the buyer to have approved this contract to spend their purchaseToken.
     * @param _tokenContract Address of the ArcToken to purchase
     * @param _purchaseAmount Amount of purchase tokens to spend
     * @param _amountOutMinimum Minimum amount of tokens to receive (in base units)
     */
    function buy(
        address _tokenContract,
        uint256 _purchaseAmount,
        uint256 _amountOutMinimum
    ) external nonReentrant {
        PurchaseStorage storage ps = _getPurchaseStorage();
        TokenInfo storage info = ps.tokenInfo[_tokenContract];

        if (!info.isEnabled) {
            revert TokenNotEnabled();
        }
        if (_purchaseAmount == 0) {
            revert ZeroAmount();
        }
        if (info.tokenPrice == 0) {
            revert TokenPriceMustBePositive();
        }

        IERC20 purchaseTkn = ps.purchaseToken;
        if (address(purchaseTkn) == address(0)) {
            revert PurchaseTokenNotSet();
        }

        ArcToken token = ArcToken(_tokenContract);
        uint8 tokenDecimals = token.decimals(); // Get decimals dynamically
        uint256 scalingFactor = 10 ** tokenDecimals;

        // Calculate ArcToken base units to buy, assuming tokenPrice is for 1 full ArcToken (scaled by its decimals)
        uint256 arcTokensBaseUnitsToBuy = (_purchaseAmount * scalingFactor) / info.tokenPrice;
        if (arcTokensBaseUnitsToBuy == 0) {
            revert PurchaseAmountTooLow();
        }

        // Check if the calculated amount meets the minimum output requirement
        if (arcTokensBaseUnitsToBuy < _amountOutMinimum) {
            revert TooLittleReceived();
        }

        uint256 remainingForSale = info.totalAmountForSale - info.amountSold; // Remaining in base units
        if (remainingForSale < arcTokensBaseUnitsToBuy) {
            revert NotEnoughTokensForSale();
        }

        // Check base unit balance
        if (token.balanceOf(address(this)) < arcTokensBaseUnitsToBuy) {
            revert ContractBalanceInsufficient();
        }

        // Transfer purchase token (e.g., USDC)
        bool purchaseSuccess = purchaseTkn.transferFrom(msg.sender, address(this), _purchaseAmount);
        if (!purchaseSuccess) {
            revert PurchaseTransferFailed();
        }

        // Transfer ArcToken base units
        bool tokenTransferSuccess = token.transfer(msg.sender, arcTokensBaseUnitsToBuy);
        if (!tokenTransferSuccess) {
            revert TokenTransferFailed();
        }

        info.amountSold += arcTokensBaseUnitsToBuy; // Track base units sold

        // Emit event with ArcToken base units bought and purchase token amount paid
        emit PurchaseMade(msg.sender, _tokenContract, arcTokensBaseUnitsToBuy, _purchaseAmount);
    }

    /**
     * @dev Set purchase token address
     * @param purchaseTokenAddress Address of the ERC20 token to use for purchases
     */
    function setPurchaseToken(
        address purchaseTokenAddress
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        PurchaseStorage storage ps = _getPurchaseStorage();
        if (ps.enabledTokens.length() > 0) {
            revert CannotChangePurchaseTokenWithActiveSales();
        }
        if (purchaseTokenAddress == address(0)) {
            revert InvalidPurchaseTokenAddress();
        }
        ps.purchaseToken = IERC20(purchaseTokenAddress);
        emit PurchaseTokenUpdated(purchaseTokenAddress);
    }

    /**
     * @dev Configure storefront for a token
     */
    function setStorefrontConfig(
        address _tokenContract,
        string memory _domain,
        string memory _title,
        string memory _description,
        string memory _ogImageUrl,
        string memory _accentColor,
        string memory _backgroundColor,
        string memory _companyLogoUrl,
        bool _showPlumeBadge
    ) external onlyTokenAdmin(_tokenContract) {
        if (bytes(_domain).length == 0) {
            revert DomainCannotBeEmpty();
        }
        PurchaseStorage storage ps = _getPurchaseStorage();
        if (ps.domainToAddress[_domain] != address(0) && ps.domainToAddress[_domain] != _tokenContract) {
            revert DomainAlreadyInUse(_domain);
        }

        ps.storefrontConfigs[_tokenContract] = StorefrontConfig({
            domain: _domain,
            title: _title,
            description: _description,
            ogImageUrl: _ogImageUrl,
            accentColor: _accentColor,
            backgroundColor: _backgroundColor,
            companyLogoUrl: _companyLogoUrl,
            showPlumeBadge: _showPlumeBadge
        });

        ps.domainToAddress[_domain] = _tokenContract;
        emit StorefrontConfigSet(_tokenContract, _domain);
    }

    // -------------- View Functions --------------

    /**
     * @dev Gets the sales information for a specific token.
     * @param _tokenContract The address of the ArcToken.
     * @return TokenInfo struct containing sale details (isEnabled, tokenPrice, totalAmountForSale, amountSold).
     */
    function getTokenInfo(
        address _tokenContract
    ) external view returns (TokenInfo memory) {
        return _getPurchaseStorage().tokenInfo[_tokenContract];
    }

    function isEnabled(
        address _tokenContract
    ) external view returns (bool) {
        return _getPurchaseStorage().tokenInfo[_tokenContract].isEnabled;
    }

    function getMaxNumberOfTokens(
        address _tokenContract
    ) external view returns (uint256) {
        TokenInfo storage info = _getPurchaseStorage().tokenInfo[_tokenContract];
        return info.totalAmountForSale - info.amountSold;
    }

    function getTokenPrice(
        address _tokenContract
    ) external view returns (uint256) {
        return _getPurchaseStorage().tokenInfo[_tokenContract].tokenPrice;
    }

    function getStorefrontConfig(
        address _tokenContract
    ) external view returns (StorefrontConfig memory) {
        return _getPurchaseStorage().storefrontConfigs[_tokenContract];
    }

    function getStorefrontConfigByDomain(
        string memory _domain
    ) external view returns (StorefrontConfig memory) {
        PurchaseStorage storage ps = _getPurchaseStorage();
        address tokenContract = ps.domainToAddress[_domain];
        if (tokenContract == address(0)) {
            revert NoConfigForDomain(_domain);
        }
        return ps.storefrontConfigs[tokenContract];
    }

    function getAddressByDomain(
        string memory _domain
    ) external view returns (address) {
        PurchaseStorage storage ps = _getPurchaseStorage();
        address tokenContract = ps.domainToAddress[_domain];
        if (tokenContract == address(0)) {
            revert NoConfigForDomain(_domain);
        }
        return tokenContract;
    }

    /**
     * @dev Returns the purchase token address
     */
    function purchaseToken() external view returns (IERC20) {
        return _getPurchaseStorage().purchaseToken;
    }

    /**
     * @dev Returns the token factory address
     */
    function tokenFactory() external view returns (address) {
        return _getPurchaseStorage().tokenFactory;
    }

    /**
     * @dev Withdraw purchase tokens to a specified address
     * @param to Address to send tokens to
     * @param amount Amount of tokens to withdraw
     */
    function withdrawPurchaseTokens(address to, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (to == address(0)) {
            revert CannotWithdrawToZeroAddress();
        }
        PurchaseStorage storage ps = _getPurchaseStorage();
        if (address(ps.purchaseToken) == address(0)) {
            revert PurchaseTokenNotSet();
        }
        bool success = ps.purchaseToken.transfer(to, amount);
        if (!success) {
            revert PurchaseTokenWithdrawalFailed();
        }
    }

    /**
     * @dev Allows the token admin to withdraw unsold ArcTokens after a sale (or if disabled).
     * @param _tokenContract The ArcToken contract address.
     * @param to The address to send the tokens to.
     * @param amount The amount of ArcTokens to withdraw.
     */
    function withdrawUnsoldArcTokens(
        address _tokenContract,
        address to,
        uint256 amount
    ) external onlyTokenAdmin(_tokenContract) {
        if (to == address(0)) {
            revert CannotWithdrawToZeroAddress();
        }
        if (amount == 0) {
            revert AmountMustBePositive();
        }

        ArcToken token = ArcToken(_tokenContract);
        uint256 contractBalance = token.balanceOf(address(this));
        if (contractBalance < amount) {
            revert InsufficientUnsoldTokens();
        }

        bool success = token.transfer(to, amount);
        if (!success) {
            revert ArcTokenWithdrawalFailed();
        }
    }

    /**
     * @dev Authorization for upgrades
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(DEFAULT_ADMIN_ROLE) { }

}
