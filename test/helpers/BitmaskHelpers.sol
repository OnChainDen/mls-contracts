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
     * @dev Counts the number of set bits (1s) in lower 4 bits of a bitmask.
     */
    function _popcount4(uint8 bitmask) internal pure returns (uint256 count) {
        for (uint256 i = 0; i < 4; i++) {
            if (((bitmask >> i) & 1) == 1) {
                count++;
            }
        }
    }
}
