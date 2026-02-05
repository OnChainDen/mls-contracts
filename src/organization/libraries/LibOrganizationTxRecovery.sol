// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationTxRecovery} from "interfaces/organization/IOrganizationTxRecovery.sol";
import {SignatureUtils} from "libraries/SignatureUtils.sol";
import {LibOrganizationRecoveryStorage} from "organization/libraries/storage/LibOrganizationRecoveryStorage.sol";

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
     * @dev Initializes transaction recovery configuration. Used both during org initialization and post-deployment
     * setup.
     *      - If already configured, reverts
     *      - Otherwise, validates address and timelock duration and writes to storage
     *
     *      Note: Event emission is handled by the caller (OrganizationTxRecoveryBase)
     *      for post-deployment setup only.
     * @param transactionAndERC1271RecoveryAddress The tx recovery address
     * @param txRecoveryTimelockDurationSeconds The timelock duration in seconds
     */
    function initializeTxRecovery(
        address transactionAndERC1271RecoveryAddress,
        uint256 txRecoveryTimelockDurationSeconds
    ) internal {
        LibOrganizationRecoveryStorage.TxRecoveryState storage
            txRecoveryLayout = LibOrganizationRecoveryStorage.layout().txRecovery;

        // Case: Transaction recovery is already configured
        if (txRecoveryLayout.recoveryAddress != address(0) || txRecoveryLayout.timelockDurationSeconds != 0) {
            revert IOrganizationTxRecovery.TransactionRecoveryAlreadyConfigured();
        }

        // Case: New tx recovery address is zero
        if (transactionAndERC1271RecoveryAddress == address(0)) {
            revert IOrganizationTxRecovery.InvalidTxRecoveryAddress();
        }

        // Case: New tx recovery timelock duration is zero
        if (txRecoveryTimelockDurationSeconds == 0) {
            revert IOrganizationTxRecovery.InvalidTxRecoveryTimelockDurationSeconds();
        }

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
        LibOrganizationRecoveryStorage.TxRecoveryState storage txRecovery =
        LibOrganizationRecoveryStorage.layout().txRecovery;

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
        LibOrganizationRecoveryStorage.TxRecoveryState storage txRecovery =
        LibOrganizationRecoveryStorage.layout().txRecovery;

        uint256 canFinalizeAtTimestamp = txRecovery.pendingEnableTimestamp;

        // Case: No pending request
        if (canFinalizeAtTimestamp == 0) {
            revert IOrganizationTxRecovery.NoTxRecoveryEnablePending();
        }

        // Case: Timelock not expired
        if (block.timestamp < canFinalizeAtTimestamp) {
            revert IOrganizationTxRecovery.TxRecoveryTimelockNotExpired(canFinalizeAtTimestamp, block.timestamp);
        }

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
        LibOrganizationRecoveryStorage.TxRecoveryState storage txRecovery =
        LibOrganizationRecoveryStorage.layout().txRecovery;

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
        LibOrganizationRecoveryStorage.TxRecoveryState storage txRecovery =
        LibOrganizationRecoveryStorage.layout().txRecovery;

        txRecovery.isEnabled = false;
        txRecovery.pendingEnableTimestamp = 0;

        emit IOrganizationTxRecovery.TxRecoveryDisabled();
    }

    /**
     * @dev Validates that a recovery account transaction is allowed.
     *      Reverts if recovery is not configured or not enabled.
     */
    function validateRecoveryAccountTransactionAllowedOrRevert() internal view {
        LibOrganizationRecoveryStorage.TxRecoveryState storage txRecovery =
        LibOrganizationRecoveryStorage.layout().txRecovery;

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
     * @dev Returns the transaction and ERC1271 recovery address.
     * @return The recovery address
     */
    function getTxRecoveryAddress() internal view returns (address) {
        return LibOrganizationRecoveryStorage.layout().txRecovery.recoveryAddress;
    }

    /**
     * @dev Returns the pending tx recovery enable timestamp.
     * @return The timestamp (0 if no pending request)
     */
    function getPendingTxRecoveryEnableTimestamp() internal view returns (uint256) {
        return LibOrganizationRecoveryStorage.layout().txRecovery.pendingEnableTimestamp;
    }

    /**
     * @dev Returns the tx recovery timelock duration in seconds.
     * @return The duration
     */
    function getTxRecoveryTimelockDurationSeconds() internal view returns (uint256) {
        return LibOrganizationRecoveryStorage.layout().txRecovery.timelockDurationSeconds;
    }
}
