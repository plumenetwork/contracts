// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface ISignedOperations {

    function isNonceUsed(bytes32 nonce) external view returns (bool used);
    function cancelSignedOperations(bytes32 nonce) external;
    function executeSignedOperations(
        address[] calldata targets,
        bytes[] calldata calls,
        uint256[] calldata values,
        bytes32 nonce,
        bytes32 nonceDependency,
        uint256 expiration,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

}
