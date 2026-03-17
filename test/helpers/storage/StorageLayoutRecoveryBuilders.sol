// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {GuardianRecoveryState, PendingRecoveryInitTimelock, TxRecoveryState} from "types/RecoveryTypes.sol";

/**
 * @dev Storage Layout Recovery Builders
 *      Helpers for building structs for recovery storage test fixtures.
 */
abstract contract StorageLayoutRecoveryBuilders {
    /**
     * @dev Builds a tx recovery state struct for concise test setup.
     * @param recoveryAddress Recovery address for the tx recovery subtree.
     * @param isEnabled Whether tx recovery is currently enabled.
     * @param timelockDurationSeconds Current tx recovery timelock duration.
     * @param pendingEnableTimestamp Timestamp when pending enablement can be accepted.
     * @param pendingRecoveryAddress Pending recovery address in the nested init struct.
     * @param pendingTimelockDurationSeconds Pending timelock duration in the nested init struct.
     * @param pendingTimestamp Pending-init timestamp in the nested init struct.
     */
    function _buildTxRecoveryState(
        address recoveryAddress,
        bool isEnabled,
        uint256 timelockDurationSeconds,
        uint256 pendingEnableTimestamp,
        address pendingRecoveryAddress,
        uint256 pendingTimelockDurationSeconds,
        uint256 pendingTimestamp
    ) internal pure returns (TxRecoveryState memory txRecoveryState) {
        txRecoveryState.recoveryAddress = recoveryAddress;
        txRecoveryState.isEnabled = isEnabled;
        txRecoveryState.timelockDurationSeconds = timelockDurationSeconds;
        txRecoveryState.pendingEnableTimestamp = pendingEnableTimestamp;
        txRecoveryState.pendingInit =
            _buildPendingRecoveryInit(pendingRecoveryAddress, pendingTimelockDurationSeconds, pendingTimestamp);
    }

    /**
     * @dev Builds a guardian recovery state struct for concise test setup.
     * @param recoveryAddress Recovery address for the guardian recovery subtree.
     * @param isUpdateReadyForAcceptance Whether guardian update is ready for acceptance.
     * @param pendingGuardian Pending guardian address.
     * @param timelockDurationSeconds Current guardian recovery timelock duration.
     * @param pendingGuardianTimestamp Timestamp for pending guardian acceptance.
     * @param pendingRecoveryAddress Pending recovery address in the nested init struct.
     * @param pendingTimelockDurationSeconds Pending timelock duration in the nested init struct.
     * @param pendingTimestamp Pending-init timestamp in the nested init struct.
     */
    function _buildGuardianRecoveryState(
        address recoveryAddress,
        bool isUpdateReadyForAcceptance,
        address pendingGuardian,
        uint256 timelockDurationSeconds,
        uint256 pendingGuardianTimestamp,
        address pendingRecoveryAddress,
        uint256 pendingTimelockDurationSeconds,
        uint256 pendingTimestamp
    ) internal pure returns (GuardianRecoveryState memory guardianRecoveryState) {
        guardianRecoveryState.recoveryAddress = recoveryAddress;
        guardianRecoveryState.isUpdateReadyForAcceptance = isUpdateReadyForAcceptance;
        guardianRecoveryState.pendingGuardian = pendingGuardian;
        guardianRecoveryState.timelockDurationSeconds = timelockDurationSeconds;
        guardianRecoveryState.pendingGuardianTimestamp = pendingGuardianTimestamp;
        guardianRecoveryState.pendingInit =
            _buildPendingRecoveryInit(pendingRecoveryAddress, pendingTimelockDurationSeconds, pendingTimestamp);
    }

    /**
     * @dev Builds shared pending-init struct used by both recovery subtrees.
     * @param pendingRecoveryAddress Pending recovery address.
     * @param pendingTimelockDurationSeconds Pending timelock duration.
     * @param pendingTimestamp Pending-init timestamp.
     */
    function _buildPendingRecoveryInit(
        address pendingRecoveryAddress,
        uint256 pendingTimelockDurationSeconds,
        uint256 pendingTimestamp
    ) internal pure returns (PendingRecoveryInitTimelock memory pendingRecoveryInitTimelock) {
        pendingRecoveryInitTimelock.pendingRecoveryAddress = pendingRecoveryAddress;
        pendingRecoveryInitTimelock.pendingTimelockDurationSeconds = pendingTimelockDurationSeconds;
        pendingRecoveryInitTimelock.pendingTimestamp = pendingTimestamp;
    }
}
