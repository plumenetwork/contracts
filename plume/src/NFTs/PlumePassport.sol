// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import "./PlumePassportStorage.sol";

/// @custom:oz-upgrades-from PlumePassport
contract PlumePassport is
    Initializable,
    ERC721Upgradeable,
    ERC721EnumerableUpgradeable,
    ERC721URIStorageUpgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable
{
    using PlumePassportStorage for PlumePassportStorage.Storage;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    uint256 public currentTokenId;

    event Minted(address indexed user, uint256 tokenId);
    event MerkleRootUpdated(bytes32 newMerkleRoot);

    error AlreadyMinted();
    error InvalidMerkleProof();

    function initialize(
        address _admin,
        string memory name,
        string memory symbol,
        bytes32 _merkleRoot,
        address minter
    ) public initializer {
        __ERC721_init(name, symbol);
        __ERC721Enumerable_init();
        __ERC721URIStorage_init();
        __AccessControl_init();
        __UUPSUpgradeable_init();

        PlumePassportStorage.Storage storage ps = PlumePassportStorage.getStorage();
        ps.admin = _admin;
        ps.plumePassportMerkleRoot = _merkleRoot;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(MINTER_ROLE, minter);
        _grantRole(UPGRADER_ROLE, _admin);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

    /**
     * @notice Verifies the user's eligibility using Merkle proof and mints the NFT.
     * @param miles User's miles.
     * @param checkInStreak User's check-in streak.
     * @param flightClass User's flight class (A=0, B=1, C=2, D=3).
     * @param boardingClass User's boarding class.
     * @param proof The Merkle proof to verify eligibility.
     */
    function mintPlumePassportNFT(
        uint256 miles,
        uint256 checkInStreak,
        uint8 flightClass,
        uint8 boardingClass,
        bytes32[] calldata proof
    ) external {
        PlumePassportStorage.Storage storage ps = PlumePassportStorage.getStorage();

        if (ps.hasMinted[msg.sender]) {
            revert AlreadyMinted();
        }
        if (!_verifyMerkleProof(msg.sender, miles, checkInStreak, flightClass, boardingClass, proof)) {
            revert InvalidMerkleProof();
        }

        uint256 newTokenId = ++currentTokenId;
        string memory tokenURI = ps.tokenURIs[flightClass]; // flightClass is used as the index for tokenURIs

        _safeMint(msg.sender, newTokenId);
        _setTokenURI(newTokenId, tokenURI);

        ps.hasMinted[msg.sender] = true;

        emit Minted(msg.sender, newTokenId);
    }

    /**
     * @notice Verifies the Merkle proof for the user's eligibility to mint the passport.
     * @param user The address of the user attempting to mint.
     * @param miles The miles accumulated by the user.
     * @param checkInStreak The user's check-in streak.
     * @param flightClass The user's flight class (A=0, B=1, C=2, D=3).
     * @param boardingClass The user's boarding class.
     * @param proof The Merkle proof.
     * @return True if the proof is valid, false otherwise.
     */
    function _verifyMerkleProof(
        address user,
        uint256 miles,
        uint256 checkInStreak,
        uint8 flightClass,
        uint8 boardingClass,
        bytes32[] memory proof
    ) internal view returns (bool) {
        PlumePassportStorage.Storage storage ps = PlumePassportStorage.getStorage();
        bytes32 leaf = keccak256(abi.encodePacked(user, miles, checkInStreak, flightClass, boardingClass));
        return MerkleProof.verify(proof, ps.plumePassportMerkleRoot, leaf);
    }

    /**
     * @notice Allows the admin to update the Merkle root.
     * @param newMerkleRoot The new Merkle root to set.
     */
    function updateMerkleRoot(bytes32 newMerkleRoot) external onlyRole(DEFAULT_ADMIN_ROLE) {
        PlumePassportStorage.Storage storage ps = PlumePassportStorage.getStorage();
        ps.plumePassportMerkleRoot = newMerkleRoot;
        emit MerkleRootUpdated(newMerkleRoot);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable, ERC721URIStorageUpgradeable, AccessControlUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function _increaseBalance(address account, uint128 value)
        internal
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable)
    {
        super._increaseBalance(account, value);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721Upgradeable, ERC721URIStorageUpgradeable)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable)
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }

    // View functions for storage variables
    function getAdmin() public view returns (address) {
        PlumePassportStorage.Storage storage ps = PlumePassportStorage.getStorage();
        return ps.admin;
    }

    function hasMinted(address user) public view returns (bool) {
        PlumePassportStorage.Storage storage ps = PlumePassportStorage.getStorage();
        return ps.hasMinted[user];
    }
}
