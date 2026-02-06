// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationTxRecovery} from "interfaces/organization/IOrganizationTxRecovery.sol";
import {SignatureUtils} from "libraries/SignatureUtils.sol";
import {TimelockUtils} from "libraries/TimelockUtils.sol";
import {LibOrganizationAdminOperationTimelock} from "organization/libraries/LibOrganizationAdminOperationTimelock.sol";
import {LibOrganizationRecoveryStorage} from "organization/libraries/storage/LibOrganizationRecoveryStorage.sol";
import {TxRecoveryState} from "types/RecoveryTypes.sol";

/**
 * @title Lib Organization Transaction Recovery
 * @dev Library for transaction and ERC1271 signature recovery operations for Organization contracts.
 *      This library handles transaction-specific recovery functionality including:
 *      - Enabling/disabling transaction recovery (with timelocks)
 *      - Recovery account transactions (bypassing guardian/policy checks)
 *      - Recovery ERC1271 signature validation
 *
 *      Separated from guardian recovery for cleaner code organization and easier auditing.
 * @author Den Technologies Inc
 */
library LibOrganizationTxRecovery {
    /**
     * @dev Initializes transaction recovery configuration. Used during org initialization
     *      and called by finalizeInitializeTxRecovery for post-deployment setup.
     *      - If already configured, reverts
     *      - Otherwise, validates address and timelock duration and writes to storage
     * @param transactionAndERC1271RecoveryAddress The tx recovery address
     * @param txRecoveryTimelockDurationSeconds The timelock duration in seconds
     */
    function initializeTxRecovery(
        address transactionAndERC1271RecoveryAddress,
        uint256 txRecoveryTimelockDurationSeconds
    ) internal {
        TxRecoveryState storage txRecoveryLayout = LibOrganizationRecoveryStorage.layout().txRecovery;

        _validateTxRecoveryNotConfiguredOrRevert(txRecoveryLayout);
        _validateTxRecoveryParamsOrRevert(transactionAndERC1271RecoveryAddress, txRecoveryTimelockDurationSeconds);

        // Set storage values
        txRecoveryLayout.isEnabled = false;
        txRecoveryLayout.recoveryAddress = transactionAndERC1271RecoveryAddress;
        txRecoveryLayout.timelockDurationSeconds = txRecoveryTimelockDurationSeconds;
    }

    /**
     * @dev Initiates enabling transaction and ERC1271 recovery (starts timelock).
     *      Reverts if recovery is not configured or if a request is already pending.
     */
    function initiateEnableTxRecovery() internal {
        TxRecoveryState storage txRecovery = LibOrganizationRecoveryStorage.layout().txRecovery;

        // Case: Recovery not configured (no recovery address or timelock duration set)
        if (txRecovery.recoveryAddress == address(0) || txRecovery.timelockDurationSeconds == 0) {
            revert IOrganizationTxRecovery.TxRecoveryNotConfigured();
        }

        // Case: Already enabled
        if (txRecovery.isEnabled) {
            revert IOrganizationTxRecovery.TxRecoveryAlreadyEnabled();
        }

        // Case: Already pending
        if (txRecovery.pendingEnableTimestamp != 0) {
            revert IOrganizationTxRecovery.TxRecoveryEnableAlreadyPending();
        }

        uint256 canFinalizeAtTimestamp = block.timestamp + txRecovery.timelockDurationSeconds;
        txRecovery.pendingEnableTimestamp = canFinalizeAtTimestamp;

        emit IOrganizationTxRecovery.TxRecoveryEnableInitiated(canFinalizeAtTimestamp);
    }

    /**
     * @dev Finalizes enabling transaction and ERC1271 recovery (after timelock).
     *      Reverts if no request is pending or timelock has not expired.
     */
    function finalizeEnableTxRecovery() internal {
        TxRecoveryState storage txRecovery = LibOrganizationRecoveryStorage.layout().txRecovery;

        uint256 canFinalizeAtTimestamp = txRecovery.pendingEnableTimestamp;

        // Case: No pending request
        if (canFinalizeAtTimestamp == 0) {
            revert IOrganizationTxRecovery.NoTxRecoveryEnablePending();
        }

        // Case: Timelock not expired
        LibOrganizationAdminOperationTimelock.validateTimelockExpiredOrRevert(canFinalizeAtTimestamp);

        // Enable recovery and clear pending state
        txRecovery.isEnabled = true;
        txRecovery.pendingEnableTimestamp = 0;

        emit IOrganizationTxRecovery.TxRecoveryEnableFinalized();
    }

    /**
     * @dev Cancels a pending transaction and ERC1271 recovery enable request.
     *      Reverts if no request is pending.
     */
    function cancelEnableTxRecovery() internal {
        TxRecoveryState storage txRecovery = LibOrganizationRecoveryStorage.layout().txRecovery;

        // Case: No pending request
        if (txRecovery.pendingEnableTimestamp == 0) {
            revert IOrganizationTxRecovery.NoTxRecoveryEnablePending();
        }

        txRecovery.pendingEnableTimestamp = 0;

        emit IOrganizationTxRecovery.TxRecoveryEnableCancelled();
    }

    /**
     * @dev Immediately disables transaction and ERC1271 recovery (no timelock).
     *      Also cancels any pending enable request (clears pendingEnableTimestamp),
     *      even if the timelock has already expired. This ensures recovery is fully disabled.
     */
    function disableTxRecovery() internal {
        TxRecoveryState storage txRecovery = LibOrganizationRecoveryStorage.layout().txRecovery;

        txRecovery.isEnabled = false;
        txRecovery.pendingEnableTimestamp = 0;

        emit IOrganizationTxRecovery.TxRecoveryDisabled();
    }

    /**
     * @dev Initiates deferred initialization of transaction recovery (starts timelock).
     *      Reverts if already configured, already pending, or inputs are invalid.
     * @param transactionAndERC1271RecoveryAddress The proposed recovery address
     * @param txRecoveryTimelockDurationSeconds The proposed timelock duration in seconds
     */
    function initiateInitializeTxRecovery(
        address transactionAndERC1271RecoveryAddress,
        uint256 txRecoveryTimelockDurationSeconds
    ) internal {
        TxRecoveryState storage txRecovery = LibOrganizationRecoveryStorage.layout().txRecovery;

        _validateTxRecoveryNotConfiguredOrRevert(txRecovery);

        // Case: Already a pending initialization
        if (txRecovery.pendingInit.pendingTimestamp != 0) {
            revert IOrganizationTxRecovery.TxRecoveryInitializationAlreadyPending();
        }

        _validateTxRecoveryParamsOrRevert(transactionAndERC1271RecoveryAddress, txRecoveryTimelockDurationSeconds);

        uint256 canFinalizeAtTimestamp = LibOrganizationAdminOperationTimelock.computeCanFinalizeAtTimestamp();

        // Store pending initialization values
        txRecovery.pendingInit.pendingRecoveryAddress = transactionAndERC1271RecoveryAddress;
        txRecovery.pendingInit.pendingTimelockDurationSeconds = txRecoveryTimelockDurationSeconds;
        txRecovery.pendingInit.pendingTimestamp = canFinalizeAtTimestamp;

        emit IOrganizationTxRecovery.TxRecoveryInitializationInitiated(
            transactionAndERC1271RecoveryAddress, txRecoveryTimelockDurationSeconds, canFinalizeAtTimestamp
        );
    }

    /**
     * @dev Finalizes deferred initialization of transaction recovery (after timelock).
     *      Reads pending values, clears pending state, then delegates to initializeTxRecovery
     *      to reuse validation and config-writing logic.
     */
    function finalizeInitializeTxRecovery() internal {
        TxRecoveryState storage txRecovery = LibOrganizationRecoveryStorage.layout().txRecovery;

        uint256 canFinalizeAtTimestamp = txRecovery.pendingInit.pendingTimestamp;

        // Case: No pending initialization
        if (canFinalizeAtTimestamp == 0) {
            revert IOrganizationTxRecovery.NoTxRecoveryInitializationPending();
        }

        // Case: Timelock not expired
        LibOrganizationAdminOperationTimelock.validateTimelockExpiredOrRevert(canFinalizeAtTimestamp);

        // Read pending values before clearing
        address pendingAddress = txRecovery.pendingInit.pendingRecoveryAddress;
        uint256 pendingTimelock = txRecovery.pendingInit.pendingTimelockDurationSeconds;

        // Clear pending state
        _clearPendingTxRecoveryInitTimelock(txRecovery);

        // Reuse initializeTxRecovery for validation + config writes
        initializeTxRecovery(pendingAddress, pendingTimelock);

        emit IOrganizationTxRecovery.TxRecoveryInitializationFinalized(pendingAddress, pendingTimelock);
    }

    /**
     * @dev Cancels a pending deferred initialization of transaction recovery.
     *      Reverts if no initialization is pending.
     */
    function cancelInitializeTxRecovery() internal {
        TxRecoveryState storage txRecovery = LibOrganizationRecoveryStorage.layout().txRecovery;

        // Case: No pending initialization
        if (txRecovery.pendingInit.pendingTimestamp == 0) {
            revert IOrganizationTxRecovery.NoTxRecoveryInitializationPending();
        }

        _clearPendingTxRecoveryInitTimelock(txRecovery);

        emit IOrganizationTxRecovery.TxRecoveryInitializationCancelled();
    }

    /**
     * @dev Validates that a recovery account transaction is allowed.
     *      Reverts if recovery is not configured or not enabled.
     */
    function validateRecoveryAccountTransactionAllowedOrRevert() internal view {
        TxRecoveryState storage txRecovery = LibOrganizationRecoveryStorage.layout().txRecovery;

        // Case: Recovery not configured (no recovery address or timelock duration set)
        if (txRecovery.recoveryAddress == address(0) || txRecovery.timelockDurationSeconds == 0) {
            revert IOrganizationTxRecovery.TxRecoveryNotConfigured();
        }

        // Case: Recovery not enabled
        if (!txRecovery.isEnabled) {
            revert IOrganizationTxRecovery.TxRecoveryNotEnabled();
        }
    }

    /**
     * @dev Checks if a signature is a valid recovery signature.
     *      The signature is valid if it's from the tx recovery address signing the hash.
     *      Supports both EOA and contract (ERC1271) recovery addresses.
     *      Returns false if the signature is malformed or signer doesn't match.
     * @param hash The hash that was signed
     * @param signature The signature to validate
     * @return True if the signature is valid from the recovery address
     */
    function isValidRecoverySignature(bytes32 hash, bytes memory signature) internal view returns (bool) {
        address recoveryAddress = LibOrganizationRecoveryStorage.layout().txRecovery.recoveryAddress;

        // Case: No recovery address configured
        if (recoveryAddress == address(0)) {
            return false;
        }

        // Use SignatureUtils to support both EOA and ERC-1271 contract signers
        // Returns false if signature is malformed or signer doesn't match
        (bool success, address signer) = SignatureUtils.tryRecoverSigner(signature, hash);
        return success && signer == recoveryAddress;
    }

    /**
     * @dev Enforces that the caller is the transaction recovery address.
     *      Reverts if msg.sender is not the tx recovery address.
     */
    function enforceOnlyTxRecoveryAddress() internal view {
        address expected = LibOrganizationRecoveryStorage.layout().txRecovery.recoveryAddress;

        if (msg.sender != expected) {
            revert IOrganizationTxRecovery.UnauthorizedTxRecoveryAddress(msg.sender, expected);
        }
    }

    /**
     * @dev Returns whether recovery is enabled for transactions and ERC1271 signatures.
     * @return True if enabled
     */
    function isRecoveryEnabledForTxAndERC1271() internal view returns (bool) {
        return LibOrganizationRecoveryStorage.layout().txRecovery.isEnabled;
    }

    /**
     * @dev Clears all pending initialization state fields.
     * @param txRecovery The tx recovery storage state
     */
    function _clearPendingTxRecoveryInitTimelock(TxRecoveryState storage txRecovery) private {
        txRecovery.pendingInit.pendingRecoveryAddress = address(0);
        txRecovery.pendingInit.pendingTimelockDurationSeconds = 0;
        txRecovery.pendingInit.pendingTimestamp = 0;
    }

    /**
     * @dev Validates that transaction recovery is not already configured.
     *      Reverts if recoveryAddress or timelockDurationSeconds is non-zero.
     * @param txRecovery The tx recovery storage state
     */
    function _validateTxRecoveryNotConfiguredOrRevert(TxRecoveryState storage txRecovery) private view {
        if (txRecovery.recoveryAddress != address(0) || txRecovery.timelockDurationSeconds != 0) {
            revert IOrganizationTxRecovery.TransactionRecoveryAlreadyConfigured();
        }
    }

    /**
     * @dev Validates tx recovery initialization parameters.
     *      Reverts if recovery address is zero or timelock duration is zero.
     * @param recoveryAddress The recovery address to validate
     * @param timelockDurationSeconds The timelock duration to validate
     */
    function _validateTxRecoveryParamsOrRevert(address recoveryAddress, uint256 timelockDurationSeconds) private pure {
        // Case: Recovery address is zero
        if (recoveryAddress == address(0)) {
            revert IOrganizationTxRecovery.InvalidTxRecoveryAddress();
        }

        // Case: Timelock duration outside allowed range
        TimelockUtils.validateTimelockDurationOrRevert(timelockDurationSeconds);
    }
}
