// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationSecureTimelock} from "interfaces/organization/IOrganizationSecureTimelock.sol";
import {LibOrganizationSecureTimelock} from "organization/libraries/LibOrganizationSecureTimelock.sol";

/**
 * @title OrganizationSecureTimelockBase
 * @dev Abstract contract implementing IOrganizationSecureTimelock.
 *      Exposes the organization-wide secure timelock duration.
 * @author Den Technologies Inc
 */
abstract contract OrganizationSecureTimelockBase is IOrganizationSecureTimelock {
    /// @inheritdoc IOrganizationSecureTimelock
    function secureTimelockDurationSeconds() external view override returns (uint256) {
        return LibOrganizationSecureTimelock.getSecureTimelockDurationSeconds();
    }
}
