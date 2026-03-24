// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

/**
 * @dev Shared bitmask utilities for tests.
 *      Centralizes bit-manipulation helpers so invariant handlers and fuzz suites can stay focused on behavior under
 *      test.
 */
abstract contract BitmaskHelpers {
    /**
     * @dev Counts set bits (1s) in the lower `nBits` of a bitmask.
     *      Reverts if `nBits` exceeds the width of `uint8`.
     */
    function _popcountLowerBits(uint8 bitmask, uint8 nBits) internal pure returns (uint256 count) {
        require(nBits <= 8, "nBits out of range");

        for (uint256 i = 0; i < nBits; i++) {
            if (((bitmask >> i) & 1) == 1) {
                count++;
            }
        }
    }
}
