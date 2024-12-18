// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { ERC4626Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";

import { BoringVaultAdapter } from "./BoringVaultAdapter.sol";

/**
 * @title pUSD
 * @author Eugene Y. Q. Shen, Alp Guneysel
 * @notice Unified Plume USD stablecoin
 */
contract pUSD is BoringVaultAdapter {

    /**
     * @notice Prevent the implementation contract from being initialized or reinitialized
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor(
        address _endpoint,
        address _delegate,
        address initialOwner
    ) BoringVaultAdapter(_endpoint, _delegate, initialOwner) Ownable(initialOwner) {
        _disableInitializers();
    }

    /**
     * @notice Initialize pUSD
     * @param owner Address of the owner of pUSD
     * @param asset_ Address of the underlying asset
     * @param vault_ Address of the BoringVault
     * @param atomicQueue_ Address of the AtomicQueue
     */
    //
    function initialize(
        address owner,
        IERC20 asset_,
        address vault_,
        address teller_,
        address atomicQueue_,
        address lens_,
        address accountant_,
        address endpoint_,
        uint32 _eid
    ) public initializer {
        super.initialize(
            owner, asset_, vault_, teller_, atomicQueue_, lens_, accountant_, endpoint_, _eid, "Plume USD", "pUSD"
        );
    }

    // ========== METADATA OVERRIDES ==========

    /**
     * @notice Get the name of the token
     * @return Name of the token
     */
    function name() public pure override(ERC20Upgradeable, IERC20Metadata) returns (string memory) {
        return "Plume USD";
    }

    /**
     * @notice Get the symbol of the token
     * @return Symbol of the token
     */
    function symbol() public pure override(ERC20Upgradeable, IERC20Metadata) returns (string memory) {
        return "pUSD";
    }

function setPeer(uint32 _eid, bytes32 _peer) public virtual override {
    require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Caller is not admin");
    _setPeer(_eid, _peer);
}

}
