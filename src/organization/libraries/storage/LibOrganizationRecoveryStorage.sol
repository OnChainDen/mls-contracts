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
     * @dev Storage layout for recovery functionality.
     *      Struct is ordered for optimal storage packing (7 slots).
     * @custom:storage-location erc7201:den.mls-wallet.organization.recovery
     * @param transactionAndERC1271RecoveryAddress The privileged address that can execute recovery transactions and
     * sign via recovery
     * @param isRecoverySupportedForTransactionsAndERC1271 Whether recovery is supported for account transactions and
     * ERC1271 signatures (immutable after init)
     * @param isRecoveryEnabledForTransactionsAndERC1271 Whether recovery is currently enabled for transactions and
     * ERC1271
     * @param guardianRecoveryAddress The privileged address that can update the guardian via recovery
     * @param txRecoveryTimelockDuration The duration in seconds for tx/ERC1271 recovery enable timelocks
     * @param pendingTxRecoveryEnableTimestamp Timestamp when pending tx recovery enable can be finalized (0 = no
     * pending)
     * @param guardianRecoveryTimelockDuration The duration in seconds for guardian recovery timelocks
     * @param recoveryPendingGuardian The proposed new guardian address for recovery flow (0 = no pending)
     * @param isRecoveryGuardianUpdateReadyForAcceptance True after finalize, waiting for new guardian to accept
     * (recovery flow)
     * @param recoveryPendingGuardianTimestamp When the recovery flow pending update timelock expires (0 = no pending)
     */
    struct Layout {
        address transactionAndERC1271RecoveryAddress;
        bool isRecoverySupportedForTransactionsAndERC1271;
        bool isRecoveryEnabledForTransactionsAndERC1271;
        address guardianRecoveryAddress;
        uint256 txRecoveryTimelockDuration;
        uint256 pendingTxRecoveryEnableTimestamp;
        uint256 guardianRecoveryTimelockDuration;
        address recoveryPendingGuardian;
        bool isRecoveryGuardianUpdateReadyForAcceptance;
        uint256 recoveryPendingGuardianTimestamp;
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
