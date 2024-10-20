// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import "./PlumeGoonStorage.sol";

/// @custom:oz-upgrades-from PlumeGoon
contract PlumeGoon is
    Initializable,
    ERC721Upgradeable,
    ERC721EnumerableUpgradeable,
    ERC721URIStorageUpgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable
{
    using PlumeGoonStorage for PlumeGoonStorage.Storage;
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

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

        PlumeGoonStorage.Storage storage ps = PlumeGoonStorage.getStorage();
        ps.admin = _admin;
        ps.plumeGoonMerkleRoot = _merkleRoot;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(MINTER_ROLE, minter);
        _grantRole(UPGRADER_ROLE, _admin);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

    /**
     * @notice Verifies that the user is allowed to mint by checking the Merkle proof.
     * @param tokenId_ The token ID for the NFT to mint
     * @param tokenURI_ The URI for the token metadata
     * @param proof The Merkle proof to verify eligibility
     */
    function mintPlumeGoonNFT(
        uint256 tokenId_,
        string memory tokenURI_,
        bytes32[] calldata proof
    ) external {
        PlumeGoonStorage.Storage storage ps = PlumeGoonStorage.getStorage();

        if (ps.hasMinted[msg.sender]) {
            revert AlreadyMinted();
        }
        if (!_verifyMerkleProof(msg.sender, tokenId_, tokenURI_, proof)) {
            revert InvalidMerkleProof();
        }

        _safeMint(msg.sender, tokenId_);
        _setTokenURI(tokenId_, tokenURI_);

        ps.hasMinted[msg.sender] = true;

        emit Minted(msg.sender, tokenId_);
    }

    /**
     * @notice Verifies the Merkle proof provided for the user's mint eligibility.
     * @param user The address of the user attempting to mint.
     * @param tokenId_ The token ID to mint.
     * @param tokenURI_ The token URI to verify.
     * @param proof The Merkle proof.
     * @return True if the proof is valid, false otherwise.
     */
    function _verifyMerkleProof(
        address user,
        uint256 tokenId_,
        string memory tokenURI_,
        bytes32[] memory proof
    ) internal view returns (bool) {
        PlumeGoonStorage.Storage storage ps = PlumeGoonStorage.getStorage();
        bytes32 leaf = keccak256(abi.encodePacked(user, tokenId_, tokenURI_));
        return MerkleProof.verify(proof, ps.plumeGoonMerkleRoot, leaf);
    }

    /**
     * @notice Allows the admin to update the Merkle root.
     * @param newMerkleRoot The new Merkle root to set.
     */
    function updateMerkleRoot(bytes32 newMerkleRoot) external onlyRole(DEFAULT_ADMIN_ROLE) {
        PlumeGoonStorage.Storage storage ps = PlumeGoonStorage.getStorage();
        ps.plumeGoonMerkleRoot = newMerkleRoot;
        emit MerkleRootUpdated(newMerkleRoot);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable,ERC721URIStorageUpgradeable, AccessControlUpgradeable)
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
        PlumeGoonStorage.Storage storage ps = PlumeGoonStorage.getStorage();
        return ps.admin;
    }

    function hasMinted(address user) public view returns (bool) {
        PlumeGoonStorage.Storage storage ps = PlumeGoonStorage.getStorage();
        return ps.hasMinted[user];
    }
}
