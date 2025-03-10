// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "../spin/Spin.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/// @custom:oz-upgrades-from Spin
contract Raffle is Initializable, AccessControlUpgradeable, UUPSUpgradeable {

    struct Prize {
        string name;
        uint256 ticketCost;
        bool isActive;
    }

    // Mapping of prize ID to prize details
    mapping(uint256 => Prize) public prizes;

    // Roles
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // Mapping of user address to their raffle ticket balance (Stored in Spin contract)
    Spin public spinContract;

    event PrizeAdded(uint256 prizeId, string name, uint256 ticketCost);
    event PrizeUpdated(uint256 prizeId, string name, uint256 ticketCost);
    event PrizeRemoved(uint256 prizeId);
    event PrizeClaimed(address indexed user, uint256 prizeId, uint256 ticketsSpent);

    modifier onlyValidPrize(
        uint256 prizeId
    ) {
        require(prizes[prizeId].isActive, "Prize not available");
        _;
    }

    function initialize(
        Spin _spinContract
    ) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();

        spinContract = _spinContract;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    /**
     * @notice Allows admin to add a new prize.
     */
    function addPrize(uint256 prizeId, string memory name, uint256 ticketCost) external onlyRole(ADMIN_ROLE) {
        require(prizes[prizeId].ticketCost == 0, "Prize already exists");
        prizes[prizeId] = Prize(name, ticketCost, true);
        emit PrizeAdded(prizeId, name, ticketCost);
    }

    /**
     * @notice Allows admin to update an existing prize.
     */
    function updatePrize(
        uint256 prizeId,
        string memory name,
        uint256 ticketCost
    ) external onlyRole(ADMIN_ROLE) onlyValidPrize(prizeId) {
        prizes[prizeId].name = name;
        prizes[prizeId].ticketCost = ticketCost;
        emit PrizeUpdated(prizeId, name, ticketCost);
    }

    /**
     * @notice Allows admin to remove a prize.
     */
    function removePrize(
        uint256 prizeId
    ) external onlyRole(ADMIN_ROLE) onlyValidPrize(prizeId) {
        prizes[prizeId].isActive = false;
        emit PrizeRemoved(prizeId);
    }

    /**
     * @notice Users claim a prize using their raffle tickets.
     */
    function claimPrize(
        uint256 prizeId
    ) external onlyValidPrize(prizeId) {
        uint256 ticketCost = prizes[prizeId].ticketCost;
        require(ticketCost > 0, "Invalid prize ID");

        // Check if the user has enough raffle tickets in Spin contract
        (,, uint256 userRaffleTickets,,) = spinContract.getUserRewards(msg.sender);
        require(userRaffleTickets >= ticketCost, "Not enough raffle tickets");

        // Deduct tickets in Spin contract
        spinContract.updateRaffleTickets(msg.sender, ticketCost);

        emit PrizeClaimed(msg.sender, prizeId, ticketCost);
    }

    /**
     * @notice Gets details of a prize.
     */
    function getPrizeDetails(
        uint256 prizeId
    ) external view returns (string memory name, uint256 ticketCost, bool isActive) {
        Prize storage prize = prizes[prizeId];
        return (prize.name, prize.ticketCost, prize.isActive);
    }

    // UUPS Authorization
    /**
     * @notice Authorizes the upgrade of the contract.
     * @param newImplementation The address of the new implementation.
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(ADMIN_ROLE) { }

}
