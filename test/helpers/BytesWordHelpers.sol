// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

/**
 * @dev Shared helpers for reading/writing ABI words inside mutable bytes payloads in tests.
 *      Used by malformed-calldata fixtures that intentionally mutate encoded enum words.
 */
abstract contract BytesWordHelpers {
    /**
     * @dev Reads a 32-byte word from `data` at `byteOffset`.
     */
    function _readWord(bytes memory data, uint256 byteOffset) internal pure returns (uint256 value) {
        if (data.length < byteOffset + 32) revert("word read out of bounds");
        assembly {
            value := mload(add(add(data, 0x20), byteOffset))
        }
    }

    /**
     * @dev Writes `value` to a 32-byte word in `data` at `byteOffset`.
     */
    function _setWord(bytes memory data, uint256 byteOffset, uint256 value) internal pure {
        if (data.length < byteOffset + 32) revert("word write out of bounds");
        assembly {
            mstore(add(add(data, 0x20), byteOffset), value)
        }
    }
}
