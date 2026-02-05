// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";

import {IOrganizationTxRecovery} from "interfaces/organization/IOrganizationTxRecovery.sol";
import {LibOrganizationTxRecovery} from "organization/libraries/LibOrganizationTxRecovery.sol";
import {LibOrganizationRecoveryStorage} from "organization/libraries/storage/LibOrganizationRecoveryStorage.sol";

/**
 * @title Transaction Recovery Test Harness
 * @notice Wraps library functions for testing with proper msg.sender handling
 */
contract TxRecoveryTestHarness {
    // ================================
    // Transaction Recovery Library Functions
    // ================================

    function initializeTxRecovery(
        address transactionAndERC1271RecoveryAddress,
        uint256 txRecoveryTimelockDurationSeconds
    ) external {
        // Only initialize if address is non-zero (matches LibOrganizationInitialization behavior)
        if (transactionAndERC1271RecoveryAddress != address(0)) {
            LibOrganizationTxRecovery.initializeTxRecovery(
                transactionAndERC1271RecoveryAddress, txRecoveryTimelockDurationSeconds
            );
        }
    }

    function setupTxRecovery(address transactionAndERC1271RecoveryAddress, uint256 txRecoveryTimelockDurationSeconds)
        external
    {
        // Simulate what OrganizationTxRecoveryBase.initializeTransactionAndERC1271Recovery does for post-deployment:
        // Initialize (will revert if already configured, invalid address, or invalid timelock)
        LibOrganizationTxRecovery.initializeTxRecovery(
            transactionAndERC1271RecoveryAddress, txRecoveryTimelockDurationSeconds
        );

        // Emit event
        emit IOrganizationTxRecovery.TransactionRecoveryConfigured(
            transactionAndERC1271RecoveryAddress, txRecoveryTimelockDurationSeconds
        );
    }

    function initiateEnableTransactionAndERC1271Recovery() external {
        LibOrganizationTxRecovery.initiateEnableTxRecovery();
    }

    function finalizeEnableTransactionAndERC1271Recovery() external {
        LibOrganizationTxRecovery.finalizeEnableTxRecovery();
    }

    function cancelEnableTransactionAndERC1271Recovery() external {
        LibOrganizationTxRecovery.cancelEnableTxRecovery();
    }

    function disableTransactionAndERC1271Recovery() external {
        LibOrganizationTxRecovery.disableTxRecovery();
    }

    function validateRecoveryAccountTransactionAllowedOrRevert() external view {
        LibOrganizationTxRecovery.validateRecoveryAccountTransactionAllowedOrRevert();
    }

    function enforceOnlyTxRecoveryAddress() external view {
        LibOrganizationTxRecovery.enforceOnlyTxRecoveryAddress();
    }

    // ================================
    // View Functions
    // ================================

    function isRecoveryEnabledForTransactionsAndERC1271() external view returns (bool) {
        return LibOrganizationTxRecovery.isRecoveryEnabledForTxAndERC1271();
    }

    function getTransactionAndERC1271RecoveryAddress() external view returns (address) {
        return LibOrganizationTxRecovery.getTxRecoveryAddress();
    }

    function getTxRecoveryTimelockDurationSeconds() external view returns (uint256) {
        return LibOrganizationTxRecovery.getTxRecoveryTimelockDurationSeconds();
    }

    function getPendingTxRecoveryEnableTimestamp() external view returns (uint256) {
        return LibOrganizationTxRecovery.getPendingTxRecoveryEnableTimestamp();
    }

    // ================================
    // Storage Direct Access (for reset in tests)
    // ================================

    function resetRecoveryStorage() external {
        LibOrganizationRecoveryStorage.Layout storage layout = LibOrganizationRecoveryStorage.layout();

        // Reset tx recovery state
        layout.txRecovery.recoveryAddress = address(0);
        layout.txRecovery.isEnabled = false;
        layout.txRecovery.timelockDurationSeconds = 0;
        layout.txRecovery.pendingEnableTimestamp = 0;

        // Reset guardian recovery state
        layout.guardianRecovery.recoveryAddress = address(0);
        layout.guardianRecovery.timelockDurationSeconds = 0;
        layout.guardianRecovery.pendingGuardian = address(0);
        layout.guardianRecovery.pendingGuardianTimestamp = 0;
        layout.guardianRecovery.isUpdateReadyForAcceptance = false;
    }
}

/**
 * @title Lib Organization Tx Recovery Test
 * @notice Tests for transaction and ERC1271 recovery functionality
 * @dev Tests initialization, timelocked enable/disable flows, and access control.
 * @author Den Technologies Inc
 */
contract LibOrganizationTxRecoveryTest is Test {
    TxRecoveryTestHarness public harness;

    address constant TX_RECOVERY_ADDRESS = address(0x100);

    uint256 constant TIMELOCK_DURATION = 1 days;

    function setUp() public {
        harness = new TxRecoveryTestHarness();

        // Initialize tx recovery configuration
        harness.initializeTxRecovery({
            transactionAndERC1271RecoveryAddress: TX_RECOVERY_ADDRESS,
            txRecoveryTimelockDurationSeconds: TIMELOCK_DURATION
        });
    }

    // ================================
    // Initialization Tests
    // ================================

    function test_initializeTxRecovery_setsCorrectValues() public view {
        assertEq(
            harness.getTransactionAndERC1271RecoveryAddress(),
            TX_RECOVERY_ADDRESS,
            "transactionAndERC1271RecoveryAddress not set"
        );
        assertEq(
            harness.getTxRecoveryTimelockDurationSeconds(),
            TIMELOCK_DURATION,
            "txRecoveryTimelockDurationSeconds not set"
        );
        assertFalse(harness.isRecoveryEnabledForTransactionsAndERC1271(), "isEnabled should be false initially");
    }

    function test_initializeTxRecovery_revertsOnZeroAddress() public {
        harness.resetRecoveryStorage();

        vm.expectRevert(IOrganizationTxRecovery.InvalidTxRecoveryAddress.selector);
        harness.setupTxRecovery({
            transactionAndERC1271RecoveryAddress: address(0), txRecoveryTimelockDurationSeconds: TIMELOCK_DURATION
        });
    }

    function test_initializeTxRecovery_revertsOnZeroTimelockDuration() public {
        harness.resetRecoveryStorage();

        vm.expectRevert(IOrganizationTxRecovery.InvalidTxRecoveryTimelockDurationSeconds.selector);
        harness.setupTxRecovery({
            transactionAndERC1271RecoveryAddress: TX_RECOVERY_ADDRESS, txRecoveryTimelockDurationSeconds: 0
        });
    }

    function test_initializeTxRecovery_allowsDeferredSetup() public {
        harness.resetRecoveryStorage();

        // Initialize with zero address (defer setup)
        harness.initializeTxRecovery({
            transactionAndERC1271RecoveryAddress: address(0), txRecoveryTimelockDurationSeconds: 0
        });

        // Verify nothing was set
        assertEq(harness.getTransactionAndERC1271RecoveryAddress(), address(0), "Recovery address should be zero");
        assertEq(harness.getTxRecoveryTimelockDurationSeconds(), 0, "Timelock should be zero");
    }

    // ================================
    // Transaction Recovery Enable Flow Tests (Timelocked)
    // ================================

    function test_initiateEnableTxRecovery_setsPendingTimestamp() public {
        harness.initiateEnableTransactionAndERC1271Recovery();

        uint256 expectedCanFinalizeAt = block.timestamp + TIMELOCK_DURATION;
        assertEq(
            harness.getPendingTxRecoveryEnableTimestamp(), expectedCanFinalizeAt, "Pending timestamp not set correctly"
        );
    }

    function test_initiateEnableTxRecovery_emitsEvent() public {
        uint256 expectedCanFinalizeAt = block.timestamp + TIMELOCK_DURATION;

        vm.expectEmit(true, true, true, true);
        emit IOrganizationTxRecovery.TxRecoveryEnableInitiated(expectedCanFinalizeAt);

        harness.initiateEnableTransactionAndERC1271Recovery();
    }

    function test_initiateEnableTxRecovery_revertsIfNotConfigured() public {
        harness.resetRecoveryStorage();

        vm.expectRevert(IOrganizationTxRecovery.TxRecoveryNotConfigured.selector);
        harness.initiateEnableTransactionAndERC1271Recovery();
    }

    function test_initiateEnableTxRecovery_revertsIfAlreadyPending() public {
        harness.initiateEnableTransactionAndERC1271Recovery();

        vm.expectRevert(IOrganizationTxRecovery.TxRecoveryEnableAlreadyPending.selector);
        harness.initiateEnableTransactionAndERC1271Recovery();
    }

    function test_initiateEnableTxRecovery_revertsIfAlreadyEnabled() public {
        // First enable recovery
        harness.initiateEnableTransactionAndERC1271Recovery();
        vm.warp(block.timestamp + TIMELOCK_DURATION);
        harness.finalizeEnableTransactionAndERC1271Recovery();
        assertTrue(harness.isRecoveryEnabledForTransactionsAndERC1271(), "Recovery should be enabled");

        // Try to initiate again - should revert
        vm.expectRevert(IOrganizationTxRecovery.TxRecoveryAlreadyEnabled.selector);
        harness.initiateEnableTransactionAndERC1271Recovery();
    }

    function test_finalizeEnableTxRecovery_enablesRecovery() public {
        harness.initiateEnableTransactionAndERC1271Recovery();
        vm.warp(block.timestamp + TIMELOCK_DURATION);
        harness.finalizeEnableTransactionAndERC1271Recovery();

        assertTrue(harness.isRecoveryEnabledForTransactionsAndERC1271(), "Recovery not enabled after finalize");
        assertEq(harness.getPendingTxRecoveryEnableTimestamp(), 0, "Pending timestamp not cleared");
    }

    function test_finalizeEnableTxRecovery_revertsIfNoPending() public {
        vm.expectRevert(IOrganizationTxRecovery.NoTxRecoveryEnablePending.selector);
        harness.finalizeEnableTransactionAndERC1271Recovery();
    }

    function test_finalizeEnableTxRecovery_revertsIfTimelockNotExpired() public {
        harness.initiateEnableTransactionAndERC1271Recovery();

        uint256 canFinalizeAt = harness.getPendingTxRecoveryEnableTimestamp();

        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationTxRecovery.TxRecoveryTimelockNotExpired.selector, canFinalizeAt, block.timestamp
            )
        );
        harness.finalizeEnableTransactionAndERC1271Recovery();
    }

    function test_cancelEnableTxRecovery_clearsPendingState() public {
        harness.initiateEnableTransactionAndERC1271Recovery();
        harness.cancelEnableTransactionAndERC1271Recovery();

        assertEq(harness.getPendingTxRecoveryEnableTimestamp(), 0, "Pending timestamp not cleared");
    }

    function test_cancelEnableTxRecovery_revertsIfNoPending() public {
        vm.expectRevert(IOrganizationTxRecovery.NoTxRecoveryEnablePending.selector);
        harness.cancelEnableTransactionAndERC1271Recovery();
    }

    function test_disableTxRecovery_disablesImmediately() public {
        harness.initiateEnableTransactionAndERC1271Recovery();
        vm.warp(block.timestamp + TIMELOCK_DURATION);
        harness.finalizeEnableTransactionAndERC1271Recovery();
        assertTrue(harness.isRecoveryEnabledForTransactionsAndERC1271(), "Recovery should be enabled");

        harness.disableTransactionAndERC1271Recovery();

        assertFalse(harness.isRecoveryEnabledForTransactionsAndERC1271(), "Recovery should be disabled");
    }

    // ================================
    // Recovery Account Transaction Validation Tests
    // ================================

    function test_validateRecoveryAccountTransactionAllowed_passesWhenEnabled() public {
        harness.initiateEnableTransactionAndERC1271Recovery();
        vm.warp(block.timestamp + TIMELOCK_DURATION);
        harness.finalizeEnableTransactionAndERC1271Recovery();

        harness.validateRecoveryAccountTransactionAllowedOrRevert();
    }

    function test_validateRecoveryAccountTransactionAllowed_revertsIfNotConfigured() public {
        harness.resetRecoveryStorage();

        vm.expectRevert(IOrganizationTxRecovery.TxRecoveryNotConfigured.selector);
        harness.validateRecoveryAccountTransactionAllowedOrRevert();
    }

    function test_validateRecoveryAccountTransactionAllowed_revertsIfNotEnabled() public {
        vm.expectRevert(IOrganizationTxRecovery.TxRecoveryNotEnabled.selector);
        harness.validateRecoveryAccountTransactionAllowedOrRevert();
    }

    // ================================
    // Post-Deployment Setup Tests
    // ================================

    function test_setupTxRecovery_configuresRecovery() public {
        harness.resetRecoveryStorage();

        // Setup recovery (simulates post-deployment initialization)
        harness.setupTxRecovery({
            transactionAndERC1271RecoveryAddress: TX_RECOVERY_ADDRESS,
            txRecoveryTimelockDurationSeconds: TIMELOCK_DURATION
        });

        assertEq(harness.getTransactionAndERC1271RecoveryAddress(), TX_RECOVERY_ADDRESS, "Recovery address not set");
        assertEq(harness.getTxRecoveryTimelockDurationSeconds(), TIMELOCK_DURATION, "Timelock duration not set");
    }

    function test_setupTxRecovery_emitsEvent() public {
        harness.resetRecoveryStorage();

        vm.expectEmit(true, true, true, true);
        emit IOrganizationTxRecovery.TransactionRecoveryConfigured(TX_RECOVERY_ADDRESS, TIMELOCK_DURATION);

        harness.setupTxRecovery({
            transactionAndERC1271RecoveryAddress: TX_RECOVERY_ADDRESS,
            txRecoveryTimelockDurationSeconds: TIMELOCK_DURATION
        });
    }

    function test_setupTxRecovery_revertsIfAlreadyConfigured() public {
        // Setup is already done in setUp(), so recovery is already configured
        vm.expectRevert(IOrganizationTxRecovery.TransactionRecoveryAlreadyConfigured.selector);
        harness.setupTxRecovery({
            transactionAndERC1271RecoveryAddress: address(0x999), txRecoveryTimelockDurationSeconds: TIMELOCK_DURATION
        });
    }

    function test_setupTxRecovery_revertsOnZeroAddress() public {
        harness.resetRecoveryStorage();

        vm.expectRevert(IOrganizationTxRecovery.InvalidTxRecoveryAddress.selector);
        harness.setupTxRecovery({
            transactionAndERC1271RecoveryAddress: address(0), txRecoveryTimelockDurationSeconds: TIMELOCK_DURATION
        });
    }

    function test_setupTxRecovery_revertsOnZeroTimelock() public {
        harness.resetRecoveryStorage();

        vm.expectRevert(IOrganizationTxRecovery.InvalidTxRecoveryTimelockDurationSeconds.selector);
        harness.setupTxRecovery({
            transactionAndERC1271RecoveryAddress: TX_RECOVERY_ADDRESS, txRecoveryTimelockDurationSeconds: 0
        });
    }

    function test_setupTxRecovery_allowsEnableFlowAfterSetup() public {
        harness.resetRecoveryStorage();

        // Setup recovery (post-deployment)
        harness.setupTxRecovery({
            transactionAndERC1271RecoveryAddress: TX_RECOVERY_ADDRESS,
            txRecoveryTimelockDurationSeconds: TIMELOCK_DURATION
        });

        // Now enable recovery
        harness.initiateEnableTransactionAndERC1271Recovery();
        vm.warp(block.timestamp + TIMELOCK_DURATION);
        harness.finalizeEnableTransactionAndERC1271Recovery();

        assertTrue(harness.isRecoveryEnabledForTransactionsAndERC1271(), "Recovery should be enabled");

        // Validate recovery transaction is now allowed
        harness.validateRecoveryAccountTransactionAllowedOrRevert();
    }
}
