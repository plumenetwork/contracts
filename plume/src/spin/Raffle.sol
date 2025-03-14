// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "../interfaces/ISpin.sol";
import "../interfaces/ISupraRouterContract.sol";

/// @custom:oz-upgrades-from Spin
contract Raffle is Initializable, AccessControlUpgradeable, UUPSUpgradeable {

    struct Prize {
        string name;
        uint256 totalTickets;
        bool isActive;
        address winner;
        uint256 totalUsers;
    }

    struct UserEntry {
        uint256 ticketsSpent;
        bool claimed;
    }

    /// @custom:storage-location erc7201:plume.storage.Raffle
    struct RaffleStorage {
        /// @dev Address of the admin managing the Spin contract
        address admin;
        /// @dev Address of the Spin contract
        ISpin spinContract;
        /// @dev Address of the Supra Router contract
        ISupraRouterContract supraRouter;
        // Mapping of prize ID to prize details
        mapping(uint256 => Prize) prizes;
        // Mapping of prize ID to user entries
        mapping(uint256 => mapping(address => UserEntry)) userEntries;
        // Mapping of ticket index to user address (for drawing winner)
        mapping(uint256 => mapping(uint256 => address)) prizeTicketEntries;
        // Mapping of VRF request ID to prize ID
        mapping(uint256 => uint256) pendingVRFRequests;
    }

    // keccak256(abi.encode(uint256(keccak256("plume.storage.Raffle")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant RAFFLE_STORAGE_LOCATION =
        0xe95941bb0551f1b2bbc74fe65e27a98b3c2b2f3747ce79c92bdb45fd344c9200;

    function _getRaffleStorage() internal pure returns (RaffleStorage storage $) {
        assembly {
            $.slot := RAFFLE_STORAGE_LOCATION
        }
    }

    // Roles
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant SUPRA_ROLE = keccak256("SUPRA_ROLE");

    event PrizeAdded(uint256 indexed prizeId, string name);
    event PrizeUpdated(uint256 indexed prizeId, string name, uint256 ticketCost);
    event PrizeRemoved(uint256 indexed prizeId);
    event TicketSpent(address indexed user, uint256 indexed prizeId, uint256 tickets);
    event WinnerRequested(uint256 indexed prizeId, uint256 indexed vrfRequestId);
    event WinnerSelected(uint256 indexed prizeId, address indexed winner);
    event PrizeClaimed(address indexed user, uint256 indexed prizeId);

    // Errors
    /// @notice Revert if the user does not have enough tickets to spend
    error InsufficientTickets();
    /// @notice Revert if reward already claimed
    error RewardClaimed(address user);
    /// @notice Revert if winner has already been drawn
    error WinnerDrawn(address winner);
    /// @notice Revert if prize has no tickets
    error EmptyTicketPool();
    /// @notice Revert if prize is inactive
    error PrizeInactive();
    /// @notice Revert if user is not the winner
    error NotAWinner();
    /// @notice Revert if prize already exists
    error PrizeAlreadyExists();

    modifier onlyValidPrize(
        uint256 prizeId
    ) {
        RaffleStorage storage $ = _getRaffleStorage();
        require($.prizes[prizeId].isActive, "Prize not available");
        _;
    }

    function initialize(address _spinContract, address _supraRouter) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();

        RaffleStorage storage $ = _getRaffleStorage();

        $.spinContract = ISpin(_spinContract);
        $.supraRouter = ISupraRouterContract(_supraRouter);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(SUPRA_ROLE, _supraRouter);
    }

    /**
     * @notice Adds a new prize with an initial total ticket pool of 0.
     */
    function addPrize(uint256 prizeId, string memory name) external onlyRole(ADMIN_ROLE) {
        RaffleStorage storage $ = _getRaffleStorage();
        if ($.prizes[prizeId].isActive) {
            revert PrizeAlreadyExists();
        }

        $.prizes[prizeId] = Prize({ name: name, totalTickets: 0, isActive: true, winner: address(0), totalUsers: 0 });

        emit PrizeAdded(prizeId, name);
    }

    /**
     * @notice Allows admin to remove a prize.
     */
    function removePrize(
        uint256 prizeId
    ) external onlyRole(ADMIN_ROLE) onlyValidPrize(prizeId) {
        RaffleStorage storage $ = _getRaffleStorage();
        $.prizes[prizeId].isActive = false;
        emit PrizeRemoved(prizeId);
    }

    /**
     * @notice Users enter a prize draw by spending raffle tickets.
     */
    function spendRaffle(uint256 prizeId, uint256 ticketAmount) external onlyValidPrize(prizeId) {
        RaffleStorage storage $ = _getRaffleStorage();
        require(ticketAmount > 0, "Must spend at least 1 ticket");

        (,, uint256 userRaffleTickets,,) = $.spinContract.getUserData(msg.sender);

        if (userRaffleTickets < ticketAmount) {
            revert InsufficientTickets();
        }

        $.spinContract.updateRaffleTickets(msg.sender, ticketAmount);

        // If user is entering this prize for the first time, increase unique count
        if ($.userEntries[prizeId][msg.sender].ticketsSpent == 0) {
            $.prizes[prizeId].totalUsers++;
        }

        // Store user entry and add tickets to the pool
        $.userEntries[prizeId][msg.sender].ticketsSpent += ticketAmount;
        uint256 entryIndex = $.prizes[prizeId].totalTickets;

        // TODO: Implement a more efficient way to store user entries
        for (uint256 i = 0; i < ticketAmount; i++) {
            $.prizeTicketEntries[prizeId][entryIndex + i] = msg.sender;
        }

        $.prizes[prizeId].totalTickets += ticketAmount;
        emit TicketSpent(msg.sender, prizeId, ticketAmount);
    }

    /**
     * @notice Requests a winner draw using Supra Oracle
     */
    function requestWinner(
        uint256 prizeId
    ) external onlyRole(ADMIN_ROLE) onlyValidPrize(prizeId) {
        RaffleStorage storage $ = _getRaffleStorage();

        if ($.prizes[prizeId].winner != address(0)) {
            revert WinnerDrawn($.prizes[prizeId].winner);
        }

        if ($.prizes[prizeId].totalTickets == 0) {
            revert EmptyTicketPool();
        }

        if (!$.prizes[prizeId].isActive) {
            revert PrizeInactive();
        }

        string memory callbackSignature = "handleWinnerSelection(uint256,uint256[])";
        uint8 rngCount = 1;
        uint256 numConfirmations = 1;
        uint256 clientSeed = uint256(keccak256(abi.encodePacked(prizeId, block.timestamp)));

        uint256 requestId =
            $.supraRouter.generateRequest(callbackSignature, rngCount, numConfirmations, clientSeed, $.admin);
        $.pendingVRFRequests[requestId] = prizeId;

        emit WinnerRequested(prizeId, requestId);
    }

    /**
     * @notice Handles the VRF callback and selects a winner.
     */
    function handleWinnerSelection(uint256 requestId, uint256[] memory rngList) external onlyRole(SUPRA_ROLE) {
        RaffleStorage storage $ = _getRaffleStorage();
        uint256 prizeId = $.pendingVRFRequests[requestId];

        // Select a random ticket from the pool
        uint256 winningTicket = rngList[0] % $.prizes[prizeId].totalTickets;
        address winner = $.prizeTicketEntries[prizeId][winningTicket];

        // Assign winner
        $.prizes[prizeId].winner = winner;

        emit WinnerSelected(prizeId, winner);
    }

    /**
     * @notice Allows the winner to claim their prize
     */
    function claimPrize(
        uint256 prizeId
    ) external onlyValidPrize(prizeId) {
        RaffleStorage storage $ = _getRaffleStorage();
        if ($.prizes[prizeId].winner != msg.sender) {
            revert NotAWinner();
        }

        if ($.userEntries[prizeId][msg.sender].claimed) {
            revert RewardClaimed(msg.sender);
        }

        $.userEntries[prizeId][msg.sender].claimed = true;
        $.prizes[prizeId].isActive = false;
        emit PrizeClaimed(msg.sender, prizeId);
    }

    /**
     * @notice Gets details of a prize.
     */
    function getPrizeDetails(
        uint256 prizeId
    )
        external
        view
        returns (string memory name, uint256 ticketCost, bool isActive, address winner, uint256 totalUsers)
    {
        RaffleStorage storage $ = _getRaffleStorage();
        Prize storage prize = $.prizes[prizeId];
        return (prize.name, prize.totalTickets, prize.isActive, prize.winner, prize.totalUsers);
    }

    /**
     * @notice Gets the user's entry details for a prize.
     */
    function getUserEntry(uint256 prizeId, address user) external view returns (uint256 ticketsSpent, bool claimed) {
        RaffleStorage storage $ = _getRaffleStorage();
        UserEntry storage entry = $.userEntries[prizeId][user];
        return (entry.ticketsSpent, entry.claimed);
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
