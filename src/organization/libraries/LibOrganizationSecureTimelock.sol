// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationSecureTimelock} from "interfaces/organization/IOrganizationSecureTimelock.sol";
import {
    LibOrganizationSecureTimelockStorage
} from "organization/libraries/storage/LibOrganizationSecureTimelockStorage.sol";

/**
 * @title Lib Organization Secure Timelock
 * @dev Library for managing the organization-wide secure timelock duration.
 *      The secure timelock is used across multiple timelocked operations:
 *      - Guardian updates (initiate → finalize → accept)
 *      - Deferred recovery initialization (initiate → finalize)
 *      - Any future timelocked operations
 *
 *      Enforces a minimum of 3 days to ensure meaningful timelock protection.
 * @author Den Technologies Inc
 */
library LibOrganizationSecureTimelock {
    /// @dev Minimum secure timelock duration: 3 days
    uint256 internal constant MIN_SECURE_TIMELOCK_DURATION_SECONDS = 3 days;

    /**
     * @dev Initializes the secure timelock duration during organization initialization.
     *      Validates that the duration is non-zero and meets the minimum requirement.
     * @param secureTimelockDurationSeconds The timelock duration in seconds
     */
    function initializeSecureTimelock(uint256 secureTimelockDurationSeconds) internal {
        // Case: Zero timelock duration
        if (secureTimelockDurationSeconds == 0) {
            revert IOrganizationSecureTimelock.InvalidSecureTimelockDurationSeconds();
        }

        // Case: Below minimum
        if (secureTimelockDurationSeconds < MIN_SECURE_TIMELOCK_DURATION_SECONDS) {
            revert IOrganizationSecureTimelock.SecureTimelockDurationBelowMinimum(
                secureTimelockDurationSeconds, MIN_SECURE_TIMELOCK_DURATION_SECONDS
            );
        }

        LibOrganizationSecureTimelockStorage.layout().secureTimelockDurationSeconds = secureTimelockDurationSeconds;
    }

    /**
     * @dev Returns the secure timelock duration in seconds.
     * @return The timelock duration
     */
    function getSecureTimelockDurationSeconds() internal view returns (uint256) {
        return LibOrganizationSecureTimelockStorage.layout().secureTimelockDurationSeconds;
    }
}
