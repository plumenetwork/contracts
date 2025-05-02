// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "./ArcToken.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title ArcTokenPurchase
 * @author Eugene Y. Q. Shen, Alp Guneysel
 * @notice Handles token sales and storefront configuration for ArcTokens.
 *         The contract holds the tokens being sold and the purchase currency received.
 * @dev Manages purchase process and storefront metadata, upgradeable via UUPS pattern.
 *      Requires ArcTokens to be transferred to this contract before enabling sale.
 */
contract ArcTokenPurchase is Initializable, AccessControlUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {

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
        // Mappings
        mapping(address => TokenInfo) tokenInfo;
        mapping(address => StorefrontConfig) storefrontConfigs;
        mapping(string => address) domainToAddress;
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
    event StorefrontConfigSet(address indexed tokenContract, string domain);
    event PurchaseTokenUpdated(address indexed newPurchaseToken);

    /**
     * @dev Initializes the contract and sets up admin role
     * @param admin Address to be granted admin role
     */
    function initialize(
        address admin
    ) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /**
     * @dev Modifier to ensure only token admin can call certain functions
     */
    modifier onlyTokenAdmin(
        address _tokenContract
    ) {
        require(
            ArcToken(_tokenContract).hasRole(ArcToken(_tokenContract).ADMIN_ROLE(), msg.sender),
            "Only token admin can call this function"
        );
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
        require(_tokenPrice > 0, "Token price must be greater than 0");
        require(_numberOfTokens > 0, "Number of tokens must be greater than 0");

        PurchaseStorage storage ps = _getPurchaseStorage();
        require(
            ArcToken(_tokenContract).balanceOf(address(this)) >= _numberOfTokens, "Contract does not hold enough tokens"
        );

        ps.tokenInfo[_tokenContract] =
            TokenInfo({ isEnabled: true, tokenPrice: _tokenPrice, totalAmountForSale: _numberOfTokens, amountSold: 0 });

        emit TokenSaleEnabled(_tokenContract, _numberOfTokens, _tokenPrice);
    }

    /**
     * @dev Purchase tokens using the purchase token.
     *      Requires the buyer to have approved this contract to spend their purchaseToken.
     * @param _tokenContract Address of the ArcToken to purchase
     * @param _purchaseAmount Amount of purchase tokens to spend
     */
    function buy(address _tokenContract, uint256 _purchaseAmount) external nonReentrant {
        PurchaseStorage storage ps = _getPurchaseStorage();
        TokenInfo storage info = ps.tokenInfo[_tokenContract];

        require(info.isEnabled, "Token is not enabled for purchase");
        require(_purchaseAmount > 0, "Purchase amount should be greater than zero");
        require(info.tokenPrice > 0, "Token price not set");

        IERC20 purchaseTkn = ps.purchaseToken;
        require(address(purchaseTkn) != address(0), "Purchase token not set");

        uint256 tokensToBuy = _purchaseAmount / info.tokenPrice;
        require(tokensToBuy > 0, "Purchase amount too low for a single token");

        uint256 remainingForSale = info.totalAmountForSale - info.amountSold;
        require(remainingForSale >= tokensToBuy, "Not enough tokens left for sale");

        ArcToken token = ArcToken(_tokenContract);
        require(token.balanceOf(address(this)) >= tokensToBuy, "Contract internal token balance insufficient");

        require(purchaseTkn.transferFrom(msg.sender, address(this), _purchaseAmount), "Purchase token transfer failed");

        require(token.transfer(msg.sender, tokensToBuy), "Token transfer failed");

        info.amountSold += tokensToBuy;

        emit PurchaseMade(msg.sender, _tokenContract, tokensToBuy, _purchaseAmount);
    }

    /**
     * @dev Set purchase token address
     * @param purchaseTokenAddress Address of the ERC20 token to use for purchases
     */
    function setPurchaseToken(
        address purchaseTokenAddress
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(purchaseTokenAddress != address(0), "Invalid purchase token address");
        PurchaseStorage storage ps = _getPurchaseStorage();
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
        require(bytes(_domain).length > 0, "Domain cannot be empty");
        PurchaseStorage storage ps = _getPurchaseStorage();
        require(
            ps.domainToAddress[_domain] == address(0) || ps.domainToAddress[_domain] == _tokenContract,
            "Domain already in use"
        );

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
        require(tokenContract != address(0), "No config found for this domain");
        return ps.storefrontConfigs[tokenContract];
    }

    function getAddressByDomain(
        string memory _domain
    ) external view returns (address) {
        PurchaseStorage storage ps = _getPurchaseStorage();
        address tokenContract = ps.domainToAddress[_domain];
        require(tokenContract != address(0), "No address found for this domain");
        return tokenContract;
    }

    /**
     * @dev Returns the purchase token address
     */
    function purchaseToken() external view returns (IERC20) {
        return _getPurchaseStorage().purchaseToken;
    }

    /**
     * @dev Withdraw purchase tokens to a specified address
     * @param to Address to send tokens to
     * @param amount Amount of tokens to withdraw
     */
    function withdrawPurchaseTokens(address to, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(to != address(0), "Cannot withdraw to zero address");
        PurchaseStorage storage ps = _getPurchaseStorage();
        require(address(ps.purchaseToken) != address(0), "Purchase token not set");
        require(ps.purchaseToken.transfer(to, amount), "Purchase token transfer failed");
    }

    /**
     * @dev Allows the contract admin to withdraw unsold ArcTokens after a sale (or if disabled).
     * @param _tokenContract The ArcToken contract address.
     * @param to The address to send the tokens to.
     * @param amount The amount of ArcTokens to withdraw.
     */
    function withdrawUnsoldArcTokens(
        address _tokenContract,
        address to,
        uint256 amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(to != address(0), "Cannot withdraw to zero address");
        require(amount > 0, "Amount must be greater than zero");

        ArcToken token = ArcToken(_tokenContract);
        uint256 contractBalance = token.balanceOf(address(this));
        require(contractBalance >= amount, "Insufficient unsold tokens in contract");

        require(token.transfer(to, amount), "ArcToken withdrawal failed");
    }

    /**
     * @dev Authorization for upgrades
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(DEFAULT_ADMIN_ROLE) { }

}
