// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import "../interfaces/IDateTime.sol";
import "../interfaces/ISupraRouterContract.sol";

contract Spin is Initializable, AccessControlUpgradeable, UUPSUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
    // Storage
    struct UserData {
        uint256 jackpotWins;
        uint256 raffleTicketsGained;
        uint256 raffleTicketsBalance;
        uint256 PPGained;
        uint256 plumeTokens;
        uint256 streakCount;
        uint256 lastSpinTimestamp;
        uint256 nothingCounts;
    }

    // Defines the probability ranges for non-jackpot rewards based on a 0-999,999 scale.
    // Jackpot probability is determined separately by the daily jackpotProbabilities array.
    struct RewardProbabilities {
        uint256 plumeTokenThreshold; // Range start depends on daily jackpot threshold, ends here.
        uint256 raffleTicketThreshold; // Starts after plumeTokenThreshold, ends here.
        uint256 ppThreshold;         // Starts after raffleTicketThreshold, ends here.
        // anything above ppThreshold is "Nothing"
    }

    // Roles
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant SUPRA_ROLE = keccak256("SUPRA_ROLE");
    uint256 public constant SECONDS_PER_DAY = 86_400;

    // State variables
    address public admin;
    uint256 public lastJackpotClaimWeek;
    mapping(address => UserData) public userData;
    uint256[7] public jackpotProbabilities;
    uint256 public baseRaffleMultiplier;
    uint256 public PP_PerSpin;
    uint256[3] public plumeAmounts;
    mapping(uint256 => address) public userNonce;
    ISupraRouterContract public supraRouter;
    IDateTime public dateTime;
    address public raffleContract;
    uint256 public campaignStartDate;
    mapping(uint8 => uint256) public jackpotPrizes;
    mapping(address => bool) public whitelists;
    bool public enableSpin;
    RewardProbabilities public rewardProbabilities;
    mapping(address => bool) public isSpinPending;

    // Reserved storage gap for future upgrades
    uint256[50] private __gap;

    // Events
    event SpinRequested(uint256 indexed nonce, address indexed user);
    event SpinCompleted(address indexed walletAddress, string rewardCategory, uint256 rewardAmount);
    event RaffleTicketsSpent(address indexed walletAddress, uint256 ticketsUsed, uint256 remainingTickets);
    event NotEnoughStreak(string message);
    event JackpotAlreadyClaimed(string message);

    // Errors
    error NotAdmin();
    error AlreadySpunToday();
    error InvalidNonce();
    error CampaignNotStarted();
    error SpinRequestPending(address user);

    /**
     * @notice Initializes the Spin contract.
     * @param supraRouterAddress The address of the Supra Router contract.
     * @param dateTimeAddress The address of the DateTime contract.
     */
    function initialize(address supraRouterAddress, address dateTimeAddress) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(SUPRA_ROLE, supraRouterAddress);

        supraRouter = ISupraRouterContract(supraRouterAddress);
        dateTime = IDateTime(dateTimeAddress);
        admin = msg.sender;
        enableSpin = false;  // Start disabled until explicitly enabled

        // Set default values
        jackpotProbabilities = [1, 2, 3, 5, 7, 10, 20];
        jackpotPrizes[0] = 5000;
        jackpotPrizes[1] = 5000;
        jackpotPrizes[2] = 10_000;
        jackpotPrizes[3] = 10_000;
        jackpotPrizes[4] = 20_000;
        jackpotPrizes[5] = 20_000;
        jackpotPrizes[6] = 30_000;
        jackpotPrizes[7] = 30_000;
        jackpotPrizes[8] = 40_000;
        jackpotPrizes[9] = 40_000;
        jackpotPrizes[10] = 50_000;
        jackpotPrizes[11] = 100_000;

        baseRaffleMultiplier = 8;
        PP_PerSpin = 100;
        plumeAmounts = [1, 1, 1];

        lastJackpotClaimWeek = 999;  // start with arbitrary non-zero value

        // Set default probabilities
        // Note: Jackpot probability is handled by jackpotProbabilities based on dayOfWeek
        rewardProbabilities = RewardProbabilities({
            plumeTokenThreshold: 200_000,  // Up to 200,000 (Approx 20%)
            raffleTicketThreshold: 600_000, // Up to 600,000 (Approx 40%)
            ppThreshold: 900_000           // Up to 900,000 (Approx 30%)
                                           // Above 900,000 is "Nothing" (Approx 10%)
        });
    }

    /// @notice Ensures that the user can only spin once per day by checking their last spin date.
    modifier canSpin() {
        // Early return if the user is whitelisted
        if (whitelists[msg.sender]) {
            _;
            return;
        }

        UserData storage userDataStorage = userData[msg.sender];
        uint256 _lastSpinTimestamp = userDataStorage.lastSpinTimestamp;

        // Retrieve last spin date components
        (uint16 lastSpinYear, uint8 lastSpinMonth, uint8 lastSpinDay) = (
            dateTime.getYear(_lastSpinTimestamp),
            dateTime.getMonth(_lastSpinTimestamp),
            dateTime.getDay(_lastSpinTimestamp)
        );

        // Retrieve current date components
        (uint16 currentYear, uint8 currentMonth, uint8 currentDay) =
            (dateTime.getYear(block.timestamp), dateTime.getMonth(block.timestamp), dateTime.getDay(block.timestamp));

        // Ensure the user hasn't already spun today
        if (isSameDay(lastSpinYear, lastSpinMonth, lastSpinDay, currentYear, currentMonth, currentDay)) {
            revert AlreadySpunToday();
        }

        _;
    }

    modifier onlyRaffleContract() {
        require(msg.sender == raffleContract, "Only Raffle contract can call this");
        _;
    }

    /// @notice Starts the spin process by generating a random number and recording the spin date.
    /// @dev This function is called by the user to initiate a spin.
    function startSpin() external whenNotPaused canSpin {
        if (!enableSpin) {
            revert CampaignNotStarted();
        }

        if (isSpinPending[msg.sender]) {
            revert SpinRequestPending(msg.sender);
        }
        isSpinPending[msg.sender] = true;

        string memory callbackSignature = "handleRandomness(uint256,uint256[])";
        uint8 rngCount = 1;
        uint256 numConfirmations = 1;
        uint256 clientSeed = uint256(keccak256(abi.encodePacked(admin, block.timestamp)));

        uint256 nonce =
            supraRouter.generateRequest(callbackSignature, rngCount, numConfirmations, clientSeed, admin);
        userNonce[nonce] = msg.sender;

        emit SpinRequested(nonce, msg.sender);
    }

    function getCurrentWeek() public view returns (uint256) {
        return (block.timestamp - campaignStartDate) / 7 days;
    }

    /**
     * @notice Handles the randomness callback from the Supra Router.
     * @dev This function is called by the Supra Router to provide the random number and determine the reward.
     * @param nonce The nonce associated with the spin request.
     * @param rngList The list of random numbers generated.
     */
    function handleRandomness(uint256 nonce, uint256[] memory rngList) external onlyRole(SUPRA_ROLE) nonReentrant {
        address user = userNonce[nonce];
        if (user == address(0)) {
            revert InvalidNonce();
        }

        isSpinPending[user] = false;
        delete userNonce[nonce];

        uint256 randomness = rngList[0]; // Use full VRF range
        (string memory rewardCategory, uint256 rewardAmount) = determineReward(randomness, user);

        // Apply reward logic
        UserData storage userDataStorage = userData[user];

        

        // ----------  Effects: update storage first  ----------
        if (keccak256(bytes(rewardCategory)) == keccak256("Jackpot")) {
            uint256 currentWeek = getCurrentWeek();
            if (currentWeek == lastJackpotClaimWeek) {
                userDataStorage.nothingCounts += 1;
                rewardCategory = "Nothing";
                rewardAmount = 0;
                emit JackpotAlreadyClaimed("Jackpot already claimed this week");
            } else if (userDataStorage.streakCount < (currentWeek + 2)) {
                userDataStorage.nothingCounts += 1;
                rewardCategory = "Nothing";
                rewardAmount = 0;
                emit NotEnoughStreak("Not enough streak count to claim Jackpot");
            } else {
                userDataStorage.jackpotWins++;
                lastJackpotClaimWeek = currentWeek;
            }
        } else if (keccak256(bytes(rewardCategory)) == keccak256("Raffle Ticket")) {
            userDataStorage.raffleTicketsGained += rewardAmount;
            userDataStorage.raffleTicketsBalance += rewardAmount;
        } else if (keccak256(bytes(rewardCategory)) == keccak256("PP")) {
            userDataStorage.PPGained += rewardAmount;
        } else if (keccak256(bytes(rewardCategory)) == keccak256("Plume Token")) {
            userDataStorage.plumeTokens += rewardAmount;
        } else {
            userDataStorage.nothingCounts += 1;
        }

        // update the streak count after their spin
        userDataStorage.streakCount = _computeStreak(user, block.timestamp, true);
        userDataStorage.lastSpinTimestamp = block.timestamp;

        // ----------  Interactions: transfer Plume last ----------
        if (
            keccak256(bytes(rewardCategory)) == keccak256("Jackpot")
                || keccak256(bytes(rewardCategory)) == keccak256("Plume Token")
        ) {
            _safeTransferPlume(user, rewardAmount * 1 ether);
        }

        emit SpinCompleted(user, rewardCategory, rewardAmount);
    }

    /**
     * @notice Determines the reward category based on the VRF random number.
     * @param randomness The random number generated by the Supra Router.
     */
    function determineReward(uint256 randomness, address user) internal view returns (string memory, uint256) {
        uint256 probability = randomness % 1_000_000; // Normalize VRF range to 1M

        // Determine the current week in the 12-week campaign
        uint256 daysSinceStart = (block.timestamp - campaignStartDate) / 1 days;
        uint8 weekNumber = uint8(getCurrentWeek());
        uint8 dayOfWeek = uint8(daysSinceStart % 7);

        // Get jackpot threshold for the day of week
        uint256 jackpotThreshold = jackpotProbabilities[dayOfWeek];

        if (probability < jackpotThreshold) {
            return ("Jackpot", jackpotPrizes[weekNumber]);
        } else if (probability <= rewardProbabilities.plumeTokenThreshold) {
            uint256 plumeAmount = plumeAmounts[probability % 3];
            return ("Plume Token", plumeAmount);
        } else if (probability <= rewardProbabilities.raffleTicketThreshold) {
            return ("Raffle Ticket", baseRaffleMultiplier * (userData[user].streakCount + 1));
        } else if (probability <= rewardProbabilities.ppThreshold) {
            return ("PP", PP_PerSpin);
        }

        return ("Nothing", 0); // Default case
    }

    // ----------  Unified streak calculation ----------
    function _computeStreak(address user, uint256 nowTs, bool justSpun) internal view returns (uint256) {
        // if a user just spun, we need to increment the streak its a new day or a broken streak
        uint256 streakAdjustment = justSpun ? 1 : 0;
        uint256 lastSpinTs = userData[user].lastSpinTimestamp;
        if (lastSpinTs == 0) return 0 + streakAdjustment;
        uint256 lastDaySpun = lastSpinTs / SECONDS_PER_DAY;
        uint256 today   = nowTs     / SECONDS_PER_DAY;
        if (today == lastDaySpun) return userData[user].streakCount; // same day
        if (today == lastDaySpun + 1)   return userData[user].streakCount + streakAdjustment; // streak not broken yet
        return 0 + streakAdjustment; // broken streak
    }

    function currentStreak(address user) public view returns (uint256) {
        return _computeStreak(user, block.timestamp, false);
    }

    function _safeTransferPlume(address to, uint256 weiAmount) internal {
        require(address(this).balance >= weiAmount, "insufficient Plume in the Spin contract");
        (bool ok,) = to.call{value: weiAmount}("");
        require(ok, "Plume transfer failed");
    }

    function spendRaffleTickets(address user, uint256 ticketsUsed) external onlyRaffleContract {
        uint256 bal = userData[user].raffleTicketsBalance;
        require(bal >= ticketsUsed, "ticket underflow");
        userData[user].raffleTicketsBalance = bal - ticketsUsed;

        emit RaffleTicketsSpent(user, ticketsUsed, userData[user].raffleTicketsBalance);
    }

    /**
     * @notice Allows the admin to withdraw Ether from the contract.
     * @param recipient The address to receive the funds.
     * @param amount The amount of Ether to withdraw (in wei).
     */
    function withdraw(address payable recipient, uint256 amount) external onlyRole(ADMIN_ROLE) {
        require(address(this).balance >= amount, "Insufficient contract balance");
        require(recipient != address(0), "Invalid recipient address");

        (bool success,) = recipient.call{ value: amount }("");
        require(success, "Withdrawal failed");
    }

    /// @dev Allows the admin to pause the contract, preventing certain actions.
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    /// @dev Allows the admin to unpause the contract, resuming normal operations.
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    // Utility Functions
    /**
     * @notice Checks if two dates are the same day.
     * @param year1 The year of the first date.
     * @param month1 The month of the first date.
     * @param day1 The day of the first date.
     * @param year2 The year of the second date.
     * @param month2 The month of the second date.
     * @param day2 The day of the second date.
     */
    function isSameDay(
        uint16 year1,
        uint8 month1,
        uint8 day1,
        uint16 year2,
        uint8 month2,
        uint8 day2
    ) internal pure returns (bool) {
        return (year1 == year2 && month1 == month2 && day1 == day2);
    }

    /**
     * @notice Checks if the current date is the next day after the last spin date.
     * @param lastYear The year of the last spin date.
     * @param lastMonth The month of the last spin date.
     * @param lastDay The day of the last spin date.
     * @param currentYear The year of the current date.
     * @param currentMonth The month of the current date.
     * @param currentDay The day of the current date.
     */
    function isNextDay(
        uint16 lastYear,
        uint8 lastMonth,
        uint8 lastDay,
        uint16 currentYear,
        uint8 currentMonth,
        uint8 currentDay
    ) internal view returns (bool) {
        uint256 lastDateTimestamp = dateTime.toTimestamp(lastYear, lastMonth, lastDay);
        uint256 nextDayTimestamp = lastDateTimestamp + SECONDS_PER_DAY;

        uint16 nextDayYear = dateTime.getYear(nextDayTimestamp);
        uint8 nextDayMonth = dateTime.getMonth(nextDayTimestamp);
        uint8 nextDayDay = dateTime.getDay(nextDayTimestamp);

        return (nextDayYear == currentYear) && (nextDayMonth == currentMonth) && (nextDayDay == currentDay);
    }

    // View Functions
    /**
     * @notice Gets the data for a user.
     * @param user The address of the wallet.
     */
    function getUserData(
        address user
    )
        external
        view
        returns (
            uint256 dailyStreak,
            uint256 lastSpinTimestamp,
            uint256 jackpotWins,
            uint256 raffleTicketsGained,
            uint256 raffleTicketsBalance,
            uint256 ppGained,
            uint256 smallPlumeTokens
        )
    {
        UserData storage userDataStorage = userData[user];

        return (
            currentStreak(user),
            userDataStorage.lastSpinTimestamp,
            userDataStorage.jackpotWins,
            userDataStorage.raffleTicketsGained,
            userDataStorage.raffleTicketsBalance,
            userDataStorage.PPGained,
            userDataStorage.plumeTokens
        );
    }

    /**
     * @notice Returns the current week's jackpot prize and required streak count
     */
    function getWeeklyJackpot()
        external
        view
        returns (uint256 weekNumber, uint256 jackpotPrize, uint256 requiredStreak)
    {
        require(campaignStartDate > 0, "Campaign not started");

        uint256 daysSinceStart = (block.timestamp - campaignStartDate) / 1 days;
        weekNumber = daysSinceStart / 7;

        if (weekNumber > 11) {
            return (weekNumber, 0, 0);
        }

        jackpotPrize = jackpotPrizes[uint8(weekNumber)];
        requiredStreak = weekNumber + 2;
    }

    function getCampaignStartDate() external view returns (uint256) {
        return campaignStartDate;
    }

    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }

    // Setters
    /// @notice Sets the jackpot probabilities for each day of the week.
    /// @param _jackpotProbabilities An array of 7 integers representing the jackpot vrf range for each day.
    function setJackpotProbabilities(
        uint8[7] memory _jackpotProbabilities
    ) external onlyRole(ADMIN_ROLE) {
        jackpotProbabilities = _jackpotProbabilities;
    }

    /// @notice Sets the jackpot prize for a specific week.
    /// @param week The week number (0-11).
    /// @param prize The jackpot prize amount.
    function setJackpotPrizes(uint8 week, uint256 prize) external onlyRole(ADMIN_ROLE) {
        jackpotPrizes[week] = prize;
    }

    function setCampaignStartDate(uint256 start) external onlyRole(ADMIN_ROLE) {
        campaignStartDate = start == 0 ? block.timestamp : start;
    }

    /// @notice Sets the base value for raffle.
    /// @param _baseRaffleMultiplier The base value for raffle.
    function setBaseRaffleMultiplier(
        uint256 _baseRaffleMultiplier
    ) external onlyRole(ADMIN_ROLE) {
        baseRaffleMultiplier = _baseRaffleMultiplier;
    }

    /// @notice Sets the PP gained per spin.
    /// @param _PP_PerSpin The PP gained per spin.
    function setPP_PerSpin(
        uint256 _PP_PerSpin
    ) external onlyRole(ADMIN_ROLE) {
        PP_PerSpin = _PP_PerSpin;
    }

    /// @notice Sets the Plume Token amounts.
    /// @param _plumeAmounts An array of 3 integers representing the Plume Token amounts.
    function setPlumeAmounts(
        uint256[3] memory _plumeAmounts
    ) external onlyRole(ADMIN_ROLE) {
        plumeAmounts = _plumeAmounts;
    }

    /// @notice Sets the Raffle contract address.
    /// @param _raffleContract The address of the Raffle contract.
    function setRaffleContract(
        address _raffleContract
    ) external onlyRole(ADMIN_ROLE) {
        raffleContract = _raffleContract;
    }

    /// @notice Whitelist address to bypass cooldown period.
    /// @param user The address of the user to whitelist.
    function whitelist(
        address user
    ) external onlyRole(ADMIN_ROLE) {
        whitelists[user] = true;
    }

    /// @notice Enable or disable spinning
    /// @param _enableSpin The flag to enable/disable spinning
    function setEnableSpin(bool _enableSpin) external onlyRole(ADMIN_ROLE) {
        enableSpin = _enableSpin;
    }

    /**
     * @notice Updates the reward probabilities.
     * @param _plumeTokenThreshold The upper threshold for Plume Token rewards.
     * @param _raffleTicketThreshold The upper threshold for Raffle Ticket rewards.
     * @param _ppThreshold The upper threshold for PP rewards.
     */
    function setRewardProbabilities(
        uint256 _plumeTokenThreshold,
        uint256 _raffleTicketThreshold,
        uint256 _ppThreshold
    ) external onlyRole(ADMIN_ROLE) {
        require(_plumeTokenThreshold < _raffleTicketThreshold, "Invalid thresholds order");
        require(_raffleTicketThreshold < _ppThreshold, "Invalid thresholds order");
        require(_ppThreshold <= 1_000_000, "Threshold exceeds maximum");
        
        rewardProbabilities.plumeTokenThreshold = _plumeTokenThreshold;
        rewardProbabilities.raffleTicketThreshold = _raffleTicketThreshold;
        rewardProbabilities.ppThreshold = _ppThreshold;
    }

    // UUPS Authorization
    /**
     * @notice Authorizes the upgrade of the contract.
     * @param newImplementation The address of the new implementation.
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(ADMIN_ROLE) { }

    /// @notice Fallback function to receive ether
    receive() external payable { }
}