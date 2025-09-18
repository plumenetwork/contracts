// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

// https://docs.synthetix.io/contracts/Owned
// NO NEED TO AUDIT
contract OwnedUpgradeable is Initializable {
    address public owner;
    address public nominatedOwner;
    uint256[10] private __gap;

    constructor(address _owner) {}

    function _owned_init(address _owner) internal onlyInitializing{
        require(_owner != address(0), "Owner address cannot be 0");
        owner = _owner;
        emit OwnerChanged(address(0), _owner);
    }

    function nominateNewOwner(address _owner) external onlyOwner {
        nominatedOwner = _owner;
        emit OwnerNominated(_owner);
    }

    function acceptOwnership() external {
        require(msg.sender == nominatedOwner, "You must be nominated before you can accept ownership");
        emit OwnerChanged(owner, nominatedOwner);
        owner = nominatedOwner;
        nominatedOwner = address(0);
    }

    modifier onlyOwner {
        require(msg.sender == owner, "Only the contract owner may perform this action");
        _;
    }

    event OwnerNominated(address newOwner);
    event OwnerChanged(address oldOwner, address newOwner);
}