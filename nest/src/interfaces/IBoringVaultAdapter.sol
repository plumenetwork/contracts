// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

interface IBoringVaultAdapter {

    // LayerZero functions
    function setTrustedRemote(uint16 _remoteChainId, bytes calldata _path) external;
    function getTrustedRemote(
        uint16 _remoteChainId
    ) external view returns (bytes memory);
    function setMinDstGas(uint16 _dstChainId, uint16 _packetType, uint256 _minGas) external;
    function setConfig(uint16 _version, uint16 _chainId, uint256 _configType, bytes calldata _config) external;
    function setSendVersion(
        uint16 _version
    ) external;
    function setReceiveVersion(
        uint16 _version
    ) external;
    function forceResumeReceive(uint16 _srcChainId, bytes calldata _srcAddress) external;

    // OFT functions
    function sendFrom(
        address _from,
        uint16 _dstChainId,
        bytes32 _toAddress,
        uint256 _amount,
        address payable _refundAddress,
        bytes calldata _payload
    ) external payable;

    // View Functions
    function getVault() external view returns (address);
    function getTeller() external view returns (address);
    function getAtomicQueue() external view returns (address);
    function version() external view returns (uint256);

    // Core Functions
    function deposit(
        uint256 assets,
        address receiver,
        address controller,
        uint256 minimumMint
    ) external returns (uint256 shares);

    function requestRedeem(
        uint256 shares,
        address receiver,
        address controller,
        uint256 price,
        uint64 deadline
    ) external returns (uint256);

    function notifyRedeem(uint256 assets, uint256 shares, address controller) external;

    function redeem(uint256 shares, address receiver, address controller) external returns (uint256 assets);

    // Preview Functions
    function previewDeposit(
        uint256 assets
    ) external view returns (uint256);
    function previewRedeem(
        uint256 shares
    ) external view returns (uint256 assets);
    function convertToShares(
        uint256 assets
    ) external view returns (uint256 shares);
    function convertToAssets(
        uint256 shares
    ) external view returns (uint256 assets);

    // Balance Functions
    function balanceOf(
        address account
    ) external view returns (uint256);
    function assetsOf(
        address account
    ) external view returns (uint256);

    // Events
    event VaultChanged(address oldVault, address newVault);
    event Reinitialized(uint256 version);

    // LZ Events
    event SetTrustedRemote(uint16 _remoteChainId, bytes _path);
    event SetMinDstGas(uint16 _dstChainId, uint16 _packetType, uint256 _minGas);

}
