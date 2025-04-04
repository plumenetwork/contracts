// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../src/RoycoNestMarketHelper.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/Test.sol";

// Mock interfaces for testing
contract MockTeller {

    function deposit(address depositAsset, uint256 depositAmount, uint256 minimumMint) external returns (uint256) {
        // Return the minimumMint for simplicity
        return minimumMint;
    }

}

contract MockBoringVault {

    function decimals() external pure returns (uint8) {
        return 18;
    }

}

contract MockLens {

    function borrowRatePerSecond() external pure returns (uint256) {
        return 1e9; // 1% per year approx
    }

    function totalSupply() external pure returns (uint256) {
        return 1_000_000e18;
    }

    function totalAssets() external pure returns (uint256) {
        return 1_100_000e18;
    }

}

contract MockAccountant {

    function getRateInQuote(
        address
    ) external pure returns (uint256) {
        return 2e18; // 2 USD per token
    }

}

contract MockERC20 {

    mapping(address => uint256) public balances;
    mapping(address => mapping(address => uint256)) public allowances;

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

    function depositToVault(address, address, uint256, uint256 minimumMint) external returns (uint256) {
        return minimumMint;
    }

}

contract RoycoNestMarketHelperTest is Test {

    RoycoNestMarketHelper implementation;
    RoycoNestMarketHelper marketHelper;

    MockTeller teller;
    MockBoringVault vault;
    MockLens lens;
    MockAccountant accountant;
    MockERC20 depositToken;
    MockAtomicQueue atomicQueue;

    address admin = address(1);
    address user = address(2);
    address pusdAddress = address(3);

    function setUp() public {
        // Deploy mock contracts
        teller = new MockTeller();
        vault = new MockBoringVault();
        lens = new MockLens();
        accountant = new MockAccountant();
        depositToken = new MockERC20();
        atomicQueue = new MockAtomicQueue();

        // Give user some tokens
        depositToken.mint(user, 1000e18);

        // Deploy implementation contract
        implementation = new RoycoNestMarketHelper();

        // Deploy proxy and initialize
        bytes memory initData = abi.encodeWithSelector(RoycoNestMarketHelper.initialize.selector, address(atomicQueue));

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);

        marketHelper = RoycoNestMarketHelper(address(proxy));

        // Set up roles
        vm.startPrank(admin);
        marketHelper.grantRole(marketHelper.ADMIN_ROLE(), admin);
        vm.stopPrank();
    }

    function testAddVault() public {
        vm.startPrank(admin);

        marketHelper.addVault(
            RoycoNestMarketHelper.VaultType.NELIXIR,
            address(teller),
            address(vault),
            address(lens),
            address(accountant),
            pusdAddress,
            100, // 1% slippage
            0 // 0% performance fee
        );

        assertEq(marketHelper.vaultCount(), 1);

        (
            address vaultTeller,
            address vaultAddr,
            address vaultLens,
            address vaultAccountant,
            address vaultQuote,
            uint256 slippageBps,
            uint256 performanceBps,
            bool active
        ) = marketHelper.vaults(0);

        assertEq(vaultTeller, address(teller));
        assertEq(vaultAddr, address(vault));
        assertEq(vaultLens, address(lens));
        assertEq(vaultAccountant, address(accountant));
        assertEq(vaultQuote, pusdAddress);
        assertEq(slippageBps, 100);
        assertEq(performanceBps, 0);
        assertTrue(active);

        vm.stopPrank();
    }

    function testUpdateVaultFees() public {
        vm.startPrank(admin);

        marketHelper.addVault(
            RoycoNestMarketHelper.VaultType.NELIXIR,
            address(teller),
            address(vault),
            address(lens),
            address(accountant),
            pusdAddress,
            100, // 1% slippage
            0 // 0% performance fee
        );

        marketHelper.updateVaultFees(0, 200, 50);

        (,,,,, uint256 slippageBps, uint256 performanceBps,) = marketHelper.vaults(0);

        assertEq(slippageBps, 200);
        assertEq(performanceBps, 50);

        vm.stopPrank();
    }

    function testCalculateMinimumMint() public {
        vm.startPrank(admin);

        marketHelper.addVault(
            RoycoNestMarketHelper.VaultType.NELIXIR,
            address(teller),
            address(vault),
            address(lens),
            address(accountant),
            pusdAddress,
            100, // 1% slippage
            0 // 0% performance fee
        );

        vm.stopPrank();

        uint256 depositAmount = 100e18;
        uint256 minimumMint = marketHelper.calculateMinimumMint(0, address(depositToken), depositAmount);

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
            RoycoNestMarketHelper.VaultType.NELIXIR,
            address(teller),
            address(vault),
            address(lens),
            address(accountant),
            pusdAddress,
            100, // 1% slippage
            0 // 0% performance fee
        );

        vm.stopPrank();

        vm.startPrank(user);
        depositToken.approve(address(marketHelper), 100e18);
        uint256 mintedAmount = marketHelper.deposit(0, address(depositToken), 100e18);
        vm.stopPrank();

        // Expected calculation:
        // rate = 2e18
        // decimals = 18
        // rawMintAmount = (100e18 * 10^18) / 2e18 = 50e18
        // reduction = 1% = 0.01
        // minimumMint = 50e18 * 0.99 = 49.5e18
        assertEq(mintedAmount, 495e17);
    }

    function testGetVaultStats() public {
        vm.startPrank(admin);

        marketHelper.addVault(
            RoycoNestMarketHelper.VaultType.NELIXIR,
            address(teller),
            address(vault),
            address(lens),
            address(accountant),
            pusdAddress,
            100, // 1% slippage
            0 // 0% performance fee
        );

        vm.stopPrank();

        (uint256 totalSupply, uint256 totalAssets, uint256 borrowRate, uint8 decimals) = marketHelper.getVaultStats(0);

        assertEq(totalSupply, 1_000_000e18);
        assertEq(totalAssets, 1_100_000e18);
        assertEq(borrowRate, 1e9);
        assertEq(decimals, 18);
    }

}
