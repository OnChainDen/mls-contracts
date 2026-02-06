// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationGuardian} from "interfaces/organization/IOrganizationGuardian.sol";
import {OrganizationModifiers} from "organization/common/OrganizationModifiers.sol";
import {LibOrganizationAdmin} from "organization/libraries/LibOrganizationAdmin.sol";
import {LibOrganizationGuardian} from "organization/libraries/LibOrganizationGuardian.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";
import {OperationType} from "types/CommonTypes.sol";

/**
 * @title OrganizationGuardianBase
 * @dev Abstract contract implementing IOrganizationGuardian.
 *      Handles normal guardian update flow: initiate → finalize → accept.
 * @author Den Technologies Inc
 */
abstract contract OrganizationGuardianBase is OrganizationModifiers, IOrganizationGuardian {
    /// @inheritdoc IOrganizationGuardian
    function initiateGuardianUpdate(address newGuardian, AdminAuthParams calldata authParams)
        external
        override
        onlyGuardian
    {
        // Encode the operation data for validation
        bytes memory operationData = abi.encode(newGuardian);

        // Validate that the current admin has authorized this operation (isApproval = true for execution)
        LibOrganizationAdmin.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.InitiateUpdateGuardian,
            operationData: operationData,
            isApproval: true,
            authParams: authParams
        });

        LibOrganizationGuardian.initiateGuardianUpdate(newGuardian);
    }

    /// @inheritdoc IOrganizationGuardian
    function finalizeGuardianUpdate(AdminAuthParams calldata authParams) external override onlyGuardian {
        // Get pending guardian for operation data
        address pendingGuardianAddr = LibOrganizationGuardian.getPendingGuardian();

        // Encode the operation data for validation
        bytes memory operationData = abi.encode(pendingGuardianAddr);

        // Validate that the current admin has authorized this operation (separate OperationType from initiate)
        LibOrganizationAdmin.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.FinalizeUpdateGuardian,
            operationData: operationData,
            isApproval: true,
            authParams: authParams
        });

        LibOrganizationGuardian.finalizeGuardianUpdate();
    }

    /// @inheritdoc IOrganizationGuardian
    function cancelGuardianUpdate(AdminAuthParams calldata authParams) external override onlyGuardian {
        // Get pending guardian for operation data
        address pendingGuardianAddr = LibOrganizationGuardian.getPendingGuardian();

        // Encode the operation data for validation
        bytes memory operationData = abi.encode(pendingGuardianAddr);

        // Validate that the current admin has authorized this operation (isApproval = false for cancellation)
        LibOrganizationAdmin.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.InitiateUpdateGuardian,
            operationData: operationData,
            isApproval: false,
            authParams: authParams
        });

        LibOrganizationGuardian.cancelGuardianUpdate();
    }

    /// @inheritdoc IOrganizationGuardian
    function acceptGuardian() external override onlyPendingGuardian {
        LibOrganizationGuardian.acceptGuardian();
    }

    /// @inheritdoc IOrganizationGuardian
    function guardian() external view override returns (address) {
        return LibOrganizationGuardian.getGuardian();
    }

    /// @inheritdoc IOrganizationGuardian
    function pendingGuardian() external view override returns (address) {
        return LibOrganizationGuardian.getPendingGuardian();
    }

    /// @inheritdoc IOrganizationGuardian
    function pendingGuardianUpdateTimestamp() external view override returns (uint256) {
        return LibOrganizationGuardian.getPendingGuardianUpdateTimestamp();
    }

    /// @inheritdoc IOrganizationGuardian
    function isGuardianUpdateReadyForAcceptance() external view override returns (bool) {
        return LibOrganizationGuardian.getIsGuardianUpdateReadyForAcceptance();
    }
}
