// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {OperationType} from "../../interfaces/IOrganization.sol";
import {SignatureUtils} from "../../libraries/SignatureUtils.sol";
import {LibOrganizationSignaturesStorage} from "./storage/LibOrganizationSignaturesStorage.sol";

/**
 * @title Lib Organization Signatures
 * @dev Library for signature and nonce-related operations for Organization contracts
 * @dev This library handles nonce management for all operation types (admin operations and account transactions)
 * @author Den Technologies Inc
 */
library LibOrganizationSignatures {
    /**
     * @dev Emitted when an operation uses a nonce that has already been used
     * @param nonce The nonce that was attempted to be used
     */
    error NonceAlreadyUsed(uint256 nonce);

    /**
     * @dev Validates that a nonce has not been used and marks it as used
     * @dev Reverts if the nonce has already been used
     * @param nonce The nonce to validate and consume
     */
    function validateAndConsumeNonceOrRevert(uint256 nonce) internal {
        LibOrganizationSignaturesStorage.Layout storage sigLayout = LibOrganizationSignaturesStorage.layout();

        if (sigLayout.usedNonces[nonce]) {
            revert NonceAlreadyUsed(nonce);
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
     * @dev Extracts the review signatures from a signatures bytes array (everything after the first signature)
     * @dev The first SIGNATURE_LENGTH bytes are assumed to be the initiator signature.
     *      Review signatures start after the initiator signature and continue to the end.
     * @param signatures The full signatures bytes array
     * @return reviewSignatures The review signatures (may be empty if only initiator signature provided)
     */
    function extractReviewSignatures(bytes memory signatures) internal pure returns (bytes memory reviewSignatures) {
        uint256 sigLength = SignatureUtils.SIGNATURE_LENGTH;

        // If signatures is SIGNATURE_LENGTH bytes or less, there are no review signatures
        if (signatures.length <= sigLength) {
            return new bytes(0);
        }

        uint256 reviewLength = signatures.length - sigLength;
        reviewSignatures = new bytes(reviewLength);

        // Copy review signatures (everything after byte 65)
        /* solhint-disable no-inline-assembly */
        assembly {
            // Source: signatures + 32 (length prefix) + 65 (skip initiator sig)
            let src := add(add(signatures, 32), sigLength)
            // Destination: reviewSignatures + 32 (length prefix)
            let dst := add(reviewSignatures, 32)
            // Copy reviewLength bytes
            for { let i := 0 } lt(i, reviewLength) { i := add(i, 32) } { mstore(add(dst, i), mload(add(src, i))) }
        }
    }
}
