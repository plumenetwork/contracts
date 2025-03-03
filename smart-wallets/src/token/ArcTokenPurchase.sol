// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "./ArcToken.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title ArcTokenPurchase
 * @author Eugene Y. Q. Shen, Alp Guneysel
 * @notice Handles token sales and storefront configuration for ArcTokens
 * @dev Manages purchase process and storefront metadata
 */
contract ArcTokenPurchase is AccessControl {

    struct TokenInfo {
        bool isEnabled;
        uint256 tokenPrice;
        uint256 totalAmountToBeSold;
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

    // The token used for purchasing ArcTokens (e.g., USDC)
    IERC20 public purchaseToken;

    // Mappings
    mapping(address => TokenInfo) public tokenInfo;
    mapping(address => StorefrontConfig) private storefrontConfigs;
    mapping(string => address) private domainToAddress;

    // Events
    event PurchaseMade(address indexed buyer, address indexed tokenContract, uint256 amount, uint256 pricePaid);
    event TokenSaleEnabled(address indexed tokenContract, uint256 numberOfTokens, uint256 tokenPrice);
    event StorefrontConfigSet(address indexed tokenContract, string domain);
    event PurchaseTokenUpdated(address indexed newPurchaseToken);

    /**
     * @dev Constructor sets up admin role
     * @param admin Address to be granted admin role
     */
    constructor(
        address admin
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /**
     * @dev Modifier to ensure only token owner can call certain functions
     */
    modifier onlyTokenOwner(
        address _tokenContract
    ) {
        require(ArcToken(_tokenContract).owner() == msg.sender, "Only token owner can call this function");
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
    ) external onlyTokenOwner(_tokenContract) {
        require(_tokenPrice > 0, "Token price must be greater than 0");
        require(_numberOfTokens > 0, "Number of tokens must be greater than 0");

        tokenInfo[_tokenContract] =
            TokenInfo({ isEnabled: true, tokenPrice: _tokenPrice, totalAmountToBeSold: _numberOfTokens });

        emit TokenSaleEnabled(_tokenContract, _numberOfTokens, _tokenPrice);
    }

    /**
     * @dev Purchase tokens using the purchase token
     * @param _tokenContract Address of the ArcToken to purchase
     * @param _purchaseAmount Amount of purchase tokens to spend
     */
    function buy(address _tokenContract, uint256 _purchaseAmount) external {
        TokenInfo storage info = tokenInfo[_tokenContract];
        require(info.isEnabled, "Token is not enabled for purchase");
        require(_purchaseAmount > 0, "Purchase amount should be greater than zero");
        require(
            purchaseToken.transferFrom(msg.sender, address(this), _purchaseAmount), "Purchase token transfer failed"
        );

        uint256 tokensToBuy = _purchaseAmount / info.tokenPrice;
        require(info.totalAmountToBeSold >= tokensToBuy, "Not enough tokens available for sale");

        // Transfer tokens from owner to buyer
        ArcToken token = ArcToken(_tokenContract);
        require(token.transferFrom(token.owner(), msg.sender, tokensToBuy), "Token transfer failed");

        // Update remaining tokens
        info.totalAmountToBeSold -= tokensToBuy;

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
        purchaseToken = IERC20(purchaseTokenAddress);
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
    ) external onlyTokenOwner(_tokenContract) {
        require(bytes(_domain).length > 0, "Domain cannot be empty");
        require(
            domainToAddress[_domain] == address(0) || domainToAddress[_domain] == _tokenContract,
            "Domain already in use"
        );

        storefrontConfigs[_tokenContract] = StorefrontConfig({
            domain: _domain,
            title: _title,
            description: _description,
            ogImageUrl: _ogImageUrl,
            accentColor: _accentColor,
            backgroundColor: _backgroundColor,
            companyLogoUrl: _companyLogoUrl,
            showPlumeBadge: _showPlumeBadge
        });

        domainToAddress[_domain] = _tokenContract;
        emit StorefrontConfigSet(_tokenContract, _domain);
    }

    // -------------- View Functions --------------

    function isEnabled(
        address _tokenContract
    ) external view returns (bool) {
        return tokenInfo[_tokenContract].isEnabled;
    }

    function getMaxNumberOfTokens(
        address _tokenContract
    ) external view returns (uint256) {
        return tokenInfo[_tokenContract].totalAmountToBeSold;
    }

    function getTokenPrice(
        address _tokenContract
    ) external view returns (uint256) {
        return tokenInfo[_tokenContract].tokenPrice;
    }

    function getStorefrontConfig(
        address _tokenContract
    ) external view returns (StorefrontConfig memory) {
        return storefrontConfigs[_tokenContract];
    }

    function getStorefrontConfigByDomain(
        string memory _domain
    ) external view returns (StorefrontConfig memory) {
        address tokenContract = domainToAddress[_domain];
        require(tokenContract != address(0), "No config found for this domain");
        return storefrontConfigs[tokenContract];
    }

    function getAddressByDomain(
        string memory _domain
    ) external view returns (address) {
        address tokenContract = domainToAddress[_domain];
        require(tokenContract != address(0), "No address found for this domain");
        return tokenContract;
    }

    /**
     * @dev Withdraw purchase tokens to a specified address
     * @param to Address to send tokens to
     * @param amount Amount of tokens to withdraw
     */
    function withdrawPurchaseTokens(address to, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(to != address(0), "Cannot withdraw to zero address");
        require(purchaseToken.transfer(to, amount), "Purchase token transfer failed");
    }

}
