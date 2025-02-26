// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC4626.sol";
//import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

// LayerZero v2
import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroComposer.sol";
// Provided by LZ as helper to decode the compose message:
import "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/libs/OFTComposeMsgCodec.sol";

interface IPerpetualVault {
    function deposit(
        address depositAsset,
        uint256 depositAmount,
        uint256 minimumMint
    ) external returns (uint256);
}

/**
 * @title LZRouterComposer
 * @notice An upgradeable contract that implements the NEW Stargate composability approach:
 *         - Implements ILayerZeroComposer.lzCompose() rather than IStargateReceiver.sgReceive().
 *         - Receives USDC from Stargate, converts to pUSD, and deposits into a vault.
 */
contract LZRouter is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ILayerZeroComposer
{
    using SafeERC20 for IERC20;

    // LayerZero v2 endpoint
    ILayerZeroEndpointV2 public lzEndpoint;

    // For trusting calls from Stargate, store the stargate address here (set it via setStargate() if needed)
    address public stargateAddress;

    // Hardcode or store references to the addresses you need:
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;     // mainnet USDC
    address public constant pUSDTeller = 0x16424eDF021697E34b800e1D98857536B0f2287B;
    address public constant pUSD = 0xdddD73F5Df1F0DC31373357beAC77545dC5A6f3F;

    // Events
    event MessageReceived(address token, uint256 amount, bytes composeMsg, address caller);
    event DepositSucceeded(address vault, address receiver, uint256 shares);
    event DepositFailed(address vault, address receiver, string reason);
    event DebugAmount(uint256 usdcBal, uint256 mintedPusd);
    event DebugInfo(address from, address caller, bytes32 guid, uint256 messageLength);


    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializer
     */
    function initialize(address _lzEndpoint, address _stargate) public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();

        lzEndpoint = ILayerZeroEndpointV2(_lzEndpoint);
        stargateAddress = _stargate;
    }

    /**
     * @dev Required by UUPS for authorization
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @notice Sets the stargate address that calls lzCompose()
     */
    function setStargate(address _stargate) external onlyOwner {
        stargateAddress = _stargate;
    }

    /**
     * @notice Set the LZ Endpoint if needed
     */
    function setLzEndpoint(address _endpoint) external onlyOwner {
        require(_endpoint != address(0), "Invalid endpoint");
        lzEndpoint = ILayerZeroEndpointV2(_endpoint);
    }

    /**
     * @notice Implementing ILayerZeroComposer
     * Stargate will call lzCompose() after bridging tokens to this contract
     * if you used a SendParam.composeMsg + extraOptions with compose gas.
     *
     * @param _from       The address that sent the tokens (should be stargateAddress in this case)
     * @param _guid       A unique ID for the message
     * @param _message    The stargate-coded message (includes bridging info, plus your composeMsg)
     * @param _executor   The address executing the call
     * @param _extraData  Extra data if any
     */
    function testCompose(
        address _from,
        bytes32 _guid,
        bytes calldata _message,
        address _executor,
        bytes calldata _extraData
    ) external payable   {
        // 1. Security checks
        //require(msg.sender == address(lzEndpoint), "Invalid caller: must be LZ endpoint");
        //require(_from == stargateAddress, "Invalid stargate sender");
        // Optionally check _executor if needed

        // 2. Decode the bridging info from _message using OFTComposeMsgCodec
        //    - The "amountLD" is how many tokens Stargate says arrived
        //    - The "composeMsg" is your custom user data that you set in SendParam.composeMsg
        uint256 amountLD = OFTComposeMsgCodec.amountLD(_message);
        // If you're bridging an OFT, you can also get the token address with OFTComposeMsgCodec.token(_message)
        // But for native Stargate USDC pool bridging, it's typically minted or credited to this contract's balance.
        // We rely on the actual USDC balance.  For demonstration, let's just read the contract's USDC balance.

        bytes memory composeMsg = OFTComposeMsgCodec.composeMsg(_message);

        // 3. Your application data inside "composeMsg"
        //    We assume you used: abi.encode(vaultContract, receiver) on the source
        //    so let's decode them:
        (address vaultContract, address receiver) = abi.decode(composeMsg, (address, address));
        emit MessageReceived(USDC, amountLD, composeMsg, msg.sender);

        // 4. Now, do the same logic you did in sgReceive: deposit USDC -> pUSD, then deposit pUSD -> vault
        uint256 usdcBal = IERC20(USDC).balanceOf(address(this));
        require(usdcBal >= amountLD, "Not enough USDC in contract");

        // Approve USDC for the perpetual vault
        IERC20(USDC).forceApprove(pUSDTeller, 0); // reset to avoid issues
        IERC20(USDC).forceApprove(pUSDTeller, usdcBal);

        // Step A: USDC -> pUSD
        uint256 pUSDAmount = IPerpetualVault(pUSDTeller).deposit(
            USDC,
            usdcBal,
            usdcBal // minimumMint = deposit amount
        );
        require(pUSDAmount > 0, "pUSD deposit failed");

        emit DebugAmount(usdcBal, pUSDAmount);

        // Step B: pUSD -> nRWA (the vaultContract is an IERC4626)
        IERC20(pUSD).forceApprove(vaultContract, 0);
        IERC20(pUSD).forceApprove(vaultContract, pUSDAmount);

        try IERC4626(vaultContract).deposit(pUSDAmount, receiver) returns (uint256 shares) {
            require(shares > 0, "No shares minted");
            emit DepositSucceeded(vaultContract, receiver, shares);
        } catch Error(string memory reason) {
            // If it fails, fallback: send pUSD to user instead
            IERC20(pUSD).safeTransfer(receiver, pUSDAmount);
            emit DepositFailed(vaultContract, receiver, reason);
        }
    }

function lzCompose(
    address _from,
    bytes32 _guid,
    bytes calldata _message,
    address _executor,
    bytes calldata _extraData
) external payable override {
    // Debug logs
    emit DebugInfo(_from, msg.sender, _guid, _message.length);
    
    // No security checks for testing
    
    // Rest of your code...
}



    /**
     * @notice Just in case you need to recover tokens
     */
    function recoverERC20(address _token, address _to, uint256 _amount) external onlyOwner {
        IERC20(_token).safeTransfer(_to, _amount);
    }
}
