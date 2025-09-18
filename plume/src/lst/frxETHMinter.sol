// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

// ====================================================================
// |     ______                   _______                             |
// |    / _____________ __  __   / ____(_____  ____ _____  ________   |
// |   / /_  / ___/ __ `| |/_/  / /_  / / __ \/ __ `/ __ \/ ___/ _ \  |
// |  / __/ / /  / /_/ _>  <   / __/ / / / / / /_/ / / / / /__/  __/  |
// | /_/   /_/   \__,_/_/|_|  /_/   /_/_/ /_/\__,_/_/ /_/\___/\___/   |
// |                                                                  |
// ====================================================================
// ============================ frxETHMinter ==========================
// ====================================================================
// Frax Finance: https://github.com/FraxFinance

// Primary Author(s)
// Jack Corddry: https://github.com/corddry
// Justin Moore: https://github.com/0xJM

// Reviewer(s) / Contributor(s)
// Travis Moore: https://github.com/FortisFortuna
// Dennis: https://github.com/denett
// Jamie Turley: https://github.com/jyturley

import { frxETH } from "./frxETH.sol";
import { IsfrxETH } from "./interfaces/IsfrxETH.sol";
import {ReentrancyGuardUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { IDepositContract } from "./DepositContract.sol";
import "./OperatorRegistry.sol";

/// @title Authorized minter contract for frxETH
/// @notice Accepts user-supplied ETH and converts it to frxETH (submit()), and also optionally inline stakes it for sfrxETH (submitAndDeposit())
/** @dev Has permission to mint frxETH. 
    Once +32 ETH has accumulated, adds it to a validator, which then deposits it for ETH 2.0 staking (depositEther())
    Withhold ratio refers to what percentage of ETH this contract keeps whenever a user makes a deposit. 0% is kept initially */
contract frxETHMinter is OperatorRegistry, ReentrancyGuardUpgradeable {    
    uint256 public constant DEPOSIT_SIZE = 32 ether; // ETH 2.0 minimum deposit size --deprecated, backwards compatibility
    uint256 public constant RATIO_PRECISION = 1e6; // 1,000,000 

    uint256 public withholdRatio; // What we keep and don't deposit whenever someone submit()'s ETH
    uint256 public currentWithheldETH; // Needed for internal tracking
    mapping(bytes => bool) public activeValidators; // Tracks validators (via their pubkeys) that already have 32 ETH in them --deprecated, backwards compatibility

    IDepositContract public depositContract; // ETH 2.0 deposit contract
    frxETH public frxETHToken;
    IsfrxETH public sfrxETHToken;

    bool public submitPaused;
    bool public depositEtherPaused;
    uint256[10] private __gap;

    constructor(
        address depositContractAddress, 
        address frxETHAddress, 
        address sfrxETHAddress, 
        address _owner, 
        address _timelock_address
    ) OperatorRegistry(_owner, _timelock_address) {}

    function _frxethminter_init(address depositContractAddress, address frxETHAddress, address sfrxETHAddress, address _owner, address _timelock_address) internal onlyInitializing {
        _operator_init(_owner, _timelock_address);
        __ReentrancyGuard_init();
        depositContract = IDepositContract(depositContractAddress);
        frxETHToken = frxETH(frxETHAddress);
        withholdRatio = 20000; // No ETH is withheld initially (2%)
        currentWithheldETH = 0;
    }

    /// @notice Mint frxETH to the recipient using sender's funds. Internal portion
    function _submit(address recipient) internal virtual returns (uint256 amount) {
        // Initial pause and value checks
        require(!submitPaused, "Submit is paused");
        require(msg.value != 0, "Cannot submit 0");

        // Give the sender frxETH
        frxETHToken.minter_mint(recipient, msg.value);

        // Track the amount of ETH that we are keeping
        uint256 withheld_amt = 0;
        if (withholdRatio != 0) {
            withheld_amt = (msg.value * withholdRatio) / RATIO_PRECISION;
            currentWithheldETH += withheld_amt;
        }
        amount = msg.value - withheld_amt;

        emit ETHSubmitted(msg.sender, recipient, msg.value, withheld_amt);
    }

    /// @notice Mint frxETH to the sender depending on the ETH value sent
    function submit() external payable {
        _submit(msg.sender);
    }

    /// @notice Mint frxETH to the recipient using sender's funds
    function submitAndGive(address recipient) external payable {
        _submit(recipient);
    }

    /// @notice Fallback to minting frxETH to the sender
    receive() external payable virtual {
        _submit(msg.sender);
    }

    /// @param newRatio of ETH that is sent to deposit contract vs withheld, 1e6 precision
    /// @notice An input of 1e6 results in 100% of Eth deposited, 0% withheld
    function setWithholdRatio(uint256 newRatio) external onlyByOwnGov {
        require (newRatio <= RATIO_PRECISION, "Ratio cannot surpass 100%");
        withholdRatio = newRatio;
        emit WithholdRatioSet(newRatio);
    }

    /// @notice Give the withheld ETH to the "to" address
    function moveWithheldETH(address payable to, uint256 amount) external onlyByOwnGov {
        require(amount <= currentWithheldETH, "Not enough withheld ETH in contract");
        currentWithheldETH -= amount;

        (bool success,) = payable(to).call{ value: amount }("");
        require(success, "Invalid transfer");

        emit WithheldETHMoved(to, amount);
    }

    /// @notice Toggle allowing submites
    function togglePauseSubmits() external onlyByOwnGov {
        submitPaused = !submitPaused;

        emit SubmitPaused(submitPaused);
    }

    /// @notice Toggle allowing depositing ETH to validators
    function togglePauseDepositEther() external onlyByOwnGov {
        depositEtherPaused = !depositEtherPaused;

        emit DepositEtherPaused(depositEtherPaused);
    }

    /// @notice For emergencies if something gets stuck
    function recoverEther(uint256 amount, address payable to) external onlyByOwnGov {
        (bool success,) = address(to).call{ value: amount }("");
        require(success, "Invalid transfer");

        emit EmergencyEtherRecovered(amount);
    }

    /// @notice For emergencies if someone accidentally sent some ERC20 tokens here
    function recoverERC20(address tokenAddress, uint256 tokenAmount, address to ) external onlyByOwnGov {
        require(IERC20(tokenAddress).transfer(to, tokenAmount), "recoverERC20: Transfer failed");

        emit EmergencyERC20Recovered(tokenAddress, tokenAmount);
    }

    event EmergencyEtherRecovered(uint256 amount);
    event EmergencyERC20Recovered(address tokenAddress, uint256 tokenAmount);
    event ETHSubmitted(address indexed sender, address indexed recipient, uint256 sent_amount, uint256 withheld_amt);
    event DepositEtherPaused(bool new_status);
    event DepositSent(uint16 indexed validatorId);
    event SubmitPaused(bool new_status);
    event WithheldETHMoved(address indexed to, uint256 amount);
    event WithholdRatioSet(uint256 newRatio);
}
