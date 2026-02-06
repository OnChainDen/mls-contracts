// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationSecureTimelock} from "interfaces/organization/IOrganizationSecureTimelock.sol";
import {TimelockUtils} from "libraries/TimelockUtils.sol";
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
 *      Validates duration via TimelockUtils to ensure it falls within the allowed range.
 * @author Den Technologies Inc
 */
library LibOrganizationSecureTimelock {
    /**
     * @dev Initializes the secure timelock duration during organization initialization.
     *      Validates that the duration is within the allowed range via TimelockUtils.
     * @param secureTimelockDurationSeconds The timelock duration in seconds
     */
    function initializeSecureTimelock(uint256 secureTimelockDurationSeconds) internal {
        TimelockUtils.validateTimelockDurationOrRevert(secureTimelockDurationSeconds);

        LibOrganizationSecureTimelockStorage.layout().secureTimelockDurationSeconds = secureTimelockDurationSeconds;
    }

    /**
     * @dev Returns the secure timelock duration in seconds.
     * @return The timelock duration
     */
    function getSecureTimelockDurationSeconds() internal view returns (uint256) {
        return LibOrganizationSecureTimelockStorage.layout().secureTimelockDurationSeconds;
    }

    /**
     * @dev Validates that a timelock has expired.
     *      Reverts with TimelockNotExpired if block.timestamp is before canFinalizeAtTimestamp.
     * @param canFinalizeAtTimestamp The timestamp when the timelock expires
     */
    function validateTimelockExpiredOrRevert(uint256 canFinalizeAtTimestamp) internal view {
        if (block.timestamp < canFinalizeAtTimestamp) {
            revert IOrganizationSecureTimelock.TimelockNotExpired(canFinalizeAtTimestamp, block.timestamp);
        }
    }

    /**
     * @dev Computes the timestamp when a newly initiated timelocked operation can be finalized.
     *      Uses the organization-wide secure timelock duration.
     * @return The finalization timestamp (block.timestamp + secureTimelockDurationSeconds)
     */
    function computeCanFinalizeAtTimestamp() internal view returns (uint256) {
        return block.timestamp + LibOrganizationSecureTimelockStorage.layout().secureTimelockDurationSeconds;
    }
}
