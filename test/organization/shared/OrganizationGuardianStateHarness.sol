// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {
    LibOrganizationAdminOperationTimelockStorage
} from "organization/libraries/storage/LibOrganizationAdminOperationTimelockStorage.sol";
import {LibOrganizationGuardianStorage} from "organization/libraries/storage/LibOrganizationGuardianStorage.sol";
import {OrganizationAdminStateHarness} from "test/organization/shared/OrganizationAdminStateHarness.sol";

/**
 * @dev Shared guardian-focused state harness surface.
 *      Extends admin/auth helpers with direct guardian and admin-timelock storage accessors.
 */
contract OrganizationGuardianStateHarness is OrganizationAdminStateHarness {
    /**
     * @dev Sets the organization-wide admin operation timelock duration.
     */
    function setAdminOperationTimelockDurationSeconds(uint256 duration) external {
        LibOrganizationAdminOperationTimelockStorage.layout().adminOperationTimelockDurationSeconds = duration;
    }

    /**
     * @dev Reads the organization-wide admin operation timelock duration.
     */
    function getAdminOperationTimelockDurationSeconds() external view returns (uint256) {
        return LibOrganizationAdminOperationTimelockStorage.layout().adminOperationTimelockDurationSeconds;
    }

    /**
     * @dev Sets pending guardian storage value.
     */
    function setPendingGuardian(address pendingGuardian) external {
        LibOrganizationGuardianStorage.layout().pendingGuardian = pendingGuardian;
    }

    /**
     * @dev Reads pending guardian storage value.
     */
    function getPendingGuardianStorage() external view returns (address) {
        return LibOrganizationGuardianStorage.layout().pendingGuardian;
    }

    /**
     * @dev Sets pending guardian update timestamp storage value.
     */
    function setPendingGuardianUpdateTimestamp(uint256 timestamp) external {
        LibOrganizationGuardianStorage.layout().pendingGuardianUpdateTimestamp = timestamp;
    }

    /**
     * @dev Reads pending guardian update timestamp storage value.
     */
    function getPendingGuardianUpdateTimestampStorage() external view returns (uint256) {
        return LibOrganizationGuardianStorage.layout().pendingGuardianUpdateTimestamp;
    }

    /**
     * @dev Sets ready-for-acceptance storage flag.
     */
    function setIsGuardianUpdateReadyForAcceptance(bool isReady) external {
        LibOrganizationGuardianStorage.layout().isGuardianUpdateReadyForAcceptance = isReady;
    }

    /**
     * @dev Reads ready-for-acceptance storage flag.
     */
    function getIsGuardianUpdateReadyForAcceptanceStorage() external view returns (bool) {
        return LibOrganizationGuardianStorage.layout().isGuardianUpdateReadyForAcceptance;
    }
}
