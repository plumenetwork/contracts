// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "../interfaces/ISupraRouterContract.sol";

interface ISpin {

    function spendRaffleTickets(
        address _user,
        uint256 _amount
    ) external;
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
        address winner; // @deprecated
        uint256 winnerIndex; // @deprecated
        bool claimed; // @deprecated
        uint256 quantity;
        string formId;
    }

    struct Range {
        address user;
        uint256 cumulativeEnd;
    }

    struct Winner {
        address winnerAddress;
        uint256 winningTicketIndex;
        uint256 drawnAt;
        bool claimed;
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

    // --- NEW STATE FOR MULTI-WINNER ---
    mapping(uint256 => Winner[]) public prizeWinners;
    mapping(uint256 => uint256) public winnersDrawn;
    mapping(uint256 => mapping(address => uint256)) public userWinCount;

    // Structure: prizeId => winnerIndex => isInvalid
    mapping(uint256 => mapping(uint256 => bool)) public invalidWinners;

    // Migration tracking
    bool private _migrationComplete;

    // Reserved storage gap for future upgrades
    uint256[45] private __gap; // Reduced by 1 due to new mapping

    // Events
    event PrizeAdded(uint256 indexed prizeId, string name);
    event NextPrizeIdUpdated(uint256 oldId, uint256 newId);
    event PrizeRemoved(uint256 indexed prizeId);
    event TicketSpent(address indexed user, uint256 indexed prizeId, uint256 tickets);
    event WinnerRequested(uint256 indexed prizeId, uint256 indexed requestId);
    event WinnerSelected(uint256 indexed prizeId, address indexed winner, uint256 winningTicketIndex);
    event PrizeClaimed(address indexed user, uint256 indexed prizeId, uint256 winnerIndex);
    event PrizeMigrated(uint256 indexed prizeId, uint256 migratedEntries, uint256 totalTickets);
    event PrizeEdited(
        uint256 indexed prizeId, string name, string description, uint256 value, uint256 quantity, string indexed formId
    );
    event WinnerSet(uint256 indexed prizeId, address indexed winner); // @deprecated

    event WinnerInvalidated(uint256 indexed prizeId, uint256 indexed winnerIndex, address indexed winner);
    error AlreadyInvalid();
    error InvalidWinnerIndex();
    error WinnerInvalid(); // used in claimPrize for invalidated winners

    // Errors
    error EmptyTicketPool();
    error WinnerDrawn(address winner); // @deprecated
    error AllWinnersDrawn();
    error NoMoreWinners();
    error WinnerClaimed();
    error PrizeInactive();
    error InsufficientTickets();
    error WinnerNotDrawn();
    error NotAWinner();
    error WinnerRequestPending(uint256 prizeId);

    // Track the next prize ID so even if some are deleted we know it
    uint256 private nextPrizeId;

    // Initialize function
    function initialize(
        address _spinContract,
        address _supraRouter
    ) public initializer {
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

    modifier prizeIsActive(
        uint256 prizeId
    ) {
        require(prizes[prizeId].isActive, "Prize not available");
        _;
    }

    // Prize management
    function addPrize(
        string calldata name,
        string calldata description,
        uint256 value,
        uint256 quantity,
        string calldata formId
    ) external onlyRole(ADMIN_ROLE) {
        uint256 prizeId = nextPrizeId++;
        prizeIds.push(prizeId);

        require(bytes(prizes[prizeId].name).length == 0, "Prize ID already in use");
        require(quantity > 0, "Quantity must be greater than 0");

        prizes[prizeId] = Prize({
            name: name,
            description: description,
            value: value,
            endTimestamp: 0,
            isActive: true,
            winner: address(0), // deprecated
            winnerIndex: 0, // deprecated
            claimed: false, // deprecated
            quantity: quantity,
            formId: formId
        });

        emit PrizeAdded(prizeId, name);
    }

    function editPrize(
        uint256 prizeId,
        string calldata name,
        string calldata description,
        uint256 value,
        uint256 quantity,
        string calldata formId
    ) external onlyRole(ADMIN_ROLE) prizeIsActive(prizeId) {
        // Update prize details without affecting tickets or active status
        Prize storage prize = prizes[prizeId];
        prize.name = name;
        prize.description = description;
        prize.value = value;
        prize.quantity = quantity;
        prize.formId = formId;

        emit PrizeEdited(prizeId, name, description, value, quantity, formId);
    }

    function removePrize(
        uint256 prizeId
    ) external onlyRole(ADMIN_ROLE) prizeIsActive(prizeId) {
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
    function spendRaffle(
        uint256 prizeId,
        uint256 ticketAmount
    ) external prizeIsActive(prizeId) {
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

    // Admin requests a winner to be selected by VRF
    function requestWinner(
        uint256 prizeId
    ) external onlyRole(ADMIN_ROLE) {
        if (getValidWinnersCount(prizeId) >= prizes[prizeId].quantity) {
            revert AllWinnersDrawn();
        }

        if (prizeRanges[prizeId].length == 0) {
            revert EmptyTicketPool();
        }
        require(prizes[prizeId].isActive, "Prize not available");

        if (isWinnerRequestPending[prizeId]) {
            revert WinnerRequestPending(prizeId);
        }
        isWinnerRequestPending[prizeId] = true;

        string memory callbackSig = "handleWinnerSelection(uint256,uint256[])";
        uint256 requestId = supraRouter.generateRequest(
            callbackSig, 1, 1, uint256(keccak256(abi.encodePacked(prizeId, block.timestamp))), msg.sender
        );

        pendingVRFRequests[requestId] = prizeId;
        emit WinnerRequested(prizeId, requestId);
    }

    function invalidateWinner(
        uint256 prizeId,
        uint256 winnerIndex
    ) external onlyRole(ADMIN_ROLE) {
        if (winnerIndex >= prizeWinners[prizeId].length) {
            revert InvalidWinnerIndex();
        }

        Winner storage w = prizeWinners[prizeId][winnerIndex];

        if (w.winnerAddress == address(0)) {
            revert InvalidWinnerIndex();
        }
        if (w.claimed) {
            revert WinnerClaimed();
        }
        if (invalidWinners[prizeId][winnerIndex]) {
            revert AlreadyInvalid();
        }

        // Mark as invalid in separate mapping
        invalidWinners[prizeId][winnerIndex] = true;

        // Keep counts consistent
        if (winnersDrawn[prizeId] > 0) {
            winnersDrawn[prizeId] -= 1;
        }
        uint256 c = userWinCount[prizeId][w.winnerAddress];
        if (c > 0) {
            userWinCount[prizeId][w.winnerAddress] = c - 1;
        }

        // Reactivate prize so it's editable & redrawable
        prizes[prizeId].isActive = true;

        emit WinnerInvalidated(prizeId, winnerIndex, w.winnerAddress);
    }

    // Callback from VRF to set the winning ticket number and determine the winner
    function handleWinnerSelection(
        uint256 requestId,
        uint256[] memory rng
    ) external onlyRole(SUPRA_ROLE) {
        uint256 prizeId = pendingVRFRequests[requestId];

        isWinnerRequestPending[prizeId] = false;
        delete pendingVRFRequests[requestId];

        if (!prizes[prizeId].isActive) {
            revert PrizeInactive();
        }

        // Check actual valid winners count
        if (getValidWinnersCount(prizeId) >= prizes[prizeId].quantity) {
            revert NoMoreWinners();
        }

        uint256 winningTicketIndex = (rng[0] % totalTickets[prizeId]) + 1;

        // Binary search for the winner
        Range[] storage ranges = prizeRanges[prizeId];
        address winnerAddress;

        if (ranges.length > 0) {
            uint256 lo = 0;
            uint256 hi = ranges.length - 1;
            while (lo < hi) {
                uint256 mid = (lo + hi) >> 1;
                if (winningTicketIndex <= ranges[mid].cumulativeEnd) {
                    hi = mid;
                } else {
                    lo = mid + 1;
                }
            }
            winnerAddress = ranges[lo].user;
        }

        // Store winner details (no 'valid' flag needed)
        prizeWinners[prizeId]
        .push(
            Winner({
                winnerAddress: winnerAddress,
                winningTicketIndex: winningTicketIndex,
                drawnAt: block.timestamp,
                claimed: false
            })
        );

        winnersDrawn[prizeId]++;
        userWinCount[prizeId][winnerAddress]++;

        // Deactivate prize if all valid winners have been drawn
        if (getValidWinnersCount(prizeId) >= prizes[prizeId].quantity) {
            prizes[prizeId].isActive = false;
        }

        emit WinnerSelected(prizeId, winnerAddress, winningTicketIndex);
    }

    // Helper function to count valid (non-invalidated) winners
    function getValidWinnersCount(
        uint256 prizeId
    ) public view returns (uint256) {
        Winner[] storage arr = prizeWinners[prizeId];
        uint256 count = 0;
        for (uint256 i = 0; i < arr.length; i++) {
            if (!invalidWinners[prizeId][i]) {
                count++;
            }
        }
        return count;
    }

    function getValidPrizeWinners(
        uint256 prizeId
    ) external view returns (Winner[] memory) {
        Winner[] storage allWins = prizeWinners[prizeId];
        uint256 n = 0;

        // Count valid winners
        for (uint256 i = 0; i < allWins.length; i++) {
            if (!invalidWinners[prizeId][i]) {
                n++;
            }
        }

        // Build array of valid winners
        Winner[] memory out = new Winner[](n);
        uint256 j = 0;
        for (uint256 i = 0; i < allWins.length; i++) {
            if (!invalidWinners[prizeId][i]) {
                out[j++] = allWins[i];
            }
        }
        return out;
    }

    // Admin function called immediately after VRF callback to set the winner in contract storage
    // Executes a binary search to find the winner but only called once
    function setWinner(
        uint256 prizeId
    ) external onlyRole(ADMIN_ROLE) {
        revert("setWinner is deprecated, winner is set in handleWinnerSelection");
    }

    // read function to get the winner of a prize by direct read
    function getWinner(
        uint256 prizeId,
        uint256 index
    ) public view returns (address) {
        return prizeWinners[prizeId][index].winnerAddress;
    }

    function claimPrize(
        uint256 prizeId,
        uint256 winnerIndex
    ) external {
        // Check if this specific winner exists
        if (winnerIndex >= prizeWinners[prizeId].length) {
            revert WinnerNotDrawn();
        }

        Winner storage individualWin = prizeWinners[prizeId][winnerIndex];

        // Check if winner has been drawn (address should not be zero)
        if (individualWin.winnerAddress == address(0)) {
            revert WinnerNotDrawn();
        }

        if (individualWin.claimed) {
            revert WinnerClaimed();
        }
        if (msg.sender != individualWin.winnerAddress) {
            revert NotAWinner();
        }

        // FIXED: Check if winner has been invalidated
        if (invalidWinners[prizeId][winnerIndex]) {
            revert WinnerInvalid();
        }

        individualWin.claimed = true;
        winnings[msg.sender].push(prizeId);

        emit PrizeClaimed(msg.sender, prizeId, winnerIndex);
    }

    /**
     * @notice Allows an admin to cancel a pending VRF winner request.
     * @dev This is an escape hatch in case the oracle callback fails,
     * which would otherwise leave the prize in a permanently pending state.
     * @param prizeId The ID of the prize with the pending request.
     */
    function cancelWinnerRequest(
        uint256 prizeId
    ) external onlyRole(ADMIN_ROLE) {
        require(isWinnerRequestPending[prizeId], "No request pending for this prize");
        isWinnerRequestPending[prizeId] = false;
    }

    function getPrizeIds() external view returns (uint256[] memory) {
        return prizeIds;
    }

    function setNextPrizeId(
        uint256 newId
    ) external onlyRole(ADMIN_ROLE) {
        require(newId != 0, "nextPrizeId cannot be 0");
        // Optional: prevent no-op
        require(newId != nextPrizeId, "No change");
        uint256 oldId = nextPrizeId;
        nextPrizeId = newId;
        emit NextPrizeIdUpdated(oldId, newId);
    }

    function getCurrentNextPrizeId() external view returns (uint256) {
        return nextPrizeId;
    }

    struct PrizeWithTickets {
        string name;
        string description;
        uint256 value;
        uint256 endTimestamp;
        bool isActive;
        uint256 quantity;
        uint256 winnersDrawn;
        uint256 totalTickets;
        uint256 totalUsers;
        string formId;
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
            address winner, // @deprecated
            uint256 winnerIndex, // @deprecated
            uint256 totalUsers,
            bool claimed, // @deprecated
            uint256 quantity,
            uint256 numWinnersDrawn,
            string memory formId
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
            totalUniqueUsers[prizeId],
            p.claimed,
            p.quantity,
            getValidWinnersCount(prizeId),
            p.formId
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
                quantity: currentPrize.quantity,
                winnersDrawn: getValidWinnersCount(currentPrizeId),
                totalTickets: totalTickets[currentPrizeId],
                totalUsers: totalUniqueUsers[currentPrizeId],
                formId: currentPrize.formId
            });
        }

        return prizeArray;
    }

    function getPrizeWinners(
        uint256 prizeId
    ) external view returns (Winner[] memory) {
        return prizeWinners[prizeId];
    }

    function isWinnerValid(
        uint256 prizeId,
        uint256 winnerIndex
    ) external view returns (bool) {
        return !invalidWinners[prizeId][winnerIndex];
    }

    /**
     * @notice Returns the indices in prizeWinners[prizeId] for a given user's wins.
     * @dev These indices are the values to pass as winnerIndex to claimPrize.
     * @param prizeId The prize identifier.
     * @param onlyUnclaimed If true, returns only indices of unclaimed wins.
     * @param user The user address to query for.
     */
    function getWinnerIndices(
        uint256 prizeId,
        bool onlyUnclaimed,
        address user
    ) external view returns (uint256[] memory) {
        Winner[] storage wins = prizeWinners[prizeId];
        uint256[] memory indices = new uint256[](wins.length);
        uint256 j = 0;
        for (uint256 i = 0; i < wins.length; i++) {
            // Also check that winner is not invalidated
            if (wins[i].winnerAddress == user && !invalidWinners[prizeId][i] && (!onlyUnclaimed || !wins[i].claimed)) {
                indices[j++] = i;
            }
        }
        assembly ("memory-safe") {
            mstore(indices, j)
        }
        return indices;
    }

    /**
     * @notice Returns the indices in prizeWinners[prizeId] for the caller's wins.
     * @dev These indices are the values to pass as winnerIndex to claimPrize.
     * @param prizeId The prize identifier.
     * @param onlyUnclaimed If true, returns only indices of unclaimed wins.
     */
    function getMyWinnerIndices(
        uint256 prizeId,
        bool onlyUnclaimed
    ) external view returns (uint256[] memory) {
        Winner[] storage wins = prizeWinners[prizeId];
        uint256[] memory indices = new uint256[](wins.length);
        uint256 j = 0;
        for (uint256 i = 0; i < wins.length; i++) {
            // Also check that winner is not invalidated
            if (
                wins[i].winnerAddress == msg.sender && !invalidWinners[prizeId][i]
                    && (!onlyUnclaimed || !wins[i].claimed)
            ) {
                indices[j++] = i;
            }
        }
        assembly ("memory-safe") {
            mstore(indices, j)
        }
        return indices;
    }

    function getUserWinnings(
        address user
    ) external view returns (uint256[] memory) {
        return winnings[user];
    }

    // Timestamp update for prizes
    function updatePrizeEndTimestamp(
        uint256 prizeId,
        uint256 endTimestamp
    ) external onlyRole(ADMIN_ROLE) {
        prizes[prizeId].endTimestamp = endTimestamp;
    }

    /**
     * @notice Set the active status of a prize manually
     * @dev This function is primarily intended for testing and administrative purposes
     * @param prizeId The ID of the prize to modify
     * @param active The new active status to set
     */
    function setPrizeActive(
        uint256 prizeId,
        bool active
    ) external onlyRole(ADMIN_ROLE) {
        Prize storage prize = prizes[prizeId];
        require(bytes(prize.name).length != 0, "Prize does not exist");
        if (active) {
            require(getValidWinnersCount(prizeId) < prize.quantity, "All winners already selected");
        }
        prizes[prizeId].isActive = active;
    }

    // UUPS Authorization
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(ADMIN_ROLE) { }

    // Allow contract to receive ETH
    receive() external payable { }

}
