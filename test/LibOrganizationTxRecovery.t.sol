// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";

import {IOrganizationSecureTimelock} from "interfaces/organization/IOrganizationSecureTimelock.sol";
import {IOrganizationTxRecovery} from "interfaces/organization/IOrganizationTxRecovery.sol";
import {TimelockUtils} from "libraries/TimelockUtils.sol";
import {LibOrganizationTxRecovery} from "organization/libraries/LibOrganizationTxRecovery.sol";
import {LibOrganizationRecoveryStorage} from "organization/libraries/storage/LibOrganizationRecoveryStorage.sol";
import {
    LibOrganizationSecureTimelockStorage
} from "organization/libraries/storage/LibOrganizationSecureTimelockStorage.sol";
import {TxRecoveryState} from "types/RecoveryTypes.sol";

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

    function initiateInitializeTxRecovery(
        address transactionAndERC1271RecoveryAddress,
        uint256 txRecoveryTimelockDurationSeconds
    ) external {
        LibOrganizationTxRecovery.initiateInitializeTxRecovery(
            transactionAndERC1271RecoveryAddress, txRecoveryTimelockDurationSeconds
        );
    }

    function finalizeInitializeTxRecovery() external {
        LibOrganizationTxRecovery.finalizeInitializeTxRecovery();
    }

    function cancelInitializeTxRecovery() external {
        LibOrganizationTxRecovery.cancelInitializeTxRecovery();
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

    function getTxRecoveryState() external view returns (TxRecoveryState memory) {
        return LibOrganizationRecoveryStorage.layout().txRecovery;
    }

    // ================================
    // Storage Direct Access (for reset/setup in tests)
    // ================================

    function initializeSecureTimelock(uint256 secureTimelockDurationSeconds) external {
        LibOrganizationSecureTimelockStorage.layout().secureTimelockDurationSeconds = secureTimelockDurationSeconds;
    }

    function resetRecoveryStorage() external {
        LibOrganizationRecoveryStorage.Layout storage layout = LibOrganizationRecoveryStorage.layout();

        // Reset tx recovery state
        layout.txRecovery.recoveryAddress = address(0);
        layout.txRecovery.isEnabled = false;
        layout.txRecovery.timelockDurationSeconds = 0;
        layout.txRecovery.pendingEnableTimestamp = 0;
        layout.txRecovery.pendingInit.pendingRecoveryAddress = address(0);
        layout.txRecovery.pendingInit.pendingTimelockDurationSeconds = 0;
        layout.txRecovery.pendingInit.pendingTimestamp = 0;

        // Reset guardian recovery state
        layout.guardianRecovery.recoveryAddress = address(0);
        layout.guardianRecovery.timelockDurationSeconds = 0;
        layout.guardianRecovery.pendingGuardian = address(0);
        layout.guardianRecovery.pendingGuardianTimestamp = 0;
        layout.guardianRecovery.isUpdateReadyForAcceptance = false;
        layout.guardianRecovery.pendingInit.pendingRecoveryAddress = address(0);
        layout.guardianRecovery.pendingInit.pendingTimelockDurationSeconds = 0;
        layout.guardianRecovery.pendingInit.pendingTimestamp = 0;
    }
}

/**
 * @title Lib Organization Tx Recovery Test
 * @notice Tests for transaction and ERC1271 recovery functionality
 * @dev Tests initialization, timelocked enable/disable flows, deferred initialization, and access control.
 * @author Den Technologies Inc
 */
contract LibOrganizationTxRecoveryTest is Test {
    TxRecoveryTestHarness public harness;

    address constant TX_RECOVERY_ADDRESS = address(0x100);

    uint256 constant TIMELOCK_DURATION = 2 days;
    uint256 constant SECURE_TIMELOCK_DURATION = 3 days;

    function setUp() public {
        harness = new TxRecoveryTestHarness();

        // Initialize secure timelock (required for deferred initialization tests)
        harness.initializeSecureTimelock(SECURE_TIMELOCK_DURATION);

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
        TxRecoveryState memory state = harness.getTxRecoveryState();
        assertEq(state.recoveryAddress, TX_RECOVERY_ADDRESS, "recoveryAddress not set");
        assertEq(state.timelockDurationSeconds, TIMELOCK_DURATION, "timelockDurationSeconds not set");
        assertFalse(state.isEnabled, "isEnabled should be false initially");
    }

    function test_initializeTxRecovery_revertsOnZeroAddress() public {
        harness.resetRecoveryStorage();

        vm.expectRevert(IOrganizationTxRecovery.InvalidTxRecoveryAddress.selector);
        harness.initiateInitializeTxRecovery({
            transactionAndERC1271RecoveryAddress: address(0), txRecoveryTimelockDurationSeconds: TIMELOCK_DURATION
        });
    }

    function test_initializeTxRecovery_revertsOnZeroTimelockDuration() public {
        harness.resetRecoveryStorage();

        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockUtils.InvalidTimelockDuration.selector,
                0,
                TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS,
                TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
            )
        );
        harness.initiateInitializeTxRecovery({
            transactionAndERC1271RecoveryAddress: TX_RECOVERY_ADDRESS, txRecoveryTimelockDurationSeconds: 0
        });
    }

    // ================================
    // Transaction Recovery Enable Flow Tests (Timelocked)
    // ================================

    function test_initiateEnableTxRecovery_setsPendingTimestamp() public {
        harness.initiateEnableTransactionAndERC1271Recovery();

        uint256 expectedCanFinalizeAt = block.timestamp + TIMELOCK_DURATION;
        assertEq(
            harness.getTxRecoveryState().pendingEnableTimestamp,
            expectedCanFinalizeAt,
            "Pending timestamp not set correctly"
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
        assertTrue(harness.getTxRecoveryState().isEnabled, "Recovery should be enabled");

        // Try to initiate again - should revert
        vm.expectRevert(IOrganizationTxRecovery.TxRecoveryAlreadyEnabled.selector);
        harness.initiateEnableTransactionAndERC1271Recovery();
    }

    function test_finalizeEnableTxRecovery_enablesRecovery() public {
        harness.initiateEnableTransactionAndERC1271Recovery();
        vm.warp(block.timestamp + TIMELOCK_DURATION);
        harness.finalizeEnableTransactionAndERC1271Recovery();

        TxRecoveryState memory state = harness.getTxRecoveryState();
        assertTrue(state.isEnabled, "Recovery not enabled after finalize");
        assertEq(state.pendingEnableTimestamp, 0, "Pending timestamp not cleared");
    }

    function test_finalizeEnableTxRecovery_revertsIfNoPending() public {
        vm.expectRevert(IOrganizationTxRecovery.NoTxRecoveryEnablePending.selector);
        harness.finalizeEnableTransactionAndERC1271Recovery();
    }

    function test_finalizeEnableTxRecovery_revertsIfTimelockNotExpired() public {
        harness.initiateEnableTransactionAndERC1271Recovery();

        uint256 canFinalizeAt = harness.getTxRecoveryState().pendingEnableTimestamp;

        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationSecureTimelock.TimelockNotExpired.selector, canFinalizeAt, block.timestamp
            )
        );
        harness.finalizeEnableTransactionAndERC1271Recovery();
    }

    function test_cancelEnableTxRecovery_clearsPendingState() public {
        harness.initiateEnableTransactionAndERC1271Recovery();
        harness.cancelEnableTransactionAndERC1271Recovery();

        assertEq(harness.getTxRecoveryState().pendingEnableTimestamp, 0, "Pending timestamp not cleared");
    }

    function test_cancelEnableTxRecovery_revertsIfNoPending() public {
        vm.expectRevert(IOrganizationTxRecovery.NoTxRecoveryEnablePending.selector);
        harness.cancelEnableTransactionAndERC1271Recovery();
    }

    function test_disableTxRecovery_disablesImmediately() public {
        harness.initiateEnableTransactionAndERC1271Recovery();
        vm.warp(block.timestamp + TIMELOCK_DURATION);
        harness.finalizeEnableTransactionAndERC1271Recovery();
        assertTrue(harness.getTxRecoveryState().isEnabled, "Recovery should be enabled");

        harness.disableTransactionAndERC1271Recovery();

        assertFalse(harness.getTxRecoveryState().isEnabled, "Recovery should be disabled");
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
    // Deferred Initialization (Timelocked) Tests
    // ================================

    function test_initiateInitializeTxRecovery_setsPendingState() public {
        harness.resetRecoveryStorage();

        harness.initiateInitializeTxRecovery({
            transactionAndERC1271RecoveryAddress: TX_RECOVERY_ADDRESS,
            txRecoveryTimelockDurationSeconds: TIMELOCK_DURATION
        });

        TxRecoveryState memory state = harness.getTxRecoveryState();
        assertEq(state.pendingInit.pendingRecoveryAddress, TX_RECOVERY_ADDRESS, "Pending address not set");
        assertEq(state.pendingInit.pendingTimelockDurationSeconds, TIMELOCK_DURATION, "Pending timelock not set");
        uint256 expectedCanFinalizeAt = block.timestamp + SECURE_TIMELOCK_DURATION;
        assertEq(state.pendingInit.pendingTimestamp, expectedCanFinalizeAt, "Pending timestamp not set");
    }

    function test_initiateInitializeTxRecovery_emitsEvent() public {
        harness.resetRecoveryStorage();

        uint256 expectedCanFinalizeAt = block.timestamp + SECURE_TIMELOCK_DURATION;

        vm.expectEmit(true, true, true, true);
        emit IOrganizationTxRecovery.TxRecoveryInitializationInitiated(
            TX_RECOVERY_ADDRESS, TIMELOCK_DURATION, expectedCanFinalizeAt
        );

        harness.initiateInitializeTxRecovery({
            transactionAndERC1271RecoveryAddress: TX_RECOVERY_ADDRESS,
            txRecoveryTimelockDurationSeconds: TIMELOCK_DURATION
        });
    }

    function test_initiateInitializeTxRecovery_revertsIfAlreadyConfigured() public {
        // setUp already configured recovery, so this should revert
        vm.expectRevert(IOrganizationTxRecovery.TransactionRecoveryAlreadyConfigured.selector);
        harness.initiateInitializeTxRecovery({
            transactionAndERC1271RecoveryAddress: address(0x999), txRecoveryTimelockDurationSeconds: TIMELOCK_DURATION
        });
    }

    function test_initiateInitializeTxRecovery_revertsIfAlreadyPending() public {
        harness.resetRecoveryStorage();

        harness.initiateInitializeTxRecovery({
            transactionAndERC1271RecoveryAddress: TX_RECOVERY_ADDRESS,
            txRecoveryTimelockDurationSeconds: TIMELOCK_DURATION
        });

        vm.expectRevert(IOrganizationTxRecovery.TxRecoveryInitializationAlreadyPending.selector);
        harness.initiateInitializeTxRecovery({
            transactionAndERC1271RecoveryAddress: address(0x999), txRecoveryTimelockDurationSeconds: TIMELOCK_DURATION
        });
    }

    function test_initiateInitializeTxRecovery_revertsOnZeroAddress() public {
        harness.resetRecoveryStorage();

        vm.expectRevert(IOrganizationTxRecovery.InvalidTxRecoveryAddress.selector);
        harness.initiateInitializeTxRecovery({
            transactionAndERC1271RecoveryAddress: address(0), txRecoveryTimelockDurationSeconds: TIMELOCK_DURATION
        });
    }

    function test_initiateInitializeTxRecovery_revertsOnZeroTimelock() public {
        harness.resetRecoveryStorage();

        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockUtils.InvalidTimelockDuration.selector,
                0,
                TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS,
                TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
            )
        );
        harness.initiateInitializeTxRecovery({
            transactionAndERC1271RecoveryAddress: TX_RECOVERY_ADDRESS, txRecoveryTimelockDurationSeconds: 0
        });
    }

    function test_finalizeInitializeTxRecovery_configuresRecovery() public {
        harness.resetRecoveryStorage();

        harness.initiateInitializeTxRecovery({
            transactionAndERC1271RecoveryAddress: TX_RECOVERY_ADDRESS,
            txRecoveryTimelockDurationSeconds: TIMELOCK_DURATION
        });

        vm.warp(block.timestamp + SECURE_TIMELOCK_DURATION);
        harness.finalizeInitializeTxRecovery();

        TxRecoveryState memory state = harness.getTxRecoveryState();
        assertEq(state.recoveryAddress, TX_RECOVERY_ADDRESS, "Recovery address not set");
        assertEq(state.timelockDurationSeconds, TIMELOCK_DURATION, "Timelock duration not set");
        assertFalse(state.isEnabled, "Should not be enabled yet");

        // Pending state should be cleared
        assertEq(state.pendingInit.pendingRecoveryAddress, address(0), "Pending address not cleared");
        assertEq(state.pendingInit.pendingTimelockDurationSeconds, 0, "Pending timelock not cleared");
        assertEq(state.pendingInit.pendingTimestamp, 0, "Pending timestamp not cleared");
    }

    function test_finalizeInitializeTxRecovery_emitsEvent() public {
        harness.resetRecoveryStorage();

        harness.initiateInitializeTxRecovery({
            transactionAndERC1271RecoveryAddress: TX_RECOVERY_ADDRESS,
            txRecoveryTimelockDurationSeconds: TIMELOCK_DURATION
        });

        vm.warp(block.timestamp + SECURE_TIMELOCK_DURATION);

        vm.expectEmit(true, true, true, true);
        emit IOrganizationTxRecovery.TxRecoveryInitializationFinalized(TX_RECOVERY_ADDRESS, TIMELOCK_DURATION);

        harness.finalizeInitializeTxRecovery();
    }

    function test_finalizeInitializeTxRecovery_revertsIfNoPending() public {
        vm.expectRevert(IOrganizationTxRecovery.NoTxRecoveryInitializationPending.selector);
        harness.finalizeInitializeTxRecovery();
    }

    function test_finalizeInitializeTxRecovery_revertsIfTimelockNotExpired() public {
        harness.resetRecoveryStorage();

        harness.initiateInitializeTxRecovery({
            transactionAndERC1271RecoveryAddress: TX_RECOVERY_ADDRESS,
            txRecoveryTimelockDurationSeconds: TIMELOCK_DURATION
        });

        uint256 canFinalizeAt = harness.getTxRecoveryState().pendingInit.pendingTimestamp;

        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationSecureTimelock.TimelockNotExpired.selector, canFinalizeAt, block.timestamp
            )
        );
        harness.finalizeInitializeTxRecovery();
    }

    function test_cancelInitializeTxRecovery_clearsPendingState() public {
        harness.resetRecoveryStorage();

        harness.initiateInitializeTxRecovery({
            transactionAndERC1271RecoveryAddress: TX_RECOVERY_ADDRESS,
            txRecoveryTimelockDurationSeconds: TIMELOCK_DURATION
        });

        harness.cancelInitializeTxRecovery();

        TxRecoveryState memory state = harness.getTxRecoveryState();
        assertEq(state.pendingInit.pendingRecoveryAddress, address(0), "Pending address not cleared");
        assertEq(state.pendingInit.pendingTimelockDurationSeconds, 0, "Pending timelock not cleared");
        assertEq(state.pendingInit.pendingTimestamp, 0, "Pending timestamp not cleared");
    }

    function test_cancelInitializeTxRecovery_emitsEvent() public {
        harness.resetRecoveryStorage();

        harness.initiateInitializeTxRecovery({
            transactionAndERC1271RecoveryAddress: TX_RECOVERY_ADDRESS,
            txRecoveryTimelockDurationSeconds: TIMELOCK_DURATION
        });

        vm.expectEmit(true, true, true, true);
        emit IOrganizationTxRecovery.TxRecoveryInitializationCancelled();

        harness.cancelInitializeTxRecovery();
    }

    function test_cancelInitializeTxRecovery_revertsIfNoPending() public {
        vm.expectRevert(IOrganizationTxRecovery.NoTxRecoveryInitializationPending.selector);
        harness.cancelInitializeTxRecovery();
    }

    function test_deferredInitializeTxRecovery_allowsEnableFlowAfterSetup() public {
        harness.resetRecoveryStorage();

        // Initiate deferred initialization
        harness.initiateInitializeTxRecovery({
            transactionAndERC1271RecoveryAddress: TX_RECOVERY_ADDRESS,
            txRecoveryTimelockDurationSeconds: TIMELOCK_DURATION
        });

        // Wait for secure timelock and finalize
        vm.warp(block.timestamp + SECURE_TIMELOCK_DURATION);
        harness.finalizeInitializeTxRecovery();

        // Now enable recovery through the normal flow
        harness.initiateEnableTransactionAndERC1271Recovery();
        vm.warp(block.timestamp + TIMELOCK_DURATION);
        harness.finalizeEnableTransactionAndERC1271Recovery();

        assertTrue(harness.getTxRecoveryState().isEnabled, "Recovery should be enabled");

        // Validate recovery transaction is now allowed
        harness.validateRecoveryAccountTransactionAllowedOrRevert();
    }
}
