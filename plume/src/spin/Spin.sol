// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import "../interfaces/IDateTime.sol";
import "../interfaces/ISupraRouterContract.sol";
import { console } from "forge-std/console.sol";

/// @custom:oz-upgrades-from Spin
contract Spin is Initializable, AccessControlUpgradeable, UUPSUpgradeable, PausableUpgradeable {

    // Storage
    struct UserData {
        uint256 jackpotWins;
        uint256 raffleTickets;
        uint256 xpGained;
        uint256 plumeTokens;
        uint256 streakCount;
        uint256 lastSpinTimestamp;
    }

    /// @custom:storage-location erc7201:plume.storage.Spin
    struct SpinStorage {
        /// @dev Address of the admin managing the Spin contract
        address admin;
        /// @dev Last Jackpot claim timestamp
        uint256 lastJackpotClaim;
        /// @dev Mapping of wallet address to rewards
        mapping(address => UserData) userData;
        /// @dev Timestamp of start time of Spin Game
        uint256 startTimestamp;
        /// @dev Mapping of Week daya to Jackpot probabilities
        uint8[7] jackpotProbabilities;
        /// @dev Raffle Multiplier
        uint256 baseRaffleMultiplier;
        /// @dev XP gained per spin
        uint256 xpPerSpin;
        /// @dev Plume Token Rewards
        uint256[3] plumeAmounts;
        /// @dev Mapping of nonce to user
        mapping(uint256 => address) userNonce;
        /// @dev Reference to the Supra VRF interface
        ISupraRouterContract supraRouter;
        /// @dev Reference to the DateTime contract
        IDateTime dateTime;
        /// @dev Address of the Raffle contract
        address raffleContract;
        /// @dev Timestamp of campaign start
        uint256 campaignStartDate;
        /// @dev Mapping of Week to Jackpot Prizes
        mapping(uint8 => uint256) jackpotPrizes;
        mapping(address => bool) whitelists;
    }

    // keccak256(abi.encode(uint256(keccak256("plume.storage.Spin")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant SPIN_STORAGE_LOCATION = 0x35fc247836aa7388208f5bf12c548be42b83fa7b653b6690498b1d90754d0b00;

    function _getSpinStorage() internal pure returns (SpinStorage storage $) {
        assembly {
            $.slot := SPIN_STORAGE_LOCATION
        }
    }

    // Roles
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant SUPRA_ROLE = keccak256("SUPRA_ROLE");
    uint256 public constant SECONDS_PER_DAY = 86_400;

    // Events
    /// @notice Emitted when a spin is requested
    event SpinRequested(uint256 indexed nonce, address indexed user);
    /// @notice Emitted when a spin is completed
    event SpinCompleted(address indexed walletAddress, string rewardCategory, uint256 rewardAmount);

    event RaffleTicketsUpdated(address indexed walletAddress, uint256 ticketsUsed, uint256 remainingTickets);

    // Errors
    /// @notice Revert if the caller is not an admin
    error NotAdmin();
    /// @notice Revert if the user has already spun today
    error AlreadySpunToday();
    /// @notice Revert if the nonce is invalid
    error InvalidNonce();

    // Modifiers

    /// @notice Ensures that the user can only spin once per day by checking their last spin date.
    ///      This modifier retrieves the last recorded spin date from storage, compares it with
    ///      the current date using the `isSameDay` function, and reverts if the user has already spun today.
    modifier canSpin() {
        SpinStorage storage $ = _getSpinStorage();

        // Early return if the user is whitelisted
        if ($.whitelists[msg.sender]) {
            _;
            return;
        }

        IDateTime dateTime = $.dateTime;
        UserData storage userData = $.userData[msg.sender];
        uint256 _lastSpinTimestamp = userData.lastSpinTimestamp;

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
        SpinStorage storage $ = _getSpinStorage();
        require(msg.sender == $.raffleContract, "Only Raffle contract can call this");
        _;
    }

    /**
     * @notice Initializes the Spin contract.
     * @param supraRouterAddress The address of the Supra Router contract.
     * @param dateTimeAddress The address of the DateTime contract.
     */
    function initialize(address supraRouterAddress, address dateTimeAddress) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __Pausable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(SUPRA_ROLE, supraRouterAddress);

        SpinStorage storage $ = _getSpinStorage();
        $.supraRouter = ISupraRouterContract(supraRouterAddress);
        $.dateTime = IDateTime(dateTimeAddress);
        $.admin = msg.sender;
        $.startTimestamp = block.timestamp;

        $.jackpotProbabilities = [5, 10, 15, 25, 35, 50, 65];
        $.jackpotPrizes[0] = 5000;
        $.jackpotPrizes[1] = 5000;
        $.jackpotPrizes[2] = 10_000;
        $.jackpotPrizes[3] = 10_000;
        $.jackpotPrizes[4] = 20_000;
        $.jackpotPrizes[5] = 20_000;
        $.jackpotPrizes[6] = 30_000;
        $.jackpotPrizes[7] = 30_000;
        $.jackpotPrizes[8] = 40_000;
        $.jackpotPrizes[9] = 40_000;
        $.jackpotPrizes[10] = 50_000;
        $.jackpotPrizes[11] = 100_000;

        $.baseRaffleMultiplier = 100;
        $.xpPerSpin = 100;
        $.plumeAmounts = [2, 5, 10];
    }

    /// @notice Starts the spin process by generating a random number and recording the spin date.
    /// @dev This function is called by the user to initiate a spin.
    function startSpin() external whenNotPaused canSpin returns (uint256) {
        SpinStorage storage $ = _getSpinStorage();
        string memory callbackSignature = "handleRandomness(uint256,uint256[])";
        uint8 rngCount = 1;
        uint256 numConfirmations = 1;
        uint256 clientSeed = uint256(keccak256(abi.encodePacked($.admin, block.timestamp)));

        uint256 nonce =
            $.supraRouter.generateRequest(callbackSignature, rngCount, numConfirmations, clientSeed, $.admin);
        $.userNonce[nonce] = msg.sender;

        console.log("Nonce:", nonce);
        emit SpinRequested(nonce, msg.sender);
        return nonce;
    }

    /**
     * @notice Handles the randomness callback from the Supra Router.
     * @dev This function is called by the Supra Router to provide the random number and determine the reward.
     * @param nonce The nonce associated with the spin request.
     * @param rngList The list of random numbers generated.
     */
    function handleRandomness(uint256 nonce, uint256[] memory rngList) external onlyRole(SUPRA_ROLE) {
        SpinStorage storage $ = _getSpinStorage();

        address user = $.userNonce[nonce];
        if (user == address(0)) {
            revert InvalidNonce();
        }

        uint256 randomness = rngList[0]; // Use full VRF range
        (string memory rewardCategory, uint256 rewardAmount) = determineReward(randomness, user);

        // Apply reward logic
        UserData storage _userData = $.userData[user];

        if (keccak256(abi.encodePacked(rewardCategory)) == keccak256(abi.encodePacked("Jackpot"))) {
            require(block.timestamp >= $.lastJackpotClaim + 7 days, "Jackpot cooldown active");
            //TODO: Add case for ot enough streak count
            require(
                _userData.streakCount >= (block.timestamp - $.campaignStartDate) / 7 days + 2,
                "Not enough streak for jackpot"
            );

            _userData.jackpotWins++;
            $.lastJackpotClaim = block.timestamp;
        } else if (keccak256(abi.encodePacked(rewardCategory)) == keccak256(abi.encodePacked("Raffle Ticket"))) {
            _userData.raffleTickets += rewardAmount;
        } else if (keccak256(abi.encodePacked(rewardCategory)) == keccak256(abi.encodePacked("XP"))) {
            _userData.xpGained += rewardAmount;
        } else if (keccak256(abi.encodePacked(rewardCategory)) == keccak256(abi.encodePacked("Plume Token"))) {
            _userData.plumeTokens += rewardAmount;
        }

        _userData.streakCount = countStreak(user);
        _userData.lastSpinTimestamp = block.timestamp;

        emit SpinCompleted(user, rewardCategory, rewardAmount);
    }

    /**
     * @notice Determines the reward category based on the VRF random number.
     * @param randomness The random number generated by the Supra Router.
     */
    function determineReward(uint256 randomness, address user) internal view returns (string memory, uint256) {
        SpinStorage storage $ = _getSpinStorage();
        uint256 probability = randomness % 1_000_000; // Normalize VRF range to 1M

        // Determine the current week in the 12-week campaign
        uint256 daysSinceStart = (block.timestamp - $.campaignStartDate) / 1 days;
        uint8 weekNumber = uint8(daysSinceStart / 7);
        if (weekNumber > 11) {
            // TODO: Handle Default case
            return ("Nothing", 0);
        }

        uint8 dayOfWeek = uint8(daysSinceStart % 7);

        uint256 jackpotThreshold = (1_000_000 * $.jackpotProbabilities[dayOfWeek]) / 100;

        if (probability < jackpotThreshold) {
            return ("Jackpot", $.jackpotPrizes[weekNumber]);
        }
        uint256 rewardCategory = probability % 4;
        if (rewardCategory == 0) {
            return ("Raffle Ticket", $.baseRaffleMultiplier * $.userData[user].streakCount);
        } else if (rewardCategory == 1) {
            return ("XP", $.xpPerSpin);
        } else if (rewardCategory == 2) {
            uint256 plumeAmount = $.plumeAmounts[probability % 3];
            return ("Plume Token", plumeAmount);
        }

        return ("Nothing", 0); // Default case
    }

    function countStreak(
        address user
    ) internal view returns (uint256) {
        SpinStorage storage $ = _getSpinStorage();
        IDateTime dateTime = $.dateTime;

        UserData storage userData = $.userData[user];
        uint256 streakCount = userData.streakCount;
        uint256 currentTimestamp = block.timestamp;
        uint256 lastTimeStamp = userData.lastSpinTimestamp;

        (uint16 currentYear, uint8 currentMonth, uint8 currentDay) =
            (dateTime.getYear(currentTimestamp), dateTime.getMonth(currentTimestamp), dateTime.getDay(currentTimestamp));

        (uint16 lastSpinYear, uint8 lastSpinMonth, uint8 lastSpinDay) =
            (dateTime.getYear(lastTimeStamp), dateTime.getMonth(lastTimeStamp), dateTime.getDay(lastTimeStamp));

        if (streakCount == 0) {
            streakCount = 1;
        } else {
            if (isNextDay(lastSpinYear, lastSpinMonth, lastSpinDay, currentYear, currentMonth, currentDay, dateTime)) {
                streakCount++;
            } else if (isSameDay(lastSpinYear, lastSpinMonth, lastSpinDay, currentYear, currentMonth, currentDay)) {
                streakCount = streakCount;
            } else {
                streakCount = 1;
            }
        }
        return streakCount;
    }

    function readCountStreak(
        address user
    ) internal view returns (uint256) {
        SpinStorage storage $ = _getSpinStorage();
        IDateTime dateTime = $.dateTime;

        UserData storage userData = $.userData[user];
        uint256 streakCount = userData.streakCount;
        uint256 currentTimestamp = block.timestamp;
        uint256 lastTimeStamp = userData.lastSpinTimestamp;

        (uint16 currentYear, uint8 currentMonth, uint8 currentDay) =
            (dateTime.getYear(currentTimestamp), dateTime.getMonth(currentTimestamp), dateTime.getDay(currentTimestamp));

        (uint16 lastSpinYear, uint8 lastSpinMonth, uint8 lastSpinDay) =
            (dateTime.getYear(lastTimeStamp), dateTime.getMonth(lastTimeStamp), dateTime.getDay(lastTimeStamp));

        if (isNextDay(lastSpinYear, lastSpinMonth, lastSpinDay, currentYear, currentMonth, currentDay, dateTime)) {
            return streakCount;
        } else if (isSameDay(lastSpinYear, lastSpinMonth, lastSpinDay, currentYear, currentMonth, currentDay)) {
            return streakCount;
        }

        return 0;
    }

    function updateRaffleTickets(address user, uint256 ticketsUsed) external onlyRaffleContract {
        SpinStorage storage $ = _getSpinStorage();

        $.userData[user].raffleTickets -= ticketsUsed;

        emit RaffleTicketsUpdated(user, ticketsUsed, $.userData[user].raffleTickets);
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
        uint8 currentDay,
        IDateTime dateTime
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
            uint256 raffleTickets,
            uint256 xpGained,
            uint256 smallPlumeTokens
        )
    {
        SpinStorage storage $ = _getSpinStorage();
        UserData storage userData = $.userData[user];

        return (
            readCountStreak(user),
            userData.lastSpinTimestamp,
            userData.jackpotWins,
            userData.raffleTickets,
            userData.xpGained,
            userData.plumeTokens
        );
    }

    function setJackpotProbabilities(
        uint8[7] memory _jackpotProbabilities
    ) external onlyRole(ADMIN_ROLE) {
        SpinStorage storage $ = _getSpinStorage();
        $.jackpotProbabilities = _jackpotProbabilities;
    }

    function setJackpotPrizes(uint8 week, uint256 prize) external onlyRole(ADMIN_ROLE) {
        SpinStorage storage $ = _getSpinStorage();
        $.jackpotPrizes[week] = prize;
    }

    function setCampaignStartDate() external onlyRole(ADMIN_ROLE) {
        SpinStorage storage $ = _getSpinStorage();
        $.campaignStartDate = block.timestamp;
    }

    function setCampaignStartDate(
        uint256 _campaignStartDate
    ) external onlyRole(ADMIN_ROLE) {
        SpinStorage storage $ = _getSpinStorage();
        $.campaignStartDate = _campaignStartDate;
    }

    function setBaseRaffleMultiplier(
        uint256 _baseRaffleMultiplier
    ) external onlyRole(ADMIN_ROLE) {
        SpinStorage storage $ = _getSpinStorage();
        $.baseRaffleMultiplier = _baseRaffleMultiplier;
    }

    function setXPPerSpin(
        uint256 _xpPerSpin
    ) external onlyRole(ADMIN_ROLE) {
        SpinStorage storage $ = _getSpinStorage();
        $.xpPerSpin = _xpPerSpin;
    }

    function setPlumeAmounts(
        uint256[3] memory _plumeAmounts
    ) external onlyRole(ADMIN_ROLE) {
        SpinStorage storage $ = _getSpinStorage();
        $.plumeAmounts = _plumeAmounts;
    }

    function whitelist(
        address user
    ) external onlyRole(ADMIN_ROLE) {
        SpinStorage storage $ = _getSpinStorage();
        $.whitelists[user] = true;
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
