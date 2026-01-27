// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationMembers} from "interfaces/organization/IOrganizationMembers.sol";
import {OrganizationModifiers} from "organization/common/OrganizationModifiers.sol";
import {LibOrganizationAdmin} from "organization/libraries/LibOrganizationAdmin.sol";
import {LibOrganizationMembers} from "organization/libraries/LibOrganizationMembers.sol";
import {AdminAuthParams, AllAdminsInOrgProofs} from "types/AdminTypes.sol";
import {OperationType} from "types/CommonTypes.sol";

/**
 * @title OrganizationMembersBase
 * @dev Abstract contract implementing IOrganizationMembers.
 *      Handles member management operations including setting members and verifying membership.
 * @author Den Technologies Inc
 */
abstract contract OrganizationMembersBase is OrganizationModifiers, IOrganizationMembers {
    /// @inheritdoc IOrganizationMembers
    function setMembers(
        bytes32 newMembersRoot,
        string calldata ipfsCid,
        AdminAuthParams calldata authParams,
        AllAdminsInOrgProofs calldata allAdminsInOrgProofs
    ) external override onlyGuardian {
        // Encode the operation data for validation
        bytes memory operationData = abi.encode(newMembersRoot, keccak256(bytes(ipfsCid)));

        // Validate that the current admin has authorized this operation (isApproval = true for execution)
        LibOrganizationAdmin.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyMembers,
            operationData: operationData,
            isApproval: true,
            authParams: authParams
        });

        LibOrganizationMembers.setMembers(newMembersRoot, ipfsCid, allAdminsInOrgProofs);
    }

    /// @inheritdoc IOrganizationMembers
    function membersRoot() external view override returns (bytes32) {
        return LibOrganizationMembers.getMembersRoot();
    }

    /// @inheritdoc IOrganizationMembers
    function isMemberInOrg(address memberAddress, bytes32[] calldata proof) external view override returns (bool) {
        return LibOrganizationMembers.isMemberInOrg(memberAddress, proof);
    }
}
