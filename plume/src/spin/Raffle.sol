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
    mapping(uint256 => bool) public isWinnerRequestPending;

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
    error WinnerRequestPending(uint256 prizeId);

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
    
    modifier prizeIsActive(uint256 prizeId) {
        require(prizes[prizeId].isActive, "Prize not available");
        _;
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

        if (isWinnerRequestPending[prizeId]) {
            revert WinnerRequestPending(prizeId);
        }
        isWinnerRequestPending[prizeId] = true;

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
        
        isWinnerRequestPending[prizeId] = false;
        delete pendingVRFRequests[requestId];

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