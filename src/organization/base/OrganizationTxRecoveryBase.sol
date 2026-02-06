// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IAccount} from "interfaces/IAccount.sol";
import {IOrganizationTxRecovery} from "interfaces/organization/IOrganizationTxRecovery.sol";
import {OrganizationModifiers} from "organization/common/OrganizationModifiers.sol";
import {LibOrganizationAccountFactory} from "organization/libraries/LibOrganizationAccountFactory.sol";
import {LibOrganizationAdmin} from "organization/libraries/LibOrganizationAdmin.sol";
import {LibOrganizationTxRecovery} from "organization/libraries/LibOrganizationTxRecovery.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";
import {OperationType} from "types/CommonTypes.sol";

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

        // Verify the account is deployed by this organization
        LibOrganizationAccountFactory.validateIsAccountDeployedByOrgOrRevert(account);

        // Emit event before external call (CEI pattern)
        emit RecoveryAccountTransactionExecuted(account, to, value, data);

        // Execute the transaction on the account (using nonce=0 and policyId=0 for recovery)
        IAccount(payable(account)).executeTransaction({to: to, value: value, data: data, nonce: 0, policyId: 0});
    }

    /// @inheritdoc IOrganizationTxRecovery
    function initiateInitializeTransactionAndERC1271Recovery(
        address recoveryAddress,
        uint256 timelockDurationSeconds,
        AdminAuthParams calldata authParams
    ) external override onlyGuardian {
        // Encode the operation data for validation
        bytes memory operationData = abi.encode(recoveryAddress, timelockDurationSeconds);

        // Validate that the current admin has authorized this initiation (isApproval = true for execution)
        LibOrganizationAdmin.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.InitiateInitializeTransactionRecovery,
            operationData: operationData,
            isApproval: true,
            authParams: authParams
        });

        // Initiate deferred initialization (starts timelock)
        LibOrganizationTxRecovery.initiateInitializeTxRecovery(recoveryAddress, timelockDurationSeconds);
    }

    /// @inheritdoc IOrganizationTxRecovery
    function finalizeInitializeTransactionAndERC1271Recovery(AdminAuthParams calldata authParams)
        external
        override
        onlyGuardian
    {
        // Get pending values for operation data
        address pendingAddress = LibOrganizationTxRecovery.getPendingInitTxRecoveryAddress();
        uint256 pendingTimelock = LibOrganizationTxRecovery.getPendingInitTxRecoveryTimelockDurationSeconds();

        // Encode the operation data for validation
        bytes memory operationData = abi.encode(pendingAddress, pendingTimelock);

        // Validate that the current admin has authorized this finalization (separate OperationType from initiate)
        LibOrganizationAdmin.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.FinalizeInitializeTransactionRecovery,
            operationData: operationData,
            isApproval: true,
            authParams: authParams
        });

        // Finalize deferred initialization (writes config after timelock)
        LibOrganizationTxRecovery.finalizeInitializeTxRecovery();
    }

    /// @inheritdoc IOrganizationTxRecovery
    function cancelInitializeTransactionAndERC1271Recovery(AdminAuthParams calldata authParams)
        external
        override
        onlyGuardian
    {
        // Get pending values for operation data
        address pendingAddress = LibOrganizationTxRecovery.getPendingInitTxRecoveryAddress();
        uint256 pendingTimelock = LibOrganizationTxRecovery.getPendingInitTxRecoveryTimelockDurationSeconds();

        // Encode the operation data for validation
        bytes memory operationData = abi.encode(pendingAddress, pendingTimelock);

        // Validate that the current admin has authorized this cancellation (isApproval = false)
        LibOrganizationAdmin.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.InitiateInitializeTransactionRecovery,
            operationData: operationData,
            isApproval: false,
            authParams: authParams
        });

        // Cancel the pending initialization
        LibOrganizationTxRecovery.cancelInitializeTxRecovery();
    }

    /// @inheritdoc IOrganizationTxRecovery
    function isRecoveryEnabledForTransactionsAndERC1271() external view override returns (bool) {
        return LibOrganizationTxRecovery.isRecoveryEnabledForTxAndERC1271();
    }

    /// @inheritdoc IOrganizationTxRecovery
    function transactionAndERC1271RecoveryAddress() external view override returns (address) {
        return LibOrganizationTxRecovery.getTxRecoveryAddress();
    }

    /// @inheritdoc IOrganizationTxRecovery
    function pendingTxRecoveryEnableTimestamp() external view override returns (uint256) {
        return LibOrganizationTxRecovery.getPendingTxRecoveryEnableTimestamp();
    }

    /// @inheritdoc IOrganizationTxRecovery
    function txRecoveryTimelockDurationSeconds() external view override returns (uint256) {
        return LibOrganizationTxRecovery.getTxRecoveryTimelockDurationSeconds();
    }

    /// @inheritdoc IOrganizationTxRecovery
    function pendingInitTxRecoveryAddress() external view override returns (address) {
        return LibOrganizationTxRecovery.getPendingInitTxRecoveryAddress();
    }

    /// @inheritdoc IOrganizationTxRecovery
    function pendingInitTxRecoveryTimelockDurationSeconds() external view override returns (uint256) {
        return LibOrganizationTxRecovery.getPendingInitTxRecoveryTimelockDurationSeconds();
    }

    /// @inheritdoc IOrganizationTxRecovery
    function pendingInitTxRecoveryTimestamp() external view override returns (uint256) {
        return LibOrganizationTxRecovery.getPendingInitTxRecoveryTimestamp();
    }
}
