// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";

/**
 * @dev SignatureTestHelpers
 *      Shared helper utilities for building EOA and ERC-1271 signatures in tests.
 */
abstract contract SignatureTestHelpers is Test {
    /// @dev secp256k1 curve order (n). Used for malleability calculations.
    uint256 internal constant SECP256K1_CURVE_ORDER =
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;

    /// @dev Half of secp256k1 curve order. Signatures with s > this are malleable.
    uint256 internal constant HALF_CURVE_ORDER = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0;

    /**
     * @dev Creates a valid EOA signature for `hash` using `privateKey`.
     *      Returns the signature in the library's format: v (1 byte) | r (32 bytes) | s (32 bytes).
     *      If vm.sign produces s in the upper half of the curve, it is normalized to the lower half.
     * @param privateKey The secp256k1 private key to sign with
     * @param hash The hash to sign
     * @return The 65-byte signature (v | r | s)
     */
    function _signHash(uint256 privateKey, bytes32 hash) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hash);

        // Normalize s to lower half of curve order if needed (vm.sign may return high s)
        if (uint256(s) > HALF_CURVE_ORDER) {
            s = bytes32(SECP256K1_CURVE_ORDER - uint256(s));
            v = v == 27 ? 28 : 27;
        }

        return abi.encodePacked(v, r, s);
    }

    /**
     * @dev Creates a malleable (high-s) signature. Takes a valid signature and flips s
     *      to the upper half of the curve: s' = secp256k1.n - s.
     * @param privateKey The secp256k1 private key to sign with
     * @param hash The hash to sign
     * @return The malleable 65-byte signature (v | r | s')
     */
    function _makeHighSSignature(uint256 privateKey, bytes32 hash) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hash);

        // If s is already in the upper half, just return as-is
        if (uint256(s) > HALF_CURVE_ORDER) {
            return abi.encodePacked(v, r, s);
        }

        // Now flip s to the upper half
        s = bytes32(SECP256K1_CURVE_ORDER - uint256(s));
        v = v == 27 ? 28 : 27;

        return abi.encodePacked(v, r, s);
    }

    /**
     * @dev Creates a signature where s is exactly at the boundary (HALF_CURVE_ORDER).
     *      This is the maximum acceptable s value.
     * @param privateKey The secp256k1 private key to sign with
     * @param hash The hash to sign
     * @return The 65-byte signature with s = HALF_CURVE_ORDER
     */
    function _makeBoundarySSignature(uint256 privateKey, bytes32 hash) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r,) = vm.sign(privateKey, hash);

        // Force s to be exactly HALF_CURVE_ORDER
        bytes32 boundaryS = bytes32(HALF_CURVE_ORDER);

        // Normalize v to canonical EOA values (27/28). SignatureUtils treats v=0 as contract-signature
        // type marker, and only accepts 27/28 for EOA signatures; this keeps the test focused on s bounds.
        if (uint256(v) < 27) {
            v += 27;
        }

        return abi.encodePacked(v, r, boundaryS);
    }

    /**
     * @dev Creates a signature where s is exactly HALF_CURVE_ORDER + 1 (one above boundary).
     *      This should be rejected by the malleability check.
     * @param privateKey The secp256k1 private key to sign with
     * @param hash The hash to sign
     * @return The 65-byte signature with s = HALF_CURVE_ORDER + 1
     */
    function _makeBoundaryPlusOneSSignature(uint256 privateKey, bytes32 hash) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r,) = vm.sign(privateKey, hash);

        // Force s to be HALF_CURVE_ORDER + 1
        bytes32 aboveBoundaryS = bytes32(HALF_CURVE_ORDER + 1);

        // Normalize v to canonical EOA values (27/28). SignatureUtils treats v=0 as contract-signature
        // type marker, and only accepts 27/28 for EOA signatures; this keeps the test focused on s bounds.
        if (uint256(v) < 27) {
            v += 27;
        }

        return abi.encodePacked(v, r, aboveBoundaryS);
    }

    /**
     * @dev Finds a valid canonical EOA signature with an explicit `v` value (27 or 28) by
     *      signing deterministic hash variants derived from `seedHash`.
     * @param privateKey The secp256k1 private key used for signing
     * @param desiredV The target recovery id to enforce (must be 27 or 28)
     * @param seedHash Base hash used to derive deterministic candidate hashes
     * @return signature A valid 65-byte signature (v | r | s) with v == desiredV
     * @return hash The candidate hash that produced `signature`
     */
    function _findValidSignatureForV(uint256 privateKey, uint8 desiredV, bytes32 seedHash)
        internal
        pure
        returns (bytes memory signature, bytes32 hash)
    {
        require(desiredV == 27 || desiredV == 28, "desiredV must be 27 or 28");

        for (uint256 i = 0; i < 256; i++) {
            hash = keccak256(abi.encodePacked(seedHash, desiredV, i));
            signature = _signHash(privateKey, hash);
            if (uint8(signature[0]) == desiredV) {
                return (signature, hash);
            }
        }

        revert("Failed to find signature with desired v");
    }

    /**
     * @dev Builds an ERC-1271 contract signature in the library's format:
     *      | 0x00 (1 byte) | signer address (20 bytes) | inner sig length (2 bytes) | inner sig (N bytes) |
     * @param signer The contract address that will validate the signature
     * @param innerSig The inner signature bytes passed to isValidSignature
     * @return The encoded contract signature
     */
    function _buildContractSignature(address signer, bytes memory innerSig) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(0), signer, uint16(innerSig.length), innerSig);
    }

    /**
     * @dev Concatenates an array of signature byte arrays into a single bytes array.
     *      Used for multi-signature testing where multiple signatures are packed together.
     * @param sigs Array of signature byte arrays to concatenate
     * @return result The concatenated signature bytes
     */
    function _concatSignatures(bytes[] memory sigs) internal pure returns (bytes memory result) {
        for (uint256 i = 0; i < sigs.length; i++) {
            result = abi.encodePacked(result, sigs[i]);
        }
    }
}
