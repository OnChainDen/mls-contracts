// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title SignatureUtils
 * @notice A library for signature utility functions
 * @author Den Technologies Inc
 */
library SignatureUtils {
    /// @dev Signature length: r (32) + s (32) + v (1) = 65 bytes
    uint256 internal constant SIGNATURE_LENGTH = 65;

    /**
     * @notice Extracts a single signature from the signatures array
     * @param signatures The signatures to extract from
     * @param index The index of the signature to extract
     * @return The extracted signature
     */
    function extractSignature(bytes memory signatures, uint256 index) internal pure returns (bytes memory) {
        // Initialize a new bytes array to store the signature
        // Note: Each signature is 65 bytes (r: 32, s: 32, v: 1)
        bytes memory extractedSignature = new bytes(SIGNATURE_LENGTH);
        uint256 signatureStartPosition = index * SIGNATURE_LENGTH;

        /* solhint-disable no-inline-assembly */
        assembly {
            // Initialize pointer to the start of the signatures array
            // Note: First 32 bytes (0x20) are the length of the array
            let signaturesPosition := add(signatures, 0x20)

            // Initialize pointer to the start of the extracted signature
            // Note: First 32 bytes (0x20) are the length of the array
            let extractedSignaturePosition := add(extractedSignature, 0x20)

            // Copy first 32 bytes (r)
            mstore(extractedSignaturePosition, mload(add(signaturesPosition, signatureStartPosition)))
            // Copy second 32 bytes (s)
            mstore(
                add(extractedSignaturePosition, 0x20), mload(add(signaturesPosition, add(signatureStartPosition, 0x20)))
            )
            // Copy last byte (v)
            mstore8(
                add(extractedSignaturePosition, 0x40),
                byte(0, mload(add(signaturesPosition, add(signatureStartPosition, 0x40))))
            )
        }

        return extractedSignature;
    }
}
