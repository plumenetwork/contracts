// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "./ArcToken.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title ArcTokenPurchase
 * @author Eugene Y. Q. Shen, Alp Guneysel
 * @notice Handles token sales and storefront configuration for ArcTokens
 * @dev Manages purchase process and storefront metadata, upgradeable via UUPS pattern
 */
contract ArcTokenPurchase is Initializable, AccessControlUpgradeable, UUPSUpgradeable {

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
        ps.tokenInfo[_tokenContract] =
            TokenInfo({ isEnabled: true, tokenPrice: _tokenPrice, totalAmountToBeSold: _numberOfTokens });

        emit TokenSaleEnabled(_tokenContract, _numberOfTokens, _tokenPrice);
    }

    /**
     * @dev Purchase tokens using the purchase token
     * @param _tokenContract Address of the ArcToken to purchase
     * @param _purchaseAmount Amount of purchase tokens to spend
     */
    function buy(address _tokenContract, uint256 _purchaseAmount) external {
        PurchaseStorage storage ps = _getPurchaseStorage();
        TokenInfo storage info = ps.tokenInfo[_tokenContract];
        require(info.isEnabled, "Token is not enabled for purchase");
        require(_purchaseAmount > 0, "Purchase amount should be greater than zero");
        require(
            ps.purchaseToken.transferFrom(msg.sender, address(this), _purchaseAmount), "Purchase token transfer failed"
        );

        uint256 tokensToBuy = _purchaseAmount / info.tokenPrice;
        require(info.totalAmountToBeSold >= tokensToBuy, "Not enough tokens available for sale");

        // Find an admin to transfer tokens from
        ArcToken token = ArcToken(_tokenContract);
        address tokenAdmin = findTokenAdmin(token);
        require(tokenAdmin != address(0), "No token admin with sufficient balance found");

        // Transfer tokens from admin to buyer
        require(token.transferFrom(tokenAdmin, msg.sender, tokensToBuy), "Token transfer failed");

        // Update remaining tokens
        info.totalAmountToBeSold -= tokensToBuy;

        emit PurchaseMade(msg.sender, _tokenContract, tokensToBuy, _purchaseAmount);
    }

    /**
     * @dev Finds a token admin with sufficient balance
     * @param token The ArcToken contract
     * @return admin Address of an admin with sufficient balance
     */
    function findTokenAdmin(
        ArcToken token
    ) internal view returns (address) {
        // Try to find any address with admin role that has sufficient tokens
        // This is a simplified approach and may need to be customized based on your needs
        bytes32 adminRole = token.ADMIN_ROLE();

        // In a real implementation, you might need a way to get all admins
        // For now, we're assuming you have a known list of admins or a primary admin
        // This is a placeholder logic that needs to be adapted to your specific needs
        return token.hasRole(adminRole, msg.sender) ? msg.sender : address(0);
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

    function isEnabled(
        address _tokenContract
    ) external view returns (bool) {
        return _getPurchaseStorage().tokenInfo[_tokenContract].isEnabled;
    }

    function getMaxNumberOfTokens(
        address _tokenContract
    ) external view returns (uint256) {
        return _getPurchaseStorage().tokenInfo[_tokenContract].totalAmountToBeSold;
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
        require(ps.purchaseToken.transfer(to, amount), "Purchase token transfer failed");
    }

    /**
     * @dev Authorization for upgrades
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(DEFAULT_ADMIN_ROLE) { }

}
