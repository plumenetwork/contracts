// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/AggregateToken.sol";
import "../src/interfaces/IComponentToken.sol";
import "../src/proxy/AggregateTokenProxy.sol";

interface IUSDT {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function decimals() external view returns (uint8);
}

interface IUSDC {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function decimals() external view returns (uint8);
    function allowance(address owner, address spender) external view returns (uint256);
}

interface ICredbullVault is IComponentToken {
    function currentPeriod() external view returns (uint256);
    function noticePeriod() external view returns (uint256);
    function balanceOf(address account, uint256 id) external view returns (uint256);
    function setApprovalForAll(address operator, bool approved) external;
    function asset() external view returns (address);
       // Add these role-related functions
    function OPERATOR_ROLE() external view returns (bytes32);
    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);
    function hasRole(bytes32 role, address account) external view returns (bool);
    function grantRole(bytes32 role, address account) external;
    function revokeRole(bytes32 role, address account) external;
    function getRoleMember(bytes32 role, uint256 index) external view returns (address);
    function getRoleMemberCount(bytes32 role) external view returns (uint256);

    // Also helpful to have these for debugging
    function unlockRequestAmount(address owner, uint256 requestId) external view returns (uint256);
    function claimableRedeemRequest(uint256 requestId, address controller) external view returns (uint256);
}

contract AggregateTokenTest is Test {
    // Contract addresses - testnet addresses
    address constant USDT_ADDRESS = 0x2413b8C79Ce60045882559f63d308aE3DFE0903d;
    address constant USDC_ADDRESS = 0x401eCb1D350407f13ba348573E5630B83638E30D;
    address constant CREDBULL_ADDRESS = 0x4B1fC984F324D2A0fDD5cD83925124b61175f5C6;

    ICredbullVault public constant CREDBULL_VAULT = ICredbullVault(CREDBULL_ADDRESS);
    IUSDT public constant USDT = IUSDT(USDT_ADDRESS);
    IUSDC public constant USDC = IUSDC(USDC_ADDRESS);
    
    // Test parameters
    uint256 constant TEST_AMOUNT = 1e6; // $1
    uint256 constant BASE = 1e18;

    // Contract instances
    AggregateToken public token;
    address public account;

     function setUp() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        account = vm.addr(privateKey);
        address controller = vm.addr(privateKey);

        console.log("Setting up test with account:", account);
        console.log("Test amount:", TEST_AMOUNT);

        vm.startBroadcast(privateKey);
        
    // First check if we need to become admin
    bytes32 adminRole = CREDBULL_VAULT.DEFAULT_ADMIN_ROLE();
    bool isAdmin = CREDBULL_VAULT.hasRole(adminRole, controller);
    
    if (!isAdmin) {
        // For testing, we can impersonate the current admin to grant our account admin rights
        // First, get the current admin
        address currentAdmin = CREDBULL_VAULT.getRoleMember(adminRole, 0);
        vm.stopBroadcast();
        vm.startPrank(currentAdmin);
        CREDBULL_VAULT.grantRole(adminRole, controller);
        vm.stopPrank();
        vm.startBroadcast(privateKey);
    }


        // Deploy implementation
        AggregateToken implementation = new AggregateToken();
        console.log("Implementation deployed at:", address(implementation));
        
        // Initialize with USDC as asset token
        bytes memory initData = abi.encodeCall(
            AggregateToken.initialize,
            (
                account,                   // owner
                "Test Aggregate USD",      // name
                "tAUSD",                  // symbol
                IComponentToken(USDC_ADDRESS),  // USDC as asset token
                BASE,                     // ask price
                BASE                      // bid price
            )
        );

        // Deploy proxy
        AggregateTokenProxy proxy = new AggregateTokenProxy(
            address(implementation),
            initData
        );
        console.log("Proxy deployed at:", address(proxy));
        
        token = AggregateToken(address(proxy));

        // Add Credbull vault as component
        token.addComponentToken(IComponentToken(address(CREDBULL_VAULT)));
        console.log("Credbull vault added as component");
        
        // Set up approvals
        USDC.approve(address(token), type(uint256).max);
        console.log("USDC approved for AggregateToken");
        console.log("USDC allowance:", USDC.allowance(account, address(token)));

        USDC.approve(address(CREDBULL_VAULT), type(uint256).max);
        console.log("USDC approved for Credbull");
        console.log("USDC allowance for Credbull:", USDC.allowance(account, address(CREDBULL_VAULT)));
        
        token.approveComponentToken(CREDBULL_VAULT, type(uint256).max);
        CREDBULL_VAULT.setApprovalForAll(address(token), true);
        console.log("Component approvals set");
        
    bytes32 operatorRole = CREDBULL_VAULT.OPERATOR_ROLE();
    if(!CREDBULL_VAULT.hasRole(operatorRole, address(token))) {
        CREDBULL_VAULT.grantRole(operatorRole, address(token));
    }
    



        vm.stopBroadcast();

        // Log initial state
        console.log("\n=== Initial State ===");
        console.log("USDC Balance:", USDC.balanceOf(account));
        console.log("AggregateToken Asset:", token.asset());
        console.log("Credbull Asset:", CREDBULL_VAULT.asset());
    }

function testComponentTokenFlow() public {
    uint256 privateKey = vm.envUint("PRIVATE_KEY");
    address controller = vm.addr(privateKey);
    vm.startBroadcast(privateKey);
    
    // Step 1: Deposit USDC to get aggregate tokens
    uint256 shares = token.deposit(TEST_AMOUNT, controller, controller);
    console.log("Deposited shares:", shares);

    // Step 2: Buy component token (Credbull Vault tokens)
    token.buyComponentToken(CREDBULL_VAULT, TEST_AMOUNT);
    console.log("Bought Credbull tokens");

    uint256 currentPeriod = CREDBULL_VAULT.currentPeriod();
    console.log("Current Period:", currentPeriod);

    // Get balances
    uint256 balance = CREDBULL_VAULT.balanceOf(address(token), currentPeriod);
    console.log("Balance at current period:", balance);

    // Step 3: We need to make our request through the AggregateToken
    vm.stopBroadcast();
    vm.startPrank(address(token));  // Act as the AggregateToken

    // Request redeem as the AggregateToken
    CREDBULL_VAULT.requestRedeem(
        TEST_AMOUNT,
        address(token),  // controller
        address(token)   // owner
    );
    console.log("Redeem requested");

    // Step 4: Wait notice period
    uint256 noticePeriod = CREDBULL_VAULT.noticePeriod();
    vm.warp(block.timestamp + noticePeriod * 1 days);
    console.log("Time warped");

    vm.stopPrank();
    vm.startBroadcast(privateKey);

    // Step 5: Now try to sell component token
    token.sellComponentToken(CREDBULL_VAULT, TEST_AMOUNT);
    console.log("Successfully sold Credbull tokens");

    vm.stopBroadcast();
}

// Add helper function to check state
function testCheckBalances() public view {
    console.log("\n=== Balances ===");
    address tokenAddr = address(token);
    uint256 currentPeriod = CREDBULL_VAULT.currentPeriod();
    
    console.log("Current Period:", currentPeriod);
    console.log("Vault balance:", CREDBULL_VAULT.balanceOf(tokenAddr, currentPeriod));
    console.log("Unlock request amount:", CREDBULL_VAULT.unlockRequestAmount(tokenAddr, currentPeriod));
    console.log("Claimable request amount:", CREDBULL_VAULT.claimableRedeemRequest(currentPeriod, tokenAddr));
}
// Helper function to check state
function testCheckState() public view {
    console.log("\n=== Vault State ===");
    address tokenAddr = address(token);
    uint256 currentPeriod = CREDBULL_VAULT.currentPeriod();
    
    console.log("Current Period:", currentPeriod);
    console.log("AggregateToken Balance in Vault:", CREDBULL_VAULT.balanceOf(tokenAddr, currentPeriod));
    console.log("Unlock Request Amount:", CREDBULL_VAULT.unlockRequestAmount(tokenAddr, currentPeriod));
    console.log("Claimable Request Amount:", CREDBULL_VAULT.claimableRedeemRequest(currentPeriod, tokenAddr));
}
/*


    function testComponentTokenFlow() public {
    uint256 privateKey = vm.envUint("PRIVATE_KEY");
    address controller = vm.addr(privateKey);
    vm.startBroadcast(privateKey);
    
    // Step 1: Deposit USDC to get aggregate tokens
    uint256 shares = token.deposit(TEST_AMOUNT, controller, controller);

    // Step 2: Request redeem to set up the unlock amount
    uint256 requestId = CREDBULL_VAULT.requestRedeem(shares, controller, controller);

    // Step 3: Fast forward to after notice period
    uint256 noticePeriod = CREDBULL_VAULT.noticePeriod();
    vm.warp(block.timestamp + noticePeriod);

    // Step 4: Call redeem to fulfill the request
    uint256 assets = CREDBULL_VAULT.redeem(shares, controller, controller);
    console.log("Redeem successful! Assets redeemed:", assets);

    vm.stopBroadcast();
}




    function testComponentTokenFlow() public {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        
        console.log("\n=== Starting Component Token Flow ===");
        uint256 initialUsdcBalance = USDC.balanceOf(account);
        
        console.log("Initial USDC:", initialUsdcBalance);
        console.log("USDC allowance for AggregateToken:", USDC.allowance(account, address(token)));
        console.log("USDC allowance for Credbull:", USDC.allowance(account, address(CREDBULL_VAULT)));
        
        // Step 1: Deposit USDC to get aggregate tokens
        try token.deposit(TEST_AMOUNT, account, account) returns (uint256 shares) {
            console.log("\nUSDC Deposit successful!");
            console.log("USDC Deposited:", TEST_AMOUNT);
            console.log("Aggregate Shares:", shares);
            console.log("USDC Balance after deposit:", USDC.balanceOf(account));
            
            // Step 2: Buy Credbull through AggregateToken
            try token.buyComponentToken(IComponentToken(address(CREDBULL_VAULT)), TEST_AMOUNT) {
                console.log("\nCredbull buy successful!");
                
                uint256 currentPeriod = CREDBULL_VAULT.currentPeriod();
                uint256 credbullBalance = CREDBULL_VAULT.balanceOf(address(token), currentPeriod);
                console.log("Current period:", currentPeriod);
                console.log("Credbull balance:", credbullBalance);
                
                // Step 3: Try to sell Credbull
                if (credbullBalance > 0) {
                    try token.sellComponentToken(IComponentToken(address(CREDBULL_VAULT)), credbullBalance) {
                        console.log("\nCredbull sell successful!");
                        console.log("Final Credbull balance:", CREDBULL_VAULT.balanceOf(address(token), currentPeriod));
                    } catch Error(string memory reason) {
                        console.log("Credbull sell failed:", reason);
                    }
                }
            } catch Error(string memory reason) {
                console.log("Credbull buy failed:", reason);
            }
        } catch Error(string memory reason) {
            console.log("USDC deposit failed:", reason);
        }
        
        console.log("\n=== Final State ===");
        console.log("USDC Balance:", USDC.balanceOf(account));
        console.log("Aggregate Token Balance:", token.balanceOf(account));
        
        uint256 finalPeriod = CREDBULL_VAULT.currentPeriod();
        console.log("Credbull Balance Period", finalPeriod, ":", 
            CREDBULL_VAULT.balanceOf(address(token), finalPeriod));
        
        vm.stopBroadcast();
    }
*/
    function testQueryBalances() public view {
        console.log("\n=== Current Balances ===");
        console.log("USDC Balance:", USDC.balanceOf(account));
        console.log("USDC Allowance (AggregateToken):", USDC.allowance(account, address(token)));
        console.log("USDC Allowance (Credbull):", USDC.allowance(account, address(CREDBULL_VAULT)));
        console.log("Aggregate Token Balance:", token.balanceOf(account));
        
        uint256 currentPeriod = CREDBULL_VAULT.currentPeriod();
        console.log("\n=== Credbull Vault Info ===");
        console.log("Current Period:", currentPeriod);
        console.log("Notice Period:", CREDBULL_VAULT.noticePeriod());
        console.log("Asset:", CREDBULL_VAULT.asset());
        console.log("Credbull Balance:", CREDBULL_VAULT.balanceOf(address(token), currentPeriod));
    }
}