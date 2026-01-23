// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";
import {SignatureUtils} from "libraries/SignatureUtils.sol";
import {LibOrganizationSignatures} from "organization/libraries/LibOrganizationSignatures.sol";

/**
 * @title LibOrganizationSignaturesHarness
 * @dev Test harness to expose internal library functions for testing
 */
contract LibOrganizationSignaturesHarness {
    function extractReviewSignatures(bytes memory signatures) external pure returns (bytes memory) {
        return LibOrganizationSignatures.extractReviewSignatures(signatures);
    }
}

/**
 * @title LibOrganizationSignaturesTest
 * @notice Comprehensive tests for LibOrganizationSignatures.extractReviewSignatures
 * @dev These tests verify the custom _sliceFrom implementation that replaces OpenZeppelin's
 *      Bytes.slice (which uses mcopy) for Paris EVM compatibility.
 *
 *      The tests are particularly important because previous hand-rolled implementations
 *      had bugs related to the 65-byte signature boundary. Key areas tested:
 *      - Edge cases (empty, boundary conditions)
 *      - Signature boundaries (exact multiples of 65 bytes)
 *      - Data integrity (no garbage bytes included)
 *      - Partial word handling (65 mod 32 = 1, so there's always a partial word)
 *
 * @author Den Technologies Inc
 */
contract LibOrganizationSignaturesTest is Test {
    LibOrganizationSignaturesHarness public harness;

    /// @dev Signature length constant (65 bytes: r=32, s=32, v=1)
    uint256 constant SIGNATURE_LENGTH = 65;

    function setUp() public {
        harness = new LibOrganizationSignaturesHarness();
    }

    // ============================================================
    // Edge Cases
    // ============================================================

    function test_extractReviewSignatures_emptyArray_returnsEmpty() public view {
        bytes memory empty = new bytes(0);
        bytes memory result = harness.extractReviewSignatures(empty);

        assertEq(result.length, 0, "Empty input should return empty output");
    }

    function test_extractReviewSignatures_lessThan65Bytes_returnsEmpty() public view {
        // Test with partial EOA signature (valid v value but incomplete signature)
        // The hybrid format requires a complete signature to be valid
        for (uint256 len = 1; len < SIGNATURE_LENGTH; len++) {
            bytes memory input = new bytes(len);
            // Set first byte to valid v value (27)
            input[0] = bytes1(uint8(27));
            bytes memory result = harness.extractReviewSignatures(input);

            assertEq(result.length, 0, string.concat("Input of length ", vm.toString(len), " should return empty"));
        }
    }

    function test_extractReviewSignatures_exactly65Bytes_returnsEmpty() public view {
        bytes memory oneSignature = _createSignaturePattern(1);
        assertEq(oneSignature.length, SIGNATURE_LENGTH, "Test setup: should be exactly 65 bytes");

        bytes memory result = harness.extractReviewSignatures(oneSignature);

        assertEq(result.length, 0, "Exactly 65 bytes (one signature) should return empty");
    }

    // ============================================================
    // Signature Boundary Tests (CRITICAL - previous bugs were here)
    // ============================================================

    function test_extractReviewSignatures_twoSignatures_returnsSecond() public view {
        bytes memory twoSignatures = _createSignaturePattern(2);
        assertEq(twoSignatures.length, 130, "Test setup: should be 130 bytes");

        bytes memory result = harness.extractReviewSignatures(twoSignatures);

        assertEq(result.length, 65, "Should return exactly 65 bytes for second signature");

        // Verify the returned bytes match the second signature exactly
        bytes memory expectedSecondSig = _extractExpectedSlice(twoSignatures, SIGNATURE_LENGTH);
        assertEq(result, expectedSecondSig, "Returned bytes should match second signature exactly");
    }

    function test_extractReviewSignatures_threeSignatures_returnsLastTwo() public view {
        bytes memory threeSignatures = _createSignaturePattern(3);
        assertEq(threeSignatures.length, 195, "Test setup: should be 195 bytes");

        bytes memory result = harness.extractReviewSignatures(threeSignatures);

        assertEq(result.length, 130, "Should return exactly 130 bytes for two signatures");

        // Verify byte-by-byte
        bytes memory expected = _extractExpectedSlice(threeSignatures, SIGNATURE_LENGTH);
        assertEq(result, expected, "Returned bytes should match signatures 2 and 3");
    }

    function test_extractReviewSignatures_fourSignatures_returnsLastThree() public view {
        bytes memory fourSignatures = _createSignaturePattern(4);
        assertEq(fourSignatures.length, 260, "Test setup: should be 260 bytes");

        bytes memory result = harness.extractReviewSignatures(fourSignatures);

        assertEq(result.length, 195, "Should return exactly 195 bytes for three signatures");

        // Verify byte-by-byte
        bytes memory expected = _extractExpectedSlice(fourSignatures, SIGNATURE_LENGTH);
        assertEq(result, expected, "Returned bytes should match signatures 2, 3, and 4");
    }

    // ============================================================
    // Data Integrity Tests
    // ============================================================

    function test_extractReviewSignatures_dataIntegrity_noGarbageBytes() public view {
        // Create signatures with a known pattern
        bytes memory signatures = _createSignaturePattern(3);

        bytes memory result = harness.extractReviewSignatures(signatures);

        // Verify each byte matches expected value
        for (uint256 i = 0; i < result.length; i++) {
            uint256 originalIndex = SIGNATURE_LENGTH + i;
            assertEq(
                uint8(result[i]),
                uint8(signatures[originalIndex]),
                string.concat("Byte mismatch at index ", vm.toString(i))
            );
        }
    }

    function test_extractReviewSignatures_dataIntegrity_lastByte() public view {
        // This test is critical for the partial word handling
        // 65 bytes mod 32 = 1, so there's always exactly 1 remaining byte
        bytes memory twoSignatures = _createSignaturePattern(2);

        bytes memory result = harness.extractReviewSignatures(twoSignatures);

        // Verify the very last byte is correct (this is the partial word case)
        uint256 lastIndex = result.length - 1;
        uint256 originalLastIndex = twoSignatures.length - 1;

        assertEq(
            uint8(result[lastIndex]), uint8(twoSignatures[originalLastIndex]), "Last byte should match (partial word)"
        );
    }

    function test_extractReviewSignatures_dataIntegrity_allBytesUnique() public pure {
        // Create two valid EOA signatures where r and s bytes are unique
        bytes memory signatures = new bytes(130);

        // First signature: v=27, then r|s with unique bytes
        signatures[0] = bytes1(uint8(27));
        for (uint256 i = 1; i < 65; i++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            signatures[i] = bytes1(uint8(i)); // Safe: i is bounded to 1-64
        }

        // Second signature: v=28, then r|s with unique bytes
        signatures[65] = bytes1(uint8(28));
        for (uint256 i = 66; i < 130; i++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            signatures[i] = bytes1(uint8(i)); // Safe: i is bounded to 66-129
        }

        bytes memory result = LibOrganizationSignatures.extractReviewSignatures(signatures);

        // Verify each byte in result matches the corresponding byte in original signatures
        // The result is the second signature (starting at offset 65)
        for (uint256 i = 0; i < result.length; i++) {
            assertEq(
                uint8(result[i]),
                uint8(signatures[65 + i]),
                string.concat("Byte ", vm.toString(i), " should match original at index ", vm.toString(65 + i))
            );
        }
    }

    // ============================================================
    // Partial Word Boundary Tests
    // ============================================================

    function test_extractReviewSignatures_partialWord_oneRemainingByte() public view {
        // 65 bytes result: 65 mod 32 = 1 remaining byte
        bytes memory twoSignatures = _createSignaturePattern(2);
        bytes memory result = harness.extractReviewSignatures(twoSignatures);

        assertEq(result.length, 65, "Should be 65 bytes");
        assertEq(result.length % 32, 1, "Should have 1 remaining byte after full words");

        // Verify the partial byte is correct
        _verifySliceCorrectness(twoSignatures, result, SIGNATURE_LENGTH);
    }

    function test_extractReviewSignatures_partialWord_twoRemainingBytes() public view {
        // 130 bytes result: 130 mod 32 = 2 remaining bytes
        bytes memory threeSignatures = _createSignaturePattern(3);
        bytes memory result = harness.extractReviewSignatures(threeSignatures);

        assertEq(result.length, 130, "Should be 130 bytes");
        assertEq(result.length % 32, 2, "Should have 2 remaining bytes after full words");

        _verifySliceCorrectness(threeSignatures, result, SIGNATURE_LENGTH);
    }

    function test_extractReviewSignatures_partialWord_threeRemainingBytes() public view {
        // 195 bytes result: 195 mod 32 = 3 remaining bytes
        bytes memory fourSignatures = _createSignaturePattern(4);
        bytes memory result = harness.extractReviewSignatures(fourSignatures);

        assertEq(result.length, 195, "Should be 195 bytes");
        assertEq(result.length % 32, 3, "Should have 3 remaining bytes after full words");

        _verifySliceCorrectness(fourSignatures, result, SIGNATURE_LENGTH);
    }

    // ============================================================
    // Fuzz Tests
    // ============================================================

    function testFuzz_extractReviewSignatures_lengthCorrectness(uint8 signatureCount) public view {
        // Bound to reasonable range (1-10 signatures)
        signatureCount = uint8(bound(signatureCount, 1, 10));

        bytes memory signatures = _createSignaturePattern(signatureCount);
        bytes memory result = harness.extractReviewSignatures(signatures);

        if (signatureCount <= 1) {
            assertEq(result.length, 0, "Should return empty for 0 or 1 signatures");
        } else {
            uint256 expectedLength = (signatureCount - 1) * SIGNATURE_LENGTH;
            assertEq(result.length, expectedLength, "Length should be (count-1) * 65");
        }
    }

    function testFuzz_extractReviewSignatures_dataIntegrity(uint8 signatureCount) public view {
        // Bound to 2-10 signatures (need at least 2 for meaningful test)
        signatureCount = uint8(bound(signatureCount, 2, 10));

        bytes memory signatures = _createSignaturePattern(signatureCount);
        bytes memory result = harness.extractReviewSignatures(signatures);

        // Verify every byte matches
        _verifySliceCorrectness(signatures, result, SIGNATURE_LENGTH);
    }

    function testFuzz_extractReviewSignatures_arbitrarySignatureCount(uint8 signatureCount) public view {
        // Test with various valid signature counts (1-15)
        signatureCount = uint8(bound(signatureCount, 1, 15));

        bytes memory signatures = _createSignaturePattern(signatureCount);
        bytes memory result = harness.extractReviewSignatures(signatures);

        if (signatureCount == 1) {
            assertEq(result.length, 0, "Should return empty for single signature");
        } else {
            uint256 expectedLength = (signatureCount - 1) * SIGNATURE_LENGTH;
            assertEq(result.length, expectedLength, "Length should be (count-1) * 65");

            // Verify data integrity
            for (uint256 i = 0; i < result.length; i++) {
                uint256 originalIndex = SIGNATURE_LENGTH + i;
                assertEq(
                    uint8(result[i]),
                    uint8(signatures[originalIndex]),
                    string.concat("Byte mismatch at index ", vm.toString(i))
                );
            }
        }
    }

    // ============================================================
    // Helper Functions
    // ============================================================

    /**
     * @dev Creates a bytes array with valid EOA signature patterns for the specified number of signatures.
     *      Each signature is 65 bytes in hybrid format: v (1) | r (32) | s (32)
     *      The v byte is set to 27 or 28 to indicate a valid EOA signature.
     *      The r and s bytes are filled with predictable patterns for verification.
     */
    function _createSignaturePattern(uint256 signatureCount) internal pure returns (bytes memory) {
        bytes memory result = new bytes(signatureCount * SIGNATURE_LENGTH);

        for (uint256 sigIndex = 0; sigIndex < signatureCount; sigIndex++) {
            uint256 baseOffset = sigIndex * SIGNATURE_LENGTH;

            // First byte is v (27 or 28) - alternating for variety
            result[baseOffset] = bytes1(uint8(27 + (sigIndex % 2)));

            // Fill r (32 bytes) and s (32 bytes) with predictable pattern
            for (uint256 i = 1; i < SIGNATURE_LENGTH; i++) {
                // forge-lint: disable-next-line(unsafe-typecast)
                result[baseOffset + i] = bytes1(uint8((baseOffset + i) % 256));
            }
        }

        return result;
    }

    /**
     * @dev Extracts a slice from `data` starting at `start` to the end using pure Solidity.
     *      Used as reference implementation for comparison.
     */
    function _extractExpectedSlice(bytes memory data, uint256 start) internal pure returns (bytes memory) {
        if (start >= data.length) {
            return new bytes(0);
        }

        uint256 len = data.length - start;
        bytes memory result = new bytes(len);

        for (uint256 i = 0; i < len; i++) {
            result[i] = data[start + i];
        }

        return result;
    }

    /**
     * @dev Verifies that `result` is the correct slice of `original` starting at `start`.
     *      Checks both length and byte-by-byte content.
     */
    function _verifySliceCorrectness(bytes memory original, bytes memory result, uint256 start) internal pure {
        uint256 expectedLength = original.length > start ? original.length - start : 0;
        assertEq(result.length, expectedLength, "Slice length mismatch");

        for (uint256 i = 0; i < result.length; i++) {
            assertEq(
                uint8(result[i]),
                uint8(original[start + i]),
                string.concat("Byte mismatch at position ", vm.toString(i))
            );
        }
    }
}
