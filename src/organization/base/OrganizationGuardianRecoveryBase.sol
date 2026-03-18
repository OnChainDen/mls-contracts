// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationAdmin} from "interfaces/organization/IOrganizationAdmin.sol";
import {IOrganizationGuardianRecovery} from "interfaces/organization/IOrganizationGuardianRecovery.sol";
import {OrganizationModifiers} from "organization/common/OrganizationModifiers.sol";
import {LibOrganizationAdmin} from "organization/libraries/LibOrganizationAdmin.sol";
import {LibOrganizationGuardianRecovery} from "organization/libraries/LibOrganizationGuardianRecovery.sol";
import {LibOrganizationRecoveryStorage} from "organization/libraries/storage/LibOrganizationRecoveryStorage.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";
import {OperationType} from "types/CommonTypes.sol";
import {GuardianRecoveryState} from "types/RecoveryTypes.sol";

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
    // slither-disable-next-line missing-zero-check
    function initiateInitializeGuardianRecovery(
        address recoveryAddress,
        uint256 timelockDurationSeconds,
        AdminAuthParams calldata authParams
    ) external override onlyGuardian {
        // Encode the operation data for validation
        bytes memory operationData = abi.encode(recoveryAddress, timelockDurationSeconds);

        // Validate that the current admin has authorized this initiation (isApproval = true for execution)
        uint256 nonce = LibOrganizationAdmin.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.InitiateInitializeGuardianRecovery,
            operationData: operationData,
            isApproval: true,
            authParams: authParams
        });

        // Execute via low-level self-call so that a revert does not bubble up.
        /* solhint-disable avoid-low-level-calls */
        // forgefmt: disable-start
        // slither-disable-next-line low-level-calls,reentrancy-events,missing-zero-check
        (bool success, bytes memory revertData) = address(this).call(
            abi.encodeCall(this.executeInitiateInitializeGuardianRecovery, (recoveryAddress, timelockDurationSeconds))
        );
        // forgefmt: disable-end
        /* solhint-enable avoid-low-level-calls */

        if (!success) {
            emit IOrganizationAdmin.AdminOperationExecutionReverted(
                OperationType.InitiateInitializeGuardianRecovery, nonce, revertData
            );
        }
    }

    /// @inheritdoc IOrganizationGuardianRecovery
    function executeInitiateInitializeGuardianRecovery(address recoveryAddress, uint256 timelockDurationSeconds)
        external
        onlySelf
    {
        LibOrganizationGuardianRecovery.initiateInitializeGuardianRecovery(recoveryAddress, timelockDurationSeconds);
    }

    /// @inheritdoc IOrganizationGuardianRecovery
    function finalizeInitializeGuardianRecovery(AdminAuthParams calldata authParams) external override onlyGuardian {
        // Get pending values directly from storage for operation data
        // forgefmt: disable-next-item
        GuardianRecoveryState storage guardianRecovery =
            LibOrganizationRecoveryStorage.layout().guardianRecovery;
        address pendingAddress = guardianRecovery.pendingInit.pendingRecoveryAddress;
        uint256 pendingTimelock = guardianRecovery.pendingInit.pendingTimelockDurationSeconds;

        // Encode the operation data for validation
        bytes memory operationData = abi.encode(pendingAddress, pendingTimelock);

        // Validate that the current admin has authorized this finalization (separate OperationType from initiate)
        uint256 nonce = LibOrganizationAdmin.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.FinalizeInitializeGuardianRecovery,
            operationData: operationData,
            isApproval: true,
            authParams: authParams
        });

        // Execute via low-level self-call so that a revert does not bubble up.
        /* solhint-disable avoid-low-level-calls */
        // slither-disable-next-line low-level-calls,reentrancy-events
        (bool success, bytes memory revertData) =
            address(this).call(abi.encodeCall(this.executeFinalizeInitializeGuardianRecovery, ()));
        /* solhint-enable avoid-low-level-calls */

        if (!success) {
            emit IOrganizationAdmin.AdminOperationExecutionReverted(
                OperationType.FinalizeInitializeGuardianRecovery, nonce, revertData
            );
        }
    }

    /// @inheritdoc IOrganizationGuardianRecovery
    function executeFinalizeInitializeGuardianRecovery() external onlySelf {
        LibOrganizationGuardianRecovery.finalizeInitializeGuardianRecovery();
    }

    /// @inheritdoc IOrganizationGuardianRecovery
    function cancelInitializeGuardianRecovery(AdminAuthParams calldata authParams) external override onlyGuardian {
        // Get pending values directly from storage for operation data
        // forgefmt: disable-next-item
        GuardianRecoveryState storage guardianRecovery =
            LibOrganizationRecoveryStorage.layout().guardianRecovery;
        address pendingAddress = guardianRecovery.pendingInit.pendingRecoveryAddress;
        uint256 pendingTimelock = guardianRecovery.pendingInit.pendingTimelockDurationSeconds;

        // Encode the operation data for validation
        bytes memory operationData = abi.encode(pendingAddress, pendingTimelock);

        // Validate that the current admin has authorized this cancellation (dedicated Cancel type)
        uint256 nonce = LibOrganizationAdmin.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.CancelInitializeGuardianRecovery,
            operationData: operationData,
            isApproval: true,
            authParams: authParams
        });

        // Execute via low-level self-call so that a revert does not bubble up.
        /* solhint-disable avoid-low-level-calls */
        // slither-disable-next-line low-level-calls,reentrancy-events
        (bool success, bytes memory revertData) =
            address(this).call(abi.encodeCall(this.executeCancelInitializeGuardianRecovery, ()));
        /* solhint-enable avoid-low-level-calls */

        if (!success) {
            emit IOrganizationAdmin.AdminOperationExecutionReverted(
                OperationType.CancelInitializeGuardianRecovery, nonce, revertData
            );
        }
    }

    /// @inheritdoc IOrganizationGuardianRecovery
    function executeCancelInitializeGuardianRecovery() external onlySelf {
        LibOrganizationGuardianRecovery.cancelInitializeGuardianRecovery();
    }

    /// @inheritdoc IOrganizationGuardianRecovery
    function getGuardianRecoveryState() external view override returns (GuardianRecoveryState memory) {
        return LibOrganizationRecoveryStorage.layout().guardianRecovery;
    }
}
