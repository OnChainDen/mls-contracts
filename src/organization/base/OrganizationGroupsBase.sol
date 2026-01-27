// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationGroups} from "interfaces/organization/IOrganizationGroups.sol";
import {OrganizationModifiers} from "organization/common/OrganizationModifiers.sol";
import {LibOrganizationAdmin} from "organization/libraries/LibOrganizationAdmin.sol";
import {LibOrganizationGroups} from "organization/libraries/LibOrganizationGroups.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";
import {OperationType} from "types/CommonTypes.sol";
import {GroupData} from "types/PolicyTypes.sol";

/**
 * @title OrganizationGroupsBase
 * @dev Abstract contract implementing IOrganizationGroups.
 *      Handles group management operations including setting groups and verifying group membership.
 * @author Den Technologies Inc
 */
abstract contract OrganizationGroupsBase is OrganizationModifiers, IOrganizationGroups {
    /// @inheritdoc IOrganizationGroups
    function setGroups(bytes32 newGroupsRoot, string calldata ipfsCid, AdminAuthParams calldata authParams)
        external
        override
        onlyGuardian
    {
        // Encode the operation data for validation
        bytes memory operationData = abi.encode(newGroupsRoot, keccak256(bytes(ipfsCid)));

        // Validate that the current admin has authorized this operation (isApproval = true for execution)
        LibOrganizationAdmin.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyGroups,
            operationData: operationData,
            isApproval: true,
            authParams: authParams
        });

        LibOrganizationGroups.setGroups(newGroupsRoot, ipfsCid);
    }

    /// @inheritdoc IOrganizationGroups
    function groupsRoot() external view override returns (bytes32) {
        return LibOrganizationGroups.getGroupsRoot();
    }

    /// @inheritdoc IOrganizationGroups
    function isGroupInOrg(GroupData calldata groupData, bytes32[] calldata groupInOrgGroupsTreeProof)
        external
        view
        override
        returns (bool)
    {
        return LibOrganizationGroups.isGroupInOrg(groupData, groupInOrgGroupsTreeProof);
    }

    /// @inheritdoc IOrganizationGroups
    function isMemberInGroupAndGroupInOrg(
        address memberAddress,
        GroupData calldata groupData,
        bytes32[] calldata groupInOrgGroupsTreeProof,
        bytes32[] calldata memberInGroupProof
    ) external view override returns (bool) {
        return LibOrganizationGroups.isMemberInGroupAndGroupInOrg(
            memberAddress, groupData, groupInOrgGroupsTreeProof, memberInGroupProof
        );
    }
}
