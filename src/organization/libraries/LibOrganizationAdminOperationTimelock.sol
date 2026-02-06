// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationAdminOperationTimelock} from "interfaces/organization/IOrganizationAdminOperationTimelock.sol";
import {TimelockUtils} from "libraries/TimelockUtils.sol";
import {
    LibOrganizationAdminOperationTimelockStorage
} from "organization/libraries/storage/LibOrganizationAdminOperationTimelockStorage.sol";

/**
 * @title Lib Organization Admin Operation Timelock
 * @dev Library for managing the organization-wide admin operation timelock duration.
 *      The admin operation timelock is used across multiple timelocked operations:
 *      - Guardian updates (initiate → finalize → accept)
 *      - Deferred recovery initialization (initiate → finalize)
 *      - Any future timelocked operations
 *
 *      Validates duration via TimelockUtils to ensure it falls within the allowed range.
 * @author Den Technologies Inc
 */
library LibOrganizationAdminOperationTimelock {
    /**
     * @dev Initializes the admin operation timelock duration during organization initialization.
     *      Validates that the duration is within the allowed range via TimelockUtils.
     * @param adminOperationTimelockDurationSeconds The timelock duration in seconds
     */
    function initializeAdminOperationTimelock(uint256 adminOperationTimelockDurationSeconds) internal {
        TimelockUtils.validateTimelockDurationOrRevert(adminOperationTimelockDurationSeconds);

        LibOrganizationAdminOperationTimelockStorage.layout().adminOperationTimelockDurationSeconds =
        adminOperationTimelockDurationSeconds;
    }

    /**
     * @dev Returns the admin operation timelock duration in seconds.
     * @return The timelock duration
     */
    function getAdminOperationTimelockDurationSeconds() internal view returns (uint256) {
        return LibOrganizationAdminOperationTimelockStorage.layout().adminOperationTimelockDurationSeconds;
    }

    /**
     * @dev Validates that a timelock has expired.
     *      Reverts with TimelockNotExpired if block.timestamp is before canFinalizeAtTimestamp.
     * @param canFinalizeAtTimestamp The timestamp when the timelock expires
     */
    function validateTimelockExpiredOrRevert(uint256 canFinalizeAtTimestamp) internal view {
        if (block.timestamp < canFinalizeAtTimestamp) {
            revert IOrganizationAdminOperationTimelock.TimelockNotExpired(canFinalizeAtTimestamp, block.timestamp);
        }
    }

    /**
     * @dev Computes the timestamp when a newly initiated timelocked operation can be finalized.
     *      Uses the organization-wide admin operation timelock duration.
     * @return The finalization timestamp (block.timestamp + adminOperationTimelockDurationSeconds)
     */
    function computeCanFinalizeAtTimestamp() internal view returns (uint256) {
        return
            block.timestamp
                + LibOrganizationAdminOperationTimelockStorage.layout().adminOperationTimelockDurationSeconds;
    }
}
