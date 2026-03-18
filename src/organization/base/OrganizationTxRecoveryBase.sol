// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IAccount} from "interfaces/IAccount.sol";
import {IOrganizationAccountTransaction} from "interfaces/organization/IOrganizationAccountTransaction.sol";
import {IOrganizationAdmin} from "interfaces/organization/IOrganizationAdmin.sol";
import {IOrganizationTxRecovery} from "interfaces/organization/IOrganizationTxRecovery.sol";
import {OrganizationModifiers} from "organization/common/OrganizationModifiers.sol";
import {LibOrganizationAccountFactory} from "organization/libraries/LibOrganizationAccountFactory.sol";
import {LibOrganizationAdmin} from "organization/libraries/LibOrganizationAdmin.sol";
import {LibOrganizationTxRecovery} from "organization/libraries/LibOrganizationTxRecovery.sol";
import {LibOrganizationRecoveryStorage} from "organization/libraries/storage/LibOrganizationRecoveryStorage.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";
import {OperationType} from "types/CommonTypes.sol";
import {TxRecoveryState} from "types/RecoveryTypes.sol";

/**
 * @title OrganizationTxRecoveryBase
 * @dev Abstract contract implementing IOrganizationTxRecovery.
 *      Handles transaction and ERC1271 recovery operations.
 * @author Den Technologies Inc
 */
abstract contract OrganizationTxRecoveryBase is OrganizationModifiers, IOrganizationTxRecovery {
    /// @inheritdoc IOrganizationTxRecovery
    function initiateEnableTransactionAndERC1271Recovery() external override onlyTxRecoveryAddress {
        LibOrganizationTxRecovery.initiateEnableTxRecovery();
    }

    /// @inheritdoc IOrganizationTxRecovery
    function finalizeEnableTransactionAndERC1271Recovery() external override onlyTxRecoveryAddress {
        LibOrganizationTxRecovery.finalizeEnableTxRecovery();
    }

    /// @inheritdoc IOrganizationTxRecovery
    function cancelEnableTransactionAndERC1271Recovery() external override onlyTxRecoveryAddress {
        LibOrganizationTxRecovery.cancelEnableTxRecovery();
    }

    /// @inheritdoc IOrganizationTxRecovery
    function disableTransactionAndERC1271Recovery() external override onlyTxRecoveryAddress {
        LibOrganizationTxRecovery.disableTxRecovery();
    }

    /// @inheritdoc IOrganizationTxRecovery
    function executeRecoveryAccountTransaction(address account, address to, uint256 value, bytes calldata data)
        external
        override
        onlyTxRecoveryAddress
    {
        // Validate recovery is allowed
        LibOrganizationTxRecovery.validateRecoveryAccountTransactionAllowedOrRevert();

        // Prevent self-calls that could reach onlySelf-gated functions via the account execution path.
        if (account == address(this)) {
            revert IOrganizationAccountTransaction.AccountCannotBeOrganization();
        }

        // Verify the account is deployed by this organization
        LibOrganizationAccountFactory.validateIsAccountDeployedByOrgOrRevert(account);

        // Emit event before external call (CEI pattern)
        emit RecoveryAccountTransactionExecuted(account, to, value, data);

        // Execute the transaction on the account (using nonce=0 and policyId=0 for recovery)
        IAccount(payable(account)).executeTransaction({to: to, value: value, data: data, nonce: 0, policyId: 0});
    }

    /// @inheritdoc IOrganizationTxRecovery
    // slither-disable-next-line missing-zero-check
    function initiateInitializeTransactionAndERC1271Recovery(
        address recoveryAddress,
        uint256 timelockDurationSeconds,
        AdminAuthParams calldata authParams
    ) external override onlyGuardian {
        // Encode the operation data for validation
        bytes memory operationData = abi.encode(recoveryAddress, timelockDurationSeconds);

        // Validate that the current admin has authorized this initiation (isApproval = true for execution)
        uint256 nonce = LibOrganizationAdmin.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.InitiateInitializeTransactionRecovery,
            operationData: operationData,
            isApproval: true,
            authParams: authParams
        });

        // Execute via low-level self-call so that a revert does not bubble up.
        /* solhint-disable avoid-low-level-calls */
        // forgefmt: disable-start
        // slither-disable-next-line low-level-calls,reentrancy-events,missing-zero-check
        (bool success, bytes memory revertData) = address(this).call(
            abi.encodeCall(this.executeInitiateInitializeTxRecovery, (recoveryAddress, timelockDurationSeconds))
        );
        // forgefmt: disable-end
        /* solhint-enable avoid-low-level-calls */

        if (!success) {
            emit IOrganizationAdmin.AdminOperationExecutionReverted(
                OperationType.InitiateInitializeTransactionRecovery, nonce, revertData
            );
        }
    }

    /// @inheritdoc IOrganizationTxRecovery
    function executeInitiateInitializeTxRecovery(address recoveryAddress, uint256 timelockDurationSeconds)
        external
        onlySelf
    {
        LibOrganizationTxRecovery.initiateInitializeTxRecovery(recoveryAddress, timelockDurationSeconds);
    }

    /// @inheritdoc IOrganizationTxRecovery
    function finalizeInitializeTransactionAndERC1271Recovery(AdminAuthParams calldata authParams)
        external
        override
        onlyGuardian
    {
        // Get pending values directly from storage for operation data
        TxRecoveryState storage txRecovery = LibOrganizationRecoveryStorage.layout().txRecovery;
        address pendingAddress = txRecovery.pendingInit.pendingRecoveryAddress;
        uint256 pendingTimelock = txRecovery.pendingInit.pendingTimelockDurationSeconds;

        // Encode the operation data for validation
        bytes memory operationData = abi.encode(pendingAddress, pendingTimelock);

        // Validate that the current admin has authorized this finalization (separate OperationType from initiate)
        uint256 nonce = LibOrganizationAdmin.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.FinalizeInitializeTransactionRecovery,
            operationData: operationData,
            isApproval: true,
            authParams: authParams
        });

        // Execute via low-level self-call so that a revert does not bubble up.
        /* solhint-disable avoid-low-level-calls */
        // slither-disable-next-line low-level-calls,reentrancy-events
        (bool success, bytes memory revertData) =
            address(this).call(abi.encodeCall(this.executeFinalizeInitializeTxRecovery, ()));
        /* solhint-enable avoid-low-level-calls */

        if (!success) {
            emit IOrganizationAdmin.AdminOperationExecutionReverted(
                OperationType.FinalizeInitializeTransactionRecovery, nonce, revertData
            );
        }
    }

    /// @inheritdoc IOrganizationTxRecovery
    function executeFinalizeInitializeTxRecovery() external onlySelf {
        LibOrganizationTxRecovery.finalizeInitializeTxRecovery();
    }

    /// @inheritdoc IOrganizationTxRecovery
    function cancelInitializeTransactionAndERC1271Recovery(AdminAuthParams calldata authParams)
        external
        override
        onlyGuardian
    {
        // Get pending values directly from storage for operation data
        TxRecoveryState storage txRecovery = LibOrganizationRecoveryStorage.layout().txRecovery;
        address pendingAddress = txRecovery.pendingInit.pendingRecoveryAddress;
        uint256 pendingTimelock = txRecovery.pendingInit.pendingTimelockDurationSeconds;

        // Encode the operation data for validation
        bytes memory operationData = abi.encode(pendingAddress, pendingTimelock);

        // Validate that the current admin has authorized this cancellation (dedicated Cancel type)
        uint256 nonce = LibOrganizationAdmin.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.CancelInitializeTransactionRecovery,
            operationData: operationData,
            isApproval: true,
            authParams: authParams
        });

        // Execute via low-level self-call so that a revert does not bubble up.
        /* solhint-disable avoid-low-level-calls */
        // slither-disable-next-line low-level-calls,reentrancy-events
        (bool success, bytes memory revertData) =
            address(this).call(abi.encodeCall(this.executeCancelInitializeTxRecovery, ()));
        /* solhint-enable avoid-low-level-calls */

        if (!success) {
            emit IOrganizationAdmin.AdminOperationExecutionReverted(
                OperationType.CancelInitializeTransactionRecovery, nonce, revertData
            );
        }
    }

    /// @inheritdoc IOrganizationTxRecovery
    function executeCancelInitializeTxRecovery() external onlySelf {
        LibOrganizationTxRecovery.cancelInitializeTxRecovery();
    }

    /// @inheritdoc IOrganizationTxRecovery
    function getTxRecoveryState() external view override returns (TxRecoveryState memory) {
        return LibOrganizationRecoveryStorage.layout().txRecovery;
    }
}
