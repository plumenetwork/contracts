// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

import { ISignedOperations } from "../interfaces/ISignedOperations.sol";

/**
 * @title SignedOperations
 * @author Eugene Y. Q. Shen
 * @notice Smart wallet extension that allows users to sign multiple operations that
 *   anyone can execute in a single transaction, enabling gasless and batched transactions.
 */
contract SignedOperations is EIP712, ISignedOperations {

    using ECDSA for bytes32;

    // Storage

    /// @custom:storage-location erc7201:plume.storage.SignedOperations
    struct SignedOperationsStorage {
        /**
         * @dev Mapping of all nonces that have ever been used in previous SignedOperations.
         *   Nonces are arbitrary values that are passed in by the user, which are used to
         *   prevent replay attacks and allow the user to specify an order in which groups
         *   of SignedOperations should be executed. The value is 1 if the nonce is used,
         *   and 0 otherwise. We store a uint256 word instead of a bool bit for efficiency.
         */
        mapping(bytes32 nonce => uint256) nonces;
    }

    // keccak256(abi.encode(uint256(keccak256("plume.storage.SignedOperations")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant SIGNED_OPERATIONS_STORAGE_LOCATION =
        0xa214e6b2b11ce39c204dc2aea686baa972436835f62e4470fcd8ece0d36fae00;

    function _getSignedOperationsStorage() private pure returns (SignedOperationsStorage storage $) {
        assembly {
            $.slot := SIGNED_OPERATIONS_STORAGE_LOCATION
        }
    }

    // Constants

    /// @dev EIP712 typehash for the SignedOperations struct.
    bytes32 private constant SIGNED_OPERATIONS_TYPEHASH = keccak256(
        "SignedOperations(address[] targets,bytes[] calls,uint256[] values,bytes32 nonce,bytes32 nonceDependency,uint256 expiresAt)"
    );

    // Events

    /**
     * @notice Emitted when a user cancels pending SignedOperations
     * @param nonce Nonce of the SignedOperations that were canceled
     */
    event SignedOperationsCanceled(bytes32 nonce);

    /**
     * @notice Emitted when someone successfully executes SignedOperations for a user
     * @param executor Address that executed the SignedOperations
     * @param nonce Nonce of the SignedOperations that were executed
     */
    event SignedOperationsExecuted(address indexed executor, bytes32 nonce);

    // Errors

    /**
     * @notice Indicates a failure because the caller is not the user wallet
     * @param invalidUser Address of the caller who tried to cancel the SignedOperations
     */
    error UnauthorizedCancel(address invalidUser);

    /**
     * @notice Indicates a failure because the SignedOperations have expired
     * @param nonce Nonce of the expired SignedOperations
     * @param expiresAt Timestamp at which the SignedOperations expired
     */
    error ExpiredSignature(bytes32 nonce, uint256 expiresAt);

    /**
     * @notice Indicates a failure because the SignedOperations were constructed
     *   using `targets`, `calls`, or `values` that have different lengths
     * @param nonce Nonce of the invalid SignedOperations
     */
    error InvalidParameters(bytes32 nonce);

    /**
     * @notice Indicates a failure because the nonce has already been used
     * @param nonce Nonce that was already used
     */
    error InvalidNonce(bytes32 nonce);

    /**
     * @notice Indicates a failure because the nonce that the SignedOperations
     *   depend on has not yet been used
     * @param nonce Nonce of the invalid SignedOperations
     * @param nonceDependency Nonce that the SignedOperations depends on
     */
    error NonceDependencyNotMet(bytes32 nonce, bytes32 nonceDependency);

    /**
     * @notice Indicates a failure because the signer of the SignedOperations does
     *   not match the user wallet that the SignedOperations is being executed on
     * @param nonce Nonce of the invalid SignedOperations
     * @param signer Address of the signer
     */
    error InvalidSigner(bytes32 nonce, address signer);

    /**
     * @notice Indicates a failure because the call to the target contract failed
     * @param nonce Nonce of the SignedOperations that failed
     * @param target Address of the contract that was called
     * @param call Calldata that was sent to the contract
     * @param value Value that was sent to the contract
     */
    error FailedCall(bytes32 nonce, address target, bytes call, uint256 value);

    // Modifiers

    /// @notice Only the user wallet can call this function
    modifier onlyWallet() {
        if (msg.sender != address(this)) {
            revert UnauthorizedCancel(msg.sender);
        }

        _;
    }

    // Functions

    /**
     * @notice Construct the SignedOperations contract
     * @dev Set the EIP721 domain separator to "Plume" and version to "1"
     */
    constructor() EIP712("Plume", "1") { }

    /**
     * @notice Check if a nonce has been used before
     * @param nonce Nonce to check
     * @return True if the nonce has been used before, false otherwise
     */
    function isNonceUsed(bytes32 nonce) public view returns (bool) {
        return _getSignedOperationsStorage().nonces[nonce] != 0;
    }

    /**
     * @notice Cancel pending SignedOperations that have not yet been executed
     * @dev This function can only be called by the user that signed the SignedOperations.
     *   After this, the affected SignedOperations will revert when trying to be executed.
     * @param nonce Nonce of the SignedOperations to cancel
     */
    function cancelSignedOperations(bytes32 nonce) public onlyWallet {
        SignedOperationsStorage storage $ = _getSignedOperationsStorage();
        if ($.nonces[nonce] != 0) {
            revert InvalidNonce(nonce);
        }

        $.nonces[nonce] = 1;

        emit SignedOperationsCanceled(nonce);
    }

    /**
     * @notice Execute multiple SignedOperations on behalf of the user that signed them
     * @dev This function is called by anyone, but the user wallet must sign the operations.
     *   The user wallet can sign the operations using the `signTypedData` method in Web3.
     *   The `targets`, `calls`, and `values` arrays must all have the same length.
     * @param targets Contract addresses to call
     * @param calls Calldata to send to each contract address
     * @param values Value to send to each contract address
     * @param nonce Arbitrary value to prevent replay attacks on SignedOperations
     * @param nonceDependency Nonce that the SignedOperations depend on, must be positive
     * @param expiresAt Timestamp at which the SignedOperations expire
     * @param v Recovery ID of the signer
     * @param r r signature of the signer
     * @param s s signature of the signer
     */
    function executeSignedOperations(
        address[] calldata targets,
        bytes[] calldata calls,
        uint256[] calldata values,
        bytes32 nonce,
        bytes32 nonceDependency,
        uint256 expiresAt,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        SignedOperationsStorage storage $ = _getSignedOperationsStorage();
        uint256 length = targets.length;

        if (block.timestamp > expiresAt) {
            revert ExpiredSignature(nonce, expiresAt);
        }
        if (length != calls.length || length != values.length) {
            revert InvalidParameters(nonce);
        }
        if ($.nonces[nonce] != 0) {
            revert InvalidNonce(nonce);
        }
        if (nonceDependency != 0 && $.nonces[nonceDependency] == 0) {
            revert NonceDependencyNotMet(nonce, nonceDependency);
        }

        // Create a new scope to avoid stack too deep errors
        {
            // Code inspired by OpenZeppelin's ERC20Permit.sol
            bytes32 structHash = keccak256(
                abi.encode(SIGNED_OPERATIONS_TYPEHASH, targets, calls, values, nonce, nonceDependency, expiresAt)
            );
            bytes32 hash = _hashTypedDataV4(structHash);
            address signer = hash.recover(v, r, s);
            if (signer != address(this)) {
                revert InvalidSigner(nonce, signer);
            }
            $.nonces[nonce] = 1;
        }

        for (uint256 i = 0; i < length; i++) {
            {
                (bool success,) = targets[i].call{ value: values[i] }(calls[i]);
                if (success) {
                    continue;
                }
            }
            revert FailedCall(nonce, targets[i], calls[i], values[i]);
        }

        emit SignedOperationsExecuted(msg.sender, nonce);
    }

}
