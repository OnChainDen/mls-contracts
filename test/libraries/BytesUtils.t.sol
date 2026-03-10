// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";

import {BytesUtils} from "libraries/BytesUtils.sol";

/**
 * @dev BytesUtilsHarness
 *      Test harness to expose internal library functions for testing
 */
contract BytesUtilsHarness {
    function sliceFrom(bytes memory buffer, uint256 startIndex) external pure returns (bytes memory) {
        return BytesUtils.sliceFrom(buffer, startIndex);
    }

    function sliceRange(bytes memory buffer, uint256 startIndex, uint256 length) external pure returns (bytes memory) {
        return BytesUtils.sliceRange(buffer, startIndex, length);
    }
}

/**
 * @dev BytesUtilsTest
 *      Comprehensive tests for BytesUtils slicing functions
 *      These tests verify the custom slicing implementations that avoid the mcopy opcode
 *      for Paris EVM compatibility (replacing OpenZeppelin's Bytes.slice which uses mcopy).
 *
 *      Key areas tested:
 *      - Edge cases (empty, boundary conditions, invalid ranges)
 *      - Data integrity (no garbage bytes included)
 *      - Partial word handling (various remainder values when length mod 32)
 *      - Fuzz testing for arbitrary inputs
 *
 * @author Den Technologies Inc
 */
contract BytesUtilsTest is Test {
    BytesUtilsHarness public harness;

    /// @dev Signature length constant (65 bytes: r=32, s=32, v=1) - useful for testing signature-related scenarios
    uint256 constant SIGNATURE_LENGTH = 65;

    function setUp() public {
        harness = new BytesUtilsHarness();
    }

    /**
     * @dev Creates a bytes array with a known pattern where each byte equals its index mod 256.
     *      This ensures each byte is predictable and verifiable.
     */
    function _createPattern(uint256 length) internal pure returns (bytes memory) {
        bytes memory result = new bytes(length);

        for (uint256 i = 0; i < result.length; i++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            result[i] = bytes1(uint8(i % 256)); // Safe: modulo 256 ensures value fits in uint8
        }

        return result;
    }

    /**
     * @dev Extracts a slice from `data` starting at `start` to the end using pure Solidity.
     *      Used as reference implementation for comparison.
     */
    function _extractExpectedSliceFrom(bytes memory data, uint256 start) internal pure returns (bytes memory) {
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
     * @dev Extracts a slice from `data` starting at `start` for `length` bytes using pure Solidity.
     *      Used as reference implementation for comparison.
     */
    function _extractExpectedSliceRange(bytes memory data, uint256 start, uint256 length)
        internal
        pure
        returns (bytes memory)
    {
        if (start + length > data.length) {
            return new bytes(0);
        }

        bytes memory result = new bytes(length);

        for (uint256 i = 0; i < length; i++) {
            result[i] = data[start + i];
        }

        return result;
    }

    /**
     * @dev Verifies that `result` is the correct slice of `original` starting at `start`.
     *      Checks both length and byte-by-byte content.
     */
    function _verifySliceFromCorrectness(bytes memory original, bytes memory result, uint256 start) internal pure {
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

    /**
     * @dev Verifies that `result` is the correct slice of `original` starting at `start` for `length` bytes.
     *      Checks both length and byte-by-byte content.
     */
    function _verifySliceRangeCorrectness(bytes memory original, bytes memory result, uint256 start, uint256 length)
        internal
        pure
    {
        // Case: Invalid range
        if (start + length > original.length) {
            assertEq(result.length, 0, "Invalid range should return empty");
            return;
        }

        assertEq(result.length, length, "Slice length mismatch");

        for (uint256 i = 0; i < result.length; i++) {
            assertEq(
                uint8(result[i]),
                uint8(original[start + i]),
                string.concat("Byte mismatch at position ", vm.toString(i))
            );
        }
    }

    function test_sliceFrom_emptyArray_returnsEmpty() public view {
        bytes memory empty = new bytes(0);
        bytes memory result = harness.sliceFrom(empty, 0);

        assertEq(result.length, 0, "Empty input should return empty output");
    }

    function test_sliceFrom_startAtZero_returnsFullArray() public view {
        bytes memory input = _createPattern(100);
        bytes memory result = harness.sliceFrom(input, 0);

        assertEq(result.length, 100, "Should return full array");
        assertEq(result, input, "Content should match original");
    }

    function test_BYTE_SLICE_2_A_sliceFrom_startBeyondLength_returnsEmpty() public view {
        bytes memory input = _createPattern(50);
        bytes memory result = harness.sliceFrom(input, 100);

        assertEq(result.length, 0, "Start beyond length should return empty");
    }

    function test_BYTE_SLICE_2_B_sliceFrom_startAtLength_returnsEmpty() public view {
        bytes memory input = _createPattern(50);
        bytes memory result = harness.sliceFrom(input, 50);

        assertEq(result.length, 0, "Start at length should return empty");
    }

    function test_sliceFrom_lessThan65Bytes_returnsEmpty() public view {
        // Test various lengths less than 65, starting from offset 65
        for (uint256 len = 1; len < SIGNATURE_LENGTH; len++) {
            bytes memory input = new bytes(len);
            bytes memory result = harness.sliceFrom(input, SIGNATURE_LENGTH);

            assertEq(result.length, 0, string.concat("Input of length ", vm.toString(len), " should return empty"));
        }
    }

    function test_sliceFrom_exactly65Bytes_fromOffset65_returnsEmpty() public view {
        bytes memory oneSignature = _createPattern(SIGNATURE_LENGTH);
        assertEq(oneSignature.length, SIGNATURE_LENGTH, "Test setup: should be exactly 65 bytes");

        bytes memory result = harness.sliceFrom(oneSignature, SIGNATURE_LENGTH);

        assertEq(result.length, 0, "Exactly 65 bytes sliced from 65 should return empty");
    }

    function test_sliceFrom_twoSignatures_returnsSecond() public view {
        bytes memory twoSignatures = _createPattern(130);
        assertEq(twoSignatures.length, 130, "Test setup: should be 130 bytes");

        bytes memory result = harness.sliceFrom(twoSignatures, SIGNATURE_LENGTH);

        assertEq(result.length, 65, "Should return exactly 65 bytes for second signature");

        // Verify the returned bytes match the second signature exactly
        bytes memory expectedSecondSig = _extractExpectedSliceFrom(twoSignatures, SIGNATURE_LENGTH);
        assertEq(result, expectedSecondSig, "Returned bytes should match second signature exactly");
    }

    function test_sliceFrom_threeSignatures_returnsLastTwo() public view {
        bytes memory threeSignatures = _createPattern(195);
        assertEq(threeSignatures.length, 195, "Test setup: should be 195 bytes");

        bytes memory result = harness.sliceFrom(threeSignatures, SIGNATURE_LENGTH);

        assertEq(result.length, 130, "Should return exactly 130 bytes for two signatures");

        // Verify byte-by-byte
        bytes memory expected = _extractExpectedSliceFrom(threeSignatures, SIGNATURE_LENGTH);
        assertEq(result, expected, "Returned bytes should match signatures 2 and 3");
    }

    function test_sliceFrom_fourSignatures_returnsLastThree() public view {
        bytes memory fourSignatures = _createPattern(260);
        assertEq(fourSignatures.length, 260, "Test setup: should be 260 bytes");

        bytes memory result = harness.sliceFrom(fourSignatures, SIGNATURE_LENGTH);

        assertEq(result.length, 195, "Should return exactly 195 bytes for three signatures");

        // Verify byte-by-byte
        bytes memory expected = _extractExpectedSliceFrom(fourSignatures, SIGNATURE_LENGTH);
        assertEq(result, expected, "Returned bytes should match signatures 2, 3, and 4");
    }

    function test_sliceFrom_dataIntegrity_noGarbageBytes() public view {
        // Create data with a known pattern
        bytes memory data = _createPattern(195);

        bytes memory result = harness.sliceFrom(data, SIGNATURE_LENGTH);

        // Verify each byte matches expected value
        for (uint256 i = 0; i < result.length; i++) {
            uint256 originalIndex = SIGNATURE_LENGTH + i;
            assertEq(
                uint8(result[i]), uint8(data[originalIndex]), string.concat("Byte mismatch at index ", vm.toString(i))
            );
        }
    }

    function test_sliceFrom_dataIntegrity_lastByte() public view {
        // This test is critical for the partial word handling
        // 65 bytes mod 32 = 1, so there's always exactly 1 remaining byte
        bytes memory twoSignatures = _createPattern(130);

        bytes memory result = harness.sliceFrom(twoSignatures, SIGNATURE_LENGTH);

        // Verify the very last byte is correct (this is the partial word case)
        uint256 lastIndex = result.length - 1;
        uint256 originalLastIndex = twoSignatures.length - 1;

        assertEq(
            uint8(result[lastIndex]), uint8(twoSignatures[originalLastIndex]), "Last byte should match (partial word)"
        );
    }

    function test_sliceFrom_dataIntegrity_allBytesUnique() public view {
        // Create a pattern where each byte is unique to detect any copying errors
        bytes memory data = new bytes(130);
        for (uint256 i = 0; i < 130; i++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            data[i] = bytes1(uint8(i)); // Safe: i is bounded to 0-129
        }

        bytes memory result = harness.sliceFrom(data, SIGNATURE_LENGTH);

        // Verify each byte in result matches the corresponding byte in original
        for (uint256 i = 0; i < result.length; i++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            uint8 expected = uint8(65 + i); // Safe: result.length is 65, so max is 129
            assertEq(
                uint8(result[i]),
                expected,
                string.concat("Byte ", vm.toString(i), " should equal ", vm.toString(65 + i))
            );
        }
    }

    function test_sliceFrom_partialWord_oneRemainingByte() public view {
        // 65 bytes result: 65 mod 32 = 1 remaining byte
        bytes memory twoSignatures = _createPattern(130);
        bytes memory result = harness.sliceFrom(twoSignatures, SIGNATURE_LENGTH);

        assertEq(result.length, 65, "Should be 65 bytes");
        assertEq(result.length % 32, 1, "Should have 1 remaining byte after full words");

        // Verify the partial byte is correct
        _verifySliceFromCorrectness(twoSignatures, result, SIGNATURE_LENGTH);
    }

    function test_sliceFrom_partialWord_twoRemainingBytes() public view {
        // 130 bytes result: 130 mod 32 = 2 remaining bytes
        bytes memory threeSignatures = _createPattern(195);
        bytes memory result = harness.sliceFrom(threeSignatures, SIGNATURE_LENGTH);

        assertEq(result.length, 130, "Should be 130 bytes");
        assertEq(result.length % 32, 2, "Should have 2 remaining bytes after full words");

        _verifySliceFromCorrectness(threeSignatures, result, SIGNATURE_LENGTH);
    }

    function test_sliceFrom_partialWord_threeRemainingBytes() public view {
        // 195 bytes result: 195 mod 32 = 3 remaining bytes
        bytes memory fourSignatures = _createPattern(260);
        bytes memory result = harness.sliceFrom(fourSignatures, SIGNATURE_LENGTH);

        assertEq(result.length, 195, "Should be 195 bytes");
        assertEq(result.length % 32, 3, "Should have 3 remaining bytes after full words");

        _verifySliceFromCorrectness(fourSignatures, result, SIGNATURE_LENGTH);
    }

    function testFuzz_BYTE_SLICE_3_A_sliceFrom_lengthCorrectness(uint8 signatureCount) public view {
        // Bound to reasonable range (1-10 signatures)
        signatureCount = uint8(bound(signatureCount, 1, 10));

        bytes memory data = _createPattern(signatureCount * SIGNATURE_LENGTH);
        bytes memory result = harness.sliceFrom(data, SIGNATURE_LENGTH);

        if (signatureCount <= 1) {
            assertEq(result.length, 0, "Should return empty for 0 or 1 signatures");
        } else {
            uint256 expectedLength = (signatureCount - 1) * SIGNATURE_LENGTH;
            assertEq(result.length, expectedLength, "Length should be (count-1) * 65");
        }
    }

    function testFuzz_BYTE_SLICE_1_A_sliceFrom_dataIntegrity(uint8 signatureCount) public view {
        // Bound to 2-10 signatures (need at least 2 for meaningful test)
        signatureCount = uint8(bound(signatureCount, 2, 10));

        bytes memory data = _createPattern(signatureCount * SIGNATURE_LENGTH);
        bytes memory result = harness.sliceFrom(data, SIGNATURE_LENGTH);

        // Verify every byte matches
        _verifySliceFromCorrectness(data, result, SIGNATURE_LENGTH);
    }

    function testFuzz_sliceFrom_arbitraryLength(uint16 totalLength, uint16 startIndex) public view {
        totalLength = uint16(bound(totalLength, 0, 1000));
        startIndex = uint16(bound(startIndex, 0, 1000));

        bytes memory input = _createPattern(totalLength);
        bytes memory result = harness.sliceFrom(input, startIndex);

        if (startIndex >= totalLength) {
            assertEq(result.length, 0, "Should return empty for start >= length");
        } else {
            uint256 expectedLength = totalLength - startIndex;
            assertEq(result.length, expectedLength, "Length should be input.length - startIndex");

            // Verify data integrity
            for (uint256 i = 0; i < result.length; i++) {
                uint256 originalIndex = startIndex + i;
                assertEq(
                    uint8(result[i]),
                    uint8(input[originalIndex]),
                    string.concat("Byte mismatch at index ", vm.toString(i))
                );
            }
        }
    }

    function test_sliceRange_emptyArray_returnsEmpty() public view {
        bytes memory empty = new bytes(0);
        bytes memory result = harness.sliceRange(empty, 0, 0);

        assertEq(result.length, 0, "Empty input with zero length should return empty");
    }

    function test_sliceRange_zeroLength_returnsEmpty() public view {
        bytes memory input = _createPattern(100);
        bytes memory result = harness.sliceRange(input, 50, 0);

        assertEq(result.length, 0, "Zero length should return empty");
    }

    function test_sliceRange_fullArray_returnsCopy() public view {
        bytes memory input = _createPattern(100);
        bytes memory result = harness.sliceRange(input, 0, 100);

        assertEq(result.length, 100, "Should return full array length");
        assertEq(result, input, "Content should match original");
    }

    function test_sliceRange_middleSlice_returnsCorrectData() public view {
        bytes memory input = _createPattern(100);
        bytes memory result = harness.sliceRange(input, 25, 50);

        assertEq(result.length, 50, "Should return 50 bytes");

        bytes memory expected = _extractExpectedSliceRange(input, 25, 50);
        assertEq(result, expected, "Content should match expected slice");
    }

    function test_BYTE_SLICE_2_C_sliceRange_startBeyondLength_returnsEmpty() public view {
        bytes memory input = _createPattern(50);
        bytes memory result = harness.sliceRange(input, 100, 10);

        assertEq(result.length, 0, "Start beyond length should return empty");
    }

    function test_BYTE_SLICE_2_D_sliceRange_lengthExceedsBuffer_returnsEmpty() public view {
        bytes memory input = _createPattern(50);
        bytes memory result = harness.sliceRange(input, 40, 20);

        assertEq(result.length, 0, "Length exceeding buffer should return empty");
    }

    function test_sliceRange_exactFit_returnsCorrectData() public view {
        bytes memory input = _createPattern(100);
        bytes memory result = harness.sliceRange(input, 50, 50);

        assertEq(result.length, 50, "Should return exactly 50 bytes");

        bytes memory expected = _extractExpectedSliceRange(input, 50, 50);
        assertEq(result, expected, "Content should match expected slice");
    }

    function test_sliceRange_singleByte_returnsCorrectByte() public view {
        bytes memory input = _createPattern(100);

        for (uint256 i = 0; i < 100; i++) {
            bytes memory result = harness.sliceRange(input, i, 1);
            assertEq(result.length, 1, "Should return single byte");
            assertEq(
                uint8(result[0]), uint8(input[i]), string.concat("Byte at index ", vm.toString(i), " should match")
            );
        }
    }

    function test_sliceRange_32Bytes_fullWord() public view {
        bytes memory input = _createPattern(100);
        bytes memory result = harness.sliceRange(input, 10, 32);

        assertEq(result.length, 32, "Should return exactly 32 bytes");
        _verifySliceRangeCorrectness(input, result, 10, 32);
    }

    function test_sliceRange_64Bytes_twoFullWords() public view {
        bytes memory input = _createPattern(100);
        bytes memory result = harness.sliceRange(input, 10, 64);

        assertEq(result.length, 64, "Should return exactly 64 bytes");
        _verifySliceRangeCorrectness(input, result, 10, 64);
    }

    function test_sliceRange_33Bytes_oneWordPlusOne() public view {
        bytes memory input = _createPattern(100);
        bytes memory result = harness.sliceRange(input, 10, 33);

        assertEq(result.length, 33, "Should return exactly 33 bytes");
        assertEq(result.length % 32, 1, "Should have 1 remaining byte");
        _verifySliceRangeCorrectness(input, result, 10, 33);
    }

    function test_sliceRange_31Bytes_lessThanOneWord() public view {
        bytes memory input = _createPattern(100);
        bytes memory result = harness.sliceRange(input, 10, 31);

        assertEq(result.length, 31, "Should return exactly 31 bytes");
        _verifySliceRangeCorrectness(input, result, 10, 31);
    }

    function test_sliceRange_dataIntegrity_noGarbageBytes() public view {
        bytes memory input = _createPattern(200);
        bytes memory result = harness.sliceRange(input, 50, 100);

        // Verify each byte matches expected value
        for (uint256 i = 0; i < result.length; i++) {
            uint256 originalIndex = 50 + i;
            assertEq(
                uint8(result[i]), uint8(input[originalIndex]), string.concat("Byte mismatch at index ", vm.toString(i))
            );
        }
    }

    function test_BYTE_SLICE_4_A_sliceRange_dataIntegrity_lastByte() public view {
        bytes memory input = _createPattern(200);
        bytes memory result = harness.sliceRange(input, 50, 65);

        // Verify the very last byte is correct (partial word case: 65 mod 32 = 1)
        uint256 lastIndex = result.length - 1;
        uint256 originalLastIndex = 50 + 65 - 1;

        assertEq(uint8(result[lastIndex]), uint8(input[originalLastIndex]), "Last byte should match (partial word)");
    }

    function test_BYTE_SLICE_4_B_sliceRange_variousRemainderValues() public view {
        bytes memory input = _createPattern(200);

        // Test all possible remainder values (0 to 31)
        for (uint256 remainder = 0; remainder <= 31; remainder++) {
            uint256 length = 32 + remainder; // One full word plus remainder
            bytes memory result = harness.sliceRange(input, 10, length);

            assertEq(result.length, length, string.concat("Length should be ", vm.toString(length)));
            assertEq(result.length % 32, remainder, string.concat("Remainder should be ", vm.toString(remainder)));
            _verifySliceRangeCorrectness(input, result, 10, length);
        }
    }

    /// @dev Verifies `sliceRange` zero-pads the trailing bytes in the last output word for non-word-aligned
    ///      lengths so adjacent source memory cannot leak. [BYTE-SLICE-4]
    function testFuzz_BYTE_SLICE_4_C_sliceRange_nonAlignedLastWordZeroPadsTrailingBytes(
        uint16 bufferLength,
        uint16 startIndex,
        uint16 sliceLength
    )
        public
        view
    {
        bufferLength = uint16(bound(bufferLength, 1, 512));
        startIndex = uint16(bound(startIndex, 0, bufferLength - 1));
        sliceLength = uint16(bound(sliceLength, 1, bufferLength - startIndex));
        vm.assume(sliceLength % 32 != 0);

        bytes memory input = _createPattern(bufferLength);

        // Setup: choose a valid in-range slice whose output length leaves a partial final word.
        bytes memory result = harness.sliceRange(input, startIndex, sliceLength);

        // Call: inspect the stored last output word in memory after performing the partial-word copy.
        uint256 wordOffset = (uint256(sliceLength) / 32) * 32;
        bytes32 lastWord;
        assembly {
            lastWord := mload(add(add(result, 32), wordOffset))
        }

        // Verify: the visible bytes match the source and the masked trailing bytes remain zeroed.
        _verifySliceRangeCorrectness(input, result, startIndex, sliceLength);
        uint256 trailingMask = type(uint256).max >> (uint256(sliceLength % 32) * 8);
        assertEq(uint256(lastWord) & trailingMask, 0, "Trailing bytes in the last word should be zero-padded");
    }

    function testFuzz_BYTE_SLICE_1_B__BYTE_SLICE_3_B_sliceRange_arbitraryInputs(
        uint16 bufferLength,
        uint16 startIndex,
        uint16 sliceLength
    )
        public
        view
    {
        bufferLength = uint16(bound(bufferLength, 0, 500));
        startIndex = uint16(bound(startIndex, 0, 600));
        sliceLength = uint16(bound(sliceLength, 0, 600));

        bytes memory input = _createPattern(bufferLength);
        bytes memory result = harness.sliceRange(input, startIndex, sliceLength);

        // Case: Invalid range
        if (uint256(startIndex) + uint256(sliceLength) > bufferLength) {
            assertEq(result.length, 0, "Invalid range should return empty");
        } else {
            assertEq(result.length, sliceLength, "Length should match requested slice length");

            // Verify data integrity
            for (uint256 i = 0; i < result.length; i++) {
                uint256 originalIndex = startIndex + i;
                assertEq(
                    uint8(result[i]),
                    uint8(input[originalIndex]),
                    string.concat("Byte mismatch at index ", vm.toString(i))
                );
            }
        }
    }

    function testFuzz_sliceRange_matchesSliceFrom(uint16 bufferLength, uint16 startIndex) public view {
        bufferLength = uint16(bound(bufferLength, 0, 500));
        startIndex = uint16(bound(startIndex, 0, 600));

        bytes memory input = _createPattern(bufferLength);

        bytes memory sliceFromResult = harness.sliceFrom(input, startIndex);

        // Case: startIndex >= bufferLength
        if (startIndex >= bufferLength) {
            assertEq(sliceFromResult.length, 0, "sliceFrom should return empty for start >= length");
            // sliceRange with length 0 should also return empty
            bytes memory sliceRangeResult = harness.sliceRange(input, startIndex, 0);
            assertEq(sliceRangeResult.length, 0, "sliceRange with 0 length should return empty");
        } else {
            // sliceFrom(buffer, start) should equal sliceRange(buffer, start, buffer.length - start)
            uint256 expectedLength = bufferLength - startIndex;
            bytes memory sliceRangeResult = harness.sliceRange(input, startIndex, expectedLength);

            assertEq(sliceFromResult.length, sliceRangeResult.length, "Lengths should match");
            assertEq(sliceFromResult, sliceRangeResult, "Content should match");
        }
    }
}
