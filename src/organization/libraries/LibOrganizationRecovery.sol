// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {IOrganizationRecovery} from "interfaces/organization/IOrganizationRecovery.sol";
import {SignatureChecker} from "libraries/SignatureChecker.sol";
import {LibOrganizationGuardianStorage} from "organization/libraries/storage/LibOrganizationGuardianStorage.sol";
import {LibOrganizationRecoveryStorage} from "organization/libraries/storage/LibOrganizationRecoveryStorage.sol";

/**
 * @title Lib Organization Recovery
 * @dev Library for disaster recovery operations for Organization contracts.
 *      This library handles all recovery-related functionality including:
 *      - Enabling/disabling recovery modes (with timelocks)
 *      - Recovery account transactions (bypassing guardian/policy checks)
 *      - Recovery guardian updates (bypassing normal admin flow)
 *      - Recovery ERC1271 signature validation
 *
 *      All recovery functions are consolidated here for easier auditing.
 * @author Den Technologies Inc
 */
library LibOrganizationRecovery {
    /**
     * @dev Initializes the recovery configuration during organization initialization.
     *      This should be called from LibOrganizationInitialization.initialize().
     * @param isRecoverySupportedForTransactionsAndERC1271 Whether recovery is supported for tx/signatures
     * @param transactionAndERC1271RecoveryAddress The tx recovery address (must be non-zero if supported)
     * @param guardianRecoveryAddress The guardian recovery address (must always be non-zero)
     * @param recoveryTimelockDuration The timelock duration in seconds (must be > 0)
     */
    function initializeRecovery(
        bool isRecoverySupportedForTransactionsAndERC1271,
        address transactionAndERC1271RecoveryAddress,
        address guardianRecoveryAddress,
        uint256 recoveryTimelockDuration
    ) internal {
        // Validate timelock duration
        if (recoveryTimelockDuration == 0) {
            revert IOrganizationRecovery.InvalidRecoveryTimelockDuration();
        }

        // Validate guardian recovery address (always required)
        if (guardianRecoveryAddress == address(0)) {
            revert IOrganizationRecovery.InvalidGuardianRecoveryAddress();
        }

        // Validate tx recovery address based on support flag
        if (isRecoverySupportedForTransactionsAndERC1271) {
            // Case: Recovery is supported, address must be set
            if (transactionAndERC1271RecoveryAddress == address(0)) {
                revert IOrganizationRecovery.InvalidTransactionAndERC1271RecoveryAddress();
            }
        } else {
            // Case: Recovery is not supported, address must be zero
            if (transactionAndERC1271RecoveryAddress != address(0)) {
                revert IOrganizationRecovery.InvalidTransactionAndERC1271RecoveryAddress();
            }
        }

        LibOrganizationRecoveryStorage.Layout storage recoveryLayout = LibOrganizationRecoveryStorage.layout();

        recoveryLayout.isRecoverySupportedForTransactionsAndERC1271 = isRecoverySupportedForTransactionsAndERC1271;
        recoveryLayout.transactionAndERC1271RecoveryAddress = transactionAndERC1271RecoveryAddress;
        recoveryLayout.guardianRecoveryAddress = guardianRecoveryAddress;
        recoveryLayout.recoveryTimelockDuration = recoveryTimelockDuration;
    }

    /**
     * @dev Initiates enabling transaction and ERC1271 recovery (starts timelock).
     *      Reverts if recovery is not supported or if a request is already pending.
     */
    function initiateEnableTransactionAndERC1271Recovery() internal {
        LibOrganizationRecoveryStorage.Layout storage recoveryLayout = LibOrganizationRecoveryStorage.layout();

        // Case: Recovery not supported
        if (!recoveryLayout.isRecoverySupportedForTransactionsAndERC1271) {
            revert IOrganizationRecovery.RecoveryNotSupportedForTransactionsAndERC1271();
        }

        // Case: Already pending
        if (recoveryLayout.pendingTxRecoveryEnableTimestamp != 0) {
            revert IOrganizationRecovery.RecoveryEnableAlreadyPending();
        }

        uint256 canFinalizeAt = block.timestamp + recoveryLayout.recoveryTimelockDuration;
        recoveryLayout.pendingTxRecoveryEnableTimestamp = canFinalizeAt;

        emit IOrganizationRecovery.TransactionAndERC1271RecoveryEnableInitiated(canFinalizeAt);
    }

    /**
     * @dev Finalizes enabling transaction and ERC1271 recovery (after timelock).
     *      Reverts if no request is pending or timelock has not expired.
     */
    function finalizeEnableTransactionAndERC1271Recovery() internal {
        LibOrganizationRecoveryStorage.Layout storage recoveryLayout = LibOrganizationRecoveryStorage.layout();

        uint256 canFinalizeAt = recoveryLayout.pendingTxRecoveryEnableTimestamp;

        // Case: No pending request
        if (canFinalizeAt == 0) {
            revert IOrganizationRecovery.NoRecoveryEnablePending();
        }

        // Case: Timelock not expired
        if (block.timestamp < canFinalizeAt) {
            revert IOrganizationRecovery.RecoveryEnableTimelockNotExpired(canFinalizeAt, block.timestamp);
        }

        // Enable recovery and clear pending state
        recoveryLayout.isRecoveryEnabledForTransactionsAndERC1271 = true;
        recoveryLayout.pendingTxRecoveryEnableTimestamp = 0;

        emit IOrganizationRecovery.TransactionAndERC1271RecoveryEnableFinalized();
    }

    /**
     * @dev Cancels a pending transaction and ERC1271 recovery enable request.
     *      Reverts if no request is pending.
     */
    function cancelEnableTransactionAndERC1271Recovery() internal {
        LibOrganizationRecoveryStorage.Layout storage recoveryLayout = LibOrganizationRecoveryStorage.layout();

        // Case: No pending request
        if (recoveryLayout.pendingTxRecoveryEnableTimestamp == 0) {
            revert IOrganizationRecovery.NoRecoveryEnablePending();
        }

        recoveryLayout.pendingTxRecoveryEnableTimestamp = 0;

        emit IOrganizationRecovery.TransactionAndERC1271RecoveryEnableCancelled();
    }

    /**
     * @dev Immediately disables transaction and ERC1271 recovery (no timelock).
     *      Also clears any pending enable request.
     */
    function disableTransactionAndERC1271Recovery() internal {
        LibOrganizationRecoveryStorage.Layout storage recoveryLayout = LibOrganizationRecoveryStorage.layout();

        recoveryLayout.isRecoveryEnabledForTransactionsAndERC1271 = false;
        recoveryLayout.pendingTxRecoveryEnableTimestamp = 0;

        emit IOrganizationRecovery.TransactionAndERC1271RecoveryDisabled();
    }

    /**
     * @dev Initiates enabling guardian recovery (starts timelock).
     *      Reverts if a request is already pending.
     */
    function initiateEnableGuardianRecovery() internal {
        LibOrganizationRecoveryStorage.Layout storage recoveryLayout = LibOrganizationRecoveryStorage.layout();

        // Case: Already pending
        if (recoveryLayout.pendingGuardianRecoveryEnableTimestamp != 0) {
            revert IOrganizationRecovery.RecoveryEnableAlreadyPending();
        }

        uint256 canFinalizeAt = block.timestamp + recoveryLayout.recoveryTimelockDuration;
        recoveryLayout.pendingGuardianRecoveryEnableTimestamp = canFinalizeAt;

        emit IOrganizationRecovery.GuardianRecoveryEnableInitiated(canFinalizeAt);
    }

    /**
     * @dev Finalizes enabling guardian recovery (after timelock).
     *      Reverts if no request is pending or timelock has not expired.
     */
    function finalizeEnableGuardianRecovery() internal {
        LibOrganizationRecoveryStorage.Layout storage recoveryLayout = LibOrganizationRecoveryStorage.layout();

        uint256 canFinalizeAt = recoveryLayout.pendingGuardianRecoveryEnableTimestamp;

        // Case: No pending request
        if (canFinalizeAt == 0) {
            revert IOrganizationRecovery.NoRecoveryEnablePending();
        }

        // Case: Timelock not expired
        if (block.timestamp < canFinalizeAt) {
            revert IOrganizationRecovery.RecoveryEnableTimelockNotExpired(canFinalizeAt, block.timestamp);
        }

        // Enable recovery and clear pending state
        recoveryLayout.isRecoveryEnabledForGuardianUpdate = true;
        recoveryLayout.pendingGuardianRecoveryEnableTimestamp = 0;

        emit IOrganizationRecovery.GuardianRecoveryEnableFinalized();
    }

    /**
     * @dev Cancels a pending guardian recovery enable request.
     *      Reverts if no request is pending.
     */
    function cancelEnableGuardianRecovery() internal {
        LibOrganizationRecoveryStorage.Layout storage recoveryLayout = LibOrganizationRecoveryStorage.layout();

        // Case: No pending request
        if (recoveryLayout.pendingGuardianRecoveryEnableTimestamp == 0) {
            revert IOrganizationRecovery.NoRecoveryEnablePending();
        }

        recoveryLayout.pendingGuardianRecoveryEnableTimestamp = 0;

        emit IOrganizationRecovery.GuardianRecoveryEnableCancelled();
    }

    /**
     * @dev Immediately disables guardian recovery (no timelock).
     *      Also clears any pending enable request.
     */
    function disableGuardianRecovery() internal {
        LibOrganizationRecoveryStorage.Layout storage recoveryLayout = LibOrganizationRecoveryStorage.layout();

        recoveryLayout.isRecoveryEnabledForGuardianUpdate = false;
        recoveryLayout.pendingGuardianRecoveryEnableTimestamp = 0;

        emit IOrganizationRecovery.GuardianRecoveryDisabled();
    }

    /**
     * @dev Initiates a recovery guardian update (starts timelock).
     *      Sets the pending guardian in the guardian storage and marks it as a recovery update.
     *      Reverts if guardian recovery is not enabled.
     * @param newGuardian The proposed new guardian address
     */
    function initiateRecoveryGuardianUpdate(address newGuardian) internal {
        LibOrganizationRecoveryStorage.Layout storage recoveryLayout = LibOrganizationRecoveryStorage.layout();
        LibOrganizationGuardianStorage.Layout storage guardianLayout = LibOrganizationGuardianStorage.layout();

        // Case: Guardian recovery not enabled
        if (!recoveryLayout.isRecoveryEnabledForGuardianUpdate) {
            revert IOrganizationRecovery.RecoveryNotEnabledForGuardianUpdate();
        }

        // Case: Already a pending guardian update
        if (guardianLayout.pendingGuardian != address(0)) {
            revert IOrganizationRecovery.RecoveryEnableAlreadyPending();
        }

        // Validate new guardian is not zero
        if (newGuardian == address(0)) {
            revert IOrganizationRecovery.InvalidGuardianRecoveryAddress();
        }

        uint256 canFinalizeAt = block.timestamp + recoveryLayout.recoveryTimelockDuration;

        // Set pending state in guardian storage
        guardianLayout.pendingGuardian = newGuardian;
        guardianLayout.pendingGuardianUpdateTimestamp = canFinalizeAt;
        guardianLayout.isRecoveryGuardianUpdate = true;
        guardianLayout.isGuardianUpdateReadyForAcceptance = false;

        emit IOrganizationRecovery.RecoveryGuardianUpdateInitiated(guardianLayout.guardian, newGuardian, canFinalizeAt);
    }

    /**
     * @dev Finalizes a recovery guardian update (after timelock, ready for new guardian to accept).
     *      Reverts if this is not a recovery guardian update or timelock has not expired.
     */
    function finalizeRecoveryGuardianUpdate() internal {
        LibOrganizationGuardianStorage.Layout storage guardianLayout = LibOrganizationGuardianStorage.layout();

        // Case: No pending guardian update
        if (guardianLayout.pendingGuardian == address(0)) {
            revert IOrganizationRecovery.NoRecoveryEnablePending();
        }

        // Case: Not a recovery guardian update
        if (!guardianLayout.isRecoveryGuardianUpdate) {
            revert IOrganizationRecovery.NotARecoveryGuardianUpdate();
        }

        uint256 canFinalizeAt = guardianLayout.pendingGuardianUpdateTimestamp;

        // Case: Timelock not expired
        if (block.timestamp < canFinalizeAt) {
            revert IOrganizationRecovery.RecoveryEnableTimelockNotExpired(canFinalizeAt, block.timestamp);
        }

        // Mark as ready for acceptance (new guardian must call acceptGuardian)
        guardianLayout.isGuardianUpdateReadyForAcceptance = true;

        emit IOrganizationRecovery.RecoveryGuardianUpdateFinalized(guardianLayout.pendingGuardian);
    }

    /**
     * @dev Cancels a pending recovery guardian update.
     *      Reverts if this is not a recovery guardian update.
     */
    function cancelRecoveryGuardianUpdate() internal {
        LibOrganizationGuardianStorage.Layout storage guardianLayout = LibOrganizationGuardianStorage.layout();

        // Case: No pending guardian update
        if (guardianLayout.pendingGuardian == address(0)) {
            revert IOrganizationRecovery.NoRecoveryEnablePending();
        }

        // Case: Not a recovery guardian update
        if (!guardianLayout.isRecoveryGuardianUpdate) {
            revert IOrganizationRecovery.CannotCancelNonRecoveryGuardianUpdate();
        }

        address cancelledGuardian = guardianLayout.pendingGuardian;

        // Clear all pending state
        guardianLayout.pendingGuardian = address(0);
        guardianLayout.pendingGuardianUpdateTimestamp = 0;
        guardianLayout.isRecoveryGuardianUpdate = false;
        guardianLayout.isGuardianUpdateReadyForAcceptance = false;

        emit IOrganizationRecovery.RecoveryGuardianUpdateCancelled(cancelledGuardian);
    }

    /**
     * @dev Validates that a recovery account transaction is allowed.
     *      Reverts if recovery is not both supported AND enabled.
     */
    function validateRecoveryAccountTransactionAllowedOrRevert() internal view {
        LibOrganizationRecoveryStorage.Layout storage recoveryLayout = LibOrganizationRecoveryStorage.layout();

        // Case: Recovery not supported
        if (!recoveryLayout.isRecoverySupportedForTransactionsAndERC1271) {
            revert IOrganizationRecovery.RecoveryNotSupportedForTransactionsAndERC1271();
        }

        // Case: Recovery not enabled
        if (!recoveryLayout.isRecoveryEnabledForTransactionsAndERC1271) {
            revert IOrganizationRecovery.RecoveryNotEnabledForTransactionsAndERC1271();
        }
    }

    /**
     * @dev Checks if a signature is a valid recovery signature.
     *      The signature is valid if it's from the tx recovery address signing the hash.
     *      Supports both EOA and contract (ERC1271) recovery addresses.
     * @param hash The hash that was signed
     * @param signature The signature to validate
     * @return True if the signature is valid from the recovery address
     */
    function isValidRecoverySignature(bytes32 hash, bytes memory signature) internal view returns (bool) {
        LibOrganizationRecoveryStorage.Layout storage recoveryLayout = LibOrganizationRecoveryStorage.layout();

        address recoveryAddress = recoveryLayout.transactionAndERC1271RecoveryAddress;

        // Case: No recovery address configured
        if (recoveryAddress == address(0)) {
            return false;
        }

        // Use SignatureChecker to support both EOA and contract signers
        return SignatureChecker.isValidSignatureNow(recoveryAddress, hash, signature);
    }

    /**
     * @dev Enforces that the caller is the transaction recovery address.
     *      Reverts if msg.sender is not the tx recovery address.
     */
    function enforceOnlyTxRecoveryAddress() internal view {
        LibOrganizationRecoveryStorage.Layout storage recoveryLayout = LibOrganizationRecoveryStorage.layout();
        address expected = recoveryLayout.transactionAndERC1271RecoveryAddress;

        if (msg.sender != expected) {
            revert IOrganizationRecovery.UnauthorizedTxRecoveryAddress(msg.sender, expected);
        }
    }

    /**
     * @dev Enforces that the caller is the guardian recovery address.
     *      Reverts if msg.sender is not the guardian recovery address.
     */
    function enforceOnlyGuardianRecoveryAddress() internal view {
        LibOrganizationRecoveryStorage.Layout storage recoveryLayout = LibOrganizationRecoveryStorage.layout();
        address expected = recoveryLayout.guardianRecoveryAddress;

        if (msg.sender != expected) {
            revert IOrganizationRecovery.UnauthorizedGuardianRecoveryAddress(msg.sender, expected);
        }
    }

    /**
     * @dev Returns whether recovery is supported for transactions and ERC1271 signatures.
     * @return True if supported
     */
    function isRecoverySupportedForTransactionsAndERC1271() internal view returns (bool) {
        return LibOrganizationRecoveryStorage.layout().isRecoverySupportedForTransactionsAndERC1271;
    }

    /**
     * @dev Returns whether recovery is enabled for transactions and ERC1271 signatures.
     * @return True if enabled
     */
    function isRecoveryEnabledForTransactionsAndERC1271() internal view returns (bool) {
        return LibOrganizationRecoveryStorage.layout().isRecoveryEnabledForTransactionsAndERC1271;
    }

    /**
     * @dev Returns the transaction and ERC1271 recovery address.
     * @return The recovery address
     */
    function getTransactionAndERC1271RecoveryAddress() internal view returns (address) {
        return LibOrganizationRecoveryStorage.layout().transactionAndERC1271RecoveryAddress;
    }

    /**
     * @dev Returns whether recovery is enabled for guardian updates.
     * @return True if enabled
     */
    function isRecoveryEnabledForGuardianUpdate() internal view returns (bool) {
        return LibOrganizationRecoveryStorage.layout().isRecoveryEnabledForGuardianUpdate;
    }

    /**
     * @dev Returns the guardian recovery address.
     * @return The recovery address
     */
    function getGuardianRecoveryAddress() internal view returns (address) {
        return LibOrganizationRecoveryStorage.layout().guardianRecoveryAddress;
    }

    /**
     * @dev Returns the recovery timelock duration in seconds.
     * @return The duration
     */
    function getRecoveryTimelockDuration() internal view returns (uint256) {
        return LibOrganizationRecoveryStorage.layout().recoveryTimelockDuration;
    }

    /**
     * @dev Returns the pending tx recovery enable timestamp.
     * @return The timestamp (0 if no pending request)
     */
    function getPendingTxRecoveryEnableTimestamp() internal view returns (uint256) {
        return LibOrganizationRecoveryStorage.layout().pendingTxRecoveryEnableTimestamp;
    }

    /**
     * @dev Returns the pending guardian recovery enable timestamp.
     * @return The timestamp (0 if no pending request)
     */
    function getPendingGuardianRecoveryEnableTimestamp() internal view returns (uint256) {
        return LibOrganizationRecoveryStorage.layout().pendingGuardianRecoveryEnableTimestamp;
    }
}
