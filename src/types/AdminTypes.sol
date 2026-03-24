// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

/**
 * @title Admin Types
 * @notice Data structures for admin-related operations in Organization contracts
 * @dev Admins are stored in a mapping (address => bool) with a counter.
 *      Admin membership is verified via direct storage reads.
 * @author Den Technologies Inc
 */

/**
 * @dev Parameters for authorizing admin operations.
 *      Groups common authorization parameters to reduce function parameter count.
 * @param salt A user-provided salt for nonce computation
 * @param expirationTimestamp The timestamp after which the signatures are no longer valid
 * @param signatures The signatures from admin(s) authorizing this operation
 */
struct AdminAuthParams {
    uint256 salt;
    uint256 expirationTimestamp;
    bytes signatures;
}
