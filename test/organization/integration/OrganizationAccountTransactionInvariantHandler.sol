// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

/**
 * @dev No-op handler used to stabilize invariant targets for account-transaction checks.
 */
contract OrganizationAccountTransactionInvariantHandler {
    uint256 public lastSeed;

    /**
     * @dev No-op stateful entrypoint for invariant engine target calls.
     */
    function noop(uint256 seed) external {
        lastSeed = seed;
    }
}
