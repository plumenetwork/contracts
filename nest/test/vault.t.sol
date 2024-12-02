// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { MockVault } from "../src/mocks/MockVault.sol";
import { pUSD } from "../src/token/pUSD.sol";

import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";
import {Auth, Authority} from "@solmate/auth/Auth.sol";

contract TestUSDC is ERC20 {

    constructor() ERC20("USD Coin", "USDC") {
        _mint(msg.sender, 1_000_000 * 10 ** 6);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

}

contract pUSDPlumeTest is Test {

    pUSD public token;
    IERC20 public asset;
    IERC4626 public vault;

    address public owner;
    address public user1;
    address public user2;

    // Constants for deployed contracts
    address constant USDC_ADDRESS = 0x401eCb1D350407f13ba348573E5630B83638E30D;
    address constant VAULT_ADDRESS = 0xe644F07B1316f28a7F134998e021eA9f7135F351;
    address constant PUSD_PROXY = 0xF66DFD0A9304D3D6ba76Ac578c31C84Dc0bd4A00;

    event VaultChanged(IERC4626 indexed oldVault, IERC4626 indexed newVault);


function setUp() public {
    // Fork Plume testnet
    string memory PLUME_RPC = vm.envString("PLUME_RPC_URL");
    vm.createSelectFork(PLUME_RPC);

    // Setup accounts using the private key
    uint256 privateKey = 0xf1906c3250e18e8036273019f2d6d4d5107404b84753068fe8fb170674461f1b;
    owner = vm.addr(privateKey);
    user1 = vm.addr(privateKey);
    user2 = address(0x2);

    // Set the default signer for all transactions
    vm.startPrank(owner, owner);

    // Connect to deployed contracts
    token = pUSD(PUSD_PROXY);
    asset = IERC20(USDC_ADDRESS);
    vault = IERC4626(VAULT_ADDRESS);

    // No need to deal USDC if the account already has balance
    // But we still need the approval
    asset.approve(address(token), type(uint256).max);

    vm.stopPrank();
}


function checkOwnership() public view {
    Auth vaultAuth = Auth(address(VAULT_ADDRESS));
    Auth authorityContract = Auth(0xe88FAdd44F65a64ffB807c5C1aF2EADCAA2BBcCC);
    
    console.log("Vault owner:", vaultAuth.owner());
    console.log("Authority owner:", authorityContract.owner());
    console.log("Vault authority:", address(vaultAuth.authority()));
}





}
