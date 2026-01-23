// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";

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
 *      Two validation functions:
 *      - recoverSignerOrRevert(): For single-signature cases
 *      - recoverSignerAtOffsetOrRevert(): For multi-signature iteration
 *
 *      Both functions revert on invalid signatures rather than returning false.
 *      Signatures are simply concatenated. No offset calculation needed off-chain.
 *
 * @author Den Technologies Inc
 */
library SignatureUtils {
    // ==================== Constants ====================

    /// @dev EOA signature size: v (1) + r (32) + s (32) = 65 bytes
    uint256 internal constant EOA_SIGNATURE_SIZE = 65;

    /// @dev ERC-1271 signature header size: v (1) + signer (20) + length (2) = 23 bytes
    uint256 internal constant CONTRACT_SIGNATURE_HEADER_SIZE = 23;

    /// @dev v value indicating an ERC-1271 contract signature
    uint8 internal constant V_CONTRACT_SIGNATURE = 0;

    /// @dev Legacy constant for backwards compatibility
    uint256 internal constant SIGNATURE_LENGTH = 65;

    /// @dev Half of the secp256k1 curve order, used for signature malleability check.
    ///      Signatures with s > HALF_CURVE_ORDER are rejected to prevent malleability.
    ///      See EIP-2 and OpenZeppelin ECDSA for details.
    uint256 private constant _HALF_CURVE_ORDER = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0;

    // ==================== Custom Errors ====================

    /// @dev Thrown when a signature has an invalid format or type
    error InvalidSignature();

    /// @dev Thrown when a signature has an invalid length
    error InvalidSignatureLength();

    /// @dev Thrown when a signature has malleable s value (s > half curve order)
    error SignatureMalleability();

    /// @dev Thrown when ECDSA recovery returns address(0)
    error ECDSARecoveryFailed();

    /// @dev Thrown when ERC-1271 validation fails for a contract signer
    error ERC1271ValidationFailed(address signer);

    // ==================== Internal View Functions ====================

    /**
     * @dev Recovers the signer from a single signature (EOA or ERC-1271).
     *      Reverts if the signature is invalid.
     * @param signature A single signature (65 bytes EOA or 23+N bytes ERC-1271)
     * @param hash The hash that was signed
     * @return signer The recovered signer address
     */
    function recoverSignerOrRevert(bytes memory signature, bytes32 hash) internal view returns (address signer) {
        // Case: Empty signature
        if (signature.length == 0) {
            revert InvalidSignatureLength();
        }

        uint8 v = _getVByte(signature, 0);

        // Case: ERC-1271 contract signature (v = 0)
        if (v == V_CONTRACT_SIGNATURE) {
            return _recoverContractSignerOrRevert(signature, 0, hash);
        }

        // Case: EOA signature (v = 27 or 28)
        if (v == 27 || v == 28) {
            // Verify exact length for single EOA signature
            if (signature.length != EOA_SIGNATURE_SIZE) {
                revert InvalidSignatureLength();
            }
            return _recoverEOASignerOrRevert(signature, 0, hash, v);
        }

        // Case: Unknown signature type
        revert InvalidSignature();
    }

    /**
     * @dev Recovers the signer from a signature at the given offset.
     *      Used for iterating through multiple signatures with a for-loop.
     *      Reverts if the signature is invalid.
     * @param signatures The concatenated signatures array
     * @param offset The byte offset where this signature starts
     * @param hash The hash that was signed (needed for ECDSA recovery)
     * @return signer The recovered signer address
     * @return nextOffset The byte offset to the next signature
     */
    function recoverSignerAtOffsetOrRevert(bytes memory signatures, uint256 offset, bytes32 hash)
        internal
        view
        returns (address signer, uint256 nextOffset)
    {
        // Case: Offset beyond signatures array
        if (offset >= signatures.length) {
            revert InvalidSignatureLength();
        }

        uint8 v = _getVByte(signatures, offset);

        // Case: ERC-1271 contract signature (v = 0)
        if (v == V_CONTRACT_SIGNATURE) {
            signer = _recoverContractSignerOrRevert(signatures, offset, hash);
            uint16 sigLength = _getContractSignatureLength(signatures, offset);
            nextOffset = offset + CONTRACT_SIGNATURE_HEADER_SIZE + sigLength;
            return (signer, nextOffset);
        }

        // Case: EOA signature (v = 27 or 28)
        if (v == 27 || v == 28) {
            signer = _recoverEOASignerOrRevert(signatures, offset, hash, v);
            nextOffset = offset + EOA_SIGNATURE_SIZE;
            return (signer, nextOffset);
        }

        // Case: Unknown signature type
        revert InvalidSignature();
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

    // ==================== Private View Functions ====================

    /**
     * @dev Checks if a signature is valid for a given signer using ERC-1271.
     *      NOTE: Unlike ECDSA signatures, contract signatures are revocable, and the outcome
     *      of this function can change through time.
     * @param signer The contract address to verify the signature against
     * @param hash The hash that was signed
     * @param signature The signature bytes to verify
     * @return True if the contract returns the ERC-1271 magic value
     */
    function _isValidERC1271SignatureNow(address signer, bytes32 hash, bytes memory signature)
        private
        view
        returns (bool)
    {
        (bool success, bytes memory result) =
            signer.staticcall(abi.encodeCall(IERC1271.isValidSignature, (hash, signature)));
        return (success && result.length >= 32
                && abi.decode(result, (bytes32)) == bytes32(IERC1271.isValidSignature.selector));
    }

    /**
     * @dev Recovers signer from an ERC-1271 contract signature at a given offset.
     *      Reverts if the signature is invalid.
     * @param signatures The concatenated signatures array
     * @param offset The byte offset where this signature starts
     * @param hash The hash that was signed
     * @return signer The recovered signer address
     */
    function _recoverContractSignerOrRevert(bytes memory signatures, uint256 offset, bytes32 hash)
        private
        view
        returns (address signer)
    {
        // Case: Not enough bytes for header
        if (offset + CONTRACT_SIGNATURE_HEADER_SIZE > signatures.length) {
            revert InvalidSignatureLength();
        }

        signer = _getContractSigner(signatures, offset);
        uint16 sigLength = _getContractSignatureLength(signatures, offset);
        uint256 totalSize = CONTRACT_SIGNATURE_HEADER_SIZE + sigLength;

        // Case: Not enough bytes for full signature
        if (offset + totalSize > signatures.length) {
            revert InvalidSignatureLength();
        }

        // Extract the inner signature bytes
        bytes memory contractSig = _extractContractInnerSignature(signatures, offset, sigLength);

        // Validate the signature
        if (!_isValidERC1271SignatureNow(signer, hash, contractSig)) {
            revert ERC1271ValidationFailed(signer);
        }
    }

    /**
     * @dev Recovers signer from an EOA signature at a given offset.
     *      Reverts if the signature is invalid.
     * @param signatures The concatenated signatures array
     * @param offset The byte offset where this signature starts
     * @param hash The hash that was signed
     * @param v The v component already extracted
     * @return signer The recovered signer address
     */
    function _recoverEOASignerOrRevert(bytes memory signatures, uint256 offset, bytes32 hash, uint8 v)
        private
        pure
        returns (address signer)
    {
        // Case: Not enough bytes for EOA signature
        if (offset + EOA_SIGNATURE_SIZE > signatures.length) {
            revert InvalidSignatureLength();
        }

        bytes32 r;
        bytes32 s;
        assembly {
            r := mload(add(add(signatures, 0x20), add(offset, 1)))
            s := mload(add(add(signatures, 0x20), add(offset, 33)))
        }

        // Case: Malleable signature (s in upper half of curve order)
        if (uint256(s) > _HALF_CURVE_ORDER) {
            revert SignatureMalleability();
        }

        signer = ecrecover(hash, v, r, s);

        // Case: Recovery failed
        if (signer == address(0)) {
            revert ECDSARecoveryFailed();
        }
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
}
