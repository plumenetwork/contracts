// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../src/RoycoNestMarketHelper.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/Test.sol";

// Mock interfaces for testing
contract MockTeller {

    function deposit(IERC20, uint256, uint256 minimumMint) external pure returns (uint256) {
        // Return the minimumMint for simplicity
        return minimumMint;
    }

}

contract MockBoringVault {

    mapping(address => uint256) public balances;
    mapping(address => mapping(address => uint256)) public allowances;

    function decimals() external pure returns (uint8) {
        return 18;
    }

    // Add these functions to make it work with the withdraw test
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(allowances[from][msg.sender] >= amount, "Insufficient allowance");
        require(balances[from] >= amount, "Insufficient balance");

        allowances[from][msg.sender] -= amount;
        balances[from] -= amount;
        balances[to] += amount;

        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowances[msg.sender][spender] = amount;
        return true;
    }

    function mint(address to, uint256 amount) external {
        balances[to] += amount;
    }

    function balanceOf(
        address account
    ) external view returns (uint256) {
        return balances[account];
    }

}

contract MockAccountant {

    function getRateInQuote(
        IERC20
    ) external pure returns (uint256) {
        return 2e18; // 2 USD per token
    }

}

contract MockERC20 {

    string private _name;
    string private _symbol;
    uint8 private _decimals;

    mapping(address => uint256) public balances;
    mapping(address => mapping(address => uint256)) public allowances;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) {
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
    }

    function name() external view returns (string memory) {
        return _name;
    }

    function symbol() external view returns (string memory) {
        return _symbol;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external {
        balances[to] += amount;
    }

    function balanceOf(
        address account
    ) external view returns (uint256) {
        return balances[account];
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowances[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(allowances[from][msg.sender] >= amount, "Insufficient allowance");
        require(balances[from] >= amount, "Insufficient balance");

        allowances[from][msg.sender] -= amount;
        balances[from] -= amount;
        balances[to] += amount;

        return true;
    }

}

contract MockAtomicQueue {

    IERC20 public lastOffer;
    IERC20 public lastWant;

    // Store the request fields directly rather than as a struct
    uint64 public lastDeadline;
    uint88 public lastAtomicPrice;
    uint96 public lastOfferAmount;
    bool public lastInSolve;

    function updateAtomicRequest(IERC20 offer, IERC20 want, IAtomicQueue.AtomicRequest memory userRequest) external {
        lastOffer = offer;
        lastWant = want;
        lastDeadline = userRequest.deadline;
        lastAtomicPrice = userRequest.atomicPrice;
        lastOfferAmount = userRequest.offerAmount;
        lastInSolve = userRequest.inSolve;
    }

}

contract MockAccountantWithCustomRate {

    uint256 private rate = 2e18; // Default rate

    function getRateInQuote(
        IERC20
    ) external view returns (uint256) {
        return rate;
    }

    function setRate(
        uint256 newRate
    ) external {
        rate = newRate;
    }

}

contract RoycoNestMarketHelperTest is Test {

    RoycoNestMarketHelper implementation;
    RoycoNestMarketHelper marketHelper;

    MockTeller teller;
    MockBoringVault vault;
    MockAccountant accountant;
    MockERC20 depositToken;
    MockAtomicQueue atomicQueue;

    address admin = address(1);
    address user = address(2);

    string constant NELIXIR_VAULT = "nelixir";

    function setUp() public {
        // Deploy mock contracts
        teller = new MockTeller();
        vault = new MockBoringVault();
        accountant = new MockAccountant();
        depositToken = new MockERC20("Mock Token", "MTK", 18);
        atomicQueue = new MockAtomicQueue();

        // Give user some tokens
        depositToken.mint(user, 1000e18);

        // Deploy implementation contract
        implementation = new RoycoNestMarketHelper();

        // Deploy proxy and initialize
        bytes memory initData = abi.encodeWithSelector(RoycoNestMarketHelper.initialize.selector, address(atomicQueue));

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);

        marketHelper = RoycoNestMarketHelper(address(proxy));

        // Set up roles - first set admin as DEFAULT_ADMIN_ROLE
        vm.startPrank(address(this)); // Start as test contract which has DEFAULT_ADMIN_ROLE after initialization
        marketHelper.grantRole(marketHelper.DEFAULT_ADMIN_ROLE(), admin);
        marketHelper.grantRole(marketHelper.ADMIN_ROLE(), admin);
        marketHelper.grantRole(marketHelper.CONTROLLER_ROLE(), admin);
        vm.stopPrank();
    }

    function testAddVault() public {
        vm.startPrank(admin);

        marketHelper.addVault(
            NELIXIR_VAULT, // String identifier instead of enum
            address(teller),
            address(vault),
            address(accountant),
            100, // 1% slippage
            0 // 0% performance fee
        );

        // Verify the vault was properly added
        (
            address vaultTeller,
            address vaultAddr,
            address vaultAccountant,
            uint256 slippageBps,
            uint256 performanceBps,
            bool active
        ) = marketHelper.vaults(NELIXIR_VAULT);

        assertEq(vaultTeller, address(teller));
        assertEq(vaultAddr, address(vault));
        assertEq(vaultAccountant, address(accountant));
        assertEq(slippageBps, 100);
        assertEq(performanceBps, 0);
        assertTrue(active);

        vm.stopPrank();
    }

    function testUpdateVaultFees() public {
        vm.startPrank(admin);

        marketHelper.addVault(
            NELIXIR_VAULT,
            address(teller),
            address(vault),
            address(accountant),
            100, // 1% slippage
            0 // 0% performance fee
        );

        marketHelper.updateVaultFees(NELIXIR_VAULT, 200, 50);

        (,,, uint256 slippageBps, uint256 performanceBps,) = marketHelper.vaults(NELIXIR_VAULT);

        assertEq(slippageBps, 200);
        assertEq(performanceBps, 50);

        vm.stopPrank();
    }

    function testCalculateMinimumMint() public {
        vm.startPrank(admin);

        marketHelper.addVault(
            NELIXIR_VAULT,
            address(teller),
            address(vault),
            address(accountant),
            100, // 1% slippage
            0 // 0% performance fee
        );

        vm.stopPrank();

        uint256 depositAmount = 100e18;
        uint256 minimumMint = marketHelper.calculateMinimumMint(NELIXIR_VAULT, address(depositToken), depositAmount);

        // Expected calculation:
        // rate = 2e18
        // decimals = 18
        // rawMintAmount = (100e18 * 10^18) / 2e18 = 50e18
        // reduction = 1% = 0.01
        // minimumMint = 50e18 * 0.99 = 49.5e18
        assertEq(minimumMint, 495e17);
    }

    function testDeposit() public {
        vm.startPrank(admin);

        marketHelper.addVault(
            NELIXIR_VAULT,
            address(teller),
            address(vault),
            address(accountant),
            100, // 1% slippage
            0 // 0% performance fee
        );

        vm.stopPrank();

        vm.startPrank(user);
        depositToken.approve(address(marketHelper), 100e18);
        uint256 mintedAmount = marketHelper.deposit(NELIXIR_VAULT, address(depositToken), 100e18);
        vm.stopPrank();

        // Expected calculation:
        // rate = 2e18
        // decimals = 18
        // rawMintAmount = (100e18 * 10^18) / 2e18 = 50e18
        // reduction = 1% = 0.01
        // minimumMint = 50e18 * 0.99 = 49.5e18
        assertEq(mintedAmount, 495e17);
    }

    function testWithdraw() public {
        vm.startPrank(admin);

        marketHelper.addVault(
            NELIXIR_VAULT,
            address(teller),
            address(vault),
            address(accountant),
            100, // 1% slippage
            0 // 0% performance fee
        );

        vm.stopPrank();

        // First deposit some tokens
        vm.startPrank(user);
        depositToken.approve(address(marketHelper), 100e18);
        marketHelper.deposit(NELIXIR_VAULT, address(depositToken), 100e18);

        // Mint some vault tokens directly to the user
        // This simulates the user having vault tokens from the deposit
        vault.mint(user, 50e18);
        vault.approve(address(marketHelper), 50e18);

        // Withdraw
        marketHelper.withdraw(NELIXIR_VAULT, IERC20(address(depositToken)), 50e18);
        vm.stopPrank();

        // Verify AtomicQueue received the correct request
        assertEq(address(atomicQueue.lastOffer()), address(vault)); // Vault token
        assertEq(address(atomicQueue.lastWant()), address(depositToken)); // Want deposit token back
        assertEq(atomicQueue.lastOfferAmount(), 50e18); // Offering 50 vault tokens
    }

    function testAtomicParameters() public {
        vm.startPrank(admin);

        // Test initial values
        (address queueAddr, uint64 deadline, uint256 price) = marketHelper.getAtomicParameters();
        assertEq(queueAddr, address(atomicQueue));
        assertEq(deadline, 3600); // 1 hour default
        assertEq(price, 9800); // 98% default

        // Update parameters
        marketHelper.updateAtomicParameters(address(0), 7200, 9900);

        // Verify updates
        (queueAddr, deadline, price) = marketHelper.getAtomicParameters();
        assertEq(queueAddr, address(atomicQueue)); // Unchanged since we passed address(0)
        assertEq(deadline, 7200);
        assertEq(price, 9900);

        vm.stopPrank();
    }

    function testGetAllVaultIdentifiers() public {
        vm.startPrank(admin);

        marketHelper.addVault(NELIXIR_VAULT, address(teller), address(vault), address(accountant), 100, 0);

        marketHelper.addVault("stargate", address(teller), address(vault), address(accountant), 100, 0);

        string[] memory identifiers = marketHelper.getAllVaultIdentifiers();
        assertEq(identifiers.length, 2);
        assertEq(identifiers[0], NELIXIR_VAULT);
        assertEq(identifiers[1], "stargate");

        vm.stopPrank();
    }

    function testDepositWithLargeAmount() public {
        vm.startPrank(admin);

        marketHelper.addVault(
            NELIXIR_VAULT,
            address(teller),
            address(vault),
            address(accountant),
            100, // 1% slippage
            0 // 0% performance fee
        );

        vm.stopPrank();

        // Mint a large amount of tokens to the user
        uint256 largeAmount = 2_000_000 * 1e18; // 2 million tokens
        depositToken.mint(user, largeAmount);

        vm.startPrank(user);
        depositToken.approve(address(marketHelper), largeAmount);

        // Calculate minimum mint amount manually to compare
        uint256 rate = 2e18; // The mock returns 2e18
        uint8 vaultDecimals = 18; // The mock returns 18
        uint256 decimalsMultiplier = 10 ** vaultDecimals;

        uint256 expectedRawMint;
        if (largeAmount <= type(uint256).max / decimalsMultiplier) {
            // Safe to multiply first
            expectedRawMint = (largeAmount * decimalsMultiplier) / rate;
        } else {
            // Fallback to divide first
            expectedRawMint = (largeAmount / rate) * decimalsMultiplier;
            if (largeAmount % rate > 0) {
                expectedRawMint += (largeAmount % rate) * decimalsMultiplier / rate;
            }
        }

        // Apply slippage reduction of 1%
        uint256 expectedMintAmount = expectedRawMint * 99 / 100;

        // Test the actual deposit
        uint256 mintedAmount = marketHelper.deposit(NELIXIR_VAULT, address(depositToken), largeAmount);

        // Verify the minted amount matches our expectation
        assertEq(mintedAmount, expectedMintAmount);

        vm.stopPrank();
    }

    function testDepositWithVaryingRates() public {
        vm.startPrank(admin);

        // Create a custom accountant that allows changing rates
        MockAccountantWithCustomRate customAccountant = new MockAccountantWithCustomRate();

        marketHelper.addVault(
            "variable_vault",
            address(teller),
            address(vault),
            address(customAccountant),
            100, // 1% slippage
            0 // 0% performance fee
        );

        vm.stopPrank();

        // Test amount to deposit
        uint256 testAmount = 1000 * 1e18; // 1000 tokens
        depositToken.mint(user, testAmount * 10); // Give enough tokens for multiple tests

        // Test with different rates
        uint256[] memory rates = new uint256[](3);
        rates[0] = 1e18; // 1:1 rate
        rates[1] = 10e18; // 1:10 rate (more expensive)
        rates[2] = 5e17; // 1:0.5 rate (cheaper)

        for (uint256 i = 0; i < rates.length; i++) {
            // Update the rate
            vm.prank(admin);
            customAccountant.setRate(rates[i]);

            // Calculate expected mint amount
            uint256 rawMintAmount = (testAmount * 1e18) / rates[i];
            uint256 expectedMintAmount = rawMintAmount * 99 / 100; // 1% slippage

            // Perform deposit
            vm.startPrank(user);
            depositToken.approve(address(marketHelper), testAmount);
            uint256 mintedAmount = marketHelper.deposit("variable_vault", address(depositToken), testAmount);
            vm.stopPrank();

            // Verify the minted amount matches our calculation
            assertEq(mintedAmount, expectedMintAmount, "Rate test failed");
        }
    }

    function testLargeDepositAmount() public {
        vm.startPrank(admin);

        marketHelper.addVault(
            NELIXIR_VAULT,
            address(teller),
            address(vault),
            address(accountant),
            100, // 1% slippage
            0 // 0% performance fee
        );

        vm.stopPrank();

        // Mint a large amount of tokens to the user
        uint256 largeAmount = 2_000_000 * 1e18; // 2 million tokens with 18 decimals
        depositToken.mint(user, largeAmount);

        vm.startPrank(user);
        depositToken.approve(address(marketHelper), largeAmount);

        // Calculate expected mint amount manually to compare
        // rate = 2e18 (from the mock)
        // rawMintAmount = (2_000_000 * 1e18 * 1e18) / 2e18 = 1_000_000 * 1e18
        // With 1% slippage: minimumMint = 1_000_000 * 1e18 * 0.99 = 990_000 * 1e18
        uint256 expectedMintAmount = 990_000 * 1e18;

        // Perform the deposit
        uint256 mintedAmount = marketHelper.deposit(NELIXIR_VAULT, address(depositToken), largeAmount);

        // Verify the minted amount matches our calculation
        assertEq(mintedAmount, expectedMintAmount);

        vm.stopPrank();
    }

    function testExtremeRates() public {
        vm.startPrank(admin);

        // Create accountant that can handle extreme rates
        MockAccountantWithCustomRate extremeAccountant = new MockAccountantWithCustomRate();

        marketHelper.addVault(
            "extreme_vault",
            address(teller),
            address(vault),
            address(extremeAccountant),
            100, // 1% slippage
            0 // 0% performance fee
        );

        vm.stopPrank();

        // Test with a very small amount and extreme rates
        uint256 smallAmount = 1 * 1e18; // 1 token
        depositToken.mint(user, smallAmount * 100); // Give tokens for tests

        // Test with extreme rates
        uint256[] memory extremeRates = new uint256[](2);
        extremeRates[0] = 1; // Extremely low rate
        extremeRates[1] = 1000 * 1e18; // Extremely high rate

        for (uint256 i = 0; i < extremeRates.length; i++) {
            // Update the rate
            vm.prank(admin);
            extremeAccountant.setRate(extremeRates[i]);

            // Calculate expected mint amount
            uint256 rawMintAmount = (smallAmount * 1e18) / extremeRates[i];
            uint256 expectedMintAmount = rawMintAmount * 99 / 100; // 1% slippage

            // Perform deposit
            vm.startPrank(user);
            depositToken.approve(address(marketHelper), smallAmount);
            uint256 mintedAmount = marketHelper.deposit("extreme_vault", address(depositToken), smallAmount);
            vm.stopPrank();

            // Verify the minted amount matches our calculation
            assertEq(mintedAmount, expectedMintAmount, "Extreme rate test failed");
        }
    }

}
