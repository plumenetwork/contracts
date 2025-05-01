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
        bool claimed;
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

    // Migration tracking
    bool private _migrationComplete;

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
    event WinnerSet(uint256 indexed prizeId, address indexed winner);

    // Errors
    error EmptyTicketPool();
    error WinnerDrawn(address winner);
    error WinnerClaimed();
    error PrizeInactive();
    error InsufficientTickets();
    error WinnerNotDrawn();
    error NotAWinner();
    error WinnerNotSet();

    // Track the next prize ID so even if some are deleted we know it
    uint256 private nextPrizeId;

    // Initialize function
    function initialize(address _spinContract, address _supraRouter) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        
        spinContract = ISpin(_spinContract);
        supraRouter = ISupraRouterContract(_supraRouter);
        admin = msg.sender;
        nextPrizeId = 1; // 1-based indexing for prizes

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(SUPRA_ROLE, _supraRouter);
    }

    // Modifiers
    modifier onlyAdmin() {
        require(hasRole(ADMIN_ROLE, msg.sender), "Not admin");
        _;
    }
    
    modifier onlySupra() {
        require(hasRole(SUPRA_ROLE, msg.sender), "Not supra");
        _;
    }
    
    modifier prizeIsActive(uint256 prizeId) {
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
        require(users.length == ticketCounts.length, "Array length mismatch");
        
        uint256 cumulative = totalTickets[prizeId];
        uint256 migrated = 0;
        
        for (uint256 i = 0; i < users.length; i++) {
            uint256 count = ticketCounts[i];
            if (count == 0) continue;
            
            if (!userHasEnteredPrize[prizeId][users[i]]) {
                userHasEnteredPrize[prizeId][users[i]] = true;
                totalUniqueUsers[prizeId]++;
            }
            
            cumulative += count;
            prizeRanges[prizeId].push(Range({
                user: users[i],
                cumulativeEnd: cumulative
            }));
            migrated++;
        }
        
        totalTickets[prizeId] = cumulative;
        
        emit PrizeMigrated(prizeId, migrated, cumulative);
    }

    // Prize management
    function addPrize(
        string calldata name,
        string calldata description,
        uint256 value
    ) external onlyRole(ADMIN_ROLE) {
        uint256 prizeId = nextPrizeId++;
        prizeIds.push(prizeId);

        require(bytes(prizes[prizeId].name).length == 0, "Prize ID already in use");

        prizes[prizeId] = Prize({
            name: name,
            description: description,
            value: value,
            endTimestamp: 0,
            isActive: true,
            winner: address(0),
            winnerIndex: 0,
            claimed: false
        });

        emit PrizeAdded(prizeId, name);
    }

    function editPrize(
        uint256 prizeId,
        string calldata name,
        string calldata description,
        uint256 value
    ) external onlyRole(ADMIN_ROLE) prizeIsActive(prizeId) {
        // Update prize details without affecting tickets or active status
        Prize storage prize = prizes[prizeId];
        prize.name = name;
        prize.description = description;
        prize.value = value;
        
        emit PrizeEdited(prizeId, name, description, value);
    }

    function removePrize(uint256 prizeId) external onlyRole(ADMIN_ROLE) prizeIsActive(prizeId) {
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

    // User is spending raffle tickets to enter a prize
    function spendRaffle(uint256 prizeId, uint256 ticketAmount) external prizeIsActive(prizeId) {
        require(ticketAmount > 0, "Must spend at least 1 ticket");

        // Verify and deduct tickets from user balance
        (,,,, uint256 userRaffleTickets,,) = spinContract.getUserData(msg.sender);
        if (userRaffleTickets < ticketAmount) revert InsufficientTickets();
        spinContract.spendRaffleTickets(msg.sender, ticketAmount);

        // Append range
        uint256 newTotal = totalTickets[prizeId] + ticketAmount;
        prizeRanges[prizeId].push(
            Range({ user: msg.sender, cumulativeEnd: newTotal })
        );
        totalTickets[prizeId] = newTotal;

        // Track unique users
        if (!userHasEnteredPrize[prizeId][msg.sender]) {
            userHasEnteredPrize[prizeId][msg.sender] = true;
            totalUniqueUsers[prizeId]++;
        }

        emit TicketSpent(msg.sender, prizeId, ticketAmount);
    }

    // Admin requests a winner to be selected by VRF
    function requestWinner(uint256 prizeId) external onlyRole(ADMIN_ROLE) prizeIsActive(prizeId) {
        if (prizeRanges[prizeId].length == 0) revert EmptyTicketPool();
        if (prizes[prizeId].winner != address(0)) revert WinnerDrawn(prizes[prizeId].winner);

        string memory callbackSig = "handleWinnerSelection(uint256,uint256[])";
        uint256 requestId = supraRouter.generateRequest(
            callbackSig,
            1,
            1,
            uint256(keccak256(abi.encodePacked(prizeId, block.timestamp))),
            msg.sender
        );
        
        pendingVRFRequests[requestId] = prizeId;
        emit WinnerRequested(prizeId, requestId);
    }

    // Callback from VRF to set the winning ticket number (does not set the winner itself)
    function handleWinnerSelection(uint256 requestId, uint256[] memory rng) external onlyRole(SUPRA_ROLE) {
        uint256 prizeId = pendingVRFRequests[requestId];
        
        if (!prizes[prizeId].isActive) revert PrizeInactive();

        uint256 idx = (rng[0] % totalTickets[prizeId]) + 1;
        prizes[prizeId].winnerIndex = idx;
        prizes[prizeId].isActive = false;
    
        emit WinnerSelected(prizeId, idx);
    }

    // Admin function called immediately after VRF callback to set the winner in contract storage
    // Executes a binary search to find the winner but only called once
    function setWinner(uint256 prizeId) external onlyRole(ADMIN_ROLE) {
        Prize storage prize = prizes[prizeId];
        require(prize.winnerIndex > 0, "Winner index not set");
        require(prize.winner == address(0), "Winner already set");
        
        // Do binary search to find winner
        Range[] storage ranges = prizeRanges[prizeId];
        uint256 target = prize.winnerIndex;
        
        if (ranges.length == 0 || target == 0) {
            revert("Invalid winner index");
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
        
        // Store winner in prize struct
        prize.winner = ranges[lo].user;
        
        emit WinnerSet(prizeId, prize.winner);
    }

    // read function to get the winner of a prize by direct read
    function getWinner(uint256 prizeId) public view returns (address) {
        return prizes[prizeId].winner;
    }

    // User claims their prize, we mark it as claimed and deactivate the prize
    function claimPrize(uint256 prizeId) external {
        Prize storage prize = prizes[prizeId];
        if (prize.isActive) revert();
        if (prize.winnerIndex == 0) revert WinnerNotDrawn();
        if (prize.claimed) revert WinnerClaimed();
        if (msg.sender != prize.winner) revert NotAWinner();

        prize.claimed = true;
        winnings[msg.sender].push(prizeId);
        
        emit PrizeClaimed(msg.sender, prizeId);
    }

    // Return the data for all prizes for a user, including the prizes themselves
    // the prizes, how much they spent on each, and how many unclaimed and claimed wins they have
    function getUserEntries(address user) external view returns (
        uint256[] memory _prizeIds,
        uint256[] memory ticketCounts,
        uint256[] memory unclaimedWinnings,
        uint256[] memory claimedWinnings
    ) {
        uint256 count = prizeIds.length;
        _prizeIds = new uint256[](count);
        ticketCounts = new uint256[](count);
        
        // Count winners first to allocate arrays correctly
        uint256 unclaimedCount = 0;
        uint256 claimedCount = 0;
        for (uint256 i = 0; i < count; i++) {
            uint256 prizeId = prizeIds[i];
            Prize storage prize = prizes[prizeId];
            if (prize.winner == user) {
                if (prize.claimed) {
                    claimedCount++;
                } else {
                    unclaimedCount++;
                }
            }
        }
        
        unclaimedWinnings = new uint256[](unclaimedCount);
        claimedWinnings = new uint256[](claimedCount);
        unclaimedCount = 0;  // Reset for reuse
        claimedCount = 0;    // Reset for reuse

        // Copy prize IDs and process each prize
        for (uint256 i = 0; i < count; i++) {
            uint256 prizeId = prizeIds[i];
            _prizeIds[i] = prizeId;
            
            // Calculate tickets spent
            Range[] storage ranges = prizeRanges[prizeId];
            for (uint256 j = 0; j < ranges.length; j++) {
                if (ranges[j].user == user) {
                    uint256 prevEnd = (j == 0) ? 0 : ranges[j - 1].cumulativeEnd;
                    ticketCounts[i] += ranges[j].cumulativeEnd - prevEnd;
                }
            }
            
            // Track winnings
            Prize storage prize = prizes[prizeId];
            if (prize.winner == user) {
                if (prize.claimed) {
                    claimedWinnings[claimedCount++] = prizeId;
                } else {
                    unclaimedWinnings[unclaimedCount++] = prizeId;
                }
            }
        }

        return (_prizeIds, ticketCounts, unclaimedWinnings, claimedWinnings);
    }

    function getPrizeIds() external view returns (uint256[] memory) {
        return prizeIds;
    }

    struct PrizeWithTickets {
        string name;
        string description;
        uint256 value;
        uint256 endTimestamp;
        bool isActive;
        address winner;
        uint256 winnerIndex;
        bool claimed;
        uint256 totalTickets;  // Added field
        uint256 totalUsers;
    }


    function getPrizeDetails(uint256 prizeId) external view returns (
        string memory name,
        string memory description,
        uint256 ticketCost,
        bool isActive,
        address winner,
        uint256 winnerIndex,
        uint256 totalUsers,
        bool claimed
    ) {
        Prize storage p = prizes[prizeId];
        
        return (
            p.name,
            p.description,
            totalTickets[prizeId],
            p.isActive,
            p.winner,
            p.winnerIndex,
            totalUniqueUsers[prizeId],
            p.claimed
        );
    }

    function getPrizeDetails() external view returns (PrizeWithTickets[] memory) {
        uint256 prizeCount = prizeIds.length;
        PrizeWithTickets[] memory prizeArray = new PrizeWithTickets[](prizeCount);
        
        for (uint256 i = 0; i < prizeCount; i++) {
            uint256 currentPrizeId = prizeIds[i];
            Prize storage currentPrize = prizes[currentPrizeId];
            
            prizeArray[i] = PrizeWithTickets({
                name: currentPrize.name,
                description: currentPrize.description,
                value: currentPrize.value,
                endTimestamp: currentPrize.endTimestamp,
                isActive: currentPrize.isActive,
                winner: currentPrize.winner,
                winnerIndex: currentPrize.winnerIndex,
                claimed: currentPrize.claimed,
                totalTickets: totalTickets[currentPrizeId],
                totalUsers: totalUniqueUsers[currentPrizeId]
            });
        }
        
        return prizeArray;
    }
    
    // Timestamp update for prizes
    function updatePrizeEndTimestamp(uint256 prizeId, uint256 endTimestamp) external onlyRole(ADMIN_ROLE) prizeIsActive(prizeId) {
        prizes[prizeId].endTimestamp = endTimestamp;
    }

    /**
     * @notice Set the active status of a prize manually
     * @dev This function is primarily intended for testing and administrative purposes
     * @param prizeId The ID of the prize to modify
     * @param active The new active status to set
     */
    function setPrizeActive(uint256 prizeId, bool active) external onlyRole(ADMIN_ROLE) {
        Prize storage prize = prizes[prizeId];
        require(bytes(prize.name).length != 0, "Prize does not exist");
        require(prize.winnerIndex == 0, "Winner already selected");
        prizes[prizeId].isActive = active;
    }

    // UUPS Authorization
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(ADMIN_ROLE) {}
    
    // Allow contract to receive ETH
    receive() external payable {}
}