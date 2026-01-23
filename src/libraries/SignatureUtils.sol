// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/**
 * @title SignatureUtils
 * @dev Unified signature validation library supporting both EOA (ECDSA) and
 *      smart contract (ERC-1271) signatures.
 *
 *      Hybrid signature format (type-prefixed, variable length):
 *
 *      EOA (v = 27 or 28):
 *        | v (1) | r (32) | s (32) | = 65 bytes
 *
 *      ERC-1271 (v = 0):
 *        | 0 (1) | signer (20) | length (2) | signature (N) | = 23 + N bytes
 *
 *      Two optimized validation paths:
 *      - isValidSignatureFrom(): For single-signature cases (Guardian, Initiator, Recovery)
 *      - parseSignatureAtOffset(): For multi-signature iteration (Members, Admins)
 *
 *      Signatures are simply concatenated. No offset calculation needed off-chain.
 *
 * @author Den Technologies Inc
 */
library SignatureUtils {
    /**
     * @dev Parsed signature data returned by parseSignatureAtOffset
     * @param nextOffset Byte offset to the next signature in the array
     * @param signer Recovered (EOA) or provided (ERC-1271) signer address
     * @param isValid True if signature parsing and validation succeeded
     * @param isContract True if this is an ERC-1271 signature
     */
    struct ParsedSignature {
        uint256 nextOffset;
        address signer;
        bool isValid;
        bool isContract;
    }

    /// @dev EOA signature size: v (1) + r (32) + s (32) = 65 bytes
    uint256 internal constant EOA_SIGNATURE_SIZE = 65;

    /// @dev ERC-1271 signature header size: v (1) + signer (20) + length (2) = 23 bytes
    uint256 internal constant CONTRACT_SIGNATURE_HEADER_SIZE = 23;

    /// @dev v value indicating an ERC-1271 contract signature
    uint8 internal constant V_CONTRACT_SIGNATURE = 0;

    /// @dev Legacy constant for backwards compatibility
    uint256 internal constant SIGNATURE_LENGTH = 65;

    // ==================== Internal View Functions ====================

    /**
     * @dev Validates a single signature (EOA or ERC-1271) against an expected signer.
     *      This is the recommended function for single-signature validation.
     *      Used by: Guardian signatures, Initiator signatures, Recovery signatures
     * @param signature A single signature (65 bytes EOA or 23+N bytes ERC-1271)
     * @param hash The hash that was signed
     * @param expectedSigner The expected signer address
     * @return True if signature is valid and from expectedSigner
     */
    function isValidSignatureFrom(bytes memory signature, bytes32 hash, address expectedSigner)
        internal
        view
        returns (bool)
    {
        // Case: Empty signature
        if (signature.length == 0) return false;

        uint8 v = _getVByte(signature, 0);

        // Case: ERC-1271 contract signature (v = 0)
        if (v == V_CONTRACT_SIGNATURE) {
            return _isContractSignatureValid(signature, hash, expectedSigner);
        }

        // Case: EOA signature (v = 27 or 28)
        if (v == 27 || v == 28) {
            return _isEOASignatureValid(signature, hash, expectedSigner, v);
        }

        // Case: Unknown signature type
        return false;
    }

    /**
     * @dev Parses a signature at the given offset and returns the signer.
     *      Used for iterating through multiple signatures with a for-loop.
     *      Used by: Member approvals, Admin signatures
     * @param signatures The concatenated signatures array
     * @param offset The byte offset where this signature starts
     * @param hash The hash that was signed (needed for ECDSA recovery)
     * @return parsed The parsed signature data including nextOffset for iteration
     */
    function parseSignatureAtOffset(bytes memory signatures, uint256 offset, bytes32 hash)
        internal
        view
        returns (ParsedSignature memory parsed)
    {
        // Case: Offset beyond signatures array
        if (offset >= signatures.length) {
            parsed.isValid = false;
            return parsed;
        }

        uint8 v = _getVByte(signatures, offset);

        // Case: ERC-1271 contract signature (v = 0)
        if (v == V_CONTRACT_SIGNATURE) {
            parsed.isContract = true;
            _parseContractSignatureAtOffset({signatures: signatures, offset: offset, hash: hash, parsed: parsed});
            return parsed;
        }

        // Case: EOA signature (v = 27 or 28)
        if (v == 27 || v == 28) {
            parsed.isContract = false;
            _parseEOASignatureAtOffset({signatures: signatures, offset: offset, hash: hash, v: v, parsed: parsed});
            return parsed;
        }

        // Case: Unknown signature type
        parsed.isValid = false;
        return parsed;
    }

    /**
     * @dev Checks if a signature is valid for a given signer using ERC-1271.
     *      NOTE: Unlike ECDSA signatures, contract signatures are revocable, and the outcome
     *      of this function can change through time.
     * @param signer The contract address to verify the signature against
     * @param hash The hash that was signed
     * @param signature The signature bytes to verify
     * @return True if the contract returns the ERC-1271 magic value
     */
    function isValidERC1271SignatureNow(address signer, bytes32 hash, bytes memory signature)
        internal
        view
        returns (bool)
    {
        (bool success, bytes memory result) =
            signer.staticcall(abi.encodeCall(IERC1271.isValidSignature, (hash, signature)));
        return (success && result.length >= 32
                && abi.decode(result, (bytes32)) == bytes32(IERC1271.isValidSignature.selector));
    }

    // ==================== Internal Pure Functions ====================

    /**
     * @dev Gets the size of the first signature in an array.
     *      Useful for extracting initiator signature from combined signatures.
     * @param signatures The signatures bytes array
     * @return The size in bytes of the first signature (0 if invalid)
     */
    function getFirstSignatureSize(bytes memory signatures) internal pure returns (uint256) {
        // Case: Empty signatures
        if (signatures.length == 0) return 0;

        uint8 v = _getVByte(signatures, 0);

        // Case: ERC-1271 contract signature (v = 0)
        if (v == V_CONTRACT_SIGNATURE) {
            // Case: Not enough bytes for header
            if (signatures.length < CONTRACT_SIGNATURE_HEADER_SIZE) return 0;

            uint16 sigLength = _getContractSignatureLength(signatures, 0);
            return CONTRACT_SIGNATURE_HEADER_SIZE + sigLength;
        }

        // Case: EOA signature (v = 27 or 28)
        if (v == 27 || v == 28) {
            return EOA_SIGNATURE_SIZE;
        }

        // Case: Unknown signature type
        return 0;
    }

    /**
     * @dev Returns the number of signatures in a concatenated signatures array.
     *      NOTE: This function only works for fixed 65-byte EOA signatures.
     *      For hybrid format with variable-length signatures, use parseSignatureAtOffset.
     * @param signatures The concatenated signatures bytes
     * @return The number of 65-byte signatures contained in the array
     */
    function getSignatureCount(bytes memory signatures) internal pure returns (uint8) {
        return SafeCast.toUint8(signatures.length / SIGNATURE_LENGTH);
    }

    // ==================== Private View Functions ====================

    /**
     * @dev Validates an ERC-1271 contract signature against an expected signer
     * @param signature The signature bytes (23+N bytes: 0|signer|length|sig)
     * @param hash The hash that was signed
     * @param expectedSigner The expected signer address
     * @return True if the signature is valid and from expectedSigner
     */
    function _isContractSignatureValid(bytes memory signature, bytes32 hash, address expectedSigner)
        private
        view
        returns (bool)
    {
        // Case: Not enough bytes for header
        if (signature.length < CONTRACT_SIGNATURE_HEADER_SIZE) return false;

        address signer = _getContractSigner(signature, 0);

        // Case: Signer mismatch
        if (signer != expectedSigner) return false;

        uint16 sigLength = _getContractSignatureLength(signature, 0);

        // Case: Invalid total length
        if (signature.length != CONTRACT_SIGNATURE_HEADER_SIZE + sigLength) return false;

        // Extract the inner signature bytes
        bytes memory contractSig = _extractContractInnerSignature(signature, 0, sigLength);

        return isValidERC1271SignatureNow(signer, hash, contractSig);
    }

    /**
     * @dev Parses an ERC-1271 contract signature at a given offset
     * @param signatures The concatenated signatures array
     * @param offset The byte offset where this signature starts
     * @param hash The hash that was signed
     * @param parsed The ParsedSignature struct to populate
     */
    function _parseContractSignatureAtOffset(
        bytes memory signatures,
        uint256 offset,
        bytes32 hash,
        ParsedSignature memory parsed
    ) private view {
        // Case: Not enough bytes for header
        if (offset + CONTRACT_SIGNATURE_HEADER_SIZE > signatures.length) {
            parsed.isValid = false;
            return;
        }

        address signer = _getContractSigner(signatures, offset);
        parsed.signer = signer;

        uint16 sigLength = _getContractSignatureLength(signatures, offset);
        uint256 totalSize = CONTRACT_SIGNATURE_HEADER_SIZE + sigLength;

        // Case: Not enough bytes for full signature
        if (offset + totalSize > signatures.length) {
            parsed.isValid = false;
            return;
        }

        // Extract the inner signature bytes
        bytes memory contractSig = _extractContractInnerSignature(signatures, offset, sigLength);

        parsed.isValid = isValidERC1271SignatureNow(signer, hash, contractSig);
        parsed.nextOffset = offset + totalSize;
    }

    // ==================== Private Pure Functions ====================

    /**
     * @dev Extracts the v byte (signature type indicator) at a given offset.
     * @param data The bytes array to read from
     * @param offset The byte offset to read the v byte from
     * @return v The v byte value
     */
    function _getVByte(bytes memory data, uint256 offset) private pure returns (uint8 v) {
        assembly {
            v := byte(0, mload(add(add(data, 0x20), offset)))
        }
    }

    /**
     * @dev Extracts the signer address from a contract signature at a given offset.
     *      The signer is located at offset+1 (after the v byte) and is 20 bytes.
     * @param data The bytes array to read from
     * @param offset The byte offset where the signature starts (v byte position)
     * @return signer The 20-byte signer address
     */
    function _getContractSigner(bytes memory data, uint256 offset) private pure returns (address signer) {
        assembly {
            signer := shr(96, mload(add(add(data, 0x20), add(offset, 1))))
        }
    }

    /**
     * @dev Extracts the inner signature length from a contract signature at a given offset.
     *      The length is a 2-byte value located at offset+21 (after v byte and signer address).
     * @param data The bytes array to read from
     * @param offset The byte offset where the signature starts (v byte position)
     * @return sigLength The 2-byte inner signature length
     */
    function _getContractSignatureLength(bytes memory data, uint256 offset) private pure returns (uint16 sigLength) {
        assembly {
            sigLength := shr(240, mload(add(add(data, 0x20), add(offset, 21))))
        }
    }

    /**
     * @dev Extracts the inner signature bytes from a contract signature at a given offset.
     *      The inner signature starts at offset+23 (after v byte, signer address, and length).
     * @param data The bytes array to read from
     * @param offset The byte offset where the signature starts (v byte position)
     * @param sigLength The length of the inner signature to extract
     * @return contractSig The extracted inner signature bytes
     */
    function _extractContractInnerSignature(bytes memory data, uint256 offset, uint16 sigLength)
        private
        pure
        returns (bytes memory contractSig)
    {
        contractSig = new bytes(sigLength);
        assembly {
            let src := add(add(data, 0x20), add(offset, 23))
            let dst := add(contractSig, 0x20)
            for { let i := 0 } lt(i, sigLength) { i := add(i, 0x20) } { mstore(add(dst, i), mload(add(src, i))) }
        }
    }

    /**
     * @dev Validates an EOA signature against an expected signer
     * @param signature The signature bytes (65 bytes: v|r|s)
     * @param hash The hash that was signed
     * @param expectedSigner The expected signer address
     * @param v The v component already extracted
     * @return True if the signature is valid and from expectedSigner
     */
    function _isEOASignatureValid(bytes memory signature, bytes32 hash, address expectedSigner, uint8 v)
        private
        pure
        returns (bool)
    {
        // Case: Invalid signature length
        if (signature.length != EOA_SIGNATURE_SIZE) return false;

        bytes32 r;
        bytes32 s;
        assembly {
            r := mload(add(signature, 0x21))
            s := mload(add(signature, 0x41))
        }

        address recovered = ecrecover(hash, v, r, s);

        // Case: Recovery failed or signer mismatch
        return recovered != address(0) && recovered == expectedSigner;
    }

    /**
     * @dev Parses an EOA signature at a given offset
     * @param signatures The concatenated signatures array
     * @param offset The byte offset where this signature starts
     * @param hash The hash that was signed
     * @param v The v component already extracted
     * @param parsed The ParsedSignature struct to populate
     */
    function _parseEOASignatureAtOffset(
        bytes memory signatures,
        uint256 offset,
        bytes32 hash,
        uint8 v,
        ParsedSignature memory parsed
    ) private pure {
        // Case: Not enough bytes for EOA signature
        if (offset + EOA_SIGNATURE_SIZE > signatures.length) {
            parsed.isValid = false;
            return;
        }

        bytes32 r;
        bytes32 s;
        assembly {
            r := mload(add(add(signatures, 0x20), add(offset, 1)))
            s := mload(add(add(signatures, 0x20), add(offset, 33)))
        }

        address signer = ecrecover(hash, v, r, s);

        // Case: Recovery failed
        if (signer == address(0)) {
            parsed.isValid = false;
            return;
        }

        parsed.signer = signer;
        parsed.isValid = true;
        parsed.nextOffset = offset + EOA_SIGNATURE_SIZE;
    }
}
