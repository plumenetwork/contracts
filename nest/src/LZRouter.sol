// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/interfaces/IERC4626Upgradeable.sol";
import "@layerzerolabs/solidity-examples/contracts/interfaces/ILayerZeroEndpoint.sol";
import "@layerzerolabs/solidity-examples/contracts/interfaces/ILayerZeroReceiver.sol";

/**
 * @title BridgeReceiver
 * @dev Upgradeable contract that receives tokens from LayerZero bridge and calls deposit on a vault
 */
contract LZRouter is Initializable, UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable, ILayerZeroReceiver {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    
    // LayerZero endpoint for cross-chain communication
    address public lzEndpoint;
    
    // Mapping of trusted source chains and source addresses
    mapping(uint16 => mapping(bytes => bool)) public trustedRemotes;
    
    // Events
    event ReceiveFromChain(uint16 srcChainId, address sender, address vaultContract, address receiver, uint256 amount);
    event TrustedRemoteAdded(uint16 srcChainId, bytes srcAddress);
    event TrustedRemoteRemoved(uint16 srcChainId, bytes srcAddress);
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    
    /**
     * @dev Initialize the contract with LayerZero endpoint
     * @param _lzEndpoint Address of the LayerZero endpoint
     */
    function initialize(address _lzEndpoint) public initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        
        lzEndpoint = _lzEndpoint;
    }
    
    /**
     * @dev LayerZero receive function called when a message arrives from another chain
     * @param _srcChainId Source chain ID
     * @param _srcAddress Source address on source chain
     * @param _nonce Message nonce
     * @param _payload Message payload (contains deposit parameters)
     */
    function lzReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64 _nonce,
        bytes memory _payload
    ) external override nonReentrant {
        // Verify that the message is from a trusted source
        require(msg.sender == lzEndpoint, "BridgeReceiver: invalid endpoint caller");
        require(trustedRemotes[_srcChainId][_srcAddress], "BridgeReceiver: source not trusted");
        
        // Decode payload to extract vault address and receiver
        (address vaultContract, address receiver) = abi.decode(_payload, (address, address));
        
        // Ensure addresses are valid
        require(vaultContract != address(0), "BridgeReceiver: invalid vault contract");
        require(receiver != address(0), "BridgeReceiver: invalid receiver");
        
        // Get the token associated with the vault
        address token = IERC4626Upgradeable(vaultContract).asset();
        
        // Get balance of tokens received (should have been sent directly to this contract)
        uint256 amount = IERC20Upgradeable(token).balanceOf(address(this));
        require(amount > 0, "BridgeReceiver: no tokens received");
        
        // Approve the vault to spend tokens
        IERC20Upgradeable(token).safeApprove(vaultContract, amount);
        
        // Deposit tokens and mint shares to the receiver
        uint256 shares = IERC4626Upgradeable(vaultContract).deposit(amount, receiver);
        emit ReceiveFromChain(_srcChainId, _srcAddress.toAddress(0), vaultContract, receiver, amount);
    }
    
    /**
     * @dev Helper function to convert bytes to address
     * @param _bytes Bytes to convert
     * @param _start Start position
     * @return addr Converted address
     */
    function toAddress(bytes memory _bytes, uint256 _start) internal pure returns (address addr) {
        require(_bytes.length >= _start + 20, "BridgeReceiver: invalid address conversion");
        assembly {
            addr := mload(add(add(_bytes, 20), _start))
        }
    }
    
    /**
     * @dev Add a trusted remote source
     * @param _srcChainId Source chain ID
     * @param _srcAddress Source address bytes
     */
    function addTrustedRemote(uint16 _srcChainId, bytes calldata _srcAddress) external onlyOwner {
        trustedRemotes[_srcChainId][_srcAddress] = true;
        emit TrustedRemoteAdded(_srcChainId, _srcAddress);
    }
    
    /**
     * @dev Remove a trusted remote source
     * @param _srcChainId Source chain ID
     * @param _srcAddress Source address bytes
     */
    function removeTrustedRemote(uint16 _srcChainId, bytes calldata _srcAddress) external onlyOwner {
        trustedRemotes[_srcChainId][_srcAddress] = false;
        emit TrustedRemoteRemoved(_srcChainId, _srcAddress);
    }
    
    /**
     * @dev Function to recover any ERC20 tokens accidentally sent to contract
     * @param _token Token address
     * @param _to Recipient address
     * @param _amount Amount to recover
     */
    function recoverERC20(address _token, address _to, uint256 _amount) external onlyOwner {
        IERC20Upgradeable(_token).safeTransfer(_to, _amount);
    }
    
    /**
     * @dev Required function for UUPS upgradeable contracts
     * @param newImplementation The new implementation address
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}