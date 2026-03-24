// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationMembers} from "interfaces/organization/IOrganizationMembers.sol";
import {OrganizationModifiers} from "organization/common/OrganizationModifiers.sol";
import {LibOrganizationAdmin} from "organization/libraries/LibOrganizationAdmin.sol";
import {LibOrganizationMembers} from "organization/libraries/LibOrganizationMembers.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";
import {OperationType} from "types/CommonTypes.sol";

/**
 * @title OrganizationMembersBase
 * @dev Abstract contract implementing IOrganizationMembers.
 *      Handles member management operations including adding/removing members and verifying membership.
 *      Member removal does not clear group memberships — see LibOrganizationMembers for details.
 * @author Den Technologies Inc
 */
abstract contract OrganizationMembersBase is OrganizationModifiers, IOrganizationMembers {
    /// @inheritdoc IOrganizationMembers
    function modifyMembers(
        address[] calldata membersToAdd,
        address[] calldata membersToRemove,
        AdminAuthParams calldata authParams
    ) external override onlyGuardian {
        // Encode the operation data for validation
        bytes memory operationData =
            abi.encode(keccak256(abi.encode(membersToAdd)), keccak256(abi.encode(membersToRemove)));

        // Validate that the current admins have authorized this operation (isApproval = true for execution)
        LibOrganizationAdmin.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyMembers,
            operationData: operationData,
            isApproval: true,
            authParams: authParams
        });

        LibOrganizationMembers.modifyMembers(membersToAdd, membersToRemove);
    }

    /// @inheritdoc IOrganizationMembers
    function isMember(address memberAddress) external view override returns (bool) {
        return LibOrganizationMembers.isMember(memberAddress);
    }
}
