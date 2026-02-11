// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationAdmin} from "interfaces/organization/IOrganizationAdmin.sol";
import {OrganizationModifiers} from "organization/common/OrganizationModifiers.sol";
import {LibOrganizationAdmin} from "organization/libraries/LibOrganizationAdmin.sol";
import {LibOrganizationSignatures} from "organization/libraries/LibOrganizationSignatures.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";
import {OperationType} from "types/CommonTypes.sol";

/**
 * @title OrganizationAdminBase
 * @dev Abstract contract implementing IOrganizationAdmin.
 *      Handles admin management operations including adding/removing admins and rejecting admin operations.
 * @author Den Technologies Inc
 */
abstract contract OrganizationAdminBase is OrganizationModifiers, IOrganizationAdmin {
    /// @inheritdoc IOrganizationAdmin
    function modifyAdmins(
        address[] calldata adminsToAdd,
        address[] calldata adminsToRemove,
        uint256 newVotingThreshold,
        AdminAuthParams calldata authParams
    ) external override onlyGuardian {
        // Encode the operation data for validation
        bytes memory operationData =
            abi.encode(keccak256(abi.encode(adminsToAdd)), keccak256(abi.encode(adminsToRemove)), newVotingThreshold);

        // Validate that the current admins have authorized this change (isApproval = true for execution)
        LibOrganizationAdmin.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins,
            operationData: operationData,
            isApproval: true,
            authParams: authParams
        });

        LibOrganizationAdmin.modifyAdmins(adminsToAdd, adminsToRemove, newVotingThreshold);
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
    function isAdmin(address adminAddress) external view override returns (bool) {
        return LibOrganizationAdmin.isAdmin(adminAddress);
    }

    /// @inheritdoc IOrganizationAdmin
    function adminCount() external view override returns (uint256) {
        return LibOrganizationAdmin.getAdminCount();
    }

    /// @inheritdoc IOrganizationAdmin
    function votingThreshold() external view override returns (uint256) {
        return LibOrganizationAdmin.getVotingThreshold();
    }
}
