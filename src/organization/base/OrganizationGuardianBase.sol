// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationAdmin} from "interfaces/organization/IOrganizationAdmin.sol";
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
    // slither-disable-next-line missing-zero-check
    function initiateGuardianUpdate(address newGuardian, AdminAuthParams calldata authParams)
        external
        override
        onlyGuardian
    {
        // Encode the operation data for validation
        bytes memory operationData = abi.encode(newGuardian);

        // Validate that the current admin has authorized this operation (isApproval = true for execution)
        uint256 nonce = LibOrganizationAdmin.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.InitiateUpdateGuardian,
            operationData: operationData,
            isApproval: true,
            authParams: authParams
        });

        // Execute via low-level self-call so that a revert does not bubble up.
        /* solhint-disable avoid-low-level-calls */
        // forgefmt: disable-start
        // slither-disable-next-line low-level-calls,reentrancy-events,missing-zero-check
        (bool success, bytes memory revertData) =
            address(this).call(abi.encodeCall(this.executeInitiateGuardianUpdate, (newGuardian)));
        // forgefmt: disable-end
        /* solhint-enable avoid-low-level-calls */

        if (!success) {
            emit IOrganizationAdmin.AdminOperationExecutionReverted(
                OperationType.InitiateUpdateGuardian, nonce, revertData
            );
        }
    }

    /// @inheritdoc IOrganizationGuardian
    function executeInitiateGuardianUpdate(address newGuardian) external override onlySelf {
        LibOrganizationGuardian.initiateGuardianUpdate(newGuardian);
    }

    /// @inheritdoc IOrganizationGuardian
    function finalizeGuardianUpdate(AdminAuthParams calldata authParams) external override onlyGuardian {
        // Get pending guardian for operation data
        address pendingGuardianAddr = LibOrganizationGuardian.getPendingGuardian();

        // Encode the operation data for validation
        bytes memory operationData = abi.encode(pendingGuardianAddr);

        // Validate that the current admin has authorized this operation (separate OperationType from initiate)
        uint256 nonce = LibOrganizationAdmin.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.FinalizeUpdateGuardian,
            operationData: operationData,
            isApproval: true,
            authParams: authParams
        });

        // Execute via low-level self-call so that a revert does not bubble up.
        /* solhint-disable avoid-low-level-calls */
        // slither-disable-next-line low-level-calls,reentrancy-events
        (bool success, bytes memory revertData) =
            address(this).call(abi.encodeCall(this.executeFinalizeGuardianUpdate, ()));
        /* solhint-enable avoid-low-level-calls */

        if (!success) {
            emit IOrganizationAdmin.AdminOperationExecutionReverted(
                OperationType.FinalizeUpdateGuardian, nonce, revertData
            );
        }
    }

    /// @inheritdoc IOrganizationGuardian
    function executeFinalizeGuardianUpdate() external override onlySelf {
        LibOrganizationGuardian.finalizeGuardianUpdate();
    }

    /// @inheritdoc IOrganizationGuardian
    function cancelGuardianUpdate(AdminAuthParams calldata authParams) external override onlyGuardian {
        // Get pending guardian for operation data
        address pendingGuardianAddr = LibOrganizationGuardian.getPendingGuardian();

        // Encode the operation data for validation
        bytes memory operationData = abi.encode(pendingGuardianAddr);

        // Validate that the current admin has authorized this cancellation (dedicated CancelUpdateGuardian type)
        uint256 nonce = LibOrganizationAdmin.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.CancelUpdateGuardian,
            operationData: operationData,
            isApproval: true,
            authParams: authParams
        });

        // Execute via low-level self-call so that a revert does not bubble up.
        /* solhint-disable avoid-low-level-calls */
        // slither-disable-next-line low-level-calls,reentrancy-events
        (bool success, bytes memory revertData) =
            address(this).call(abi.encodeCall(this.executeCancelGuardianUpdate, ()));
        /* solhint-enable avoid-low-level-calls */

        if (!success) {
            emit IOrganizationAdmin.AdminOperationExecutionReverted(
                OperationType.CancelUpdateGuardian, nonce, revertData
            );
        }
    }

    /// @inheritdoc IOrganizationGuardian
    function executeCancelGuardianUpdate() external override onlySelf {
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
