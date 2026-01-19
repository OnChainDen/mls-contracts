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
     * @param txRecoveryTimelockDurationSeconds The timelock duration in seconds (must be > 0 if supported)
     */
    function initializeTxRecovery(
        bool isRecoverySupportedForTransactionsAndERC1271,
        address transactionAndERC1271RecoveryAddress,
        uint256 txRecoveryTimelockDurationSeconds
    ) internal {
        // Validate tx recovery address based on support flag
        if (isRecoverySupportedForTransactionsAndERC1271) {
            // Case: Recovery is supported, address must be set
            if (transactionAndERC1271RecoveryAddress == address(0)) {
                revert IOrganizationTxRecovery.InvalidTxRecoveryAddress();
            }
            // Case: Recovery is supported, timelock duration must be > 0
            if (txRecoveryTimelockDurationSeconds == 0) {
                revert IOrganizationTxRecovery.InvalidTxRecoveryTimelockDurationSeconds();
            }
        } else {
            // Case: Recovery is not supported, address must be zero
            if (transactionAndERC1271RecoveryAddress != address(0)) {
                revert IOrganizationTxRecovery.InvalidTxRecoveryAddress();
            }
        }

        LibOrganizationRecoveryStorage.TxRecoveryState storage txRecovery =
        LibOrganizationRecoveryStorage.layout().txRecovery;

        txRecovery.isSupported = isRecoverySupportedForTransactionsAndERC1271;
        txRecovery.recoveryAddress = transactionAndERC1271RecoveryAddress;
        txRecovery.timelockDurationSeconds = txRecoveryTimelockDurationSeconds;
    }

    /**
     * @dev Initiates enabling transaction and ERC1271 recovery (starts timelock).
     *      Reverts if recovery is not supported or if a request is already pending.
     */
    function initiateEnableTxRecovery() internal {
        LibOrganizationRecoveryStorage.TxRecoveryState storage txRecovery =
        LibOrganizationRecoveryStorage.layout().txRecovery;

        // Case: Recovery not supported
        if (!txRecovery.isSupported) {
            revert IOrganizationTxRecovery.TxRecoveryNotSupported();
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
     *      Reverts if recovery is not both supported AND enabled.
     */
    function validateRecoveryAccountTransactionAllowedOrRevert() internal view {
        LibOrganizationRecoveryStorage.TxRecoveryState storage txRecovery =
        LibOrganizationRecoveryStorage.layout().txRecovery;

        // Case: Recovery not supported
        if (!txRecovery.isSupported) {
            revert IOrganizationTxRecovery.TxRecoveryNotSupported();
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

        // Use SignatureChecker to support both EOA and contract signers
        return SignatureChecker.isValidSignatureNow(recoveryAddress, hash, signature);
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
     * @dev Returns whether recovery is supported for transactions and ERC1271 signatures.
     * @return True if supported
     */
    function isRecoverySupportedForTxAndERC1271() internal view returns (bool) {
        return LibOrganizationRecoveryStorage.layout().txRecovery.isSupported;
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
