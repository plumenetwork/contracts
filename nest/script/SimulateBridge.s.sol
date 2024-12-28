// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";

import { IBoringVault } from "../src/interfaces/IBoringVault.sol";

import { BridgeData, ICrossChainTellerBase } from "../src/interfaces/ICrossChainTellerBase.sol";
import { IRWAStaking } from "../src/interfaces/IRWAStaking.sol";
import { ITeller } from "../src/interfaces/ITeller.sol";
import { console2 } from "forge-std/console2.sol";

contract SimulateBridge is Test {

    // Constants
    address constant RWA_STAKING = address(0xdbd03D676e1cf3c3b656972F88eD21784372AcAB);
    address constant ADMIN = address(0xDE1509CC56D740997c70E1661BA687e950B4a241);
    address constant TELLER = address(0x16424eDF021697E34b800e1D98857536B0f2287B);
    address constant VAULT = address(0x16424eDF021697E34b800e1D98857536B0f2287B);
    address constant PUSD = address(0xdddD73F5Df1F0DC31373357beAC77545dC5A6f3F);

    address constant NATIVE = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
    address constant PLUME_RECEIVER = address(0x04354e44ed31022716e77eC6320C04Eda153010c);
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address constant MULTISIG = 0xa472f6bDf1E676C7B773591d5D820aDC27a2D51c;

    IRWAStaking rwaStaking;
    ICrossChainTellerBase teller;
    IBoringVault vault;
    BridgeData bridgeData;

    function run() public {
        // Get total amounts to bridge
        uint256 usdcAmount = IERC20(USDC).balanceOf(RWA_STAKING);
        uint256 usdtAmount = IERC20(USDT).balanceOf(RWA_STAKING);

        console2.log("=== Current Balances ===");
        console2.log("USDC balance:", usdcAmount / 1e6, "USDC");
        console2.log("USDT balance:", usdtAmount / 1e6, "USDT");
        console2.log("Total USD value:", (usdcAmount + usdtAmount) / 1e6, "USD");
        console2.log("------------------------");

        address timelock = address(IRWAStaking(RWA_STAKING).getTimelock());

        console2.log("\n=== Contract Addresses ===");
        console2.log("Timelock:", timelock);
        console2.log("Multisig:", MULTISIG);

        // Start measuring gas
        uint256 startGas = gasleft();

        // adminWithdraw through timelock
        vm.startPrank(address(timelock));
        IRWAStaking(RWA_STAKING).adminWithdraw();
        vm.stopPrank();

        uint256 withdrawGas = startGas - gasleft();
        console2.log("\n=== Admin Withdrawal ===");
        console2.log("Withdrawal gas used:", withdrawGas);

        // Funds are in the multisig, approve and bridge
        vm.startPrank(MULTISIG);

        // Approve tokens to vault
        startGas = gasleft();

        IERC20(USDC).approve(TELLER, usdcAmount);
        IERC20(USDC).approve(PUSD, usdcAmount);

        SafeERC20.safeIncreaseAllowance(IERC20(USDT), TELLER, 0);
        SafeERC20.safeIncreaseAllowance(IERC20(USDT), TELLER, usdtAmount);
        SafeERC20.safeIncreaseAllowance(IERC20(USDT), PUSD, 0);
        SafeERC20.safeIncreaseAllowance(IERC20(USDT), PUSD, usdtAmount);

        uint256 approvalGas = startGas - gasleft();
        console2.log("\n=== Approvals ===");
        console2.log("Approval gas used:", approvalGas);

        // Calculate bridge fees
        BridgeData memory data = BridgeData({
            chainSelector: 30_318,
            destinationChainReceiver: PLUME_RECEIVER,
            bridgeFeeToken: ERC20(NATIVE),
            messageGas: 100_000,
            data: ""
        });

        teller = ICrossChainTellerBase(TELLER);

        uint256 usdcFee = teller.previewFee(usdcAmount, data);
        uint256 usdtFee = teller.previewFee(usdtAmount, data);
        uint256 totalBridgeFee = usdcFee + usdtFee;

        console2.log("\n=== Bridge Fees ===");
        console2.log("USDC bridge fee:", usdcFee, "wei");
        console2.log("USDT bridge fee:", usdtFee, "wei");
        console2.log("Total bridge fee:", totalBridgeFee, "wei");

        // Deal ETH to multisig to cover bridge fees
        vm.deal(MULTISIG, totalBridgeFee);
        console2.log("Funded multisig with", totalBridgeFee, "wei");

        // Track gas before bridging
        uint256 bridgeStartGas = gasleft();

        // Bridge USDC
        teller.depositAndBridge{ value: usdcFee }(ERC20(USDC), usdcAmount, usdcAmount, data);
        console2.log("USDC bridged successfully");

        // Bridge USDT
        teller.depositAndBridge{ value: usdtFee }(ERC20(USDT), usdtAmount, usdtAmount, data);
        console2.log("USDT bridged successfully");

        vm.stopPrank();

        // Calculate final costs
        uint256 gasUsed = startGas - gasleft();
        uint256 bridgeGasUsed = bridgeStartGas - gasleft();
        uint256 gasPrice = tx.gasprice;
        uint256 totalGasCost = gasUsed * gasPrice;
        uint256 bridgeGasCost = bridgeGasUsed * gasPrice;

        console2.log("\n=== Final Cost Analysis ===");
        console2.log("Total gas used:", gasUsed);
        console2.log("Bridge operation gas used:", bridgeGasUsed);
        console2.log("Gas price:", gasPrice, "wei");
        console2.log("Total gas cost:", totalGasCost, "wei");
        console2.log("Bridge gas cost:", bridgeGasCost, "wei");
        console2.log("Bridge fees:", totalBridgeFee, "wei");
        console2.log("Total cost (gas + fees):", totalGasCost + totalBridgeFee, "wei");
        console2.log("Total cost in ETH:", (totalGasCost + totalBridgeFee) / 1e18, "ETH");

        // Convert to USD using 3500 as ETH price
        uint256 ethPrice = 3500; 
        uint256 totalCostUSD = ((totalGasCost + totalBridgeFee) * ethPrice) / 1e18;
        console2.log("Estimated total cost in USD: $", totalCostUSD);
    }

}
