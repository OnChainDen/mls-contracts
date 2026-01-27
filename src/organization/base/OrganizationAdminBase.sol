// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationAdmin} from "interfaces/organization/IOrganizationAdmin.sol";
import {OrganizationModifiers} from "organization/common/OrganizationModifiers.sol";
import {LibOrganizationAdmin} from "organization/libraries/LibOrganizationAdmin.sol";
import {LibOrganizationMembers} from "organization/libraries/LibOrganizationMembers.sol";
import {LibOrganizationSignatures} from "organization/libraries/LibOrganizationSignatures.sol";
import {AdminAuthParams, AdminConfig, AllAdminsInOrgProofs} from "types/AdminTypes.sol";
import {OperationType} from "types/CommonTypes.sol";

/**
 * @title OrganizationAdminBase
 * @dev Abstract contract implementing IOrganizationAdmin.
 *      Handles admin management operations including setting admins and rejecting admin operations.
 * @author Den Technologies Inc
 */
abstract contract OrganizationAdminBase is OrganizationModifiers, IOrganizationAdmin {
    /// @inheritdoc IOrganizationAdmin
    function setAdmins(
        bytes32 newAdminsRoot,
        uint256 newAdminCount,
        uint256 newVotingThreshold,
        AdminAuthParams calldata authParams,
        AllAdminsInOrgProofs calldata newAdminsInOrgProofs
    ) external override onlyGuardian {
        // Encode the operation data for validation
        bytes memory operationData = abi.encode(newAdminsRoot, newAdminCount, newVotingThreshold);

        // Validate that the current admin has authorized this change (isApproval = true for execution)
        LibOrganizationAdmin.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins,
            operationData: operationData,
            isApproval: true,
            authParams: authParams
        });

        // Get current members root for validation
        bytes32 currentMembersRoot = LibOrganizationMembers.getMembersRoot();

        LibOrganizationAdmin.setAdmins({
            newAdminsRoot: newAdminsRoot,
            newAdminCount: newAdminCount,
            newVotingThreshold: newVotingThreshold,
            newAdminsInOrgProofs: newAdminsInOrgProofs,
            currentMembersRoot: currentMembersRoot
        });
    }

    /// @inheritdoc IOrganizationAdmin
    function rejectAdminOperation(
        OperationType operationType,
        bytes calldata operationData,
        AdminAuthParams calldata authParams
    ) external override onlyGuardian {
        // Compute nonce for this operation
        uint256 nonce = LibOrganizationSignatures.computeNonce(operationType, operationData, authParams.salt);

        // Validate admin authorization and consume the nonce (isApproval = false for rejection)
        LibOrganizationAdmin.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: operationType, operationData: operationData, isApproval: false, authParams: authParams
        });

        emit AdminOperationRejected(operationType, operationData, nonce);
    }

    /// @inheritdoc IOrganizationAdmin
    function adminConfig() external view override returns (AdminConfig memory) {
        return LibOrganizationAdmin.getAdminConfig();
    }
}
