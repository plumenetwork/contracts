// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";

contract PlumeGoon is
    Initializable,
    ERC721Upgradeable,
    ERC721EnumerableUpgradeable,
    ERC721URIStorageUpgradeable,
    ERC721PausableUpgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable
{

    struct PlumeGoonStorage {
        address admin;
        mapping(string => uint256) tokenURIs; // to ensure token uri is unique i.e same nft cannot be claimed by another
            // user
        mapping(address => bool) hasMinted;
        mapping(bytes32 => bool) usedNonces;
    }

    // keccak256(abi.encode(uint256(keccak256("plume.storage.PlumeStorage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant PLUMEGOON_STORAGE_LOCATION =
        0x40f2ca4cf3a525ed9b1b2649f0f850db77540accc558be58ba47f8638359e800;

    function _getPlumeGoonStorage() internal pure returns (PlumeGoonStorage storage $) {
        assembly {
            $.slot := PLUMEGOON_STORAGE_LOCATION
        }
    }

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    event Minted(address indexed user, uint256 tokenId);

    /**
     * @dev Initializes the contract with given parameters and assigns roles.
     * @param _admin Address of the contract admin.
     * @param name Name of the NFT collection.
     * @param symbol Symbol of the NFT collection.
     * @param pauser Address with the PAUSER_ROLE.
     * @param minter Address with the MINTER_ROLE.
     */
    function initialize(
        address _admin,
        string memory name,
        string memory symbol,
        address pauser,
        address minter
    ) public initializer {
        __ERC721_init(name, symbol);
        __ERC721Enumerable_init();
        __ERC721URIStorage_init();
        __ERC721Pausable_init();
        __AccessControl_init();
        __UUPSUpgradeable_init();

        PlumeGoonStorage storage ps = _getPlumeGoonStorage();
        ps.admin = _admin;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(PAUSER_ROLE, pauser);
        _grantRole(MINTER_ROLE, minter);
        _grantRole(UPGRADER_ROLE, _admin);
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(UPGRADER_ROLE) { }

    /// @notice Ensures that the function caller is authorized via an admin-signed message.
    /// @dev Requires that the provided nonce has not been used before to prevent replay attacks.
    /// @dev Verifies that the request is signed by an admin using `onlySignedByAdmin`.
    /// @dev Marks the nonce as used after successful verification.
    modifier _onlyWithAdminSignature(string memory _tokenUri, address user, uint8 tier, bytes memory signature, bytes32 nonce) {
        PlumeGoonStorage storage ps = _getPlumeGoonStorage();
        require(!isNonceUsed(nonce), "Nonce already used");
        require(onlySignedByAdmin(_tokenUri, user, tier, signature, nonce), "Invalid signature");
        ps.usedNonces[nonce] = true;
        _;
    }

    /// @notice Recovers the signer address from a given signature and message hash.
    /// @param message The hashed message that was signed.
    /// @param sig The cryptographic signature.
    /// @return The address of the signer.
    /// @dev Requires that the signature length is exactly 65 bytes.
    /// @dev Uses `ecrecover` to derive the signer address from the signature.

    function recoverSignerFromSignature(bytes32 message, bytes memory sig) internal pure returns (address) {
        require(sig.length == 65);

        uint8 v;
        bytes32 r;
        bytes32 s;

        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }

        return ecrecover(message, v, r, s);
    }
    /// @notice Returns the Ethereum signed message hash for a given hash.
    /// @param hash The original hash to be prefixed.
    /// @return The Ethereum Signed Message hash.
    /// @dev Uses the standard Ethereum prefix (`\x19Ethereum Signed Message:\n32`) for compatibility with `ecrecover`.

    function prefixed(
        bytes32 hash
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
    }

    function onlySignedByAdmin(
        string memory _tokenUri,
        address user,
        uint8 tier,
        bytes memory signature,
        bytes32 nonce
    ) internal view returns (bool) {
        PlumeGoonStorage storage ps = _getPlumeGoonStorage();
        bytes32 message = prefixed(keccak256(abi.encodePacked(_tokenUri, user, tier, nonce)));
        return recoverSignerFromSignature(message, signature) == ps.admin;
    }

    /**
     * @dev Mints a new NFT for a user.
     * @param _tokenId ID of the token.
     * @param _tokenUri URI for the token metadata.
     * @param user Address of the recipient.
     */
    function _mintNFT(uint256 _tokenId, string memory _tokenUri, address user) private {
        PlumeGoonStorage storage ps = _getPlumeGoonStorage();

        require(_tokenId != 0, "Token Id cannot be 0");

        _safeMint(user, _tokenId);
        _setTokenURI(_tokenId, _tokenUri);

        ps.tokenURIs[_tokenUri] = _tokenId;
        ps.hasMinted[user] = true;
    }

    /// @notice Mints an NFT with a unique token ID and URI, ensuring admin authorization and preventing duplicates.
    /// @param _tokenId The unique identifier for the NFT.
    /// @param _tokenUri The metadata URI associated with the NFT.
    /// @param signature A cryptographic signature from an admin to authorize the minting.
    /// @param tier The tier level of the NFT, used for rewards calculation.
    /// @param nonce A unique value to prevent replay attacks.
    /// @dev Requires an admin-signed message for authentication. Ensures that the sender has not minted before and that
    /// the token URI is unique.
    /// @dev Emits a `Minted` event upon successful minting.

    function mintNFT(
        uint256 _tokenId,
        string memory _tokenUri,
        bytes memory signature,
        uint8 tier,
        bytes32 nonce
    ) public _onlyWithAdminSignature(_tokenUri, msg.sender, tier, signature, nonce) {
        PlumeGoonStorage storage ps = _getPlumeGoonStorage();

        require(!ps.hasMinted[msg.sender], "You have already minted an NFT");
        require(ps.tokenURIs[_tokenUri] == 0, "Token URI already exists");

        _mintNFT(_tokenId, _tokenUri, msg.sender);

        emit Minted(msg.sender, _tokenId);
    }

    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function forceTransfer(address from, address to, uint256 tokenId) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_ownerOf(tokenId) != address(0), "Token Id does not exist");
        require(ownerOf(tokenId) == from, "From address is not the owner of the token");

        _safeTransfer(from, to, tokenId, "");
    }

    function reset(
        address user
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        PlumeGoonStorage storage ps = _getPlumeGoonStorage();
        ps.hasMinted[user] = false;
    }

    function reset(address user, uint256 burnTokenId) public onlyRole(DEFAULT_ADMIN_ROLE) {
        PlumeGoonStorage storage ps = _getPlumeGoonStorage();

        require(ps.hasMinted[user], "User should have already minted an NFT to reset them");
        require(balanceOf(user) > 0, "User should have already minted an NFT to reset them");
        require(ownerOf(burnTokenId) == user, "Incorrect Token Id provided for reset");

        string memory _oldTokenUri = tokenURI(burnTokenId);

        ps.tokenURIs[_oldTokenUri] = 0;
        _burn(burnTokenId);
        ps.hasMinted[user] = false;
    }

    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal override(ERC721Upgradeable, ERC721EnumerableUpgradeable, ERC721PausableUpgradeable) returns (address) {
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(
        address account,
        uint128 value
    ) internal override(ERC721Upgradeable, ERC721EnumerableUpgradeable) {
        super._increaseBalance(account, value);
    }

    function tokenURI(
        uint256 tokenId
    ) public view override(ERC721Upgradeable, ERC721URIStorageUpgradeable) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable, ERC721URIStorageUpgradeable, AccessControlUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function isNonceUsed(
        bytes32 nonce
    ) public view returns (bool) {
        PlumeGoonStorage storage ps = _getPlumeGoonStorage();
        return ps.usedNonces[nonce];
    }

    // View functions for storage variables

    function getAdmin() public view returns (address) {
        PlumeGoonStorage storage ps = _getPlumeGoonStorage();
        return ps.admin;
    }

    function getTokenURI(
        string memory uri
    ) public view returns (uint256) {
        PlumeGoonStorage storage ps = _getPlumeGoonStorage();
        return ps.tokenURIs[uri];
    }

    function hasMinted(
        address user
    ) public view returns (bool) {
        PlumeGoonStorage storage ps = _getPlumeGoonStorage();
        return ps.hasMinted[user];
    }

}
