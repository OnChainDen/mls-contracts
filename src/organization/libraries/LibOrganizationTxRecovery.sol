// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {IOrganizationTxRecovery} from "interfaces/organization/IOrganizationTxRecovery.sol";
import {SignatureChecker} from "libraries/SignatureChecker.sol";
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
     * @dev Initializes the transaction recovery configuration during organization initialization.
     *      This should be called from LibOrganizationInitialization.initialize().
     * @param isRecoverySupportedForTransactionsAndERC1271 Whether recovery is supported for tx/signatures
     * @param transactionAndERC1271RecoveryAddress The tx recovery address (must be non-zero if supported)
     */
    function initializeTxRecovery(
        bool isRecoverySupportedForTransactionsAndERC1271,
        address transactionAndERC1271RecoveryAddress
    ) internal {
        // Validate tx recovery address based on support flag
        if (isRecoverySupportedForTransactionsAndERC1271) {
            // Case: Recovery is supported, address must be set
            if (transactionAndERC1271RecoveryAddress == address(0)) {
                revert IOrganizationTxRecovery.InvalidTxRecoveryAddress();
            }
        } else {
            // Case: Recovery is not supported, address must be zero
            if (transactionAndERC1271RecoveryAddress != address(0)) {
                revert IOrganizationTxRecovery.InvalidTxRecoveryAddress();
            }
        }

        LibOrganizationRecoveryStorage.Layout storage recoveryLayout = LibOrganizationRecoveryStorage.layout();

        recoveryLayout.isRecoverySupportedForTransactionsAndERC1271 = isRecoverySupportedForTransactionsAndERC1271;
        recoveryLayout.transactionAndERC1271RecoveryAddress = transactionAndERC1271RecoveryAddress;
    }

    /**
     * @dev Initiates enabling transaction and ERC1271 recovery (starts timelock).
     *      Reverts if recovery is not supported or if a request is already pending.
     */
    function initiateEnableTxRecovery() internal {
        LibOrganizationRecoveryStorage.Layout storage recoveryLayout = LibOrganizationRecoveryStorage.layout();

        // Case: Recovery not supported
        if (!recoveryLayout.isRecoverySupportedForTransactionsAndERC1271) {
            revert IOrganizationTxRecovery.TxRecoveryNotSupported();
        }

        // Case: Already pending
        if (recoveryLayout.pendingTxRecoveryEnableTimestamp != 0) {
            revert IOrganizationTxRecovery.TxRecoveryEnableAlreadyPending();
        }

        uint256 canFinalizeAt = block.timestamp + recoveryLayout.recoveryTimelockDuration;
        recoveryLayout.pendingTxRecoveryEnableTimestamp = canFinalizeAt;

        emit IOrganizationTxRecovery.TxRecoveryEnableInitiated(canFinalizeAt);
    }

    /**
     * @dev Finalizes enabling transaction and ERC1271 recovery (after timelock).
     *      Reverts if no request is pending or timelock has not expired.
     */
    function finalizeEnableTxRecovery() internal {
        LibOrganizationRecoveryStorage.Layout storage recoveryLayout = LibOrganizationRecoveryStorage.layout();

        uint256 canFinalizeAt = recoveryLayout.pendingTxRecoveryEnableTimestamp;

        // Case: No pending request
        if (canFinalizeAt == 0) {
            revert IOrganizationTxRecovery.NoTxRecoveryEnablePending();
        }

        // Case: Timelock not expired
        if (block.timestamp < canFinalizeAt) {
            revert IOrganizationTxRecovery.TxRecoveryTimelockNotExpired(canFinalizeAt, block.timestamp);
        }

        // Enable recovery and clear pending state
        recoveryLayout.isRecoveryEnabledForTransactionsAndERC1271 = true;
        recoveryLayout.pendingTxRecoveryEnableTimestamp = 0;

        emit IOrganizationTxRecovery.TxRecoveryEnableFinalized();
    }

    /**
     * @dev Cancels a pending transaction and ERC1271 recovery enable request.
     *      Reverts if no request is pending.
     */
    function cancelEnableTxRecovery() internal {
        LibOrganizationRecoveryStorage.Layout storage recoveryLayout = LibOrganizationRecoveryStorage.layout();

        // Case: No pending request
        if (recoveryLayout.pendingTxRecoveryEnableTimestamp == 0) {
            revert IOrganizationTxRecovery.NoTxRecoveryEnablePending();
        }

        recoveryLayout.pendingTxRecoveryEnableTimestamp = 0;

        emit IOrganizationTxRecovery.TxRecoveryEnableCancelled();
    }

    /**
     * @dev Immediately disables transaction and ERC1271 recovery (no timelock).
     *      Also cancels any pending enable request (clears pendingTxRecoveryEnableTimestamp),
     *      even if the timelock has already expired. This ensures recovery is fully disabled.
     */
    function disableTxRecovery() internal {
        LibOrganizationRecoveryStorage.Layout storage recoveryLayout = LibOrganizationRecoveryStorage.layout();

        recoveryLayout.isRecoveryEnabledForTransactionsAndERC1271 = false;
        recoveryLayout.pendingTxRecoveryEnableTimestamp = 0;

        emit IOrganizationTxRecovery.TxRecoveryDisabled();
    }

    /**
     * @dev Validates that a recovery account transaction is allowed.
     *      Reverts if recovery is not both supported AND enabled.
     */
    function validateRecoveryAccountTransactionAllowedOrRevert() internal view {
        LibOrganizationRecoveryStorage.Layout storage recoveryLayout = LibOrganizationRecoveryStorage.layout();

        // Case: Recovery not supported
        if (!recoveryLayout.isRecoverySupportedForTransactionsAndERC1271) {
            revert IOrganizationTxRecovery.TxRecoveryNotSupported();
        }

        // Case: Recovery not enabled
        if (!recoveryLayout.isRecoveryEnabledForTransactionsAndERC1271) {
            revert IOrganizationTxRecovery.TxRecoveryNotEnabled();
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
            revert IOrganizationTxRecovery.UnauthorizedTxRecoveryAddress(msg.sender, expected);
        }
    }

    /**
     * @dev Returns whether recovery is supported for transactions and ERC1271 signatures.
     * @return True if supported
     */
    function isRecoverySupportedForTxAndERC1271() internal view returns (bool) {
        return LibOrganizationRecoveryStorage.layout().isRecoverySupportedForTransactionsAndERC1271;
    }

    /**
     * @dev Returns whether recovery is enabled for transactions and ERC1271 signatures.
     * @return True if enabled
     */
    function isRecoveryEnabledForTxAndERC1271() internal view returns (bool) {
        return LibOrganizationRecoveryStorage.layout().isRecoveryEnabledForTransactionsAndERC1271;
    }

    /**
     * @dev Returns the transaction and ERC1271 recovery address.
     * @return The recovery address
     */
    function getTxRecoveryAddress() internal view returns (address) {
        return LibOrganizationRecoveryStorage.layout().transactionAndERC1271RecoveryAddress;
    }

    /**
     * @dev Returns the pending tx recovery enable timestamp.
     * @return The timestamp (0 if no pending request)
     */
    function getPendingTxRecoveryEnableTimestamp() internal view returns (uint256) {
        return LibOrganizationRecoveryStorage.layout().pendingTxRecoveryEnableTimestamp;
    }
}
