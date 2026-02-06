// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

/**
 * @title IOrganizationSecureTimelock
 * @notice Interface for organization-wide secure timelock configuration
 * @dev The secure timelock duration applies to all sensitive timelocked operations
 *      in the organization, including guardian updates and deferred recovery initialization.
 * @author Den Technologies Inc
 */
interface IOrganizationSecureTimelock {
    /**
     * @notice Thrown when the secure timelock duration is invalid (zero or below minimum)
     */
    error InvalidSecureTimelockDurationSeconds();

    /**
     * @notice Returns the organization-wide secure timelock duration in seconds
     * @return The timelock duration in seconds
     */
    function secureTimelockDurationSeconds() external view returns (uint256);
}
