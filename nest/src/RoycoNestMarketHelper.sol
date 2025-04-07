// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

interface IAccountantWithRateProviders {

    function getRateInQuote(
        IERC20 quote
    ) external view returns (uint256 rateInQuote);

}

interface IBoringVault {

    function decimals() external view returns (uint8);

}

interface ITeller {

    function deposit(
        IERC20 depositAsset,
        uint256 depositAmount,
        uint256 minimumMint
    ) external payable returns (uint256 shares);

}

interface IAtomicQueue {

    struct AtomicRequest {
        uint64 deadline;
        uint88 atomicPrice;
        uint96 offerAmount;
        bool inSolve;
    }

    function updateAtomicRequest(IERC20 offer, IERC20 want, AtomicRequest memory userRequest) external;

}

// Custom errors
error VaultNotActive(string identifier);
error InvalidRate();
error VaultAlreadyExists(string identifier);
error InvalidOwner();
error InvalidController();

contract RoycoNestMarketHelper is Initializable, AccessControlUpgradeable, UUPSUpgradeable {

    using Math for uint256;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant CONTROLLER_ROLE = keccak256("CONTROLLER_ROLE");

    // BoringVault struct with all needed references
    struct BoringVault {
        ITeller teller;
        IBoringVault vault;
        IAccountantWithRateProviders accountant;
        uint256 slippageBps; // Slippage in basis points (1% = 100)
        uint256 performanceBps; // Performance fee in basis points
        bool active; // Whether this vault is active
    }

    /// @custom:storage-location erc7201:royco.storage.RoycoMarketHelper
    struct RoycoMarketHelperStorage {
        // Global atomic request parameters
        uint64 deadlinePeriod;
        uint256 pricePercentage;
        IAtomicQueue atomicQueue;
        // Direct string to vault mapping
        mapping(string => BoringVault) vaults;
        // Track all vault identifiers for iteration if needed
        string[] vaultIdentifiers;
        mapping(string => bool) vaultExists;
    }

    // keccak256(abi.encode(uint256(keccak256("royco.storage.RoycoMarketHelper")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ROYCO_MARKET_HELPER_STORAGE_LOCATION =
        0xd3dfe08e47e09d2daf2ebd77a9ad4b9c3d6d6a37cfad2eb9860008e9f3b2d600;

    function _getRoycoMarketHelperStorage() private pure returns (RoycoMarketHelperStorage storage $) {
        assembly {
            $.slot := ROYCO_MARKET_HELPER_STORAGE_LOCATION
        }
    }

    // Events
    event VaultAdded(string identifier);
    event VaultRemoved(string identifier);
    event VaultUpdated(string identifier);
    event Deposited(
        string identifier, address indexed user, address asset, uint256 amount, uint256 mintedAmount, address receiver
    );
    event WithdrawRequested(
        string identifier, address indexed user, address indexed asset, uint256 shares, uint64 deadline
    );
    event AtomicParametersUpdated(uint64 deadlinePeriod, uint256 pricePercentage, address atomicQueue);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _atomicQueue
    ) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(CONTROLLER_ROLE, msg.sender);

        RoycoMarketHelperStorage storage $ = _getRoycoMarketHelperStorage();
        $.atomicQueue = IAtomicQueue(_atomicQueue);
        $.deadlinePeriod = 3600; // 1 hour default
        $.pricePercentage = 9900; // 99% default (1% discount)
    }

    /**
     * @dev Required by the UUPS module
     */
    function _authorizeUpgrade(
        address
    ) internal override onlyRole(ADMIN_ROLE) { }

    /**
     * @dev Update atomic queue and related parameters
     * @param _atomicQueue New atomic queue address (if unchanged, pass 0)
     * @param _deadlinePeriod New deadline period in seconds
     * @param _pricePercentage New price percentage (10000 = 100%)
     */
    function updateAtomicParameters(
        address _atomicQueue,
        uint64 _deadlinePeriod,
        uint256 _pricePercentage
    ) external onlyRole(ADMIN_ROLE) {
        RoycoMarketHelperStorage storage $ = _getRoycoMarketHelperStorage();

        // Only update atomicQueue if a new address is provided
        if (_atomicQueue != address(0)) {
            $.atomicQueue = IAtomicQueue(_atomicQueue);
        }

        $.deadlinePeriod = _deadlinePeriod;
        $.pricePercentage = _pricePercentage;

        emit AtomicParametersUpdated($.deadlinePeriod, $.pricePercentage, address($.atomicQueue));
    }

    /**
     * @dev Get current atomic parameters
     */
    function getAtomicParameters()
        external
        view
        returns (address _atomicQueue, uint64 _deadlinePeriod, uint256 _pricePercentage)
    {
        RoycoMarketHelperStorage storage $ = _getRoycoMarketHelperStorage();
        return (address($.atomicQueue), $.deadlinePeriod, $.pricePercentage);
    }

    /**
     * @dev Get atomic queue address
     */
    function atomicQueue() external view returns (address) {
        return address(_getRoycoMarketHelperStorage().atomicQueue);
    }

    /**
     * @dev Get deadline period
     */
    function deadlinePeriod() external view returns (uint64) {
        return _getRoycoMarketHelperStorage().deadlinePeriod;
    }

    /**
     * @dev Get price percentage
     */
    function pricePercentage() external view returns (uint256) {
        return _getRoycoMarketHelperStorage().pricePercentage;
    }

    /**
     * @dev Add a new vault configuration
     */
    function addVault(
        string memory identifier,
        address teller,
        address vault,
        address accountant,
        uint256 slippageBps,
        uint256 performanceBps
    ) external onlyRole(ADMIN_ROLE) {
        RoycoMarketHelperStorage storage $ = _getRoycoMarketHelperStorage();

        // Check if vault already exists and is active
        if ($.vaultExists[identifier] && $.vaults[identifier].active) {
            revert VaultAlreadyExists(identifier);
        }

        // Create or update the vault
        $.vaults[identifier] = BoringVault({
            teller: ITeller(teller),
            vault: IBoringVault(vault),
            accountant: IAccountantWithRateProviders(accountant),
            slippageBps: slippageBps,
            performanceBps: performanceBps,
            active: true
        });

        // Add identifier to tracking structures if it's new
        if (!$.vaultExists[identifier]) {
            $.vaultIdentifiers.push(identifier);
            $.vaultExists[identifier] = true;
        }

        emit VaultAdded(identifier);
    }

    /**
     * @dev Remove a vault configuration (deactivate it)
     */
    function removeVault(
        string memory identifier
    ) external onlyRole(ADMIN_ROLE) {
        RoycoMarketHelperStorage storage $ = _getRoycoMarketHelperStorage();

        if (!$.vaults[identifier].active) {
            revert VaultNotActive(identifier);
        }

        $.vaults[identifier].active = false;
        emit VaultRemoved(identifier);
    }

    /**
     * @dev Update an existing vault configuration
     */
    function updateVault(
        string memory identifier,
        address teller,
        address vault,
        address accountant,
        uint256 slippageBps,
        uint256 performanceBps
    ) external onlyRole(ADMIN_ROLE) {
        RoycoMarketHelperStorage storage $ = _getRoycoMarketHelperStorage();

        // If the vault doesn't exist in our tracking, add it
        if (!$.vaultExists[identifier]) {
            $.vaultIdentifiers.push(identifier);
            $.vaultExists[identifier] = true;
        }

        // Update the vault
        $.vaults[identifier] = BoringVault({
            teller: ITeller(teller),
            vault: IBoringVault(vault),
            accountant: IAccountantWithRateProviders(accountant),
            slippageBps: slippageBps,
            performanceBps: performanceBps,
            active: true
        });

        emit VaultUpdated(identifier);
    }

    /**
     * @dev Update fees for a vault
     */
    function updateVaultFees(
        string memory identifier,
        uint256 slippageBps,
        uint256 performanceBps
    ) external onlyRole(ADMIN_ROLE) {
        RoycoMarketHelperStorage storage $ = _getRoycoMarketHelperStorage();

        if (!$.vaults[identifier].active) {
            revert VaultNotActive(identifier);
        }

        $.vaults[identifier].slippageBps = slippageBps;
        $.vaults[identifier].performanceBps = performanceBps;

        emit VaultUpdated(identifier);
    }

    /**
     * @dev Get vault details
     */
    function vaults(
        string memory identifier
    )
        external
        view
        returns (
            address teller,
            address vault,
            address accountant,
            uint256 slippageBps,
            uint256 performanceBps,
            bool active
        )
    {
        RoycoMarketHelperStorage storage $ = _getRoycoMarketHelperStorage();
        BoringVault storage boringVault = $.vaults[identifier];

        return (
            address(boringVault.teller),
            address(boringVault.vault),
            address(boringVault.accountant),
            boringVault.slippageBps,
            boringVault.performanceBps,
            boringVault.active
        );
    }

    /**
     * @dev Calculate minimum mint amount based on vault parameters
     */
    function calculateMinimumMint(
        string memory identifier,
        address depositAsset,
        uint256 depositAmount
    ) public view returns (uint256) {
        RoycoMarketHelperStorage storage $ = _getRoycoMarketHelperStorage();

        BoringVault storage boringVault = $.vaults[identifier];

        if (!boringVault.active) {
            revert VaultNotActive(identifier);
        }

        // Get rate from Accountant using the depositAsset
        // Note: rate already includes decimals (e.g., 2e18 for 2 USD)
        uint256 rate = boringVault.accountant.getRateInQuote(IERC20(depositAsset));
        if (rate == 0) {
            revert InvalidRate();
        }

        // Get vault decimals
        uint8 vaultDecimals = boringVault.vault.decimals();

        // Calculate raw mint amount with precision by multiplying first
        // Solidity 0.8+ will revert on overflow automatically
        uint256 decimalsMultiplier = 10 ** vaultDecimals;
        uint256 rawMintAmount = (depositAmount * decimalsMultiplier) / rate;

        // Skip fee reduction if both fees are zero
        if (boringVault.slippageBps == 0 && boringVault.performanceBps == 0) {
            return rawMintAmount;
        }

        // Apply slippage and performance fee reductions
        uint256 totalReductionBps = boringVault.slippageBps + boringVault.performanceBps;
        uint256 minimumMint = rawMintAmount * (10_000 - totalReductionBps) / 10_000;

        return minimumMint;
    }

    /**
     * @dev Get all vault identifiers
     */
    function getAllVaultIdentifiers() external view returns (string[] memory) {
        return _getRoycoMarketHelperStorage().vaultIdentifiers;
    }

    /**
     * @dev Check if a vault exists and is active
     */
    function isVaultActive(
        string memory identifier
    ) public view returns (bool) {
        return _getRoycoMarketHelperStorage().vaults[identifier].active;
    }

    /**
     * @dev Deposit assets using string identifier (backward compatibility)
     */
    function deposit(string memory identifier, address depositAsset, uint256 depositAmount) public returns (uint256) {
        return deposit(identifier, depositAsset, depositAmount, msg.sender);
    }

    /**
     * @dev Deposit assets using string identifier with a specified receiver
     * @param identifier The vault identifier
     * @param depositAsset The asset being deposited
     * @param depositAmount The amount to deposit
     * @param receiver The address that will receive the minted shares
     * @return The amount of shares minted
     */
    function deposit(
        string memory identifier,
        address depositAsset,
        uint256 depositAmount,
        address receiver
    ) public returns (uint256) {
        RoycoMarketHelperStorage storage $ = _getRoycoMarketHelperStorage();
        BoringVault storage boringVault = $.vaults[identifier];

        if (!boringVault.active) {
            revert VaultNotActive(identifier);
        }

        // Calculate minimum mint amount
        uint256 minimumMint = calculateMinimumMint(identifier, depositAsset, depositAmount);

        // Approve token transfer
        IERC20(depositAsset).transferFrom(msg.sender, address(this), depositAmount);
        IERC20(depositAsset).approve(address(boringVault.vault), depositAmount);

        // Call deposit on vault teller
        uint256 mintedAmount = boringVault.teller.deposit(IERC20(depositAsset), depositAmount, minimumMint);

        // Transfer the minted shares to the specified receiver if different from this contract
        if (receiver != address(this)) {
            IERC20(address(boringVault.vault)).transfer(receiver, mintedAmount);
        }

        // Emit event
        emit Deposited(identifier, msg.sender, depositAsset, depositAmount, mintedAmount, receiver);

        return mintedAmount;
    }

    /**
     * @dev Request withdrawal from a vault using atomic queue
     * @param identifier The vault identifier
     * @param assetToken The token to receive from the withdrawal
     * @param shares The amount of vault shares to withdraw
     */
    function withdraw(string memory identifier, IERC20 assetToken, uint96 shares) public {
        RoycoMarketHelperStorage storage $ = _getRoycoMarketHelperStorage();
        BoringVault storage boringVault = $.vaults[identifier];

        // Check vault is active
        if (!boringVault.active) {
            revert VaultNotActive(identifier);
        }

        // Transfer vault tokens from user to this contract
        IERC20 vaultToken = IERC20(address(boringVault.vault));
        vaultToken.transferFrom(msg.sender, address(this), shares);

        // Calculate atomic price based on rate and percentage
        uint256 rate = boringVault.accountant.getRateInQuote(assetToken);
        if (rate == 0) {
            revert InvalidRate();
        }

        // Calculate atomic price with percentage adjustment using global parameter
        uint88 atomicPrice = uint88(rate.mulDiv($.pricePercentage, 10_000));

        // Create atomic request with global deadline
        IAtomicQueue.AtomicRequest memory request = IAtomicQueue.AtomicRequest({
            deadline: uint64(block.timestamp + $.deadlinePeriod),
            atomicPrice: atomicPrice,
            offerAmount: shares,
            inSolve: false
        });

        // Approve atomicQueue to spend the vault tokens
        vaultToken.approve(address($.atomicQueue), shares);

        // Submit request to atomic queue
        $.atomicQueue.updateAtomicRequest(vaultToken, assetToken, request);

        // Emit event
        emit WithdrawRequested(
            identifier, msg.sender, address(assetToken), shares, uint64(block.timestamp + $.deadlinePeriod)
        );
    }

}
