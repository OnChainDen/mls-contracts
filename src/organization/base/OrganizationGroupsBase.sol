// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationGroups} from "interfaces/organization/IOrganizationGroups.sol";
import {OrganizationModifiers} from "organization/common/OrganizationModifiers.sol";
import {LibOrganizationAdmin} from "organization/libraries/LibOrganizationAdmin.sol";
import {LibOrganizationGroups} from "organization/libraries/LibOrganizationGroups.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";
import {GroupModification, OperationType} from "types/CommonTypes.sol";

/**
 * @title OrganizationGroupsBase
 * @dev Abstract contract implementing IOrganizationGroups.
 *      Handles group management operations including creating, modifying, and deleting groups.
 * @author Den Technologies Inc
 */
abstract contract OrganizationGroupsBase is OrganizationModifiers, IOrganizationGroups {
    /// @inheritdoc IOrganizationGroups
    function modifyGroups(GroupModification[] calldata modifications, AdminAuthParams calldata authParams)
        external
        override
        onlyGuardian
    {
        // Encode the operation data for validation
        bytes memory operationData = abi.encode(keccak256(abi.encode(modifications)));

        // Validate that the current admins have authorized this operation (isApproval = true for execution)
        LibOrganizationAdmin.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyGroups,
            operationData: operationData,
            isApproval: true,
            authParams: authParams
        });

        LibOrganizationGroups.modifyGroups(modifications);
    }

    /// @inheritdoc IOrganizationGroups
    function isGroup(uint256 groupId) external view override returns (bool) {
        return LibOrganizationGroups.isGroup(groupId);
    }

    /// @inheritdoc IOrganizationGroups
    function isGroupMember(uint256 groupId, address memberAddress) external view override returns (bool) {
        return LibOrganizationGroups.isGroupMember(groupId, memberAddress);
    }
}
