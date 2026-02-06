// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

/**
 * @title Recovery Types
 * @notice Shared data structures for recovery subsystems (transaction recovery and guardian recovery)
 * @author Den Technologies Inc
 */

/**
 * @notice Shared struct for pending deferred recovery initialization state.
 *         Used by both TxRecoveryState and GuardianRecoveryState.
 * @param pendingRecoveryAddress The proposed recovery address (0 = no pending)
 * @param pendingTimelockDurationSeconds The proposed timelock duration
 * @param pendingTimestamp Timestamp when initialization can be finalized (0 = no pending)
 */
struct PendingRecoveryInitTimelock {
    address pendingRecoveryAddress;
    uint256 pendingTimelockDurationSeconds;
    uint256 pendingTimestamp;
}

/**
 * @notice Storage state for transaction and ERC1271 signature recovery functionality.
 * @param recoveryAddress The privileged address that can execute recovery transactions and sign via recovery
 * @param isEnabled Whether recovery is currently enabled for transactions and ERC1271
 * @param timelockDurationSeconds The duration in seconds for tx/ERC1271 recovery enable timelocks
 * @param pendingEnableTimestamp Timestamp when pending tx recovery enable can be finalized (0 = no pending)
 * @param pendingInit Pending deferred initialization state
 */
struct TxRecoveryState {
    address recoveryAddress;
    bool isEnabled;
    uint256 timelockDurationSeconds;
    uint256 pendingEnableTimestamp;
    PendingRecoveryInitTimelock pendingInit;
}

/**
 * @notice Storage state for guardian recovery functionality.
 * @param recoveryAddress The privileged address that can update the guardian via recovery
 * @param isUpdateReadyForAcceptance True after finalize, waiting for new guardian to accept (recovery flow)
 * @param pendingGuardian The proposed new guardian address for recovery flow (0 = no pending)
 * @param timelockDurationSeconds The duration in seconds for guardian recovery timelocks
 * @param pendingGuardianTimestamp When the recovery flow pending update timelock expires (0 = no pending)
 * @param pendingInit Pending deferred initialization state
 */
struct GuardianRecoveryState {
    address recoveryAddress;
    bool isUpdateReadyForAcceptance;
    address pendingGuardian;
    uint256 timelockDurationSeconds;
    uint256 pendingGuardianTimestamp;
    PendingRecoveryInitTimelock pendingInit;
}
