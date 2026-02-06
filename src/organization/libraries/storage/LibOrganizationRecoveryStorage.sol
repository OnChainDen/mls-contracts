// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

/**
 * @title Organization Recovery Storage
 * @dev ERC-7201 namespaced storage for disaster recovery functionality.
 *      Stores recovery configuration (set at init) and recovery state.
 *      Storage is organized into two nested structs for clarity:
 *      - TxRecoveryState: Transaction and ERC1271 signature recovery
 *      - GuardianRecoveryState: Guardian update recovery
 * @author Den Technologies Inc
 */
library LibOrganizationRecoveryStorage {
    /**
     * @dev Storage for transaction and ERC1271 signature recovery functionality.
     * @param recoveryAddress The privileged address that can execute recovery transactions and sign via recovery
     * @param isEnabled Whether recovery is currently enabled for transactions and ERC1271
     * @param timelockDurationSeconds The duration in seconds for tx/ERC1271 recovery enable timelocks
     * @param pendingEnableTimestamp Timestamp when pending tx recovery enable can be finalized (0 = no pending)
     * @param pendingInitRecoveryAddress The proposed recovery address during deferred initialization (0 = no pending)
     * @param pendingInitTimelockDurationSeconds The proposed timelock duration during deferred initialization
     * @param pendingInitTimestamp Timestamp when pending initialization can be finalized (0 = no pending)
     */
    struct TxRecoveryState {
        address recoveryAddress;
        bool isEnabled;
        uint256 timelockDurationSeconds;
        uint256 pendingEnableTimestamp;
        address pendingInitRecoveryAddress;
        uint256 pendingInitTimelockDurationSeconds;
        uint256 pendingInitTimestamp;
    }

    /**
     * @dev Storage for guardian recovery functionality.
     * @param recoveryAddress The privileged address that can update the guardian via recovery
     * @param isUpdateReadyForAcceptance True after finalize, waiting for new guardian to accept (recovery flow)
     * @param pendingGuardian The proposed new guardian address for recovery flow (0 = no pending)
     * @param timelockDurationSeconds The duration in seconds for guardian recovery timelocks
     * @param pendingGuardianTimestamp When the recovery flow pending update timelock expires (0 = no pending)
     * @param pendingInitRecoveryAddress The proposed recovery address during deferred initialization (0 = no pending)
     * @param pendingInitTimelockDurationSeconds The proposed timelock duration during deferred initialization
     * @param pendingInitTimestamp Timestamp when pending initialization can be finalized (0 = no pending)
     */
    struct GuardianRecoveryState {
        address recoveryAddress;
        bool isUpdateReadyForAcceptance;
        address pendingGuardian;
        uint256 timelockDurationSeconds;
        uint256 pendingGuardianTimestamp;
        address pendingInitRecoveryAddress;
        uint256 pendingInitTimelockDurationSeconds;
        uint256 pendingInitTimestamp;
    }

    /**
     * @dev Main storage layout containing both recovery subsystems.
     * @custom:storage-location erc7201:den.mls-wallet.organization.recovery
     * @param txRecovery Storage for transaction and ERC1271 signature recovery
     * @param guardianRecovery Storage for guardian recovery
     */
    struct Layout {
        TxRecoveryState txRecovery;
        GuardianRecoveryState guardianRecovery;
    }

    /// @dev Storage location for RecoveryStorage, following ERC-7201 namespaced storage pattern.
    /// @dev Formula: keccak256(abi.encode(uint256(keccak256("den.mls-wallet.organization.recovery")) - 1)) &
    /// ~bytes32(uint256(0xff)) @dev Verify: `cast index-erc7201 "den.mls-wallet.organization.recovery"`
    bytes32 internal constant STORAGE_LOCATION = 0x3422f7ce8e1ae9226ca4f03d7ea92f44f09e1e9e24da8779dcbf69ffe6d91c00;

    /**
     * @dev Returns the storage layout at the namespaced slot
     * @return _layout The storage layout struct
     */
    function layout() internal pure returns (Layout storage _layout) {
        assembly {
            _layout.slot := STORAGE_LOCATION
        }
    }
}
