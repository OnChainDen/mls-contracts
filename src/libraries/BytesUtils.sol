// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

/**
 * @title Bytes Utils
 * @dev Utility library for bytes manipulation operations.
 *      Contains Paris EVM-compatible slicing functions that avoid the mcopy opcode (Cancun).
 * @author Den Technologies Inc
 */
library BytesUtils {
    /**
     * @dev Slices a bytes array from a start index to the end, without using the mcopy opcode.
     *      This is a Paris EVM-compatible replacement for OpenZeppelin's Bytes.slice which uses mcopy (Cancun).
     * @param buffer The source bytes array to slice from
     * @param startIndex The starting index (inclusive) for the slice
     * @return result A new bytes array containing buffer[startIndex:buffer.length]
     */
    function sliceFrom(bytes memory buffer, uint256 startIndex) internal pure returns (bytes memory result) {
        uint256 bufferLength = buffer.length;

        // Case: Start index is at or beyond the buffer length
        if (startIndex >= bufferLength) {
            return new bytes(0);
        }

        uint256 resultLength = bufferLength - startIndex;
        return sliceRange(buffer, startIndex, resultLength);
    }

    /**
     * @dev Slices a bytes array from a start index for a specified length.
     *      This is a Paris EVM-compatible implementation without using the mcopy opcode.
     * @param buffer The source bytes array to slice from
     * @param startIndex The starting index (inclusive) for the slice
     * @param length The number of bytes to copy
     * @return result A new bytes array containing buffer[startIndex:startIndex+length]
     */
    function sliceRange(bytes memory buffer, uint256 startIndex, uint256 length)
        internal
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
