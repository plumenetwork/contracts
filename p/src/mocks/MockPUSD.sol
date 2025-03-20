// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

/**
 * @title MockPUSD
 * @dev A mock implementation of the pUSD token for testing purposes.
 * This contract implements the ERC20 standard with additional minting and burning functionality.
 * It uses the UUPS upgradeable pattern for proxy-based upgradeability.
 */
contract MockPUSD is Initializable, ERC20Upgradeable, OwnableUpgradeable, UUPSUpgradeable {

    // The number of decimals for the token
    uint8 private _decimals;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the contract replacing the constructor for upgradeable contracts
     * @param initialOwner The address that will own this contract
     * @param initialSupply The initial token supply to mint to the owner
     */
    function initialize(address initialOwner, uint256 initialSupply) public initializer {
        __ERC20_init("Plume USD Test", "pUSDTest");
        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();

        _decimals = 6;

        // Mint initial supply to the owner if specified
        if (initialSupply > 0) {
            _mint(initialOwner, initialSupply);
        }
    }

    /**
     * @dev Required by the UUPSUpgradeable module
     * Only allows the owner to upgrade the implementation
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner { }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     */
    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    /**
     * @dev Mints new tokens to the specified address.
     * Only callable by the owner.
     * @param to The address that will receive the minted tokens
     * @param amount The amount of tokens to mint
     */
    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    /**
     * @dev Burns tokens from the specified address.
     * Only callable by the owner.
     * @param from The address from which to burn tokens
     * @param amount The amount of tokens to burn
     */
    function burn(address from, uint256 amount) public onlyOwner {
        _burn(from, amount);
    }

    /**
     * @dev Allows the account owner to burn their own tokens.
     * @param amount The amount of tokens to burn
     */
    function burnOwn(
        uint256 amount
    ) public {
        _burn(msg.sender, amount);
    }

    /**
     * @dev Destroys the contract and sends any remaining Ether to the owner.
     * Only callable by the owner.
     */
    function destroyContract() public onlyOwner {
        // Instead of selfdestruct, simply transfer any remaining ETH to the owner
        address payable ownerAddress = payable(owner());

        // Get the current balance of the contract
        uint256 balance = address(this).balance;

        // Transfer the balance to the owner
        if (balance > 0) {
            (bool success,) = ownerAddress.call{ value: balance }("");
            require(success, "ETH transfer failed");
        }

        // Note: The contract code will still exist on the blockchain
        // but we've transferred all funds to the owner
    }

}
