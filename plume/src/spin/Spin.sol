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
    struct UserRewards {
        uint256 jackpotWins;
        uint256 raffleTickets;
        uint256 xpGained;
        uint256 plumeTokens;
        uint256 lastJackpotClaim;
        uint256 streakCount;
    }

    /// @custom:storage-location erc7201:plume.storage.Spin
    struct SpinStorage {
        /// @dev Address of the admin managing the Spin contract
        address admin;
        /// @dev Cooldown period between spins (in seconds)
        uint256 cooldownPeriod;
        /// @dev Mapping of wallet address to rewards
        mapping(address => UserRewards) userRewards;
        /// @dev Timestamp of start time of Spin Game
        uint256 startTimestamp;
        /// @dev Mapping of wallet address to the last spin date (timestamp)
        mapping(address => uint256) lastSpinDate;
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
    /// @notice Revert if the callback is unauthorized
    error UnauthorizedCallback();
    /// @notice Revert if the nonce is invalid
    error InvalidNonce();

    // Modifiers

    /// @notice Ensures that the user can only spin once per day by checking their last spin date.
    ///      This modifier retrieves the last recorded spin date from storage, compares it with
    ///      the current date using the `isSameDay` function, and reverts if the user has already spun today.
    modifier canSpin() {
        SpinStorage storage $ = _getSpinStorage();
        IDateTime dateTime = $.dateTime;

        // Retrieve last spin date components
        (uint16 lastSpinYear, uint8 lastSpinMonth, uint8 lastSpinDay) = (
            dateTime.getYear($.lastSpinDate[msg.sender]),
            dateTime.getMonth($.lastSpinDate[msg.sender]),
            dateTime.getDay($.lastSpinDate[msg.sender])
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
     * @param _cooldownPeriod The cooldown period between spins in seconds.
     */
    function initialize(
        address supraRouterAddress,
        address dateTimeAddress,
        uint256 _cooldownPeriod
    ) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __Pausable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);

        SpinStorage storage $ = _getSpinStorage();
        $.supraRouter = ISupraRouterContract(supraRouterAddress);
        $.dateTime = IDateTime(dateTimeAddress);
        $.cooldownPeriod = _cooldownPeriod;
        $.admin = msg.sender;
        $.startTimestamp = block.timestamp;

        $.jackpotProbabilities = [5, 10, 15, 25, 35, 50, 65];
        $.jackpotPrizes[1] = 5000;
        $.jackpotPrizes[2] = 5000;
        $.jackpotPrizes[3] = 10000;
        $.jackpotPrizes[4] = 10000;
        $.jackpotPrizes[5] = 20000;
        $.jackpotPrizes[6] = 20000;
        $.jackpotPrizes[7] = 30000;
        $.jackpotPrizes[8] = 30000;
        $.jackpotPrizes[9] = 40000;
        $.jackpotPrizes[10] = 40000;
        $.jackpotPrizes[11] = 50000;
        $.jackpotPrizes[12] = 100000;

        $.baseRaffleMultiplier = 100;
        $.xpPerSpin = 100;
        $.plumeAmounts = [2, 5, 10];
    }

    /// @notice Starts the spin process by generating a random number and recording the spin date.
    /// @dev This function is called by the user to initiate a spin.
    function startSpin() external whenNotPaused canSpin {
        SpinStorage storage $ = _getSpinStorage();
        string memory callbackSignature = "handleRandomness(uint256,uint256[])";
        uint8 rngCount = 1;
        uint256 numConfirmations = 1;
        uint256 clientSeed = uint256(keccak256(abi.encodePacked($.admin, block.timestamp)));

        uint256 nonce =
            $.supraRouter.generateRequest(callbackSignature, rngCount, numConfirmations, clientSeed, $.admin);
        $.lastSpinDate[msg.sender] = block.timestamp;
        $.userNonce[nonce] = msg.sender;

        emit SpinRequested(nonce, msg.sender);
    }

    /**
     * @notice Handles the randomness callback from the Supra Router.
     * @dev This function is called by the Supra Router to provide the random number and determine the reward.
     * @param nonce The nonce associated with the spin request.
     * @param rngList The list of random numbers generated.
     */
    function handleRandomness(uint256 nonce, uint256[] memory rngList) external {
        console.log("handleRandomness CALLED");
        SpinStorage storage $ = _getSpinStorage();
        if (msg.sender != address($.supraRouter)) {
            revert UnauthorizedCallback();
        }

        address user = $.userNonce[nonce];
        if (user == address(0)) {
            revert InvalidNonce();
        }

        uint256 randomness = rngList[0]; // Use full VRF range
        (string memory rewardCategory, uint256 rewardAmount) = determineReward(randomness);

        // Apply reward logic
        UserRewards storage userData = $.userRewards[user];

        if (keccak256(abi.encodePacked(rewardCategory)) == keccak256(abi.encodePacked("Jackpot"))) {
            require(block.timestamp >= userData.lastJackpotClaim + 7 days, "Jackpot cooldown active");
            require(
                userData.streakCount >= (block.timestamp - $.campaignStartDate) / 7 days + 2,
                "Not enough streak for jackpot"
            );

            userData.jackpotWins++;
            userData.lastJackpotClaim = block.timestamp;
        } else if (keccak256(abi.encodePacked(rewardCategory)) == keccak256(abi.encodePacked("Raffle Ticket"))) {
            userData.raffleTickets += rewardAmount;
        } else if (keccak256(abi.encodePacked(rewardCategory)) == keccak256(abi.encodePacked("XP"))) {
            userData.xpGained += rewardAmount;
        } else if (keccak256(abi.encodePacked(rewardCategory)) == keccak256(abi.encodePacked("Plume Token"))) {
            userData.plumeTokens += rewardAmount;
        }
        userData.streakCount++;

        emit SpinCompleted(user, rewardCategory, rewardAmount);
    }

    /**
     * @notice Determines the reward category based on the VRF random number.
     * @param randomness The random number generated by the Supra Router.
     */
    function determineReward(
        uint256 randomness
    ) internal view returns (string memory, uint256) {
        SpinStorage storage $ = _getSpinStorage();
        uint256 probability = randomness % 1_000_000; // Normalize VRF range to 1M

        // Determine the current week in the 12-week campaign
        uint256 daysSinceStart = (block.timestamp - $.campaignStartDate) / 1 days;
        uint8 weekNumber = uint8(daysSinceStart / 7);
        if (weekNumber > 11) {
            // TODO: Handle Default case
            return ("Nothing", 0);
        }

        uint256 jackpotThreshold = (1_000_000 * $.jackpotProbabilities[weekNumber]) / 100;
        console.logUint(probability);

        if (probability < jackpotThreshold) {
            return ("Jackpot", $.jackpotPrizes[weekNumber]);
        }
        uint256 rewardCategory = probability % 4;
        if (rewardCategory == 0) {
            return ("Raffle Ticket", $.baseRaffleMultiplier * $.userRewards[msg.sender].streakCount);
        } else if (rewardCategory == 1) {
            return ("XP", $.xpPerSpin);
        } else if (rewardCategory == 2) {
            uint256 plumeAmount = $.plumeAmounts[probability % 3];
            return ("Plume Token", plumeAmount);
        }

        return ("Nothing", 0); // Default case
    }

    function updateRaffleTickets(address user, uint256 ticketsUsed) external onlyRaffleContract {
        SpinStorage storage $ = _getSpinStorage();
        require($.userRewards[user].raffleTickets >= ticketsUsed, "Not enough raffle tickets");

        $.userRewards[user].raffleTickets -= ticketsUsed;

        emit RaffleTicketsUpdated(user, ticketsUsed, $.userRewards[user].raffleTickets);
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

    // View Functions
    /**
     * @notice Gets the awards for a user.
     * @param walletAddress The address of the wallet.
     */
    function getUserRewards(
        address walletAddress
    )
        external
        view
        returns (
            uint256 dailyStreak,
            uint256 jackpotWins,
            uint256 raffleTickets,
            uint256 xpGained,
            uint256 smallPlumeTokens,
            uint256 lastJackpotClaim
        )
    {
        SpinStorage storage $ = _getSpinStorage();
        UserRewards storage userData = $.userRewards[walletAddress];

        return (
            userData.streakCount,
            userData.jackpotWins,
            userData.raffleTickets,
            userData.xpGained,
            userData.plumeTokens,
            userData.lastJackpotClaim
        );
    }

    function setJackpotProbabilities(
        uint8[7] memory _jackpotProbabilities
    ) external onlyRole(ADMIN_ROLE) {
        SpinStorage storage $ = _getSpinStorage();
        $.jackpotProbabilities = _jackpotProbabilities;
    }

    function setJackpotPrizes(
        uint8 week,
        uint256 prize
    ) external onlyRole(ADMIN_ROLE) {
        SpinStorage storage $ = _getSpinStorage();
        $.jackpotPrizes[week] = prize;
    }

    function setCampaignStartDate(
        uint256 _campaignStartDate
    ) external onlyRole(ADMIN_ROLE) {
        SpinStorage storage $ = _getSpinStorage();
        $.campaignStartDate = _campaignStartDate;
    }

    function setCoooldownPeriod(
        uint256 _cooldownPeriod
    ) external onlyRole(ADMIN_ROLE) {
        SpinStorage storage $ = _getSpinStorage();
        $.cooldownPeriod = _cooldownPeriod;
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

    // UUPS Authorization
    /**
     * @notice Authorizes the upgrade of the contract.
     * @param newImplementation The address of the new implementation.
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(ADMIN_ROLE) { }

}
