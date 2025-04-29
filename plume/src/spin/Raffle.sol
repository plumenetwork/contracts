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

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant SUPRA_ROLE = keccak256("SUPRA_ROLE");

    // prizeId => Prize
    mapping(uint256 => Prize) public prizes;
    // active prize IDs
    uint256[] public prizeIds;
    // prizeId => ranges of ticket ownership
    mapping(uint256 => Range[]) public prizeRanges;
    // tracking total tickets via ranges
    mapping(uint256 => uint256) public totalTickets;
    // VRF
    ISupraRouterContract public supraRouter;
    // VRF request mapping
    mapping(uint256 => uint256) private pendingRequestPrize;
    // Spin contract
    ISpin public spinContract;
    // Add this to your contract state variables
    mapping(uint256 => mapping(address => bool)) public userHasEnteredPrize;
    mapping(uint256 => uint256) public totalUniqueUsers;
    mapping(address => uint256[]) public userWinnings;

    event PrizeAdded(uint256 indexed prizeId, string name);
    event PrizeRemoved(uint256 indexed prizeId);
    event TicketSpent(address indexed user, uint256 indexed prizeId, uint256 tickets);
    event WinnerRequested(uint256 indexed prizeId, uint256 indexed requestId);
    event WinnerSelected(uint256 indexed prizeId, uint256 winnerIndex);
    event PrizeClaimed(address indexed user, uint256 indexed prizeId);

    // Add these custom errors near the top of your contract
    error EmptyTicketPool();
    error WinnerDrawn(address winner);
    error PrizeInactive();
    error InsufficientTickets();
    error WinnerNotDrawn();
    error NotAWinner();

    function initialize(address _spinContract, address _supraRouter) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        spinContract = ISpin(_spinContract);
        supraRouter = ISupraRouterContract(_supraRouter);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(SUPRA_ROLE, _supraRouter);
    }

    modifier onlyAdmin() {
        require(hasRole(ADMIN_ROLE, msg.sender), "Not admin");
        _;
    }
    modifier onlySupra() {
        require(hasRole(SUPRA_ROLE, msg.sender), "Not supra");
        _;
    }
    modifier onlyPrize(uint256 prizeId) {
        require(prizes[prizeId].isActive, "Prize not available");
        _;
    }

    function addPrize(
        string calldata name,
        string calldata description,
        uint256 value
    ) external onlyAdmin {
        uint256 prizeId = prizeIds.length + 1;
        prizes[prizeId] = Prize({
            name: name,
            description: description,
            value: value,
            endTimestamp: 0,
            isActive: true,
            winner: address(0),
            winnerIndex: 0
        });
        prizeIds.push(prizeId);
        emit PrizeAdded(prizeId, name);
    }

    function removePrize(uint256 prizeId) external onlyAdmin onlyPrize(prizeId) {
        prizes[prizeId].isActive = false;
        // remove from prizeIds array
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

    function spendRaffle(uint256 prizeId, uint256 ticketAmount)
        external
        onlyPrize(prizeId)
    {
        require(ticketAmount > 0, "Must spend at least 1 ticket");

        // Verify and deduct tickets from user balance
        (,,,, uint256 userRaffleTickets,,) = spinContract.getUserData(msg.sender);
        if (userRaffleTickets < ticketAmount) revert InsufficientTickets();
        spinContract.updateRaffleTickets(msg.sender, ticketAmount);

        // append range
        uint256 prevTotal = totalTickets[prizeId];
        uint256 newTotal = prevTotal + ticketAmount;
        prizeRanges[prizeId].push(
            Range({ user: msg.sender, cumulativeEnd: newTotal })
        );
        totalTickets[prizeId] = newTotal;

        // Then in spendRaffle, add:
        if (!userHasEnteredPrize[prizeId][msg.sender]) {
            userHasEnteredPrize[prizeId][msg.sender] = true;
            totalUniqueUsers[prizeId]++;
        }

        emit TicketSpent(msg.sender, prizeId, ticketAmount);
    }

    function requestWinner(uint256 prizeId)
        external
        onlyAdmin
        onlyPrize(prizeId)
    {
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
        pendingRequestPrize[requestId] = prizeId;
        emit WinnerRequested(prizeId, requestId);
    }

    function handleWinnerSelection(uint256 requestId, uint256[] memory rng)
        external
        onlySupra
    {
        uint256 prizeId = pendingRequestPrize[requestId];
        if (!prizes[prizeId].isActive) revert PrizeInactive();

        uint256 idx = (rng[0] % totalTickets[prizeId]) + 1;
        prizes[prizeId].winnerIndex = idx;
        emit WinnerSelected(prizeId, idx);
    }

    /// @notice binary-search lookup
    function getWinner(uint256 prizeId)
        public
        view
        returns (address)
    {
        Range[] storage ranges = prizeRanges[prizeId];
        uint256 target = prizes[prizeId].winnerIndex;
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

    function claimPrize(uint256 prizeId) external onlyPrize(prizeId) {
        if (prizes[prizeId].winnerIndex == 0) revert WinnerNotDrawn();
        address winner = getWinner(prizeId);
        if (msg.sender != winner) revert NotAWinner();

        prizes[prizeId].winner = winner;
        prizes[prizeId].isActive = false;
        
        userWinnings[msg.sender].push(prizeId);
        
        emit PrizeClaimed(winner, prizeId);
    }

    // First function - get entries for specific prize
    function getUserEntries(uint256 prizeId, address user) external view returns (uint256 ticketCount, uint256[] memory winnings) {
        // Calculate total tickets by user for this prize
        ticketCount = 0;
        Range[] storage ranges = prizeRanges[prizeId];
        
        for (uint256 i = 0; i < ranges.length; i++) {
            if (ranges[i].user == user) {
                // Calculate how many tickets in this range
                uint256 rangeStart = i > 0 ? ranges[i-1].cumulativeEnd : 0;
                uint256 rangeEnd = ranges[i].cumulativeEnd;
                ticketCount += (rangeEnd - rangeStart);
            }
        }
        
        // Return the user's winnings
        return (ticketCount, userWinnings[user]);
    }

    // Second function - get entries across all prizes
    function getUserEntries(address user) external view returns (
        uint256[] memory _prizeIds,
        uint256[] memory ticketCounts,
        uint256[] memory winnings
    ) {
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
                    uint256 rangeStart = j > 0 ? ranges[j-1].cumulativeEnd : 0;
                    uint256 rangeEnd = ranges[j].cumulativeEnd;
                    ticketCounts[i] += (rangeEnd - rangeStart);
                }
            }
        }
        
        return (_prizeIds, ticketCounts, userWinnings[user]);
    }

    // view helpers
    function getPrizeIds() external view returns (uint256[] memory) {
        return prizeIds;
    }

    function getPrizeDetails(uint256 prizeId) external view returns (
        string memory name,
        string memory description,
        uint256 ticketCost,
        bool     isActive,
        address  winner,
        uint256  winnerIndex,
        uint256  totalUsers
    )
    {
        Prize storage p = prizes[prizeId];
        return (
            p.name,
            p.description,
            totalTickets[prizeId],
            p.isActive,
            p.winner,
            p.winnerIndex,
            totalUniqueUsers[prizeId]
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

    function getUserWinningStatus(address user) external view returns (
        uint256[] memory wonUnclaimedPrizeIds,
        uint256[] memory claimedPrizeIds
    ) {
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
        
        // Return claimed prizes from userWinnings
        claimedPrizeIds = userWinnings[user];
        
        return (wonUnclaimedPrizeIds, claimedPrizeIds);
    }

    function _authorizeUpgrade(address) internal override onlyAdmin {}
}
