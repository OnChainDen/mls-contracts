// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

/**
 * @title Timelock Utils
 * @dev Utility library for validating timelock duration parameters.
 *      Enforces a minimum of 2 days and maximum of 30 days for all timelock durations
 *      to ensure meaningful protection without making timelocked operations impractical.
 * @author Den Technologies Inc
 */
library TimelockUtils {
    /// @dev Minimum timelock duration: 2 days
    uint256 internal constant MIN_TIMELOCK_DURATION_SECONDS = 2 days;

    /// @dev Maximum timelock duration: 30 days
    uint256 internal constant MAX_TIMELOCK_DURATION_SECONDS = 30 days;

    /**
     * @dev Thrown when a timelock duration is outside the allowed range [min, max]
     * @param provided The provided timelock duration in seconds
     * @param min The minimum allowed timelock duration in seconds
     * @param max The maximum allowed timelock duration in seconds
     */
    error InvalidTimelockDuration(uint256 provided, uint256 min, uint256 max);

    /**
     * @dev Validates that a timelock duration is within the allowed range.
     *      Reverts if below MIN_TIMELOCK_DURATION_SECONDS or above MAX_TIMELOCK_DURATION_SECONDS.
     * @param timelockDurationSeconds The timelock duration to validate
     */
    function validateTimelockDurationOrRevert(uint256 timelockDurationSeconds) internal pure {
        if (
            timelockDurationSeconds < MIN_TIMELOCK_DURATION_SECONDS
                || timelockDurationSeconds > MAX_TIMELOCK_DURATION_SECONDS
        ) {
            revert InvalidTimelockDuration(
                timelockDurationSeconds, MIN_TIMELOCK_DURATION_SECONDS, MAX_TIMELOCK_DURATION_SECONDS
            );
        }
    }
}
