// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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

contract RoycoNestMarketHelper is Initializable, AccessControlUpgradeable, UUPSUpgradeable {

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // BoringVault struct with all needed references
    struct BoringVault {
        ITeller teller;
        IBoringVault vault;
        IAccountantWithRateProviders accountant;
        uint256 slippageBps; // Slippage in basis points (1% = 100)
        uint256 performanceBps; // Performance fee in basis points
        bool active; // Whether this vault is active
    }

    // Atomic Queue address (constant for all vaults)
    IAtomicQueue public atomicQueue;

    // Direct string to vault mapping
    mapping(string => BoringVault) public vaults;

    // Track all vault identifiers for iteration if needed
    string[] public vaultIdentifiers;
    mapping(string => bool) private vaultExists;

    // Events
    event VaultAdded(string identifier);
    event VaultRemoved(string identifier);
    event VaultUpdated(string identifier);
    event Deposited(string identifier, address indexed user, address asset, uint256 amount, uint256 mintedAmount);

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

        atomicQueue = IAtomicQueue(_atomicQueue);
    }

    /**
     * @dev Required by the UUPS module
     */
    function _authorizeUpgrade(
        address
    ) internal override onlyRole(ADMIN_ROLE) { }

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
        // Check if vault already exists and is active
        if (vaultExists[identifier] && vaults[identifier].active) {
            revert VaultAlreadyExists(identifier);
        }

        // Create or update the vault
        vaults[identifier] = BoringVault({
            teller: ITeller(teller),
            vault: IBoringVault(vault),
            accountant: IAccountantWithRateProviders(accountant),
            slippageBps: slippageBps,
            performanceBps: performanceBps,
            active: true
        });

        // Add identifier to tracking structures if it's new
        if (!vaultExists[identifier]) {
            vaultIdentifiers.push(identifier);
            vaultExists[identifier] = true;
        }

        emit VaultAdded(identifier);
    }

    /**
     * @dev Remove a vault configuration (deactivate it)
     */
    function removeVault(
        string memory identifier
    ) external onlyRole(ADMIN_ROLE) {
        if (!vaults[identifier].active) {
            revert VaultNotActive(identifier);
        }

        vaults[identifier].active = false;
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
        // If the vault doesn't exist in our tracking, add it
        if (!vaultExists[identifier]) {
            vaultIdentifiers.push(identifier);
            vaultExists[identifier] = true;
        }

        // Update the vault
        vaults[identifier] = BoringVault({
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
        if (!vaults[identifier].active) {
            revert VaultNotActive(identifier);
        }

        vaults[identifier].slippageBps = slippageBps;
        vaults[identifier].performanceBps = performanceBps;

        emit VaultUpdated(identifier);
    }

    /**
     * @dev Calculate minimum mint amount based on vault parameters
     */
    function calculateMinimumMint(
        string memory identifier,
        address depositAsset,
        uint256 depositAmount
    ) public view returns (uint256) {
        BoringVault storage boringVault = vaults[identifier];
        if (!boringVault.active) {
            revert VaultNotActive(identifier);
        }

        // Get rate from Accountant using the depositAsset
        uint256 rate = boringVault.accountant.getRateInQuote(IERC20(depositAsset));
        if (rate == 0) {
            revert InvalidRate();
        }

        // Get vault decimals
        uint8 vaultDecimals = boringVault.vault.decimals();

        // Calculate raw mint amount: (depositAmount * (10 ** vault.decimals)) / getRateInQuote
        uint256 rawMintAmount = (depositAmount * (10 ** vaultDecimals)) / rate;

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
        return vaultIdentifiers;
    }

    /**
     * @dev Check if a vault exists and is active
     */
    function isVaultActive(
        string memory identifier
    ) public view returns (bool) {
        return vaults[identifier].active;
    }

    /**
     * @dev Deposit assets using string identifier
     */
    function deposit(string memory identifier, address depositAsset, uint256 depositAmount) public returns (uint256) {
        BoringVault storage boringVault = vaults[identifier];
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

        // Emit event
        emit Deposited(identifier, msg.sender, depositAsset, depositAmount, mintedAmount);

        return mintedAmount;
    }

}
