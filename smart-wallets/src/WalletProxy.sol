// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Proxy } from "@openzeppelin/contracts/proxy/Proxy.sol";

import { WalletFactory } from "./WalletFactory.sol";

/**
 * @title WalletProxy
 * @author Eugene Y. Q. Shen
 * @notice Double proxy contract that is loaded into every smart wallet call.
 *   The WalletProxy is deployed to 0x38F983FcC64217715e00BeA511ddf2525b8DC692.
 * @dev The bytecode of this contract is loaded whenever anyone uses `Call`
 *   or `StaticCall` on an EOA (see `plumenetwork/go-ethereum` for details).
 *   The bytecode must be static to minimize changes to geth, so everything
 *   in this contract is immutable. The WalletProxy delegates all calls to
 *   the SmartWallet implementation through the WalletFactory, which then
 *   delegates calls to the user's wallet extensions, hence the double proxy.
 */
contract WalletProxy is Proxy {

    /// @notice Address of the WalletFactory that the WalletProxy delegates to
    WalletFactory public immutable walletFactory;

    /**
     * @notice Construct the WalletProxy
     * @param walletFactory_ WalletFactory implementation
     * @dev The WalletFactory is immutable and set at deployment
     */
    constructor(
        WalletFactory walletFactory_
    ) {
        walletFactory = walletFactory_;
    }

    /**
     * @notice Fallback function for the proxy implementation, which
     *   delegates calls to the SmartWallet through the WalletFactory
     * @return impl Address of the SmartWallet implementation
     */
    function _implementation() internal view virtual override returns (address impl) {
        return address(walletFactory.smartWallet());
    }

    /// @notice Fallback function to receive ether
    receive() external payable { }

}
