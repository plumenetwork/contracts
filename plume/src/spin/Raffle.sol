// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "../interfaces/ISupraRouterContract.sol";

interface ISpin {

    function updateRaffleTickets(address _user, uint256 _amount) external;
    function getUserData(
        address _user
    ) external view returns (uint256, uint256, uint256, uint256, uint256, uint256, uint256);

}

/// @custom:oz-upgrades-from Spin
contract Raffle is Initializable, AccessControlUpgradeable, UUPSUpgradeable {

    struct Prize {
        string name;
        string description;
        uint256 value;
        uint256 totalTickets;
        bool isActive;
        address winner;
        uint256 winnerIndex;
        uint256 totalUsers;
        uint256 endTimestamp;
    }

    struct Index {
        uint256 startIndex; // First ticket index
        uint256 ticketCount; // Number of tickets
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
        mapping(uint256 => Prize) prizes; // prizeId => Prize
        // List of prize IDs
        uint256[] prizeIds;
        // Mapping of ticket index to user address (for drawing winner)
        mapping(uint256 => mapping(address => Index[])) tickets; // prizeId -> user -> ticket range
        // Mapping of user address to prize IDs won
        mapping(address => uint256[]) winnings; // user -> prizeId[]
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
    event WinnerSelected(uint256 indexed prizeId, uint256 winnerIndex);
    event PrizeClaimed(address indexed user, uint256 indexed prizeId);
    event SpentRaffle(address indexed user, uint256 indexed prizeId, uint256 tickets);

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
    /// @notice Revert if winner has not been drawn yet
    error WinnerNotDrawn();
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
        $.admin = msg.sender;

        $.spinContract = ISpin(_spinContract);
        $.supraRouter = ISupraRouterContract(_supraRouter);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(SUPRA_ROLE, _supraRouter);
    }

    /**
     * @notice Adds a new prize with an initial total ticket pool of 0.
     */
    /// @notice Adds a new prize (ID autoincrements: `prizeIds.length + 1`)
    function addPrize(
        string memory name,
        string memory description,
        uint256 value
    ) external onlyRole(ADMIN_ROLE) {
        RaffleStorage storage $ = _getRaffleStorage();

        uint256 prizeId = $.prizeIds.length + 1;
        $.prizeIds.push(prizeId);          // track active IDs

        $.prizes[prizeId] = Prize({
            name: name,
            description: description,
            value: value,
            totalTickets: 0,
            isActive: true,
            winner: address(0),
            winnerIndex: 0,
            totalUsers: 0,
            endTimestamp: 0
        });

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

        // remove the ID from prizeIds[]
        uint256 len = $.prizeIds.length;
        for (uint256 i = 0; i < len; i++) {
            if ($.prizeIds[i] == prizeId) {
                $.prizeIds[i] = $.prizeIds[len - 1];
                $.prizeIds.pop();
                break;
            }
        }
        emit PrizeRemoved(prizeId);
    }

    /**
     * @notice Users enter a prize draw by spending raffle tickets.
     */
    function spendRaffle(uint256 prizeId, uint256 ticketAmount) external onlyValidPrize(prizeId) {
        RaffleStorage storage $ = _getRaffleStorage();
        require(ticketAmount > 0, "Must spend at least 1 ticket");

        (,,,, uint256 userRaffleTickets,,) = $.spinContract.getUserData(msg.sender);

        if (userRaffleTickets < ticketAmount) {
            revert InsufficientTickets();
        }

        $.spinContract.updateRaffleTickets(msg.sender, ticketAmount);

        Prize storage prize = $.prizes[prizeId];
        Index[] storage userEntries = $.tickets[prizeId][msg.sender];

        bool isNewUser = (userEntries.length == 0); // Check if it's a new user entry

        userEntries.push(Index({ startIndex: prize.totalTickets + 1, ticketCount: ticketAmount }));

        // Update total tickets in prize pool
        prize.totalTickets += ticketAmount;

        // Increment unique user count only if this is the user's first ticket entry
        if (isNewUser) {
            $.prizes[prizeId].totalUsers++;
        }

        emit SpentRaffle(msg.sender, prizeId, ticketAmount);
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
        uint256 winnerIndex = rngList[0] % $.prizes[prizeId].totalTickets;
        $.prizes[prizeId].winnerIndex = winnerIndex;

        emit WinnerSelected(prizeId, winnerIndex);
    }

    function getWinner(
        uint256 prizeId,
        uint256 winnerIndex
    ) external view onlyRole(ADMIN_ROLE) returns (address winner) { }

    /**
     * @notice Allows the winner to claim their prize
     */
    function claimPrize(
        uint256 prizeId
    ) external onlyValidPrize(prizeId) {
        RaffleStorage storage $ = _getRaffleStorage();
        uint256 winnerIndex = $.prizes[prizeId].winnerIndex;

        if (winnerIndex == 0 && $.prizes[prizeId].totalTickets > 0) {
            revert WinnerNotDrawn();
        }

        Index[] storage userEntries = $.tickets[prizeId][msg.sender];

        // Verify if the user owns the winning ticket
        for (uint256 i = 0; i < userEntries.length; i++) {
            if (
                winnerIndex >= userEntries[i].startIndex
                    && winnerIndex < (userEntries[i].startIndex + userEntries[i].ticketCount)
            ) {
                $.prizes[prizeId].winner = msg.sender;
                $.prizes[prizeId].isActive = false;

                // Add prize to user's winnings
                $.winnings[msg.sender].push(prizeId);

                emit PrizeClaimed(msg.sender, prizeId);
                return;
            }
        }

        revert NotAWinner();
    }

    /**
     * @notice Gets details of a prize.
     */
    function getPrizeDetails(
        uint256 prizeId
    )
        external
        view
        returns (
            string memory name,
            string memory description,
            uint256 ticketCost,
            bool isActive,
            address winner,
            uint256 winnerIndex,
            uint256 totalUsers
        )
    {
        RaffleStorage storage $ = _getRaffleStorage();
        Prize storage prize = $.prizes[prizeId];
        return (
            prize.name,
            prize.description,
            prize.totalTickets,
            prize.isActive,
            prize.winner,
            prize.winnerIndex,
            prize.totalUsers
        );
    }

    function getPrizeDetails() external view returns (Prize[] memory) {
        RaffleStorage storage $ = _getRaffleStorage();
        uint256 prizeCount = $.prizeIds.length;
        Prize[] memory prizes = new Prize[](prizeCount);
        for (uint256 i = 0; i < prizeCount; i++) {
            prizes[i] = $.prizes[$.prizeIds[i]];
        }
        return prizes;
    }

    /**
     * @notice Gets the user's entry details for a prize.
     */
    function getUserEntries(uint256 prizeId, address user) external view returns (uint256, uint256[] memory) {
        RaffleStorage storage $ = _getRaffleStorage();
        Index[] storage entries = $.tickets[prizeId][user];

        uint256 ticketCounts = 0;

        for (uint256 i = 0; i < entries.length; i++) {
            ticketCounts += entries[i].ticketCount;
        }

        return (ticketCounts, $.winnings[user]);
    }

    function getUserEntries(
        address user
    ) external view returns (uint256[] memory, uint256[] memory, uint256[] memory) {
        RaffleStorage storage $ = _getRaffleStorage();
        uint256 prizeCount = $.prizeIds.length;

        uint256[] memory ticketCounts = new uint256[](prizeCount);

        for (uint256 i = 0; i < prizeCount; i++) {
            Index[] storage entries = $.tickets[$.prizeIds[i]][user];
            uint256 _ticketCounts = 0;

            for (uint256 j = 0; j < entries.length; j++) {
                _ticketCounts += entries[j].ticketCount;
            }

            ticketCounts[i] = _ticketCounts;
        }

        return ($.prizeIds, ticketCounts, $.winnings[user]);
    }

    function updatePrizeEndTimestamp(
        uint256 prizeId,
        uint256 endtimestamp
    ) external onlyRole(ADMIN_ROLE) onlyValidPrize(prizeId) {
        RaffleStorage storage $ = _getRaffleStorage();
        Prize storage prize = $.prizes[prizeId];

        prize.endTimestamp = endtimestamp;
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
