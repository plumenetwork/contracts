// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IYieldToken {

    function deposit(
        uint256 amount
    ) external returns (uint256);
    function withdraw(
        uint256 shares
    ) external returns (uint256);
    function previewRedeem(
        uint256 shares
    ) external view returns (uint256);

}



contract PUSDReceiptToken is ERC20 {
    address public immutable stakingContract;

    constructor(address _stakingContract) ERC20("pUSD Staking Receipt", "pUSDr") {
        stakingContract = _stakingContract;
    }

    function mint(address to, uint256 amount) external {
        require(msg.sender == stakingContract, "Only staking contract can mint");
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        require(msg.sender == stakingContract, "Only staking contract can burn");
        _burn(from, amount);
    }
}

contract PUSDStaking is ReentrancyGuard, Pausable, Ownable {

    IERC20 public pUSDToken;
    IYieldToken public yieldToken;
    PUSDReceiptToken public receiptToken;

    struct StakeInfo {
        uint256 amount;
        uint256 shares;
        uint256 unlockTime;
    }

    mapping(address => StakeInfo) public stakes;
    uint256 public constant UNSTAKE_DELAY = 30 days;
    uint256 public totalStaked;
    uint256 public totalShares;

    event Staked(address indexed user, uint256 amount, uint256 shares);
    event UnstakeRequested(address indexed user, uint256 unlockTime);
    event Unstaked(address indexed user, uint256 amount);

    constructor(address _pUSDToken, address _yieldToken) {
        pUSDToken = IERC20(_pUSDToken);
        yieldToken = IYieldToken(_yieldToken);
        receiptToken = new PUSDReceiptToken(address(this));

    }

    function stake(
        uint256 amount
    ) external nonReentrant whenNotPaused {
        require(amount > 0, "Cannot stake 0");
        require(pUSDToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");

        uint256 shares = yieldToken.deposit(amount);
        StakeInfo storage userStake = stakes[msg.sender];
        userStake.amount += amount;
        userStake.shares += shares;
        totalStaked += amount;
        totalShares += shares;

        // Mint receipt tokens 1:1 with staked amount
        receiptToken.mint(msg.sender, amount);

        emit Staked(msg.sender, amount, shares);
    }

    function requestUnstake() external nonReentrant whenNotPaused {
        StakeInfo storage userStake = stakes[msg.sender];
        require(userStake.amount > 0, "No stake found");
        require(userStake.unlockTime == 0, "Unstake already requested");

        userStake.unlockTime = block.timestamp + UNSTAKE_DELAY;
        emit UnstakeRequested(msg.sender, userStake.unlockTime);
    }

    function unstake() external nonReentrant whenNotPaused {
        StakeInfo storage userStake = stakes[msg.sender];
        require(userStake.unlockTime > 0, "Must request unstake first");
        require(block.timestamp >= userStake.unlockTime, "Still in unstake delay period");

        uint256 shares = userStake.shares;
        require(shares > 0, "No stake found");

        uint256 withdrawnAmount = yieldToken.withdraw(shares);

          // Burn receipt tokens
        receiptToken.burn(msg.sender, userStake.amount);

        userStake.amount = 0;
        userStake.shares = 0;
        userStake.unlockTime = 0;
        totalStaked -= userStake.amount;
        totalShares -= shares;

        require(pUSDToken.transfer(msg.sender, withdrawnAmount), "Transfer failed");
        emit Unstaked(msg.sender, withdrawnAmount);
    }

    function previewWithdraw(
        address user
    ) external view returns (uint256) {
        StakeInfo storage userStake = stakes[user];
        return yieldToken.previewRedeem(userStake.shares);
    }

    function depositToVault(IERC20 token, uint256 minimumMint) internal returns (uint256 shares) {
        BoringVaultPredepositStorage storage $ = _getBoringVaultPredepositStorage();

        BoringVault memory vault = $.vault;
        UserState storage userState = $.userStates[msg.sender];

        if (block.timestamp < $.vaultConversionStartTime) {
            revert ConversionNotStarted(block.timestamp, $.vaultConversionStartTime);
        }

        if (!$.allowedTokens[token]) {
            revert NotAllowedToken(token);
        }

        // Get user's token balance and convert to deposit amount
        uint256 tokenBaseAmount = userState.tokenAmounts[token];
        if (tokenBaseAmount == 0) {
            revert InvalidAmount(0, 0);
        }

        uint256 depositAmount = _fromBaseUnits(tokenBaseAmount, token);
        if (depositAmount == 0) {
            revert InvalidAmount(0, 0);
        }

        // Update accumulated stake-time before modifying state
        uint256 currentTime = block.timestamp;
        userState.lastUpdate = currentTime;

        // Update state before external calls
        userState.tokenAmounts[token] = 0;
        $.totalAmountStaked[token] -= tokenBaseAmount; // Update per token

        // Approve spending
        token.forceApprove(address(vault.vault), depositAmount);

        // Deposit and get shares
        shares = vault.teller.deposit(token, depositAmount, minimumMint);

        // Transfer and record shares
        IERC20(address(vault.vault)).safeTransfer(msg.sender, shares);
        userState.vaultShares[token] += shares;

        emit ConvertedToBoringVault(msg.sender, token, depositAmount, shares);
    }

}
