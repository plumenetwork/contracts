// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
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
contract ArcToken is ERC20Upgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable {

    using SafeERC20 for ERC20Upgradeable;
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @custom:storage-location erc7201:asset.token.storage
    struct ArcTokenStorage {
        // Whitelist mapping (address => true if allowed to transfer/hold when restricted)
        mapping(address => bool) isWhitelisted;
        // Flag to control if transfers are unrestricted (true) or only whitelisted (false)
        bool transfersAllowed;
        // Address of the ERC20 token used for yield distribution (e.g., USDC)
        address yieldToken;
        // Yield distribution accounting
        uint256 yieldPerToken; // accumulated yield per token (scaled by 1e18)
        mapping(address => uint256) lastYieldPerToken; // last yield-per-token value seen by each holder
        mapping(address => uint256) unclaimedYield; // yield amount pending withdrawal for each holder
        // Set of all current token holders (for distribution purposes)
        EnumerableSet.AddressSet holders;
        // Added for asset valuation tracking
        uint256 assetValuation; // Total valuation of the company in the same unit as yieldToken (e.g., USD)
        string assetName; // Name of the underlying asset (e.g., "Mineral Vault I")
        mapping(uint256 => uint256) yieldHistory; // Timestamp -> amount mapping for yield distribution history
        uint256[] yieldDates; // Array of timestamps when yield was distributed
        // Flag to control yield distribution method (true = direct transfer, false = claimable)
        bool directYieldDistribution;
        // Token URI storage
        string baseURI;
        string tokenURI;
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
    event YieldDistributed(uint256 amount, bool directDistribution);
    event YieldClaimed(address indexed account, uint256 amount);
    event YieldTokenUpdated(address indexed newYieldToken);
    event AssetValuationUpdated(uint256 newValuation);
    event AssetNameUpdated(string newAssetName);
    event YieldDistributionMethodUpdated(bool isDirectDistribution);
    event BaseURIUpdated(string newBaseURI);
    event TokenURIUpdated(string newTokenURI);

    // -------------- Initializer --------------
    /**
     * @dev Initialize the token with name, symbol, asset name, valuation, and supply.
     *      The deployer becomes the owner (issuer). Transfers are restricted to whitelisted accounts by default.
     * @param name_ Token name (e.g., "aMNRL")
     * @param symbol_ Token symbol (e.g., "aMNRL")
     * @param assetName_ Name of the underlying asset (e.g., "Mineral Vault I")
     * @param assetValuation_ Initial valuation of the entire company in yield token units
     * @param initialSupply_ Initial token supply to mint to the owner
     * @param yieldToken_ Address of the ERC20 token for yield distribution (e.g., USDC).
     *                    Can be address(0) if setting later.
     */
    function initialize(
        string memory name_,
        string memory symbol_,
        string memory assetName_,
        uint256 assetValuation_,
        uint256 initialSupply_,
        address yieldToken_
    ) public initializer {
        __ERC20_init(name_, symbol_);
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();

        ArcTokenStorage storage $ = _getArcTokenStorage();

        // Set initial transfer restriction (false = restricted to whitelist)
        $.transfersAllowed = false;

        // Set initial yield distribution method (default to claimable)
        $.directYieldDistribution = false;

        // Set asset-specific information
        $.assetName = assetName_;
        $.assetValuation = assetValuation_;

        // Set initial yield token if provided
        if (yieldToken_ != address(0)) {
            $.yieldToken = yieldToken_;
        }

        // By default, whitelist the owner/issuer so they can receive and transfer tokens
        $.isWhitelisted[owner()] = true;
        $.holders.add(owner());
        emit WhitelistStatusChanged(owner(), true);

        // Mint initial supply to the owner
        if (initialSupply_ > 0) {
            _mint(owner(), initialSupply_);
        }
    }

    // -------------- Asset Information --------------
    /**
     * @dev Update the asset valuation. Only the owner (issuer) can update this.
     * @param newValuation The new valuation of the company in yield token units
     */
    function updateAssetValuation(
        uint256 newValuation
    ) external onlyOwner {
        _getArcTokenStorage().assetValuation = newValuation;
        emit AssetValuationUpdated(newValuation);
    }

    /**
     * @dev Update the asset name. Only the owner (issuer) can update this.
     * @param newAssetName The new name of the underlying asset
     */
    function updateAssetName(
        string memory newAssetName
    ) external onlyOwner {
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
    ) external onlyOwner {
        ArcTokenStorage storage $ = _getArcTokenStorage();
        require(!$.isWhitelisted[account], "Already whitelisted");
        $.isWhitelisted[account] = true;
        emit WhitelistStatusChanged(account, true);
    }

    /**
     * @dev Adds multiple accounts to the whitelist in a single transaction.
     * @param accounts Array of addresses to add to the whitelist
     */
    function batchAddToWhitelist(
        address[] calldata accounts
    ) external onlyOwner {
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
    ) external onlyOwner {
        ArcTokenStorage storage $ = _getArcTokenStorage();
        require($.isWhitelisted[account], "Not whitelisted");
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
    ) external onlyOwner {
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
     * @dev Mints new tokens to an account. Only the issuer (owner) can call this.
     * The recipient must be whitelisted if transfers are restricted.
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    /**
     * @dev Burns tokens from an account, reducing the total supply. Only the issuer (owner) can call this.
     * The owner can burn tokens from any account (for example, to redeem or reduce supply).
     */
    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }

    // -------------- Yield Distribution --------------
    /**
     * @dev Sets or updates the ERC20 token to use for yield distribution (e.g., USDC).
     * Only the issuer can update this.
     */
    function setYieldToken(
        address yieldTokenAddr
    ) external onlyOwner {
        require(yieldTokenAddr != address(0), "Invalid address");
        _getArcTokenStorage().yieldToken = yieldTokenAddr;
        emit YieldTokenUpdated(yieldTokenAddr);
    }

    /**
     * @dev Sets the yield distribution method between direct transfer and claimable.
     * Only the owner can update this.
     * @param isDirectDistribution If true, yields will be directly transferred to holders.
     *                            If false, holders must claim their yield.
     */
    function setYieldDistributionMethod(
        bool isDirectDistribution
    ) external onlyOwner {
        _getArcTokenStorage().directYieldDistribution = isDirectDistribution;
        emit YieldDistributionMethodUpdated(isDirectDistribution);
    }

    /**
     * @dev Returns the current yield distribution method
     * @return true if yields are directly distributed, false if they must be claimed
     */
    function isDirectYieldDistribution() external view returns (bool) {
        return _getArcTokenStorage().directYieldDistribution;
    }

    /**
     * @dev Get a preview of the yield distribution for token holders.
     * This allows the issuer to check how much each holder would receive before
     * actually distributing yiel$.
     * @param amount The amount of yield token to preview distribution for
     * @return holders Array of token holder addresses
     * @return amounts Array of amounts each holder would receive
     */
    function previewYieldDistribution(
        uint256 amount
    ) external view returns (address[] memory holders, uint256[] memory amounts) {
        ArcTokenStorage storage $ = _getArcTokenStorage();
        require($.yieldToken != address(0), "Yield token not set");
        require(totalSupply() > 0, "No tokens in circulation");

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
     * @dev Distribute yield to token holders.
     * Distribution method is determined by the directYieldDistribution flag:
     * - If true: directly transfers yield tokens to each holder
     * - If false: credits each holder with claimable yield
     * @param amount The amount of yield token to distribute.
     * NOTE: The issuer must have approved this contract to transfer `amount` of the yield token on their behalf.
     */
    function distributeYield(
        uint256 amount
    ) external onlyOwner nonReentrant {
        ArcTokenStorage storage $ = _getArcTokenStorage();
        require($.yieldToken != address(0), "Yield token not set");
        require(totalSupply() > 0, "No tokens in circulation");
        ERC20Upgradeable yToken = ERC20Upgradeable($.yieldToken);

        // Transfer yield tokens from issuer into this contract
        yToken.safeTransferFrom(msg.sender, address(this), amount);

        bool direct = $.directYieldDistribution;
        if (direct) {
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
        } else {
            // Use claim-based distribution: add to global yield tracker
            // (Yield tokens remain in contract until claimed by holders)
            uint256 supply = totalSupply();
            // Update the global yield-per-token accumulator
            // (scaled by 1e18 to handle fractional division)
            $.yieldPerToken += (amount * 1e18) / supply;
        }

        // Record the yield distribution in history
        uint256 timestamp = block.timestamp;
        $.yieldHistory[timestamp] = amount;
        $.yieldDates.push(timestamp);

        emit YieldDistributed(amount, direct);
    }

    /**
     * @dev Allows a token holder to claim any accumulated yield (in the configured yield token)
     * that has been allocated to them. Yield is accrued whenever `distributeYield` is called
     * (if distributed via the claim mechanism).
     */
    function claimYield() external nonReentrant {
        ArcTokenStorage storage $ = _getArcTokenStorage();
        require($.yieldToken != address(0), "Yield token not set");
        ERC20Upgradeable yToken = ERC20Upgradeable($.yieldToken);
        address account = msg.sender;

        // Calculate the claimable yield for `account`:
        // Unclaimed yield = (current balance * (global yieldPerToken - lastYieldPerToken[account]) / 1e18) + any stored
        // unclaimedYield.
        uint256 accountBalance = balanceOf(account);
        uint256 globalYieldPerToken = $.yieldPerToken;
        uint256 lastClaimedYieldPerToken = $.lastYieldPerToken[account];
        uint256 accumulated = 0;
        if (globalYieldPerToken > lastClaimedYieldPerToken) {
            // Yield from the last checkpoint to now
            uint256 delta = globalYieldPerToken - lastClaimedYieldPerToken;
            accumulated = (accountBalance * delta) / 1e18;
        }
        // Include any yield previously accrued (from past transfers or burns)
        accumulated += $.unclaimedYield[account];
        require(accumulated > 0, "No yield to claim");

        // Update state before transferring
        $.lastYieldPerToken[account] = globalYieldPerToken;
        $.unclaimedYield[account] = 0;

        // Transfer the yield tokens to the account
        yToken.safeTransfer(account, accumulated);
        emit YieldClaimed(account, accumulated);
    }

    /**
     * @dev Get the yield distribution history
     * @return dates Array of timestamps when yield was distributed
     * @return amounts Array of amounts distributed at each timestamp
     */
    function getYieldHistory() external view returns (uint256[] memory dates, uint256[] memory amounts) {
        ArcTokenStorage storage $ = _getArcTokenStorage();
        dates = $.yieldDates;
        amounts = new uint256[](dates.length);

        for (uint256 i = 0; i < dates.length; i++) {
            amounts[i] = $.yieldHistory[dates[i]];
        }

        return (dates, amounts);
    }

    /**
     * @dev Get the unclaimed yield amount for an account
     * @param account The address to check
     * @return unclaimedAmount The amount of yield tokens claimable by the account
     */
    function getUnclaimedYield(
        address account
    ) external view returns (uint256 unclaimedAmount) {
        ArcTokenStorage storage $ = _getArcTokenStorage();

        uint256 accountBalance = balanceOf(account);
        uint256 globalYieldPerToken = $.yieldPerToken;
        uint256 lastClaimedYieldPerToken = $.lastYieldPerToken[account];

        // Calculate accrued but not yet claimed yield
        if (globalYieldPerToken > lastClaimedYieldPerToken) {
            uint256 delta = globalYieldPerToken - lastClaimedYieldPerToken;
            unclaimedAmount = (accountBalance * delta) / 1e18;
        }

        // Add any previously stored unclaimed yield
        unclaimedAmount += $.unclaimedYield[account];

        return unclaimedAmount;
    }

    // -------------- URI Management --------------
    /**
     * @dev Returns the URI for token metadata. This implementation returns the concatenation
     * of the `baseURI` and `tokenURI` if both are set. If `tokenURI` is empty, returns
     * just the `baseURI`. If both are empty, returns an empty string.
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
     * @dev Sets the base URI for computing the token URI. Only callable by owner.
     * @param newBaseURI The new base URI to set
     */
    function setBaseURI(
        string memory newBaseURI
    ) external onlyOwner {
        ArcTokenStorage storage $ = _getArcTokenStorage();
        $.baseURI = newBaseURI;
        emit BaseURIUpdated(newBaseURI);
    }

    /**
     * @dev Sets the token-specific URI component. Only callable by owner.
     * @param newTokenURI The new token URI component to set
     */
    function setTokenURI(
        string memory newTokenURI
    ) external onlyOwner {
        ArcTokenStorage storage $ = _getArcTokenStorage();
        $.tokenURI = newTokenURI;
        emit TokenURIUpdated(newTokenURI);
    }

    // -------------- Internal Hooks --------------
    /**
     * @dev Internal function to handle token transfers, including whitelist restrictions
     * and yield accrual. This overrides the _update function from ERC20Upgradeable.
     */
    function _update(address from, address to, uint256 amount) internal virtual override {
        ArcTokenStorage storage $ = _getArcTokenStorage();

        // Enforce whitelist if transfers are restricted
        if (!$.transfersAllowed) {
            if (from != address(0)) {
                // not minting
                require($.isWhitelisted[from], "Sender not whitelisted");
            }
            if (to != address(0)) {
                // not burning
                require($.isWhitelisted[to], "Recipient not whitelisted");
            }
        }

        // Yield accrual logic: update unclaimed yield for sender and receiver
        // (This ensures yield up to the current distribution is assigned to the correct holder)
        if (amount > 0 && from != to) {
            uint256 globalYieldPerToken = $.yieldPerToken;
            if (from != address(0)) {
                // Credit any pending yield to the sender (for the tokens they are about to transfer or burn)
                uint256 senderBalance = balanceOf(from);
                if (senderBalance > 0) {
                    uint256 delta = globalYieldPerToken - $.lastYieldPerToken[from];
                    if (delta > 0) {
                        uint256 pendingYield = (senderBalance * delta) / 1e18;
                        if (pendingYield > 0) {
                            $.unclaimedYield[from] += pendingYield;
                        }
                    }
                }
                // Update sender's yield checkpoint to current
                $.lastYieldPerToken[from] = globalYieldPerToken;
            }
            if (to != address(0)) {
                // Credit any pending yield to the recipient (for tokens they already held before this transfer)
                uint256 receiverBalance = balanceOf(to);
                if (receiverBalance > 0) {
                    uint256 delta2 = globalYieldPerToken - $.lastYieldPerToken[to];
                    if (delta2 > 0) {
                        uint256 pendingYieldTo = (receiverBalance * delta2) / 1e18;
                        if (pendingYieldTo > 0) {
                            $.unclaimedYield[to] += pendingYieldTo;
                        }
                    }
                }
                // Update recipient's yield checkpoint to current
                $.lastYieldPerToken[to] = globalYieldPerToken;
            }
        }

        // Call parent implementation
        super._update(from, to, amount);

        // Update holders set
        if (from != address(0) && balanceOf(from) == 0) {
            // If `from` has no more tokens, remove from holders set
            $.holders.remove(from);
        }
        if (to != address(0) && amount > 0) {
            // If `to` receives tokens and was not a holder before, add to holders set
            $.holders.add(to);
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

}
