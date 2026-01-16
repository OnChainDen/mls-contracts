// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

/**
 * @title Organization Recovery Storage
 * @dev ERC-7201 namespaced storage for disaster recovery functionality.
 *      Stores recovery configuration (set at init) and recovery state.
 * @author Den Technologies Inc
 */
library LibOrganizationRecoveryStorage {
    /**
     * @dev Storage layout for recovery functionality
     * @custom:storage-location erc7201:den.mls-wallet.organization.recovery
     * @param isRecoverySupportedForTransactionsAndERC1271 Whether recovery is supported for account transactions and
     * ERC1271 signatures (immutable after init)
     * @param transactionAndERC1271RecoveryAddress The privileged address that can execute recovery transactions and
     * sign via recovery
     * @param guardianRecoveryAddress The privileged address that can update the guardian via recovery
     * @param recoveryTimelockDuration The duration in seconds for recovery timelocks
     * @param isRecoveryEnabledForTransactionsAndERC1271 Whether recovery is currently enabled for transactions and
     * ERC1271
     * @param pendingTxRecoveryEnableTimestamp Timestamp when pending tx recovery enable can be finalized (0 = no
     * pending)
     * @param recoveryPendingGuardian The proposed new guardian address for recovery flow (0 = no pending)
     * @param recoveryPendingGuardianTimestamp When the recovery flow pending update timelock expires (0 = no pending)
     * @param isRecoveryGuardianUpdateReadyForAcceptance True after finalize, waiting for new guardian to accept
     * (recovery flow)
     */
    struct Layout {
        // Core config (set at init, immutable after)
        bool isRecoverySupportedForTransactionsAndERC1271;
        address transactionAndERC1271RecoveryAddress;
        address guardianRecoveryAddress;
        uint256 recoveryTimelockDuration;
        // Transaction/ERC1271 recovery enabled state (toggleable via timelocked functions)
        bool isRecoveryEnabledForTransactionsAndERC1271;
        // Pending timelock timestamp for enabling tx recovery (0 = no pending request)
        uint256 pendingTxRecoveryEnableTimestamp;
        // Recovery guardian update state (separate from normal flow)
        address recoveryPendingGuardian;
        uint256 recoveryPendingGuardianTimestamp;
        bool isRecoveryGuardianUpdateReadyForAcceptance;
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
