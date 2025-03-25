// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
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
contract ArcToken is ERC20Upgradeable, AccessControlUpgradeable, ReentrancyGuardUpgradeable, UUPSUpgradeable {

    using SafeERC20 for ERC20Upgradeable;
    using EnumerableSet for EnumerableSet.AddressSet;

    // -------------- Role Definitions --------------
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant YIELD_MANAGER_ROLE = keccak256("YIELD_MANAGER_ROLE");
    bytes32 public constant YIELD_DISTRIBUTOR_ROLE = keccak256("YIELD_DISTRIBUTOR_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    // -------------- Custom Errors --------------
    error AlreadyWhitelisted(address account);
    error NotWhitelisted(address account);
    error YieldTokenNotSet();
    error NoTokensInCirculation();
    error InvalidYieldTokenAddress();
    error IssuePriceMustBePositive();
    error InvalidAddress();
    error TransferRestricted();
    error ZeroAmount();

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
        // Token URI
        string tokenURI;
        // For symbol updating
        string updatedSymbol;
        // For name updating
        string updatedName;
        // Configurable decimal places for the token
        uint8 tokenDecimals;
    }

    // Calculate a unique storage slot for ArcTokenStorage (EIP-7201 standard).
    // keccak256(abi.encode(uint256(keccak256("arc.token.storage")) - 1)) & ~bytes32(uint256(0xff))
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
    event YieldDistributed(uint256 amount, address indexed token);
    event YieldTokenUpdated(address indexed newYieldToken);
    event TokenNameUpdated(string oldName, string newName);
    event TokenURIUpdated(string newTokenURI);
    event SymbolUpdated(string oldSymbol, string newSymbol);

    // -------------- Initializer --------------
    /**
     * @dev Initialize the token with name, symbol, and supply.
     *      The deployer becomes the default admin. Transfers are unrestricted by default.
     * @param name_ Token name (e.g., "Mineral Vault Fund I)")
     * @param symbol_ Token symbol (e.g., "aMNRL")
     * @param initialSupply_ Initial token supply to mint to the admin
     * @param yieldToken_ Address of the ERC20 token for yield distribution (e.g., USDC).
     *                    Can be address(0) if setting later.
     * @param initialTokenHolder_ Address that will receive the initial token supply
     * @param decimals_ Number of decimal places for the token (default is 18 if 0 is provided)
     */
    function initialize(
        string memory name_,
        string memory symbol_,
        uint256 initialSupply_,
        address yieldToken_,
        address initialTokenHolder_,
        uint8 decimals_
    ) public initializer {
        __ERC20_init(name_, symbol_);
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        ArcTokenStorage storage $ = _getArcTokenStorage();

        // Set token decimals (use 18 as default if 0 is provided)
        $.tokenDecimals = decimals_ == 0 ? 18 : decimals_;

        // Set up roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(MANAGER_ROLE, msg.sender);
        _grantRole(YIELD_MANAGER_ROLE, msg.sender);
        _grantRole(YIELD_DISTRIBUTOR_ROLE, msg.sender);

        // Set initial transfer restriction (true = unrestricted transfers)
        $.transfersAllowed = true;

        // By default, whitelist the admin so they can receive and transfer tokens
        $.isWhitelisted[msg.sender] = true;
        $.holders.add(msg.sender);
        emit WhitelistStatusChanged(msg.sender, true);

        // Also whitelist the initial token holder if it's not the admin
        if (initialTokenHolder_ != msg.sender && initialTokenHolder_ != address(0)) {
            $.isWhitelisted[initialTokenHolder_] = true;
            $.holders.add(initialTokenHolder_);
            emit WhitelistStatusChanged(initialTokenHolder_, true);
        }

        // Set the yield token if provided
        if (yieldToken_ != address(0)) {
            $.yieldToken = yieldToken_;
            emit YieldTokenUpdated(yieldToken_);
        }

        // Mint initial supply to the initial token holder if specified, otherwise to the admin
        if (initialSupply_ > 0) {
            address recipient = initialTokenHolder_ != address(0) ? initialTokenHolder_ : msg.sender;
            _mint(recipient, initialSupply_);
        }
    }

    // Backward compatibility for older deployment scripts
    function initializeWithDefaultDecimals(
        string memory name_,
        string memory symbol_,
        uint256 initialSupply_,
        address yieldToken_,
        address initialTokenHolder_
    ) public initializer {
        initialize(name_, symbol_, initialSupply_, yieldToken_, initialTokenHolder_, 18);
    }

    // -------------- Asset Information --------------
    /**
     * @dev Update the token name. Only accounts with MANAGER_ROLE can update this.
     * @param newName The new name for the token
     */
    function updateTokenName(
        string memory newName
    ) external onlyRole(MANAGER_ROLE) {
        ArcTokenStorage storage $ = _getArcTokenStorage();
        string memory oldName = name();
        $.updatedName = newName;
        emit TokenNameUpdated(oldName, newName);
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
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    /**
     * @dev Burns tokens from an account, reducing the total supply. Only accounts with MANAGER_ROLE can call this.
     */
    function burn(address from, uint256 amount) external onlyRole(BURNER_ROLE) {
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

        if (amount == 0) {
            revert ZeroAmount();
        }

        uint256 supply = totalSupply();
        if (supply == 0) {
            revert NoTokensInCirculation();
        }

        uint256 holderCount = $.holders.length();
        if (holderCount == 0) {
            return (new address[](0), new uint256[](0));
        }

        holders = new address[](holderCount);
        amounts = new uint256[](holderCount);

        uint256 totalPreviewAmount = 0;

        // Process all but last holder
        for (uint256 i = 0; i < holderCount - 1; i++) {
            address holder = $.holders.at(i);
            holders[i] = holder;

            uint256 holderBalance = balanceOf(holder);
            if (holderBalance > 0) {
                uint256 share = (amount * holderBalance) / supply;
                amounts[i] = share;
                totalPreviewAmount += share;
            } else {
                amounts[i] = 0;
            }
        }

        // Handle last holder separately to ensure full distribution
        uint256 lastIndex = holderCount - 1;
        address lastHolder = $.holders.at(lastIndex);
        holders[lastIndex] = lastHolder;

        // Last holder gets the remainder
        amounts[lastIndex] = amount - totalPreviewAmount;

        return (holders, amounts);
    }

    /**
     * @dev Get a preview of the yield distribution for a limited number of token holders.
     * Processes holders in batches to avoid excessive gas consumption.
     * @param amount The amount of yield token to preview distribution for
     * @param startIndex The index to start processing holders from
     * @param maxHolders The maximum number of holders to process (limited by gas constraints)
     * @return holders Array of token holder addresses (up to maxHolders)
     * @return amounts Array of amounts each holder would receive
     * @return nextIndex The index to use for the next batch (0 if all holders were processed)
     * @return totalHolders The total number of holders in the system
     */
    function previewYieldDistributionWithLimit(
        uint256 amount,
        uint256 startIndex,
        uint256 maxHolders
    )
        external
        view
        returns (address[] memory holders, uint256[] memory amounts, uint256 nextIndex, uint256 totalHolders)
    {
        ArcTokenStorage storage $ = _getArcTokenStorage();

        if (amount == 0) {
            revert ZeroAmount();
        }

        uint256 supply = totalSupply();
        if (supply == 0) {
            revert NoTokensInCirculation();
        }

        totalHolders = $.holders.length();
        if (totalHolders == 0) {
            return (new address[](0), new uint256[](0), 0, 0);
        }

        // If startIndex exceeds holder count, reset to 0
        if (startIndex >= totalHolders) {
            startIndex = 0;
        }

        // Calculate end index (exclusive)
        uint256 endIndex = startIndex + maxHolders;
        if (endIndex > totalHolders) {
            endIndex = totalHolders;
        }

        // Calculate actual number of holders in this batch
        uint256 batchSize = endIndex - startIndex;
        if (batchSize == 0) {
            return (new address[](0), new uint256[](0), 0, totalHolders);
        }

        // Create result arrays
        holders = new address[](batchSize);
        amounts = new uint256[](batchSize);

        // Process all holders in the batch
        for (uint256 i = 0; i < batchSize; i++) {
            uint256 holderIndex = startIndex + i;
            address holder = $.holders.at(holderIndex);
            holders[i] = holder;

            uint256 holderBalance = balanceOf(holder);
            if (holderBalance > 0) {
                // Calculate this holder's share
                amounts[i] = (amount * holderBalance) / supply;
            } else {
                amounts[i] = 0;
            }
        }

        // Set the index for the next batch
        nextIndex = endIndex < totalHolders ? endIndex : 0;

        return (holders, amounts, nextIndex, totalHolders);
    }

    /**
     * @dev Distribute yield to token holders directly.
     * Each holder receives a portion of the yield proportional to their token balance.
     * The caller must have approved this contract to transfer `amount` of the yield token on their behalf.
     * @param amount The amount of yield token to distribute.
     */
    function distributeYield(
        uint256 amount
    ) external onlyRole(YIELD_DISTRIBUTOR_ROLE) nonReentrant {
        ArcTokenStorage storage $ = _getArcTokenStorage();

        if (amount == 0) {
            revert ZeroAmount();
        }

        uint256 supply = totalSupply();
        if (supply == 0) {
            revert NoTokensInCirculation();
        }

        address yieldTokenAddr = $.yieldToken;
        if (yieldTokenAddr == address(0)) {
            revert YieldTokenNotSet();
        }

        ERC20Upgradeable yToken = ERC20Upgradeable(yieldTokenAddr);

        // Transfer yield tokens from caller into this contract
        yToken.safeTransferFrom(msg.sender, address(this), amount);

        uint256 distributedSum = 0;
        uint256 holderCount = $.holders.length();
        if (holderCount == 0) {
            return;
        }

        // Distribute to all but last holder
        for (uint256 i = 0; i < holderCount - 1; i++) {
            address holder = $.holders.at(i);
            uint256 holderBalance = balanceOf(holder);

            if (holderBalance > 0) {
                uint256 share = (amount * holderBalance) / supply;
                if (share > 0) {
                    yToken.safeTransfer(holder, share);
                    distributedSum += share;
                }
            }
        }

        // Last holder gets the remaining amount to ensure full distribution
        address lastHolder = $.holders.at(holderCount - 1);
        uint256 lastShare = amount - distributedSum;

        if (lastShare > 0) {
            yToken.safeTransfer(lastHolder, lastShare);
        }

        emit YieldDistributed(amount, yieldTokenAddr);
    }

    /**
     * @dev Distribute yield to a limited number of token holders.
     * Processes holders in batches to avoid excessive gas consumption.
     * The caller must have approved this contract to transfer `totalAmount` of the yield token on their behalf.
     * @param totalAmount The total amount of yield token to distribute across all batches
     * @param startIndex The index to start processing holders from
     * @param maxHolders The maximum number of holders to process in this batch
     * @return nextIndex The index to use for the next batch (0 if all holders were processed)
     * @return totalHolders The total number of holders in the system
     * @return amountDistributed The amount of yield distributed in this batch
     */
    function distributeYieldWithLimit(
        uint256 totalAmount,
        uint256 startIndex,
        uint256 maxHolders
    )
        external
        onlyRole(YIELD_DISTRIBUTOR_ROLE)
        nonReentrant
        returns (uint256 nextIndex, uint256 totalHolders, uint256 amountDistributed)
    {
        ArcTokenStorage storage $ = _getArcTokenStorage();

        address yieldTokenAddr = $.yieldToken;
        if (yieldTokenAddr == address(0)) {
            revert YieldTokenNotSet();
        }

        if (totalAmount == 0) {
            revert ZeroAmount();
        }

        uint256 supply = totalSupply();
        if (supply == 0) {
            revert NoTokensInCirculation();
        }

        totalHolders = $.holders.length();
        if (totalHolders == 0) {
            return (0, 0, 0);
        }

        // If startIndex exceeds holder count, reset to 0
        if (startIndex >= totalHolders) {
            startIndex = 0;
        }

        // Calculate end index (exclusive)
        uint256 endIndex = startIndex + maxHolders;
        if (endIndex > totalHolders) {
            endIndex = totalHolders;
        }

        // Calculate actual number of holders in this batch
        uint256 batchSize = endIndex - startIndex;
        if (batchSize == 0) {
            return (0, totalHolders, 0);
        }

        ERC20Upgradeable yToken = ERC20Upgradeable(yieldTokenAddr);
        amountDistributed = 0;

        // For the first batch, transfer the yield tokens into this contract
        if (startIndex == 0) {
            yToken.safeTransferFrom(msg.sender, address(this), totalAmount);
        }

        // Process the specified batch of holders
        for (uint256 i = 0; i < batchSize; i++) {
            uint256 holderIndex = startIndex + i;
            address holder = $.holders.at(holderIndex);
            uint256 holderBalance = balanceOf(holder);

            if (holderBalance > 0) {
                // Calculate this holder's share
                uint256 share = (totalAmount * holderBalance) / supply;

                if (share > 0) {
                    yToken.safeTransfer(holder, share);
                    amountDistributed += share;
                }
            }
        }

        // Set the index for the next batch
        nextIndex = endIndex < totalHolders ? endIndex : 0;

        // If this is the last batch, distribute any remaining amount to the last holder
        if (nextIndex == 0 && amountDistributed < totalAmount) {
            address lastHolder = $.holders.at(totalHolders - 1);
            uint256 remainingAmount = totalAmount - amountDistributed;

            if (remainingAmount > 0) {
                yToken.safeTransfer(lastHolder, remainingAmount);
                amountDistributed += remainingAmount;
            }

            // Emit the event for the full distribution only after completing all batches
            emit YieldDistributed(totalAmount, yieldTokenAddr);
        }

        return (nextIndex, totalHolders, amountDistributed);
    }

    // -------------- URI Management --------------
    /**
     * @dev Returns the URI for token metadata.
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
     *         // other properties as needed
     *     }
     * }
     */
    function uri() public view returns (string memory) {
        return _getArcTokenStorage().tokenURI;
    }

    /**
     * @dev Sets the complete token URI. Only callable by MANAGER_ROLE.
     * @param newTokenURI The full URI including domain (e.g., "https://arc.plumenetwork.xyz/tokens/metadata.json")
     */
    function setTokenURI(
        string memory newTokenURI
    ) external onlyRole(MANAGER_ROLE) {
        ArcTokenStorage storage $ = _getArcTokenStorage();
        _getArcTokenStorage().tokenURI = newTokenURI;
        emit TokenURIUpdated(newTokenURI);
    }

    // -------------- Token Metadata Management --------------
    /**
     * @dev Updates the token symbol. Only accounts with MANAGER_ROLE can update this.
     * @param newSymbol The new symbol for the token
     */
    function updateTokenSymbol(
        string memory newSymbol
    ) external onlyRole(MANAGER_ROLE) {
        ArcTokenStorage storage $ = _getArcTokenStorage();
        string memory oldSymbol = symbol();
        $.updatedSymbol = newSymbol;
        emit SymbolUpdated(oldSymbol, newSymbol);
    }

    // Override _update to track holders and enforce transfer restrictions
    function _update(address from, address to, uint256 amount) internal virtual override {
        // Check transfer restrictions
        ArcTokenStorage storage $ = _getArcTokenStorage();
        if (!$.transfersAllowed && (!$.isWhitelisted[from] || !$.isWhitelisted[to])) {
            revert TransferRestricted();
        }

        // Check sender balance before transfer to determine if they'll have a zero balance after
        if (from != address(0)) {
            // Skip for minting
            uint256 fromBalanceBefore = balanceOf(from);
            if (fromBalanceBefore == amount) {
                // Will have zero balance after transfer, remove from holders
                $.holders.remove(from);
            }
        }

        // Call parent implementation to perform the transfer
        super._update(from, to, amount);

        // Add recipient to holders if they're receiving tokens and not burning
        if (to != address(0) && balanceOf(to) > 0) {
            // Skip for burning
            $.holders.add(to);
        }
    }

    /**
     * @dev Returns the decimals places of the token.
     * @return The number of decimals places configured for this token
     */
    function decimals() public view override returns (uint8) {
        return _getArcTokenStorage().tokenDecimals;
    }

    /**
     * @dev Returns the name of the token.
     * @return The token name
     */
    function name() public view override returns (string memory) {
        string memory updatedName = _getArcTokenStorage().updatedName;
        if (bytes(updatedName).length > 0) {
            return updatedName;
        }
        return super.name();
    }

    /**
     * @dev Returns the symbol of the token.
     * @return The token symbol
     */
    function symbol() public view override returns (string memory) {
        string memory updatedSymbol = _getArcTokenStorage().updatedSymbol;
        if (bytes(updatedSymbol).length > 0) {
            return updatedSymbol;
        }
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
    /**
     * @dev Authorization for upgrades
     */

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(UPGRADER_ROLE) { }

}
