// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/**
 * @title ArcToken
 * @author Eugene Y. Q. Shen, Alp Guneysel
 * @notice ERC20 token representing shares of a company, with whitelist control,
 *      configurable transfer restrictions, minting/burning by the issuer,
 *      yield distribution to token holders, and valuation tracking.
 * @dev Implements ERC20Upgradeable which includes IERC20Metadata functionality
 */
contract ArcToken is ERC20Upgradeable, AccessControlUpgradeable, ReentrancyGuardUpgradeable {

    using SafeERC20 for ERC20Upgradeable;
    using EnumerableSet for EnumerableSet.AddressSet;

    // -------------- Role Definitions --------------
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant YIELD_MANAGER_ROLE = keccak256("YIELD_MANAGER_ROLE");
    bytes32 public constant YIELD_DISTRIBUTOR_ROLE = keccak256("YIELD_DISTRIBUTOR_ROLE");

    // -------------- Custom Errors --------------
    error AlreadyWhitelisted(address account);
    error NotWhitelisted(address account);
    error YieldTokenNotSet();
    error NoTokensInCirculation();
    error InvalidYieldTokenAddress();
    error IssuePriceMustBePositive();
    error InvalidAddress();
    error TransferRestricted();

    /// @custom:storage-location erc7201:asset.token.storage
    struct ArcTokenStorage {
        // Whitelist mapping (address => true if allowed to transfer/hold when restricted)
        mapping(address => bool) isWhitelisted;
        // Flag to control if transfers are unrestricted (true) or only whitelisted (false)
        bool transfersAllowed;
        // Address of the ERC20 token used for yield distribution (e.g., USDC)
        address yieldToken;
        // Set of all current token holders (for distribution purposes)
        EnumerableSet.AddressSet holders;
        // Added for asset valuation tracking
        uint256 assetValuation; // Total valuation of the company in the same unit as yieldToken (e.g., USD)
        string assetName; // Name of the underlying asset (e.g., "Mineral Vault I")
        // Token URI storage
        string baseURI;
        string tokenURI;
        // Financial metrics
        uint256 tokenIssuePrice; // Price at which tokens are issued (scaled by 1e18)
        uint256 accrualRatePerSecond; // Accrual rate per second (scaled by 1e18)
        uint256 totalTokenOffering; // Total number of tokens available for sale
        // Purchase tracking
        mapping(address => uint256) purchaseTimestamp; // When each holder purchased their tokens
    }

    // Calculate a unique storage slot for ArcTokenStorage (EIP-7201 standard).
    // keccak256(abi.encode(uint256(keccak256("asset.token.storage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ARC_TOKEN_STORAGE_LOCATION =
        0xf52c08b2e4132efdd78c079b339999bf65bd68aae758ed08b1bb84dc8f47c000;

    function _getArcTokenStorage() private pure returns (ArcTokenStorage storage $) {
        assembly {
            $.slot := ARC_TOKEN_STORAGE_LOCATION
        }
    }

    // -------------- Events --------------
    event WhitelistStatusChanged(address indexed account, bool isWhitelisted);
    event TransfersRestrictionToggled(bool transfersAllowed);
    event YieldDistributed(uint256 amount);
    event YieldTokenUpdated(address indexed newYieldToken);
    event AssetValuationUpdated(uint256 newValuation);
    event AssetNameUpdated(string newAssetName);
    event BaseURIUpdated(string newBaseURI);
    event TokenURIUpdated(string newTokenURI);
    event TokenMetricsUpdated(uint256 tokenIssuePrice, uint256 accrualRatePerSecond, uint256 totalTokenOffering);
    event TokenPurchased(address indexed buyer, uint256 amount, uint256 timestamp);
    event TokenPriceUpdated(uint256 newIssuePrice);

    // -------------- Initializer --------------
    /**
     * @dev Initialize the token with name, symbol, asset name, valuation, and supply.
     *      The deployer becomes the default admin. Transfers are unrestricted by default.
     * @param name_ Token name (e.g., "aMNRL")
     * @param symbol_ Token symbol (e.g., "aMNRL")
     * @param assetName_ Name of the underlying asset (e.g., "Mineral Vault I")
     * @param initialSupply_ Initial token supply to mint to the admin
     * @param yieldToken_ Address of the ERC20 token for yield distribution (e.g., USDC).
     *                    Can be address(0) if setting later.
     * @param tokenIssuePrice_ Price at which tokens are issued (scaled by 1e18)
     * @param totalTokenOffering_ Total number of tokens available for sale
     */
    function initialize(
        string memory name_,
        string memory symbol_,
        string memory assetName_,
        uint256 initialSupply_,
        address yieldToken_,
        uint256 tokenIssuePrice_,
        uint256 totalTokenOffering_
    ) public initializer {
        __ERC20_init(name_, symbol_);
        __AccessControl_init();
        __ReentrancyGuard_init();

        ArcTokenStorage storage $ = _getArcTokenStorage();

        // Set up roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(MANAGER_ROLE, msg.sender);
        _grantRole(YIELD_MANAGER_ROLE, msg.sender);
        _grantRole(YIELD_DISTRIBUTOR_ROLE, msg.sender);

        // Set initial transfer restriction (true = unrestricted transfers)
        $.transfersAllowed = true;

        // Set asset-specific information
        $.assetName = assetName_;
        // Calculate asset valuation from token issue price and total offering
        $.assetValuation = tokenIssuePrice_ * totalTokenOffering_ / 1e18;

        // Set financial metrics
        $.tokenIssuePrice = tokenIssuePrice_;
        // Remove accrualRatePerSecond - it's no longer used
        $.accrualRatePerSecond = 0;
        $.totalTokenOffering = totalTokenOffering_;

        // Set initial yield token if provided
        if (yieldToken_ != address(0)) {
            $.yieldToken = yieldToken_;
        }

        // By default, whitelist the admin so they can receive and transfer tokens
        $.isWhitelisted[msg.sender] = true;
        $.holders.add(msg.sender);
        emit WhitelistStatusChanged(msg.sender, true);

        // Mint initial supply to the admin
        if (initialSupply_ > 0) {
            _mint(msg.sender, initialSupply_);
        }

        emit TokenMetricsUpdated(tokenIssuePrice_, 0, totalTokenOffering_);
    }

    // -------------- Asset Information --------------
    /**
     * @dev Update the asset valuation. Only accounts with MANAGER_ROLE can update this.
     * @param newValuation The new valuation of the company in yield token units
     */
    function updateAssetValuation(
        uint256 newValuation
    ) external onlyRole(MANAGER_ROLE) {
        _getArcTokenStorage().assetValuation = newValuation;
        emit AssetValuationUpdated(newValuation);
    }

    /**
     * @dev Update the asset name. Only accounts with MANAGER_ROLE can update this.
     * @param newAssetName The new name of the underlying asset
     */
    function updateAssetName(
        string memory newAssetName
    ) external onlyRole(MANAGER_ROLE) {
        _getArcTokenStorage().assetName = newAssetName;
        emit AssetNameUpdated(newAssetName);
    }

    /**
     * @dev Get current asset information
     * @return assetName The name of the underlying asset
     * @return assetValuation The current valuation of the company
     * @return pricePerToken The calculated price per token based on total supply and valuation
     */
    function getAssetInfo()
        external
        view
        returns (string memory assetName, uint256 assetValuation, uint256 pricePerToken)
    {
        ArcTokenStorage storage $ = _getArcTokenStorage();
        assetName = $.assetName;
        assetValuation = $.assetValuation;

        uint256 supply = totalSupply();
        pricePerToken = supply > 0 ? assetValuation / supply : 0;
    }

    // -------------- Whitelist Control --------------
    /**
     * @dev Adds an account to the whitelist, allowing it to hold and transfer tokens when transfers are restricted.
     */
    function addToWhitelist(
        address account
    ) external onlyRole(MANAGER_ROLE) {
        ArcTokenStorage storage $ = _getArcTokenStorage();
        if ($.isWhitelisted[account]) {
            revert AlreadyWhitelisted(account);
        }
        $.isWhitelisted[account] = true;
        emit WhitelistStatusChanged(account, true);
    }

    /**
     * @dev Adds multiple accounts to the whitelist in a single transaction.
     * @param accounts Array of addresses to add to the whitelist
     */
    function batchAddToWhitelist(
        address[] calldata accounts
    ) external onlyRole(MANAGER_ROLE) {
        ArcTokenStorage storage $ = _getArcTokenStorage();
        for (uint256 i = 0; i < accounts.length; i++) {
            address account = accounts[i];
            if (!$.isWhitelisted[account]) {
                $.isWhitelisted[account] = true;
                emit WhitelistStatusChanged(account, true);
            }
        }
    }

    /**
     * @dev Removes an account from the whitelist, preventing transfers when restrictions are enabled.
     * Accounts not whitelisted cannot send or receive tokens while transfers are restricted.
     */
    function removeFromWhitelist(
        address account
    ) external onlyRole(MANAGER_ROLE) {
        ArcTokenStorage storage $ = _getArcTokenStorage();
        if (!$.isWhitelisted[account]) {
            revert NotWhitelisted(account);
        }
        $.isWhitelisted[account] = false;
        emit WhitelistStatusChanged(account, false);
    }

    /**
     * @dev Checks if an account is whitelisted.
     */
    function isWhitelisted(
        address account
    ) external view returns (bool) {
        return _getArcTokenStorage().isWhitelisted[account];
    }

    // -------------- Transfer Restrictions Toggle --------------
    /**
     * @dev Toggles transfer restrictions. When `transfersAllowed` is true, anyone can transfer tokens.
     * When false, only whitelisted addresses can send/receive tokens.
     */
    function setTransfersAllowed(
        bool allowed
    ) external onlyRole(ADMIN_ROLE) {
        _getArcTokenStorage().transfersAllowed = allowed;
        emit TransfersRestrictionToggled(allowed);
    }

    /**
     * @dev Returns true if token transfers are currently unrestricted (open to all).
     */
    function transfersAllowed() external view returns (bool) {
        return _getArcTokenStorage().transfersAllowed;
    }

    // -------------- Minting and Burning --------------
    /**
     * @dev Mints new tokens to an account. Only accounts with MANAGER_ROLE can call this.
     * The recipient must be whitelisted if transfers are restricted.
     */
    function mint(address to, uint256 amount) external onlyRole(MANAGER_ROLE) {
        _mint(to, amount);
    }

    /**
     * @dev Burns tokens from an account, reducing the total supply. Only accounts with MANAGER_ROLE can call this.
     */
    function burn(address from, uint256 amount) external onlyRole(MANAGER_ROLE) {
        _burn(from, amount);
    }

    // -------------- Yield Distribution --------------
    /**
     * @dev Sets or updates the ERC20 token to use for yield distribution (e.g., USDC).
     * Only accounts with YIELD_MANAGER_ROLE can update this.
     */
    function setYieldToken(
        address yieldTokenAddr
    ) external onlyRole(YIELD_MANAGER_ROLE) {
        if (yieldTokenAddr == address(0)) {
            revert InvalidYieldTokenAddress();
        }
        _getArcTokenStorage().yieldToken = yieldTokenAddr;
        emit YieldTokenUpdated(yieldTokenAddr);
    }

    /**
     * @dev Get a preview of the yield distribution for token holders.
     * This allows the yield distributor to check how much each holder would receive before
     * actually distributing yield.
     * @param amount The amount of yield token to preview distribution for
     * @return holders Array of token holder addresses
     * @return amounts Array of amounts each holder would receive
     */
    function previewYieldDistribution(
        uint256 amount
    ) external view returns (address[] memory holders, uint256[] memory amounts) {
        ArcTokenStorage storage $ = _getArcTokenStorage();
        if ($.yieldToken == address(0)) {
            revert YieldTokenNotSet();
        }
        if (totalSupply() == 0) {
            revert NoTokensInCirculation();
        }

        uint256 holderCount = $.holders.length();
        holders = new address[](holderCount);
        amounts = new uint256[](holderCount);

        uint256 supply = totalSupply();
        uint256 totalPreviewAmount = 0;

        // Calculate distribution for all but last holder
        for (uint256 i = 0; i < holderCount; i++) {
            address holder = $.holders.at(i);
            holders[i] = holder;

            uint256 holderBalance = balanceOf(holder);
            if (holderBalance == 0) {
                amounts[i] = 0;
                continue;
            }

            uint256 share = (amount * holderBalance) / supply;

            // For the last holder, give them the remainder to ensure full distribution
            if (i == holderCount - 1) {
                amounts[i] = amount - totalPreviewAmount;
            } else {
                amounts[i] = share;
                totalPreviewAmount += share;
            }
        }

        return (holders, amounts);
    }

    /**
     * @dev Distribute yield to token holders directly.
     * Each holder receives a portion of the yield proportional to their token balance.
     * @param amount The amount of yield token to distribute.
     * NOTE: The caller must have approved this contract to transfer `amount` of the yield token on their behalf.
     */
    function distributeYield(
        uint256 amount
    ) external onlyRole(YIELD_DISTRIBUTOR_ROLE) nonReentrant {
        ArcTokenStorage storage $ = _getArcTokenStorage();
        if ($.yieldToken == address(0)) {
            revert YieldTokenNotSet();
        }
        if (totalSupply() == 0) {
            revert NoTokensInCirculation();
        }
        ERC20Upgradeable yToken = ERC20Upgradeable($.yieldToken);

        // Transfer yield tokens from caller into this contract
        yToken.safeTransferFrom(msg.sender, address(this), amount);

        uint256 supply = totalSupply();
        uint256 distributedSum = 0;
        uint256 holderCount = $.holders.length();

        // Distribute to all but last holder (to handle rounding remainders)
        for (uint256 i = 0; i < holderCount - 1; i++) {
            address holder = $.holders.at(i);
            uint256 holderBalance = balanceOf(holder);
            if (holderBalance == 0) {
                continue;
            }
            uint256 share = (amount * holderBalance) / supply;
            distributedSum += share;
            if (share > 0) {
                yToken.safeTransfer(holder, share);
            }
        }

        // Last holder gets the remaining amount to ensure full distribution
        if (holderCount > 0) {
            address lastHolder = $.holders.at(holderCount - 1);
            uint256 lastShare = amount - distributedSum;
            if (lastShare > 0) {
                yToken.safeTransfer(lastHolder, lastShare);
            }
        }

        emit YieldDistributed(amount);
    }

    // -------------- URI Management --------------
    /**
     * @dev Returns the URI for token metadata. This implementation returns the concatenation
     * of the `baseURI` and `tokenURI` if both are set. If `tokenURI` is empty, returns
     * just the `baseURI`. If both are empty, returns an empty string.
     * @notice The URI should point to a JSON metadata object that follows the ERC-1155/OpenSea
     * metadata standard format:
     * {
     *     "name": "Token Name",
     *     "symbol": "SYMBOL",
     *     "description": "Token description",
     *     "image": "https://...", // URL to token image
     *     "decimals": 18,
     *     "properties": {
     *         "assetName": "Asset Name",
     *         "assetValuation": "1000000",
     *         "tokenIssuePrice": "4200000000000000000000",
     *         "tokenRedemptionPrice": "4393120000000000000000",
     *         "dailyAccrualRate": "547950000000000",
     *         "projectedRedemptionPeriod": 90,
     *         "totalTokenOffering": "100",
     *         "irr": "200000000000000000"
     *     }
     * }
     */
    function uri() public view returns (string memory) {
        ArcTokenStorage storage $ = _getArcTokenStorage();

        bytes memory baseURIBytes = bytes($.baseURI);
        bytes memory tokenURIBytes = bytes($.tokenURI);

        if (baseURIBytes.length == 0 && tokenURIBytes.length == 0) {
            return "";
        }

        if (tokenURIBytes.length == 0) {
            return $.baseURI;
        }

        return string.concat($.baseURI, $.tokenURI);
    }

    /**
     * @dev Sets the base URI for computing the token URI. Only callable by MANAGER_ROLE.
     * @param newBaseURI The new base URI to set
     */
    function setBaseURI(
        string memory newBaseURI
    ) external onlyRole(MANAGER_ROLE) {
        ArcTokenStorage storage $ = _getArcTokenStorage();
        $.baseURI = newBaseURI;
        emit BaseURIUpdated(newBaseURI);
    }

    /**
     * @dev Sets the token-specific URI component. Only callable by MANAGER_ROLE.
     * @param newTokenURI The new token URI component to set
     */
    function setTokenURI(
        string memory newTokenURI
    ) external onlyRole(MANAGER_ROLE) {
        ArcTokenStorage storage $ = _getArcTokenStorage();
        $.tokenURI = newTokenURI;
        emit TokenURIUpdated(newTokenURI);
    }

    // -------------- Financial Metrics Management --------------
    /**
     * @dev Updates token issue price. Only callable by MANAGER_ROLE.
     * Price value should be scaled by 1e18.
     * @param newIssuePrice The new token issue price
     */
    function updateTokenPrice(
        uint256 newIssuePrice
    ) external onlyRole(MANAGER_ROLE) {
        if (newIssuePrice == 0) {
            revert IssuePriceMustBePositive();
        }

        ArcTokenStorage storage $ = _getArcTokenStorage();
        $.tokenIssuePrice = newIssuePrice;

        emit TokenPriceUpdated(newIssuePrice);
    }

    /**
     * @dev Updates the token's financial metrics. Only callable by MANAGER_ROLE.
     * All price values should be scaled by 1e18.
     */
    function updateTokenMetrics(
        uint256 tokenIssuePrice_,
        uint256 totalTokenOffering_
    ) external onlyRole(MANAGER_ROLE) {
        ArcTokenStorage storage $ = _getArcTokenStorage();
        $.tokenIssuePrice = tokenIssuePrice_;
        $.totalTokenOffering = totalTokenOffering_;

        // Update asset valuation based on new metrics
        $.assetValuation = tokenIssuePrice_ * totalTokenOffering_ / 1e18;

        emit TokenMetricsUpdated(tokenIssuePrice_, 0, totalTokenOffering_);
    }

    /**
     * @dev Returns all financial metrics for the token and the purchase timestamp
     */
    function getTokenMetrics(
        address holder
    )
        external
        view
        returns (uint256 tokenIssuePrice, uint256 totalTokenOffering, uint256 assetValuation, uint256 secondsHeld)
    {
        ArcTokenStorage storage $ = _getArcTokenStorage();

        // Calculate seconds held
        uint256 purchaseTime = $.purchaseTimestamp[holder];
        secondsHeld = purchaseTime > 0 ? block.timestamp - purchaseTime : 0;

        return ($.tokenIssuePrice, $.totalTokenOffering, $.assetValuation, secondsHeld);
    }

    // Override _update to track purchase timestamps and enforce transfer restrictions
    function _update(address from, address to, uint256 amount) internal virtual override {
        // Check transfer restrictions
        ArcTokenStorage storage $ = _getArcTokenStorage();
        if (!$.transfersAllowed && (!$.isWhitelisted[from] || !$.isWhitelisted[to])) {
            revert TransferRestricted();
        }

        super._update(from, to, amount);

        // If this is a purchase (transfer from admin to buyer)
        if (hasRole(ADMIN_ROLE, from) && to != address(0) && amount > 0) {
            $.purchaseTimestamp[to] = block.timestamp;
            emit TokenPurchased(to, amount, block.timestamp);
        }
    }

    /**
     * @dev Returns the decimals places of the token.
     * @return The number of decimals places (always returns 18 for this implementation)
     */
    function decimals() public pure override returns (uint8) {
        return 18;
    }

    /**
     * @dev Returns the name of the token.
     * @return The token name
     */
    function name() public view override returns (string memory) {
        return super.name();
    }

    /**
     * @dev Returns the symbol of the token.
     * @return The token symbol
     */
    function symbol() public view override returns (string memory) {
        return super.symbol();
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view override(AccessControlUpgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

}
