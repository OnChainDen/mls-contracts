// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationGuardianRecovery} from "interfaces/organization/IOrganizationGuardianRecovery.sol";
import {OrganizationModifiers} from "organization/common/OrganizationModifiers.sol";
import {LibOrganizationAdmin} from "organization/libraries/LibOrganizationAdmin.sol";
import {LibOrganizationGuardianRecovery} from "organization/libraries/LibOrganizationGuardianRecovery.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";
import {OperationType} from "types/CommonTypes.sol";

/**
 * @title OrganizationGuardianRecoveryBase
 * @dev Abstract contract implementing IOrganizationGuardianRecovery.
 *      Handles guardian recovery flow: initiate → finalize → accept.
 *      Uses separate storage from normal guardian updates.
 * @author Den Technologies Inc
 */
abstract contract OrganizationGuardianRecoveryBase is OrganizationModifiers, IOrganizationGuardianRecovery {
    /// @inheritdoc IOrganizationGuardianRecovery
    function initiateRecoveryGuardianUpdate(address newGuardian) external override onlyGuardianRecoveryAddress {
        LibOrganizationGuardianRecovery.initiateRecoveryGuardianUpdate(newGuardian);
    }

    /// @inheritdoc IOrganizationGuardianRecovery
    function finalizeRecoveryGuardianUpdate() external override onlyGuardianRecoveryAddress {
        LibOrganizationGuardianRecovery.finalizeRecoveryGuardianUpdate();
    }

    /// @inheritdoc IOrganizationGuardianRecovery
    function cancelRecoveryGuardianUpdate() external override onlyGuardianRecoveryAddress {
        LibOrganizationGuardianRecovery.cancelRecoveryGuardianUpdate();
    }

    /// @inheritdoc IOrganizationGuardianRecovery
    function acceptGuardianRecovery() external override onlyRecoveryPendingGuardian {
        LibOrganizationGuardianRecovery.acceptGuardianRecovery();
    }

    /// @inheritdoc IOrganizationGuardianRecovery
    function initiateInitializeGuardianRecovery(
        address recoveryAddress,
        uint256 timelockDurationSeconds,
        AdminAuthParams calldata authParams
    ) external override onlyGuardian {
        // Encode the operation data for validation
        bytes memory operationData = abi.encode(recoveryAddress, timelockDurationSeconds);

        // Validate that the current admin has authorized this initiation (isApproval = true for execution)
        LibOrganizationAdmin.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.InitiateInitializeGuardianRecovery,
            operationData: operationData,
            isApproval: true,
            authParams: authParams
        });

        // Initiate deferred initialization (starts timelock)
        LibOrganizationGuardianRecovery.initiateInitializeGuardianRecovery(recoveryAddress, timelockDurationSeconds);
    }

    /// @inheritdoc IOrganizationGuardianRecovery
    function finalizeInitializeGuardianRecovery(AdminAuthParams calldata authParams) external override onlyGuardian {
        // Get pending values for operation data
        address pendingAddress = LibOrganizationGuardianRecovery.getPendingInitGuardianRecoveryAddress();
        // forgefmt: disable-next-item
        uint256 pendingTimelock =
            LibOrganizationGuardianRecovery.getPendingInitGuardianRecoveryTimelockDurationSeconds();

        // Encode the operation data for validation
        bytes memory operationData = abi.encode(pendingAddress, pendingTimelock);

        // Validate that the current admin has authorized this finalization (separate OperationType from initiate)
        LibOrganizationAdmin.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.FinalizeInitializeGuardianRecovery,
            operationData: operationData,
            isApproval: true,
            authParams: authParams
        });

        // Finalize deferred initialization (writes config after timelock)
        LibOrganizationGuardianRecovery.finalizeInitializeGuardianRecovery();
    }

    /// @inheritdoc IOrganizationGuardianRecovery
    function cancelInitializeGuardianRecovery(AdminAuthParams calldata authParams) external override onlyGuardian {
        // Get pending values for operation data
        address pendingAddress = LibOrganizationGuardianRecovery.getPendingInitGuardianRecoveryAddress();
        // forgefmt: disable-next-item
        uint256 pendingTimelock =
            LibOrganizationGuardianRecovery.getPendingInitGuardianRecoveryTimelockDurationSeconds();

        // Encode the operation data for validation
        bytes memory operationData = abi.encode(pendingAddress, pendingTimelock);

        // Validate that the current admin has authorized this cancellation (isApproval = false)
        LibOrganizationAdmin.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.InitiateInitializeGuardianRecovery,
            operationData: operationData,
            isApproval: false,
            authParams: authParams
        });

        // Cancel the pending initialization
        LibOrganizationGuardianRecovery.cancelInitializeGuardianRecovery();
    }

    /// @inheritdoc IOrganizationGuardianRecovery
    function guardianRecoveryAddress() external view override returns (address) {
        return LibOrganizationGuardianRecovery.getGuardianRecoveryAddress();
    }

    /// @inheritdoc IOrganizationGuardianRecovery
    function guardianRecoveryTimelockDurationSeconds() external view override returns (uint256) {
        return LibOrganizationGuardianRecovery.getGuardianRecoveryTimelockDurationSeconds();
    }

    /// @inheritdoc IOrganizationGuardianRecovery
    function recoveryPendingGuardian() external view override returns (address) {
        return LibOrganizationGuardianRecovery.getRecoveryPendingGuardian();
    }

    /// @inheritdoc IOrganizationGuardianRecovery
    function recoveryPendingGuardianTimestamp() external view override returns (uint256) {
        return LibOrganizationGuardianRecovery.getRecoveryPendingGuardianTimestamp();
    }

    /// @inheritdoc IOrganizationGuardianRecovery
    function isRecoveryGuardianUpdateReadyForAcceptance() external view override returns (bool) {
        return LibOrganizationGuardianRecovery.getIsRecoveryGuardianUpdateReadyForAcceptance();
    }

    /// @inheritdoc IOrganizationGuardianRecovery
    function pendingInitGuardianRecoveryAddress() external view override returns (address) {
        return LibOrganizationGuardianRecovery.getPendingInitGuardianRecoveryAddress();
    }

    /// @inheritdoc IOrganizationGuardianRecovery
    function pendingInitGuardianRecoveryTimelockDurationSeconds() external view override returns (uint256) {
        return LibOrganizationGuardianRecovery.getPendingInitGuardianRecoveryTimelockDurationSeconds();
    }

    /// @inheritdoc IOrganizationGuardianRecovery
    function pendingInitGuardianRecoveryTimestamp() external view override returns (uint256) {
        return LibOrganizationGuardianRecovery.getPendingInitGuardianRecoveryTimestamp();
    }
}
