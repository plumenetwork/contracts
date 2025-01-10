// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import "../interfaces/IDateTime.sol";
import "../interfaces/ISupraRouterContract.sol";

/// @custom:oz-upgrades-from Spin
contract Spin is Initializable, AccessControlUpgradeable, UUPSUpgradeable, PausableUpgradeable {

    // Storage

    /// @custom:storage-location erc7201:plume.storage.Spin
    struct SpinStorage {
        /// @dev Address of the admin managing the Spin contract
        address admin;
        /// @dev Cooldown period between spins (in seconds)
        uint256 cooldownPeriod;
        /// @dev Mapping of wallet address to feathers gained
        mapping(address => uint256) feathersGained;
        /// @dev Mapping of wallet address to current daily streak
        mapping(address => uint256) dailyStreak;
        /// @dev Mapping of wallet address to the last spin date (timestamp)
        mapping(address => uint256) lastSpinDate;
        /// @dev Mapping of probabilities to rewards
        mapping(uint256 => uint256) probabilitiesToRewards;
        /// @dev Reference to the Supra VRF interface
        ISupraRouterContract supraRouter;
        /// @dev Reference to the DateTime contract
        IDateTime dateTime;
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
    event SpinRequested(uint256 indexed nonce, address indexed user);
    event SpinCompleted(address indexed walletAddress, uint256 feathersGained);

    // Modifiers
    modifier onlyAdmin() {
        require(hasRole(ADMIN_ROLE, msg.sender), "Caller is not an admin");
        _;
    }

    modifier canSpin() {
        SpinStorage storage s = _getSpinStorage();
        IDateTime dateTime = s.dateTime;

        uint16 lastSpinYear = dateTime.getYear(s.lastSpinDate[msg.sender]);
        uint8 lastSpinMonth = dateTime.getMonth(s.lastSpinDate[msg.sender]);
        uint8 lastSpinDay = dateTime.getDay(s.lastSpinDate[msg.sender]);

        uint16 currentYear = dateTime.getYear(block.timestamp);
        uint8 currentMonth = dateTime.getMonth(block.timestamp);
        uint8 currentDay = dateTime.getDay(block.timestamp);

        require(
            !isSameDay(lastSpinYear, lastSpinMonth, lastSpinDay, currentYear, currentMonth, currentDay),
            "Can only spin once per day"
        );
        _;
    }

    // Initializer
    function initialize(address supraRouterAddress, address dateTimeAddress, uint256 _cooldownPeriod) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __Pausable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);

        SpinStorage storage s = _getSpinStorage();
        s.supraRouter = ISupraRouterContract(supraRouterAddress);
        s.dateTime = IDateTime(dateTimeAddress);
        s.cooldownPeriod = _cooldownPeriod;
        s.admin = msg.sender;
    }

    function startSpin() external whenNotPaused canSpin {
        SpinStorage storage s = _getSpinStorage();
        string memory callbackSignature = "handleRandomness(uint256,uint256[])";
        uint8 rngCount = 1; 
        uint256 numConfirmations = 1; 
        uint256 clientSeed = uint256(keccak256(abi.encodePacked(msg.sender, block.timestamp)));

        uint256 nonce = s.supraRouter.generateRequest(callbackSignature, rngCount, numConfirmations, clientSeed, address(this));
        s.lastSpinDate[msg.sender] = block.timestamp;

        emit SpinRequested(nonce, msg.sender);
    }

    function handleRandomness(uint256 nonce, uint256[] memory rngList) external {
        SpinStorage storage s = _getSpinStorage();
        require(msg.sender == address(s.supraRouter), "Unauthorized callback");

        uint256 vrfValue = rngList[0]; 
        uint256 reward = determineReward(vrfValue);

        if (reward > 0) {
            s.feathersGained[msg.sender] += reward;
            s.dailyStreak[msg.sender] += 1;
        } else {
            s.dailyStreak[msg.sender] = 0; 
        }

        emit SpinCompleted(msg.sender, reward);
    }

    function determineReward(uint256 randomness) internal view returns (uint256) {
        SpinStorage storage s = _getSpinStorage();
        uint256 probability = randomness % 100; // Probabilities are 0-99
        return s.probabilitiesToRewards[probability];
    }

    // Utility Functions
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
    function getStreakAndFeathers(address walletAddress) external view returns (uint256 streak, uint256 feathers) {
        SpinStorage storage s = _getSpinStorage();
        return (s.dailyStreak[walletAddress], s.feathersGained[walletAddress]);
    }

    // UUPS Authorization
    function _authorizeUpgrade(address newImplementation) internal override onlyAdmin {}
}
