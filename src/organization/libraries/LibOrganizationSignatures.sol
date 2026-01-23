// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationSignatures} from "interfaces/organization/IOrganizationSignatures.sol";
import {BytesUtils} from "libraries/BytesUtils.sol";
import {SignatureUtils} from "libraries/SignatureUtils.sol";
import {LibOrganizationSignaturesStorage} from "organization/libraries/storage/LibOrganizationSignaturesStorage.sol";
import {OperationType} from "types/CommonTypes.sol";

/**
 * @title Lib Organization Signatures
 * @dev Library for signature and nonce-related operations for Organization contracts.
 *      This library handles nonce management for all operation types (admin operations and account transactions).
 * @author Den Technologies Inc
 */
library LibOrganizationSignatures {
    /**
     * @dev Validates that a nonce has not been used and marks it as used.
     *      Reverts if the nonce has already been used.
     * @param nonce The nonce to validate and consume
     */
    function validateAndConsumeNonceOrRevert(uint256 nonce) internal {
        LibOrganizationSignaturesStorage.Layout storage sigLayout = LibOrganizationSignaturesStorage.layout();

        if (sigLayout.usedNonces[nonce]) {
            revert IOrganizationSignatures.NonceAlreadyUsed(nonce);
        }

        sigLayout.usedNonces[nonce] = true;
    }

    /**
     * @dev Checks if a nonce has been used
     * @param nonce The nonce to check
     * @return True if the nonce has been used, false otherwise
     */
    function isNonceUsed(uint256 nonce) internal view returns (bool) {
        return LibOrganizationSignaturesStorage.layout().usedNonces[nonce];
    }

    /**
     * @notice Computes a deterministic nonce from operation data and salt
     * @param operationType The type of operation being performed
     * @param operationData The ABI-encoded data of the operation
     * @param salt A user-provided salt for nonce computation
     * @return The computed nonce
     */
    function computeNonce(OperationType operationType, bytes memory operationData, uint256 salt)
        internal
        view
        returns (uint256)
    {
        return uint256(keccak256(abi.encode(address(this), operationType, keccak256(operationData), salt)));
    }

    /**
     * @dev Extracts the initiator signature from a signatures bytes array (the first signature).
     *      Supports both fixed 65-byte EOA signatures and variable-length ERC-1271 signatures.
     * @param signatures The full signatures bytes array
     * @return The initiator signature bytes
     */
    function extractInitiatorSignature(bytes memory signatures) internal pure returns (bytes memory) {
        uint256 initiatorSigSize = SignatureUtils.getFirstSignatureSize(signatures);

        // Case: Invalid or empty initiator signature
        if (initiatorSigSize == 0 || initiatorSigSize > signatures.length) {
            return new bytes(0);
        }

        // Return the initiator signature
        return BytesUtils.sliceRange(signatures, 0, initiatorSigSize);
    }

    /**
     * @dev Extracts the review signatures from a signatures bytes array (everything after the first signature).
     *      Supports both fixed 65-byte EOA signatures and variable-length ERC-1271 signatures.
     *      Review signatures start after the initiator signature and continue to the end.
     * @param signatures The full signatures bytes array
     * @return The review signatures (may be empty if only initiator signature provided)
     */
    function extractReviewSignatures(bytes memory signatures) internal pure returns (bytes memory) {
        uint256 initiatorSigSize = SignatureUtils.getFirstSignatureSize(signatures);

        // Case: Invalid initiator signature or no review signatures
        if (initiatorSigSize == 0 || initiatorSigSize >= signatures.length) {
            return new bytes(0);
        }

        return BytesUtils.sliceFrom(signatures, initiatorSigSize);
    }
}
