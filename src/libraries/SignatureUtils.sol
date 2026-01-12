// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title SignatureUtils
 * @dev Utilities for handling pure 65-byte ECDSA signatures
 * @dev Canonical signature format: r (32 bytes) || s (32 bytes) || v (1 byte)
 *
 *      This library provides utilities for working with concatenated ECDSA signatures.
 *      Multiple signatures are stored as a single bytes array where each signature
 *      occupies exactly 65 bytes.
 *
 *      Signers are derived using ECDSA.recover(), not embedded in the signature.
 *      This library only supports EOA signatures (not ERC-1271 contract signatures).
 *
 *      Signature format:
 *      | Offset | Size | Field | Description           |
 *      |--------|------|-------|-----------------------|
 *      | 0      | 32   | r     | ECDSA r component     |
 *      | 32     | 32   | s     | ECDSA s component     |
 *      | 64     | 1    | v     | ECDSA v component     |
 *
 * @author Den Technologies Inc
 */
library SignatureUtils {
    /// @dev Standard ECDSA signature length in bytes: r (32) + s (32) + v (1) = 65 bytes
    uint256 internal constant SIGNATURE_LENGTH = 65;

    /**
     * @dev Returns the number of signatures in a concatenated signatures array
     * @param signatures The concatenated signatures bytes
     * @return The number of 65-byte signatures contained in the array
     */
    function getSignatureCount(bytes memory signatures) internal pure returns (uint8) {
        return uint8(signatures.length / SIGNATURE_LENGTH);
    }

    /**
     * @dev Extracts a single signature from the signatures array
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
