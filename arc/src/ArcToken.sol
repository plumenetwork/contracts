// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "./restrictions/IRestrictionsRouter.sol";
import "./restrictions/ITransferRestrictions.sol";
import "./restrictions/IYieldRestrictions.sol";

/**
 * @title ArcToken
 * @author Eugene Y. Q. Shen, Alp Guneysel
 * @notice ERC20 token representing shares, delegating restriction logic to external modules via a router.
 * @dev Implements ERC20Upgradeable. Uses UUPS. Restriction checks are modular.
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
    error YieldTokenNotSet();
    error NoTokensInCirculation();
    error InvalidYieldTokenAddress();
    error IssuePriceMustBePositive();
    error InvalidAddress();
    error TransferRestricted();
    error YieldDistributionRestricted();
    error ZeroAmount();
    error ModuleNotSetForType(bytes32 typeId);
    error RouterNotSet();

    // -------------- Constants for Module Type IDs --------------
    bytes32 public constant TRANSFER_RESTRICTION_TYPE = keccak256("TRANSFER_RESTRICTION");
    bytes32 public constant YIELD_RESTRICTION_TYPE = keccak256("YIELD_RESTRICTION");
    bytes32 public constant GLOBAL_SANCTIONS_TYPE = keccak256("GLOBAL_SANCTIONS");

    // -------------- Storage --------------
    /// @custom:storage-location erc7201:asset.token.storage
    struct ArcTokenStorage {
        address restrictionsRouter;
        address yieldToken;
        EnumerableSet.AddressSet holders;
        string tokenURI;
        string updatedSymbol;
        string updatedName;
        uint8 tokenDecimals;
        mapping(bytes32 => address) specificRestrictionModules;
    }

    bytes32 private constant ARC_TOKEN_STORAGE_LOCATION =
        0xf52c08b2e4132efdd78c079b339999bf65bd68aae758ed08b1bb84dc8f47c000;

    function _getArcTokenStorage() private pure returns (ArcTokenStorage storage $) {
        assembly {
            $.slot := ARC_TOKEN_STORAGE_LOCATION
        }
    }

    // -------------- Events --------------
    event YieldDistributed(uint256 amount, address indexed token);
    event YieldTokenUpdated(address indexed newYieldToken);
    event TokenNameUpdated(string oldName, string newName);
    event TokenURIUpdated(string newTokenURI);
    event SymbolUpdated(string oldSymbol, string newSymbol);
    event SpecificRestrictionModuleSet(bytes32 indexed typeId, address indexed moduleAddress);

    // -------------- Initializer --------------
    /**
     * @dev Initialize the token with name, symbol, and supply.
     *      The deployer becomes the default admin.
     * @param name_ Token name (e.g., "Mineral Vault Fund I")
     * @param symbol_ Token symbol (e.g., "aMNRL")
     * @param initialSupply_ Initial token supply to mint to the admin
     * @param yieldToken_ Address of the ERC20 token for yield distribution.
     * @param initialTokenHolder_ Address that will receive the initial token supply
     * @param decimals_ Number of decimal places for the token (default is 18 if 0 is provided)
     * @param routerAddress_ Address of the deployed RestrictionsRouter proxy.
     */
    function initialize(
        string memory name_,
        string memory symbol_,
        uint256 initialSupply_,
        address yieldToken_,
        address initialTokenHolder_,
        uint8 decimals_,
        address routerAddress_
    ) public initializer {
        require(routerAddress_ != address(0), "Router address cannot be zero");

        __ERC20_init(name_, symbol_);
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        ArcTokenStorage storage $ = _getArcTokenStorage();

        $.restrictionsRouter = routerAddress_;

        $.tokenDecimals = decimals_ == 0 ? 18 : decimals_;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(MANAGER_ROLE, msg.sender);
        _grantRole(YIELD_MANAGER_ROLE, msg.sender);
        _grantRole(YIELD_DISTRIBUTOR_ROLE, msg.sender);

        $.holders.add(msg.sender);
        if (initialTokenHolder_ != msg.sender && initialTokenHolder_ != address(0)) {
            $.holders.add(initialTokenHolder_);
        }

        if (yieldToken_ != address(0)) {
            $.yieldToken = yieldToken_;
            emit YieldTokenUpdated(yieldToken_);
        }

        if (initialSupply_ > 0) {
            address recipient = initialTokenHolder_ != address(0) ? initialTokenHolder_ : msg.sender;
            _mint(recipient, initialSupply_);
        }
    }

    // -------------- Restrictions Module Management --------------
    /**
     * @dev Sets the address of a specific restriction module instance for this token.
     * @notice The router must have a module type registered for this typeId with isGlobal = false.
     * @param typeId The unique identifier for the module type (e.g., TRANSFER_RESTRICTION_TYPE).
     * @param moduleAddress The address of the deployed module instance (e.g., WhitelistRestrictions).
     */
    function setSpecificRestrictionModule(bytes32 typeId, address moduleAddress) external onlyRole(ADMIN_ROLE) {
        _getArcTokenStorage().specificRestrictionModules[typeId] = moduleAddress;
        emit SpecificRestrictionModuleSet(typeId, moduleAddress);
    }

    /**
     * @dev Returns the address of the specific restriction module instance for a given type.
     * @param typeId The unique identifier for the module type.
     */
    function getSpecificRestrictionModule(
        bytes32 typeId
    ) external view returns (address) {
        return _getArcTokenStorage().specificRestrictionModules[typeId];
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

    // -------------- Minting and Burning --------------
    /**
     * @dev Mints new tokens to an account. Only accounts with MINTER_ROLE can call this.
     */
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    /**
     * @dev Burns tokens from an account, reducing the total supply. Only accounts with BURNER_ROLE can call this.
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
     * @dev Helper function to check all relevant yield restrictions for an account.
     */
    function _isYieldAllowed(
        address account
    ) internal view returns (bool) {
        ArcTokenStorage storage $ = _getArcTokenStorage();
        bool allowed = true;

        address specificYieldModule = $.specificRestrictionModules[YIELD_RESTRICTION_TYPE];
        if (specificYieldModule != address(0)) {
            allowed = allowed && IYieldRestrictions(specificYieldModule).isYieldAllowed(account);
        }

        address routerAddr = $.restrictionsRouter;
        if (routerAddr == address(0)) {
            revert RouterNotSet();
        }
        address globalYieldModule = IRestrictionsRouter(routerAddr).getGlobalModuleAddress(GLOBAL_SANCTIONS_TYPE);
        if (globalYieldModule != address(0)) {
            try IYieldRestrictions(globalYieldModule).isYieldAllowed(account) returns (bool globalAllowed) {
                allowed = allowed && globalAllowed;
            } catch {
                // If global module doesn't implement IYieldRestrictions or call fails, treat as restricted?
                // Or handle based on specific global module design.
                // Current: Assume allowed if call fails/not implemented (less restrictive).
            }
        }

        return allowed;
    }

    /**
     * @dev Get a preview of the yield distribution for token holders.
     *      Accounts restricted by yield modules will show a share of 0.
     */
    function previewYieldDistribution(
        uint256 amount
    ) external returns (address[] memory holders, uint256[] memory amounts) {
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
        uint256 effectiveTotalSupply = 0;

        for (uint256 i = 0; i < holderCount; i++) {
            address holder = $.holders.at(i);
            if (_isYieldAllowed(holder)) {
                effectiveTotalSupply += balanceOf(holder);
            }
        }

        if (effectiveTotalSupply == 0) {
            return (holders, amounts);
        }

        uint256 lastProcessedIndex = holderCount > 0 ? holderCount - 1 : 0;
        for (uint256 i = 0; i < lastProcessedIndex; i++) {
            address holder = $.holders.at(i);
            holders[i] = holder;

            if (!_isYieldAllowed(holder)) {
                amounts[i] = 0;
                continue;
            }

            uint256 holderBalance = balanceOf(holder);
            if (holderBalance > 0) {
                uint256 share = (amount * holderBalance) / effectiveTotalSupply;
                amounts[i] = share;
                totalPreviewAmount += share;
            } else {
                amounts[i] = 0;
            }
        }

        if (holderCount > 0) {
            address lastHolder = $.holders.at(lastProcessedIndex);
            holders[lastProcessedIndex] = lastHolder;

            if (!_isYieldAllowed(lastHolder)) {
                amounts[lastProcessedIndex] = 0;
            } else {
                amounts[lastProcessedIndex] = amount - totalPreviewAmount;
            }
        }

        return (holders, amounts);
    }

    /**
     * @dev Get a preview of the yield distribution for a limited number of token holders.
     */
    function previewYieldDistributionWithLimit(
        uint256 amount,
        uint256 startIndex,
        uint256 maxHolders
    ) external returns (address[] memory holders, uint256[] memory amounts, uint256 nextIndex, uint256 totalHolders) {
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

        if (startIndex >= totalHolders) {
            startIndex = 0;
        }

        uint256 endIndex = startIndex + maxHolders;
        if (endIndex > totalHolders) {
            endIndex = totalHolders;
        }

        uint256 batchSize = endIndex - startIndex;
        if (batchSize == 0) {
            return (new address[](0), new uint256[](0), 0, totalHolders);
        }

        holders = new address[](batchSize);
        amounts = new uint256[](batchSize);

        uint256 effectiveTotalSupply = 0;
        for (uint256 i = 0; i < totalHolders; i++) {
            address holder = $.holders.at(i);
            if (_isYieldAllowed(holder)) {
                effectiveTotalSupply += balanceOf(holder);
            }
        }

        if (effectiveTotalSupply == 0) {
            nextIndex = endIndex < totalHolders ? endIndex : 0;
            return (holders, amounts, nextIndex, totalHolders);
        }

        ERC20Upgradeable yToken = ERC20Upgradeable($.yieldToken);
        amounts = new uint256[](batchSize);

        for (uint256 i = 0; i < batchSize; i++) {
            uint256 holderIndex = startIndex + i;
            address holder = $.holders.at(holderIndex);
            holders[i] = holder;

            if (!_isYieldAllowed(holder)) {
                amounts[i] = 0;
                continue;
            }

            uint256 holderBalance = balanceOf(holder);
            if (holderBalance > 0) {
                amounts[i] = (amount * holderBalance) / effectiveTotalSupply;
            } else {
                amounts[i] = 0;
            }
        }

        nextIndex = endIndex < totalHolders ? endIndex : 0;

        return (holders, amounts, nextIndex, totalHolders);
    }

    /**
     * @dev Distribute yield to token holders, skipping restricted accounts.
     *      Yield for restricted accounts remains in the contract.
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
        yToken.safeTransferFrom(msg.sender, address(this), amount);

        uint256 distributedSum = 0;
        uint256 holderCount = $.holders.length();
        if (holderCount == 0) {
            emit YieldDistributed(0, yieldTokenAddr);
            return;
        }

        uint256 effectiveTotalSupply = 0;
        for (uint256 i = 0; i < holderCount; i++) {
            address holder = $.holders.at(i);
            if (_isYieldAllowed(holder)) {
                effectiveTotalSupply += balanceOf(holder);
            }
        }

        if (effectiveTotalSupply == 0) {
            emit YieldDistributed(0, yieldTokenAddr);
            return;
        }

        uint256 lastProcessedIndex = holderCount > 0 ? holderCount - 1 : 0;
        for (uint256 i = 0; i < lastProcessedIndex; i++) {
            address holder = $.holders.at(i);

            if (!_isYieldAllowed(holder)) {
                continue;
            }

            uint256 holderBalance = balanceOf(holder);
            if (holderBalance > 0) {
                uint256 share = (amount * holderBalance) / effectiveTotalSupply;
                if (share > 0) {
                    yToken.safeTransfer(holder, share);
                    distributedSum += share;
                }
            }
        }

        if (holderCount > 0) {
            address lastHolder = $.holders.at(lastProcessedIndex);
            if (_isYieldAllowed(lastHolder)) {
                uint256 lastShare = amount - distributedSum;
                if (lastShare > 0) {
                    yToken.safeTransfer(lastHolder, lastShare);
                    distributedSum += lastShare;
                }
            }
        }

        emit YieldDistributed(distributedSum, yieldTokenAddr);
    }

    /**
     * @dev Distribute yield to a limited number of token holders, skipping restricted accounts.
     *      Yield for restricted accounts remains in the contract.
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

        if (startIndex >= totalHolders) {
            startIndex = 0;
        }

        uint256 endIndex = startIndex + maxHolders;
        if (endIndex > totalHolders) {
            endIndex = totalHolders;
        }

        uint256 batchSize = endIndex - startIndex;
        if (batchSize == 0) {
            return (0, totalHolders, 0);
        }

        uint256 effectiveTotalSupply = 0;
        for (uint256 i = 0; i < totalHolders; i++) {
            address holder = $.holders.at(i);
            if (_isYieldAllowed(holder)) {
                effectiveTotalSupply += balanceOf(holder);
            }
        }

        if (effectiveTotalSupply == 0) {
            nextIndex = endIndex < totalHolders ? endIndex : 0;
            return (nextIndex, totalHolders, 0);
        }

        ERC20Upgradeable yToken = ERC20Upgradeable(yieldTokenAddr);
        amountDistributed = 0;

        if (startIndex == 0) {
            yToken.safeTransferFrom(msg.sender, address(this), totalAmount);
        }

        for (uint256 i = 0; i < batchSize; i++) {
            uint256 holderIndex = startIndex + i;
            address holder = $.holders.at(holderIndex);

            if (!_isYieldAllowed(holder)) {
                continue;
            }

            uint256 holderBalance = balanceOf(holder);
            if (holderBalance > 0) {
                uint256 share = (totalAmount * holderBalance) / effectiveTotalSupply;
                if (share > 0) {
                    yToken.safeTransfer(holder, share);
                    amountDistributed += share;
                }
            }
        }

        nextIndex = endIndex < totalHolders ? endIndex : 0;

        if (nextIndex == 0) {
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

    // Override _update to track holders and enforce transfer restrictions via router/modules
    function _update(address from, address to, uint256 amount) internal virtual override {
        ArcTokenStorage storage $ = _getArcTokenStorage();

        bool transferAllowed = true;

        address routerAddr = $.restrictionsRouter;
        if (routerAddr == address(0)) {
            revert RouterNotSet();
        }

        address specificTransferModule = $.specificRestrictionModules[TRANSFER_RESTRICTION_TYPE];
        if (specificTransferModule != address(0)) {
            transferAllowed =
                transferAllowed && ITransferRestrictions(specificTransferModule).isTransferAllowed(from, to, amount);
        }

        address globalTransferModule = IRestrictionsRouter(routerAddr).getGlobalModuleAddress(GLOBAL_SANCTIONS_TYPE);
        if (globalTransferModule != address(0)) {
            try ITransferRestrictions(globalTransferModule).isTransferAllowed(from, to, amount) returns (
                bool globalAllowed
            ) {
                transferAllowed = transferAllowed && globalAllowed;
            } catch {
                transferAllowed = false;
            }
        }

        if (!transferAllowed) {
            revert TransferRestricted();
        }

        if (specificTransferModule != address(0)) {
            ITransferRestrictions(specificTransferModule).beforeTransfer(from, to, amount);
        }
        if (globalTransferModule != address(0)) {
            try ITransferRestrictions(globalTransferModule).beforeTransfer(from, to, amount) { }
                catch { /* Ignore if hook not implemented or fails? */ }
        }

        if (from != address(0)) {
            uint256 fromBalanceBefore = balanceOf(from);
            if (fromBalanceBefore == amount) {
                $.holders.remove(from);
            }
        }

        super._update(from, to, amount);

        if (to != address(0) && balanceOf(to) > 0) {
            $.holders.add(to);
        }

        if (specificTransferModule != address(0)) {
            ITransferRestrictions(specificTransferModule).afterTransfer(from, to, amount);
        }
        if (globalTransferModule != address(0)) {
            try ITransferRestrictions(globalTransferModule).afterTransfer(from, to, amount) { }
                catch { /* Ignore if hook not implemented or fails? */ }
        }
    }

}
