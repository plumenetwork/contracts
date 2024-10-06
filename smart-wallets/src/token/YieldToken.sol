// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { WalletUtils } from "../WalletUtils.sol";
import { IAssetToken } from "../interfaces/IAssetToken.sol";
import { ISmartWallet } from "../interfaces/ISmartWallet.sol";
import { IYieldDistributionToken } from "../interfaces/IYieldDistributionToken.sol";
import { IYieldToken } from "../interfaces/IYieldToken.sol";
import { YieldDistributionToken } from "./YieldDistributionToken.sol";

/**
 * @title YieldToken
 * @author Eugene Y. Q. Shen
 * @notice ERC20 token that receives yield redistributions from an AssetToken
 */
contract YieldToken is YieldDistributionToken, WalletUtils, IYieldToken {

    // Storage

    /// @custom:storage-location erc7201:plume.storage.YieldToken
    struct YieldTokenStorage {
        /// @dev AssetToken that redistributes yield to the YieldToken
        IAssetToken assetToken;
    }

    // keccak256(abi.encode(uint256(keccak256("plume.storage.YieldToken")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant YIELD_TOKEN_STORAGE_LOCATION =
        0xe0df32b9dab2596a95926c5b17cc961f10a49277c3685726d2657c9ac0b50e00;

    function _getYieldTokenStorage() private pure returns (YieldTokenStorage storage $) {
        assembly {
            $.slot := YIELD_TOKEN_STORAGE_LOCATION
        }
    }

    // Constants

    // Base that is used to divide all price inputs in order to represent e.g. 1.000001 as 1000001e12
    uint256 private constant _BASE = 1e18;

    // Errors

    /**
     * @notice Indicates a failure because the given CurrencyToken does not match the actual CurrencyToken
     * @param invalidCurrencyToken CurrencyToken that does not match the actual CurrencyToken
     * @param currencyToken Actual CurrencyToken used to mint and burn the AggregateToken
     */
    error InvalidCurrencyToken(IERC20 invalidCurrencyToken, IERC20 currencyToken);

    /**
     * @notice Indicates a failure because the given AssetToken does not match the actual AssetToken
     * @param invalidAssetToken AssetToken that does not match the actual AssetToken
     * @param assetToken Actual AssetToken that redistributes yield to the YieldToken
     */
    error InvalidAssetToken(IAssetToken invalidAssetToken, IAssetToken assetToken);

    // Constructor

    /**
     * @notice Construct the YieldToken
     * @param owner Address of the owner of the YieldToken
     * @param name Name of the YieldToken
     * @param symbol Symbol of the YieldToken
     * @param currencyToken Token in which the yield is deposited and denominated
     * @param decimals_ Number of decimals of the YieldToken
     * @param tokenURI_ URI of the YieldToken metadata
     * @param assetToken AssetToken that redistributes yield to the YieldToken
     * @param initialSupply Initial supply of the YieldToken
     */
    constructor(
        address owner,
        string memory name,
        string memory symbol,
        IERC20 currencyToken,
        uint8 decimals_,
        string memory tokenURI_,
        IAssetToken assetToken,
        uint256 initialSupply
    ) YieldDistributionToken(owner, name, symbol, currencyToken, decimals_, tokenURI_) {
        if (currencyToken != assetToken.getCurrencyToken()) {
            revert InvalidCurrencyToken(currencyToken, assetToken.getCurrencyToken());
        }
        _getYieldTokenStorage().assetToken = assetToken;
        _mint(owner, initialSupply);
    }

    /**
     * @notice Mint new YieldTokens to the user
     * @dev Only the owner can call this function
     * @param user Address of the user to mint YieldTokens to
     * @param yieldTokenAmount Amount of YieldTokens to mint
     */
    function mint(address user, uint256 yieldTokenAmount) external onlyOwner {
        _mint(user, yieldTokenAmount);
    }

    /**
     * @notice Receive yield into the YieldToken
     * @dev Anyone can call this function to deposit yield from their AssetToken into the YieldToken
     * @param assetToken AssetToken that redistributes yield to the YieldToken
     * @param currencyToken CurrencyToken in which the yield is received and denominated
     * @param currencyTokenAmount Amount of CurrencyToken to receive as yield
     */
    function receiveYield(IAssetToken assetToken, IERC20 currencyToken, uint256 currencyTokenAmount) external {
        if (assetToken != _getYieldTokenStorage().assetToken) {
            revert InvalidAssetToken(assetToken, _getYieldTokenStorage().assetToken);
        }
        if (currencyToken != _getYieldDistributionTokenStorage().currencyToken) {
            revert InvalidCurrencyToken(currencyToken, _getYieldDistributionTokenStorage().currencyToken);
        }
        _depositYield(block.timestamp, currencyTokenAmount);
    }

    /**
     * @notice Make the SmartWallet redistribute yield from their AssetToken into this YieldToken
     * @dev The Solidity compiler adds a check that the target address has `extcodesize > 0`
     *   and otherwise reverts for high-level calls, so we have to use a low-level call here
     * @param from Address of the SmartWallet to request the yield from
     */
    function requestYield(address from) external override(YieldDistributionToken, IYieldDistributionToken) {
        // Have to override both until updated in https://github.com/ethereum/solidity/issues/12665
        (bool success,) = from.call(
            abi.encodeWithSelector(ISmartWallet.claimAndRedistributeYield.selector, _getYieldTokenStorage().assetToken)
        );
        if (!success) {
            revert SmartWalletCallFailed(from);
        }
    }

}
