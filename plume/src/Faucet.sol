// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.25;

// import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
// import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
// import { IERC20Metadata } from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
// import { ERC20Pausable } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
// import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
// import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

// /**
//  * @title Faucet
//  * @author Eugene Y. Q. Shen
//  * @notice Contract that mints tokens to users that submit a signed message from the owner
//  */
// contract Faucet is Initializable, UUPSUpgradeable {

//     using ECDSA for bytes32;
//     using MessageHashUtils for bytes32;

//     // Storage

//     /// @custom:storage-location erc7201:plume.storage.Faucet
//     struct FaucetStorage {
//         /// @dev Address of the owner of the Faucet
//         address owner;
//         /// @dev Amount of tokens to mint to each user per faucet call
//         mapping(address tokenAddress => uint256 dripAmount) dripAmounts;
//         /// @dev Mapping of token names to their addresses, or to 0x1 for ETH
//         mapping(string tokenName => address tokenAddress) tokens;
//         /// @dev True if the nonce has been used; false otherwise
//         mapping(bytes32 nonce => bool used) usedNonces;
//     }

//     // keccak256(abi.encode(uint256(keccak256("plume.storage.Faucet")) - 1)) & ~bytes32(uint256(0xff))
//     bytes32 private constant FAUCET_STORAGE_LOCATION =
//         0xba213a20809c9d49f5b31f993c1d71bca94443a1b2f0e23907f4ad1f30c71500;

//     function _getFaucetStorage() internal pure returns (FaucetStorage storage $) {
//         assembly {
//             $.slot := FAUCET_STORAGE_LOCATION
//         }
//     }

//     // Constants

//     /// @notice Magic constant to represent the address of the gas token on Plume
//     address public constant ETH_ADDRESS = address(1);

//     // Events

//     /**
//      * @notice Emitted when the recipient has received tokens from the faucet
//      * @param recipient Address of the recipient
//      * @param amount Amount of tokens received
//      * @param tokenAddress Address of the token received
//      */
//     event TokenSent(address indexed recipient, uint256 amount, address tokenAddress);

//     /**
//      * @notice Emitted when the owner withdraws tokens from the faucet
//      * @param recipient Address of the recipient
//      * @param amount Amount of tokens received
//      * @param token Name of the token received
//      */
//     event Withdrawn(address indexed recipient, uint256 amount, string token);

//     /**
//      * @notice Emitted when the owner of the faucet changes
//      * @param oldOwner Address of the old owner
//      * @param newOwner Address of the new owner
//      */
//     event OwnerChanged(address indexed oldOwner, address indexed newOwner);

//     // Errors

//     /// @notice Indicates a failure because the requested token is not supported
//     error InvalidToken();

//     /// @notice Indicates a failure because the hashed signed message has already been used
//     error InvalidNonce();

//     /// @notice Indicates a failure because the signature is invalid
//     error InvalidSignature();

//     /// @notice Indicates a failure because the address is invalid
//     error InvalidAddress();

//     /// @notice Indicates a failure because the flightClass is invalid
//     error InvalidFlightClass(uint256 flightClass);

//     /**
//      * @notice Indicates a failure because the sender is not authorized to perform the action
//      * @param sender Address of the sender that is not authorized
//      * @param authorizedUser Address of the authorized user who can perform the action
//      */
//     error Unauthorized(address sender, address authorizedUser);

//     /**
//      * @notice Indicates a failure because the faucet does not have enough tokens
//      * @param amount Amount of tokens requested
//      * @param token Name of the token requested
//      */
//     error InsufficientBalance(uint256 amount, string token);

//     /**
//      * @notice Indicates a failure because the transfer failed
//      * @param amount Amount of tokens requested
//      * @param tokenAddress Address of the token requested
//      */
//     error TransferFailed(uint256 amount, address tokenAddress);

//     // Modifiers

//     /// @notice Only the owner can call this function
//     modifier onlyOwner() {
//         if (msg.sender != _getFaucetStorage().owner) {
//             revert Unauthorized(msg.sender, _getFaucetStorage().owner);
//         }
//         _;
//     }

//     /// @notice Must pass in a message signed by the owner to call this function
//     modifier onlySignedByOwner(string calldata token, uint256 flightClass, bytes32 salt, bytes calldata signature) {
//         FaucetStorage storage $ = _getFaucetStorage();
//         bytes32 message = keccak256(abi.encodePacked(msg.sender, token, flightClass, salt));

//         if ($.usedNonces[message]) {
//             revert InvalidNonce();
//         }
//         if (message.toEthSignedMessageHash().recover(signature) != $.owner) {
//             revert InvalidSignature();
//         }

//         $.usedNonces[message] = true;
//         _;
//     }

//     // Initializer

//     /**
//      * @notice Prevent the implementation contract from being initialized or reinitialized
//      * @custom:oz-upgrades-unsafe-allow constructor
//      */
//     constructor() {
//         _disableInitializers();
//     }

//     /**
//      * @notice Initialize the Faucet
//      * @param owner Address of the owner of the Faucet
//      * @param tokens Names of the tokens to add to the faucet
//      * @param tokenAddresses Addresses of the tokens to add to the faucet
//      */
//     function initialize(address owner, string[] memory tokens, address[] memory tokenAddresses) public initializer {
//         if (owner == address(0) || tokens.length == 0 || tokens.length != tokenAddresses.length) {
//             revert InvalidInitialization();
//         }

//         __UUPSUpgradeable_init();

//         FaucetStorage storage $ = _getFaucetStorage();
//         $.owner = owner;

//         bytes32 ethHash = keccak256(abi.encodePacked("ETH"));
//         uint256 length = tokens.length;
//         for (uint256 i = 0; i < length; ++i) {
//             if (keccak256(bytes(tokens[i])) == ethHash) {
//                 $.tokens[tokens[i]] = ETH_ADDRESS;
//                 $.dripAmounts[ETH_ADDRESS] = 0.001 ether;
//             } else {
//                 $.tokens[tokens[i]] = tokenAddresses[i];
//                 $.dripAmounts[tokenAddresses[i]] = 1e9; // $1000 USDT (6 decimals)
//             }
//         }
//     }

//     // Override Functions

//     /**
//      * @notice Revert when `msg.sender` is not authorized to upgrade the contract
//      * @param newImplementation Address of the new implementation
//      */
//     function _authorizeUpgrade(
//         address newImplementation
//     ) internal override(UUPSUpgradeable) onlyOwner { }

//     // User Functions

//     /**
//      * @notice Get tokens from the faucet
//      * @param token Name of the token requested
//      * @param flightClass User's flight class
//      * @param salt Random value to prevent replay attacks
//      * @param signature Signature of the message signed by the owner
//      */
//     function getToken(
//         string calldata token,
//         uint256 flightClass,
//         bytes32 salt,
//         bytes calldata signature
//     ) external onlySignedByOwner(token, flightClass, salt, signature) {
//         FaucetStorage storage $ = _getFaucetStorage();
//         address tokenAddress = $.tokens[token];
//         uint256 baseAmount = $.dripAmounts[tokenAddress];

//         if (tokenAddress == address(0) || baseAmount == 0) {
//             revert InvalidToken();
//         }

//         uint256 amount = _calculateDripAmount(baseAmount, flightClass);

//         if (tokenAddress == ETH_ADDRESS) {
//             if (address(this).balance < amount) {
//                 revert InsufficientBalance(amount, token);
//             }
//             (bool success,) = msg.sender.call{ value: amount, gas: 2300 }("");
//             if (!success) {
//                 revert TransferFailed(amount, tokenAddress);
//             }
//         } else {
//             if (!IERC20Metadata(tokenAddress).transfer(msg.sender, amount)) {
//                 revert TransferFailed(amount, tokenAddress);
//             }
//         }

//         emit TokenSent(msg.sender, amount, tokenAddress);
//     }

//     // Admin Functions

//     /**
//      * @notice Withdraw tokens from the faucet
//      * @dev Only the owner can call this function
//      * @param token Name of the token to withdraw
//      * @param amount Amount of tokens to withdraw
//      * @param recipient Address to receive the tokens
//      */
//     function withdrawToken(string calldata token, uint256 amount, address payable recipient) external onlyOwner {
//         FaucetStorage storage $ = _getFaucetStorage();
//         address tokenAddress = $.tokens[token];
//         if (tokenAddress == address(0) || amount == 0) {
//             revert InvalidToken();
//         }

//         if (tokenAddress == ETH_ADDRESS) {
//             if (address(this).balance < amount) {
//                 revert InsufficientBalance(amount, token);
//             }
//             (bool success,) = recipient.call{ value: amount, gas: 2300 }("");
//             if (!success) {
//                 revert TransferFailed(amount, tokenAddress);
//             }
//         } else {
//             if (!IERC20Metadata(tokenAddress).transfer(recipient, amount)) {
//                 revert TransferFailed(amount, tokenAddress);
//             }
//         }

//         emit Withdrawn(recipient, amount, token);
//     }

//     /**
//      * @notice Calculate the amount of tokens to mint based on the base amount and flight class
//      * @dev Internal function to calculate the drip amount based on the flight class multiplier
//      *      Flight classes correspond to:
//      *        - Class 1: Economy
//      *        - Class 2: Plus
//      *        - Class 3: Premium
//      *        - Class 4: Business
//      *        - Class 5: First
//      *        - Class 6: Private
//      * @param baseAmount Base amount of tokens to mint
//      * @param flightClass User flight class
//      */
//     function _calculateDripAmount(uint256 baseAmount, uint256 flightClass) internal pure returns (uint256) {
//         uint256 multiplier;
//         if (flightClass == 1) {
//             multiplier = 1; // 1x
//         } else if (flightClass == 2) {
//             multiplier = 11; // 1.1x (scaled by 10)
//         } else if (flightClass == 3) {
//             multiplier = 125; // 1.25x (scaled by 100)
//         } else if (flightClass == 4) {
//             multiplier = 200; // 2x (scaled by 100)
//         } else if (flightClass == 5) {
//             multiplier = 300; // 3x (scaled by 100)
//         } else if (flightClass == 6) {
//             multiplier = 500; // 5x (scaled by 100)
//         } else {
//             revert InvalidFlightClass(flightClass);
//         }

//         return (baseAmount * multiplier) / 100; // Normalize for scaling
//     }

//     /**
//      * @notice Set ownership of the faucet contract to the given address
//      * @dev Only the owner can call this function
//      * @param newOwner New owner of the faucet
//      */
//     function setOwner(
//         address newOwner
//     ) external onlyOwner {
//         FaucetStorage storage $ = _getFaucetStorage();
//         if (newOwner == address(0)) {
//             revert InvalidAddress();
//         }

//         emit OwnerChanged($.owner, newOwner);
//         $.owner = newOwner;
//     }

//     /**
//      * @notice Set the amount of tokens to mint per faucet call
//      * @dev Only the owner can call this function
//      * @param token Name of the token to set the amount for
//      * @param amount Amount of tokens to mint per faucet call
//      */
//     function setDripAmount(string calldata token, uint256 amount) external onlyOwner {
//         FaucetStorage storage $ = _getFaucetStorage();
//         $.dripAmounts[$.tokens[token]] = amount;
//     }

//     /**
//      * @notice Add a new supported token to the faucet
//      * @dev Only the owner can call this function
//      * @param token Name of the token to add
//      * @param tokenAddress Address of the token to add
//      * @param amount Amount of tokens to mint per faucet call
//      */
//     function addToken(string calldata token, address tokenAddress, uint256 amount) external onlyOwner {
//         FaucetStorage storage $ = _getFaucetStorage();
//         $.tokens[token] = tokenAddress;
//         $.dripAmounts[tokenAddress] = amount;
//     }

//     // Getter View Functions

//     /// @notice Get the owner of the faucet
//     function getOwner() public view returns (address) {
//         return _getFaucetStorage().owner;
//     }

//     /**
//      * @notice Get the base amount of tokens to mint per faucet call for the given token
//      * @param token Name of the token to get the amount for
//      * @return dripAmount Base amount of tokens to mint per faucet call
//      */
//     function getDripAmount(
//         string calldata token
//     ) public view returns (uint256 dripAmount) {
//         FaucetStorage storage $ = _getFaucetStorage();
//         return $.dripAmounts[$.tokens[token]];
//     }

//     /**
//      * @notice Get the amount of tokens to mint per user call for the given token
//      * @param token Name of the token to get the amount for
//      * @param flightClass User's flight class
//      * @return dripAmount Amount of tokens to mint per faucet call
//      */
//     function getDripAmount(string calldata token, uint256 flightClass) public view returns (uint256 dripAmount) {
//         FaucetStorage storage $ = _getFaucetStorage();
//         address tokenAddress = $.tokens[token];
//         uint256 baseAmount = $.dripAmounts[tokenAddress];

//         if (tokenAddress == address(0) || baseAmount == 0) {
//             revert InvalidToken();
//         }

//         return _calculateDripAmount(baseAmount, flightClass);
//     }

//     /**
//      * @notice Get the address of the given token
//      * @param token Name of the token to get the address for
//      * @return tokenAddress Address of the token
//      */
//     function getTokenAddress(
//         string calldata token
//     ) public view returns (address tokenAddress) {
//         return _getFaucetStorage().tokens[token];
//     }

//     /**
//      * @notice Check if the given nonce has been used
//      * @param nonce Nonce to check
//      * @return used True if the nonce has been used; false otherwise
//      */
//     function isNonceUsed(
//         bytes32 nonce
//     ) public view returns (bool used) {
//         return _getFaucetStorage().usedNonces[nonce];
//     }

//     // Fallback Functions

//     receive() external payable { }

// }
