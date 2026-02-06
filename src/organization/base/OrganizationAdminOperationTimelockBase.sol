// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationAdminOperationTimelock} from "interfaces/organization/IOrganizationAdminOperationTimelock.sol";
import {LibOrganizationAdminOperationTimelock} from "organization/libraries/LibOrganizationAdminOperationTimelock.sol";

/**
 * @title OrganizationAdminOperationTimelockBase
 * @dev Abstract contract implementing IOrganizationAdminOperationTimelock.
 *      Exposes the organization-wide admin operation timelock duration.
 * @author Den Technologies Inc
 */
abstract contract OrganizationAdminOperationTimelockBase is IOrganizationAdminOperationTimelock {
    /// @inheritdoc IOrganizationAdminOperationTimelock
    function adminOperationTimelockDurationSeconds() external view override returns (uint256) {
        return LibOrganizationAdminOperationTimelock.getAdminOperationTimelockDurationSeconds();
    }
}
