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
    /// @dev ERC-1271 magic value returned when signature is valid.
    /// Equals bytes4(keccak256("isValidSignature(bytes32,bytes)")) = 0x1626ba7e
    bytes4 internal constant ERC1271_MAGIC_VALUE = IERC1271.isValidSignature.selector;

    /// @dev Value returned when signature validation fails per ERC-1271 standard
    bytes4 internal constant ERC1271_INVALID_VALUE = 0xffffffff;

    /// @dev EOA signature size: v (1) + r (32) + s (32) = 65 bytes
    uint256 internal constant EOA_SIGNATURE_SIZE = 65;

    /// @dev ERC-1271 signature header size: v (1) + signer (20) + length (2) = 23 bytes
    uint256 internal constant CONTRACT_SIGNATURE_HEADER_SIZE = 23;

    /// @dev v value indicating an ERC-1271 contract signature
    uint8 internal constant V_CONTRACT_SIGNATURE = 0;

    /// @dev Half of the secp256k1 curve order, used for signature malleability check.
    ///      Signatures with s > HALF_CURVE_ORDER are rejected to prevent malleability.
    ///      See EIP-2 and OpenZeppelin ECDSA for details.
    uint256 private constant _HALF_CURVE_ORDER = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0;

    /// @dev Thrown when signature recovery fails (invalid format, length, malleability, or validation)
    error SignatureRecoveryFailed();

    /**
     * @dev Recovers the signer from a single signature (EOA or ERC-1271).
     *      Reverts if the signature is invalid.
     * @param signature A single signature (65 bytes EOA or 23+N bytes ERC-1271)
     * @param hash The hash that was signed
     * @return signer The recovered signer address
     */
    function recoverSignerOrRevert(bytes memory signature, bytes32 hash) internal view returns (address signer) {
        bool success;
        (success, signer) = tryRecoverSigner(signature, hash);
        if (!success) {
            revert SignatureRecoveryFailed();
        }
    }

    /**
     * @dev Attempts to recover the signer from a single signature (EOA or ERC-1271).
     *      Returns false instead of reverting on failure.
     * @param signature A single signature (65 bytes EOA or 23+N bytes ERC-1271)
     * @param hash The hash that was signed
     * @return success True if recovery succeeded
     * @return signer The recovered signer address (address(0) if failed)
     */
    function tryRecoverSigner(bytes memory signature, bytes32 hash)
        internal
        view
        returns (bool success, address signer)
    {
        // Case: Empty signature
        if (signature.length == 0) {
            return (false, address(0));
        }

        uint8 v = _getVByte(signature, 0);

        // Case: ERC-1271 contract signature (v = 0)
        if (v == V_CONTRACT_SIGNATURE) {
            return _tryRecoverContractSigner(signature, 0, hash);
        }

        // Case: EOA signature (v = 27 or 28)
        if (v == 27 || v == 28) {
            // Verify exact length for single EOA signature
            if (signature.length != EOA_SIGNATURE_SIZE) {
                return (false, address(0));
            }
            return _tryRecoverEOASigner(signature, 0, hash, v);
        }

        // Case: Unknown signature type
        return (false, address(0));
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
        bool success;
        (success, signer, nextOffset) = tryRecoverSignerAtOffset(signatures, offset, hash);
        if (!success) {
            revert SignatureRecoveryFailed();
        }
    }

    /**
     * @dev Attempts to recover the signer from a signature at the given offset.
     *      Returns false instead of reverting on failure.
     *      Used for iterating through multiple signatures with a for-loop.
     * @param signatures The concatenated signatures array
     * @param offset The byte offset where this signature starts
     * @param hash The hash that was signed (needed for ECDSA recovery)
     * @return success True if recovery succeeded
     * @return signer The recovered signer address (address(0) if failed)
     * @return nextOffset The byte offset to the next signature
     */
    function tryRecoverSignerAtOffset(bytes memory signatures, uint256 offset, bytes32 hash)
        internal
        view
        returns (bool success, address signer, uint256 nextOffset)
    {
        // Case: Offset beyond signatures array
        if (offset >= signatures.length) {
            return (false, address(0), 0);
        }

        uint8 v = _getVByte(signatures, offset);

        // Case: ERC-1271 contract signature (v = 0)
        if (v == V_CONTRACT_SIGNATURE) {
            (success, signer) = _tryRecoverContractSigner(signatures, offset, hash);
            if (!success) {
                return (false, address(0), 0);
            }
            uint16 sigLength = _getContractSignatureLength(signatures, offset);
            nextOffset = offset + CONTRACT_SIGNATURE_HEADER_SIZE + sigLength;
            return (true, signer, nextOffset);
        }

        // Case: EOA signature (v = 27 or 28)
        if (v == 27 || v == 28) {
            (success, signer) = _tryRecoverEOASigner(signatures, offset, hash, v);
            if (!success) {
                return (false, address(0), 0);
            }
            nextOffset = offset + EOA_SIGNATURE_SIZE;
            return (true, signer, nextOffset);
        }

        // Case: Unknown signature type
        return (false, address(0), 0);
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
    // forge-lint: disable-next-line(mixed-case-function)
    function _isValidERC1271SignatureNow(address signer, bytes32 hash, bytes memory signature)
        internal
        view
        returns (bool)
    {
        (bool success, bytes memory result) =
            signer.staticcall(abi.encodeCall(IERC1271.isValidSignature, (hash, signature)));
        return (success && result.length == 32 && abi.decode(result, (bytes32)) == bytes32(ERC1271_MAGIC_VALUE));
    }

    /**
     * @dev Attempts to recover signer from an ERC-1271 contract signature at a given offset.
     *      Returns false instead of reverting on failure.
     * @param signatures The concatenated signatures array
     * @param offset The byte offset where this signature starts
     * @param hash The hash that was signed
     * @return success True if recovery and validation succeeded
     * @return signer The recovered signer address (address(0) if failed)
     */
    function _tryRecoverContractSigner(bytes memory signatures, uint256 offset, bytes32 hash)
        internal
        view
        returns (bool success, address signer)
    {
        // Case: Not enough bytes for header
        if (offset + CONTRACT_SIGNATURE_HEADER_SIZE > signatures.length) {
            return (false, address(0));
        }

        signer = _getContractSigner(signatures, offset);
        uint16 sigLength = _getContractSignatureLength(signatures, offset);
        uint256 totalSize = CONTRACT_SIGNATURE_HEADER_SIZE + sigLength;

        // Case: Not enough bytes for full signature
        if (offset + totalSize > signatures.length) {
            return (false, address(0));
        }

        // Extract the inner signature bytes
        bytes memory contractSig = _extractContractInnerSignature(signatures, offset, sigLength);

        // Validate the signature
        if (!_isValidERC1271SignatureNow(signer, hash, contractSig)) {
            return (false, address(0));
        }

        return (true, signer);
    }

    /**
     * @dev Attempts to recover signer from an EOA signature at a given offset.
     *      Returns false instead of reverting on failure.
     * @param signatures The concatenated signatures array
     * @param offset The byte offset where this signature starts
     * @param hash The hash that was signed
     * @param v The v component already extracted
     * @return success True if recovery succeeded
     * @return signer The recovered signer address (address(0) if failed)
     */
    // forge-lint: disable-next-line(mixed-case-function)
    function _tryRecoverEOASigner(bytes memory signatures, uint256 offset, bytes32 hash, uint8 v)
        internal
        pure
        returns (bool success, address signer)
    {
        // Case: Not enough bytes for EOA signature
        if (offset + EOA_SIGNATURE_SIZE > signatures.length) {
            return (false, address(0));
        }

        bytes32 r;
        bytes32 s;
        assembly {
            r := mload(add(add(signatures, 0x20), add(offset, 1)))
            s := mload(add(add(signatures, 0x20), add(offset, 33)))
        }

        // Case: Malleable signature (s in upper half of curve order)
        if (uint256(s) > _HALF_CURVE_ORDER) {
            return (false, address(0));
        }

        signer = ecrecover(hash, v, r, s);

        // Case: Recovery failed
        if (signer == address(0)) {
            return (false, address(0));
        }

        return (true, signer);
    }

    /**
     * @dev Extracts the v byte (signature type indicator) at a given offset.
     * @param data The bytes array to read from
     * @param offset The byte offset to read the v byte from
     * @return v The v byte value
     */
    function _getVByte(bytes memory data, uint256 offset) internal pure returns (uint8 v) {
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
    function _getContractSigner(bytes memory data, uint256 offset) internal pure returns (address signer) {
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
    function _getContractSignatureLength(bytes memory data, uint256 offset) internal pure returns (uint16 sigLength) {
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
        internal
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
