// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "../interfaces/ISupraRouterContract.sol";

interface ISpin {

    function spendRaffleTickets(address _user, uint256 _amount) external;
    function getUserData(
        address _user
    ) external view returns (uint256, uint256, uint256, uint256, uint256, uint256, uint256);

}

contract Raffle is Initializable, AccessControlUpgradeable, UUPSUpgradeable {

    struct Prize {
        string name;
        string description;
        uint256 value;
        uint256 endTimestamp;
        bool isActive;
        address winner;
        uint256 winnerIndex;
    }

    struct Range {
        address user;
        uint256 cumulativeEnd;
    }

    // Roles
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant SUPRA_ROLE = keccak256("SUPRA_ROLE");

    // State variables
    address public admin;
    ISpin public spinContract;
    ISupraRouterContract public supraRouter;

    // Prize storage
    mapping(uint256 => Prize) public prizes;
    uint256[] public prizeIds;

    // Ticket tracking
    mapping(uint256 => Range[]) public prizeRanges;
    mapping(uint256 => uint256) public totalTickets;

    // User tracking
    mapping(uint256 => mapping(address => bool)) public userHasEnteredPrize;
    mapping(uint256 => uint256) public totalUniqueUsers;
    mapping(address => uint256[]) public winnings;

    // VRF
    mapping(uint256 => uint256) public pendingVRFRequests;
    mapping(uint256 => bool) public isWinnerRequestPending;

    // Migration tracking
    bool private _migrationComplete;

    // Counter for unique prize IDs
    uint256 private _nextPrizeId = 1;

    // Reserved storage gap for future upgrades
    uint256[50] private __gap;

    // Events
    event PrizeAdded(uint256 indexed prizeId, string name);
    event PrizeRemoved(uint256 indexed prizeId);
    event TicketSpent(address indexed user, uint256 indexed prizeId, uint256 tickets);
    event WinnerRequested(uint256 indexed prizeId, uint256 indexed requestId);
    event WinnerSelected(uint256 indexed prizeId, uint256 winnerIndex);
    event PrizeClaimed(address indexed user, uint256 indexed prizeId);
    event PrizeMigrated(uint256 indexed prizeId, uint256 migratedEntries, uint256 totalTickets);
    event PrizeEdited(uint256 indexed prizeId, string name, string description, uint256 value);

    // Errors
    error EmptyTicketPool();
    error WinnerDrawn(address winner);
    error PrizeInactive();
    error InsufficientTickets();
    error WinnerNotDrawn();
    error NotAWinner();

    // Initialize function
    function initialize(address _spinContract, address _supraRouter) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();

        spinContract = ISpin(_spinContract);
        supraRouter = ISupraRouterContract(_supraRouter);
        admin = msg.sender;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(SUPRA_ROLE, _supraRouter);
    }

    // Modifiers
    modifier onlyPrize(
        uint256 prizeId
    ) {
        require(prizes[prizeId].isActive, "Prize not available");
        _;
    }

    // Migration function - preserved for migrating ticket data
    // @notice this function is not planned to be used in production, is for
    // moving data from the previous pre-production test to this data structure
    function migrateTickets(
        uint256 prizeId,
        address[] calldata users,
        uint256[] calldata ticketCounts
    ) external onlyRole(ADMIN_ROLE) {
        require(prizes[prizeId].isActive, "Prize not available");
        require(prizeRanges[prizeId].length == 0, "Already has tickets");
        require(users.length == ticketCounts.length, "Array length mismatch");

        uint256 cumulative = 0;
        uint256 migrated = 0;

        for (uint256 i = 0; i < users.length; i++) {
            uint256 count = ticketCounts[i];
            if (count == 0) {
                continue;
            }

            if (!userHasEnteredPrize[prizeId][users[i]]) {
                userHasEnteredPrize[prizeId][users[i]] = true;
                totalUniqueUsers[prizeId]++;
            }

            cumulative += count;
            prizeRanges[prizeId].push(Range({ user: users[i], cumulativeEnd: cumulative }));
            migrated++;
        }

        totalTickets[prizeId] = cumulative;

        emit PrizeMigrated(prizeId, migrated, cumulative);
    }

    // Prize management
    function addPrize(string calldata name, string calldata description, uint256 value) external onlyRole(ADMIN_ROLE) {
        // Use incrementing counter for unique ID
        uint256 prizeId = _nextPrizeId++;
        prizeIds.push(prizeId);

        prizes[prizeId] = Prize({
            name: name,
            description: description,
            value: value,
            endTimestamp: 0,
            isActive: true,
            winner: address(0),
            winnerIndex: 0
        });

        emit PrizeAdded(prizeId, name);
    }

    function editPrize(
        uint256 prizeId,
        string calldata name,
        string calldata description,
        uint256 value
    ) external onlyRole(ADMIN_ROLE) onlyPrize(prizeId) {
        // Update prize details without affecting tickets or active status
        Prize storage prize = prizes[prizeId];
        prize.name = name;
        prize.description = description;
        prize.value = value;

        emit PrizeEdited(prizeId, name, description, value);
    }

    function removePrize(
        uint256 prizeId
    ) external onlyRole(ADMIN_ROLE) onlyPrize(prizeId) {
        prizes[prizeId].isActive = false;

        // Remove from prizeIds array
        uint256 len = prizeIds.length;
        for (uint256 i = 0; i < len; i++) {
            if (prizeIds[i] == prizeId) {
                prizeIds[i] = prizeIds[len - 1];
                prizeIds.pop();
                break;
            }
        }

        emit PrizeRemoved(prizeId);
    }

    // Raffle entry
    function spendRaffle(uint256 prizeId, uint256 ticketAmount) external onlyPrize(prizeId) {
        require(ticketAmount > 0, "Must spend at least 1 ticket");

        // Verify and deduct tickets from user balance
        (,,,, uint256 userRaffleTickets,,) = spinContract.getUserData(msg.sender);
        if (userRaffleTickets < ticketAmount) {
            revert InsufficientTickets();
        }
        spinContract.spendRaffleTickets(msg.sender, ticketAmount);

        // Append range
        uint256 newTotal = totalTickets[prizeId] + ticketAmount;
        prizeRanges[prizeId].push(Range({ user: msg.sender, cumulativeEnd: newTotal }));
        totalTickets[prizeId] = newTotal;

        // Track unique users
        if (!userHasEnteredPrize[prizeId][msg.sender]) {
            userHasEnteredPrize[prizeId][msg.sender] = true;
            totalUniqueUsers[prizeId]++;
        }

        emit TicketSpent(msg.sender, prizeId, ticketAmount);
    }

    // Winner selection
    function requestWinner(
        uint256 prizeId
    ) external onlyRole(ADMIN_ROLE) onlyPrize(prizeId) {
        if (prizeRanges[prizeId].length == 0) {
            revert EmptyTicketPool();
        }
        if (prizes[prizeId].winner != address(0)) {
            revert WinnerDrawn(prizes[prizeId].winner);
        }

        // Prevent multiple pending winner requests for the same prize
        require(!isWinnerRequestPending[prizeId], "Winner request already pending");
        isWinnerRequestPending[prizeId] = true; // Mark winner request as pending

        string memory callbackSig = "handleWinnerSelection(uint256,uint256[])";
        uint256 requestId = supraRouter.generateRequest(
            callbackSig, 1, 1, uint256(keccak256(abi.encodePacked(prizeId, block.timestamp))), msg.sender
        );

        pendingVRFRequests[requestId] = prizeId;
        emit WinnerRequested(prizeId, requestId);
    }

    function handleWinnerSelection(uint256 requestId, uint256[] memory rng) external onlyRole(SUPRA_ROLE) {
        uint256 prizeId = pendingVRFRequests[requestId];

        // Reset pending status and clean up request ID
        isWinnerRequestPending[prizeId] = false;
        delete pendingVRFRequests[requestId];

        if (!prizes[prizeId].isActive) {
            revert PrizeInactive();
        }

        uint256 idx = (rng[0] % totalTickets[prizeId]) + 1;
        prizes[prizeId].winnerIndex = idx;
        emit WinnerSelected(prizeId, idx);
    }

    // Binary search to find winner
    function getWinner(
        uint256 prizeId
    ) public view returns (address) {
        Range[] storage ranges = prizeRanges[prizeId];
        uint256 target = prizes[prizeId].winnerIndex;

        if (ranges.length == 0 || target == 0) {
            return address(0);
        }

        uint256 lo = 0;
        uint256 hi = ranges.length - 1;

        while (lo < hi) {
            uint256 mid = (lo + hi) >> 1;
            if (target <= ranges[mid].cumulativeEnd) {
                hi = mid;
            } else {
                lo = mid + 1;
            }
        }

        return ranges[lo].user;
    }

    // Claim prize
    function claimPrize(
        uint256 prizeId
    ) external onlyPrize(prizeId) {
        if (prizes[prizeId].winnerIndex == 0) {
            revert WinnerNotDrawn();
        }
        if (prizes[prizeId].winner != address(0)) {
            revert WinnerDrawn(prizes[prizeId].winner);
        }
        address winner = getWinner(prizeId);
        if (msg.sender != winner) {
            revert NotAWinner();
        }

        prizes[prizeId].winner = winner;
        prizes[prizeId].isActive = false;
        winnings[msg.sender].push(prizeId);

        emit PrizeClaimed(winner, prizeId);
    }

    // View functions
    function getUserEntries(
        uint256 prizeId,
        address user
    ) external view returns (uint256 ticketCount, uint256[] memory _winnings) {
        // Calculate total tickets by user for this prize
        ticketCount = 0;
        Range[] storage ranges = prizeRanges[prizeId];

        for (uint256 i = 0; i < ranges.length; i++) {
            if (ranges[i].user == user) {
                // Calculate how many tickets in this range
                uint256 rangeStart = i > 0 ? ranges[i - 1].cumulativeEnd : 0;
                uint256 rangeEnd = ranges[i].cumulativeEnd;
                ticketCount += (rangeEnd - rangeStart);
            }
        }

        // Return the user's winnings
        return (ticketCount, winnings[user]);
    }

    function getUserEntries(
        address user
    ) external view returns (uint256[] memory _prizeIds, uint256[] memory ticketCounts, uint256[] memory _winnings) {
        uint256 count = prizeIds.length;
        _prizeIds = new uint256[](count);
        ticketCounts = new uint256[](count);

        // Copy prize IDs to return array
        for (uint256 i = 0; i < count; i++) {
            _prizeIds[i] = prizeIds[i];
        }

        // For each prize, calculate user's ticket count
        for (uint256 i = 0; i < count; i++) {
            uint256 prizeId = _prizeIds[i];
            Range[] storage ranges = prizeRanges[prizeId];

            for (uint256 j = 0; j < ranges.length; j++) {
                if (ranges[j].user == user) {
                    uint256 rangeStart = j > 0 ? ranges[j - 1].cumulativeEnd : 0;
                    uint256 rangeEnd = ranges[j].cumulativeEnd;
                    ticketCounts[i] += (rangeEnd - rangeStart);
                }
            }
        }

        return (_prizeIds, ticketCounts, winnings[user]);
    }

    function getPrizeIds() external view returns (uint256[] memory) {
        return prizeIds;
    }

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
        Prize storage p = prizes[prizeId];

        return (
            p.name, p.description, totalTickets[prizeId], p.isActive, p.winner, p.winnerIndex, totalUniqueUsers[prizeId]
        );
    }

    function getPrizeDetails() external view returns (Prize[] memory) {
        uint256 prizeCount = prizeIds.length;
        Prize[] memory prizeArray = new Prize[](prizeCount);

        for (uint256 i = 0; i < prizeCount; i++) {
            prizeArray[i] = prizes[prizeIds[i]];
        }

        return prizeArray;
    }

    function getUserWinningStatus(
        address user
    ) external view returns (uint256[] memory wonUnclaimedPrizeIds, uint256[] memory claimedPrizeIds) {
        // Find prizes the user has won but not claimed yet
        uint256[] memory tempWonUnclaimed = new uint256[](prizeIds.length);
        uint256 wonUnclaimedCount = 0;

        for (uint256 i = 0; i < prizeIds.length; i++) {
            uint256 prizeId = prizeIds[i];
            Prize storage prize = prizes[prizeId];

            // If prize has a winner index but no winner address yet, and it's still active
            if (prize.winnerIndex > 0 && prize.winner == address(0) && prize.isActive) {
                // Check if this user is the winner
                if (getWinner(prizeId) == user) {
                    tempWonUnclaimed[wonUnclaimedCount] = prizeId;
                    wonUnclaimedCount++;
                }
            }
        }

        // Resize arrays to actual count
        wonUnclaimedPrizeIds = new uint256[](wonUnclaimedCount);
        for (uint256 i = 0; i < wonUnclaimedCount; i++) {
            wonUnclaimedPrizeIds[i] = tempWonUnclaimed[i];
        }

        // Return claimed prizes from winnings
        claimedPrizeIds = winnings[user];

        return (wonUnclaimedPrizeIds, claimedPrizeIds);
    }

    // Timestamp update for prizes
    function updatePrizeEndTimestamp(
        uint256 prizeId,
        uint256 endTimestamp
    ) external onlyRole(ADMIN_ROLE) onlyPrize(prizeId) {
        prizes[prizeId].endTimestamp = endTimestamp;
    }

    /**
     * @notice Set the active status of a prize manually
     * @dev This function is primarily intended for testing and administrative purposes
     * @param prizeId The ID of the prize to modify
     * @param active The new active status to set
     */
    function setPrizeActive(uint256 prizeId, bool active) external onlyRole(ADMIN_ROLE) {
        require(prizeId <= prizeIds.length, "Prize does not exist");
        prizes[prizeId].isActive = active;
    }

    // UUPS Authorization
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(ADMIN_ROLE) { }

    // Allow contract to receive ETH
    receive() external payable { }

}
