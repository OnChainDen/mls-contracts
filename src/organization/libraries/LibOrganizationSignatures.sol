// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationSignatures} from "interfaces/organization/IOrganizationSignatures.sol";
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
        return _sliceRange(signatures, 0, initiatorSigSize);
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

        return _sliceFrom(signatures, initiatorSigSize);
    }

    /**
     * @dev Slices a bytes array from a start index to the end, without using the mcopy opcode.
     *      This is a Paris EVM-compatible replacement for OpenZeppelin's Bytes.slice which uses mcopy (Cancun).
     * @param buffer The source bytes array to slice from
     * @param startIndex The starting index (inclusive) for the slice
     * @return result A new bytes array containing buffer[startIndex:buffer.length]
     */
    function _sliceFrom(bytes memory buffer, uint256 startIndex) private pure returns (bytes memory result) {
        uint256 bufferLength = buffer.length;

        // Case: Start index is at or beyond the buffer length
        if (startIndex >= bufferLength) {
            return new bytes(0);
        }

        uint256 resultLength = bufferLength - startIndex;
        return _sliceRange(buffer, startIndex, resultLength);
    }

    /**
     * @dev Slices a bytes array from a start index for a specified length.
     *      This is a Paris EVM-compatible implementation without using the mcopy opcode.
     * @param buffer The source bytes array to slice from
     * @param startIndex The starting index (inclusive) for the slice
     * @param length The number of bytes to copy
     * @return result A new bytes array containing buffer[startIndex:startIndex+length]
     */
    function _sliceRange(bytes memory buffer, uint256 startIndex, uint256 length)
        private
        pure
        returns (bytes memory result)
    {
        // Case: Invalid range
        if (startIndex + length > buffer.length) {
            return new bytes(0);
        }

        result = new bytes(length);

        assembly {
            // Source pointer: skip 32-byte length prefix, then advance by startIndex offset
            let src := add(add(buffer, 32), startIndex)
            // Destination pointer: skip 32-byte length prefix
            let dest := add(result, 32)

            // Calculate number of full 32-byte words to copy
            let numFullWordsToCopy := div(length, 32)

            // Copy full 32-byte words
            for { let i := 0 } lt(i, numFullWordsToCopy) { i := add(i, 1) } {
                mstore(dest, mload(src))
                dest := add(dest, 32)
                src := add(src, 32)
            }

            // Handle remaining bytes (0-31 bytes)
            let remainingBytesToCopy := mod(length, 32)
            if remainingBytesToCopy {
                // Create a mask that preserves only the 'remainingBytesToCopy' high-order bytes
                let numBitsToShift := sub(256, mul(remainingBytesToCopy, 8))
                let mask := shl(numBitsToShift, not(0))
                // Load source word, mask out garbage bytes, store to destination
                mstore(dest, and(mload(src), mask))
            }
        }
    }
}
