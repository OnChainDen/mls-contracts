// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationAdmin} from "interfaces/organization/IOrganizationAdmin.sol";
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
        uint256 nonce = LibOrganizationAdmin.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyGroups,
            operationData: operationData,
            isApproval: true,
            authParams: authParams
        });

        // Execute via low-level self-call so that a revert does not bubble up.
        /* solhint-disable avoid-low-level-calls */
        // slither-disable-next-line low-level-calls,reentrancy-events
        (bool success, bytes memory revertData) =
            address(this).call(abi.encodeCall(this.executeModifyGroups, (modifications)));
        /* solhint-enable avoid-low-level-calls */

        if (!success) {
            emit IOrganizationAdmin.AdminOperationExecutionReverted(OperationType.ModifyGroups, nonce, revertData);
        }
    }

    /// @inheritdoc IOrganizationGroups
    function executeModifyGroups(GroupModification[] calldata modifications) external onlySelf {
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
