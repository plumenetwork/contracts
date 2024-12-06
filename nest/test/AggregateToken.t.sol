// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";

import { AggregateToken } from "../src/AggregateToken.sol";
import { IComponentToken } from "../src/interfaces/IComponentToken.sol";

import { AggregateTokenProxy } from "../src/proxy/AggregateTokenProxy.sol";

contract MockUSDC is ERC20 {

    constructor() ERC20("Invalid Token", "INVALID") {
        _mint(msg.sender, 1_000_000 * 10 ** decimals());
    }

    function decimals() public pure override returns (uint8) {
        return 12; // Different from USDC's 6 decimals
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

}

contract MockInvalidToken is ERC20 {

    constructor() ERC20("Invalid Token", "INVALID") {
        _mint(msg.sender, 1_000_000 * 10 ** decimals());
    }

    function decimals() public pure override returns (uint8) {
        return 12; // Different from USDC's 6 decimals
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

}

contract AggregateTokenTest is Test {

    AggregateToken public token;
    MockUSDC public usdc;
    MockUSDC public newUsdc;
    address public owner;
    address public user1;
    address public user2;

    // Events
    event AssetTokenUpdated(IERC20 indexed oldAsset, IERC20 indexed newAsset);
    event ComponentTokenListed(IComponentToken indexed componentToken);
    event ComponentTokenUnlisted(IComponentToken indexed componentToken);
    event ComponentTokenBought(
        address indexed buyer, IComponentToken indexed componentToken, uint256 componentTokenAmount, uint256 assets
    );
    event ComponentTokenSold(
        address indexed seller, IComponentToken indexed componentToken, uint256 componentTokenAmount, uint256 assets
    );

    function setUp() public {
        owner = makeAddr("owner");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // Deploy tokens
        usdc = new MockUSDC();
        newUsdc = new MockUSDC();

        // Deploy through proxy
        AggregateToken impl = new AggregateToken();
        ERC1967Proxy proxy = new AggregateTokenProxy(
            address(impl),
            abi.encodeCall(
                AggregateToken.initialize,
                (
                    owner,
                    "Aggregate Token",
                    "AGG",
                    IComponentToken(address(usdc)),
                    1e18, // 1:1 askPrice
                    1e18 // 1:1 bidPrice
                )
            )
        );
        token = AggregateToken(address(proxy));

        // Setup initial balances and approvals
        usdc.mint(user1, 1000e6);
        vm.prank(user1);
        usdc.approve(address(token), type(uint256).max);
    }

    // Helper function for access control error message
    function accessControlErrorMessage(address account, bytes32 role) internal pure returns (bytes memory) {
        return abi.encodePacked(
            "AccessControl: account ",
            Strings.toHexString(account),
            " is missing role ",
            Strings.toHexString(uint256(role), 32)
        );
    }

}
