// SPDX-License-Identifier: MIT
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
        bool isTxRecoverySupported,
        address transactionAndERC1271RecoveryAddress,
        uint256 txRecoveryTimelockDuration
    ) external {
        LibOrganizationTxRecovery.initializeTxRecovery(
            isTxRecoverySupported, transactionAndERC1271RecoveryAddress, txRecoveryTimelockDuration
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

    function isRecoverySupportedForTransactionsAndERC1271() external view returns (bool) {
        return LibOrganizationTxRecovery.isRecoverySupportedForTxAndERC1271();
    }

    function isRecoveryEnabledForTransactionsAndERC1271() external view returns (bool) {
        return LibOrganizationTxRecovery.isRecoveryEnabledForTxAndERC1271();
    }

    function getTransactionAndERC1271RecoveryAddress() external view returns (address) {
        return LibOrganizationTxRecovery.getTxRecoveryAddress();
    }

    function getTxRecoveryTimelockDuration() external view returns (uint256) {
        return LibOrganizationTxRecovery.getTxRecoveryTimelockDuration();
    }

    function getPendingTxRecoveryEnableTimestamp() external view returns (uint256) {
        return LibOrganizationTxRecovery.getPendingTxRecoveryEnableTimestamp();
    }

    // ================================
    // Storage Direct Access (for reset in tests)
    // ================================

    function setRecoverySupportedForTransactionsAndERC1271(bool supported) external {
        LibOrganizationRecoveryStorage.layout().txRecovery.isSupported = supported;
    }

    function resetRecoveryStorage() external {
        LibOrganizationRecoveryStorage.Layout storage layout = LibOrganizationRecoveryStorage.layout();

        // Reset tx recovery state
        layout.txRecovery.recoveryAddress = address(0);
        layout.txRecovery.isSupported = false;
        layout.txRecovery.isEnabled = false;
        layout.txRecovery.timelockDuration = 0;
        layout.txRecovery.pendingEnableTimestamp = 0;

        // Reset guardian recovery state
        layout.guardianRecovery.recoveryAddress = address(0);
        layout.guardianRecovery.timelockDuration = 0;
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
            isTxRecoverySupported: true,
            transactionAndERC1271RecoveryAddress: TX_RECOVERY_ADDRESS,
            txRecoveryTimelockDuration: TIMELOCK_DURATION
        });
    }

    // ================================
    // Initialization Tests
    // ================================

    function test_initializeTxRecovery_setsCorrectValues() public view {
        assertEq(
            harness.isRecoverySupportedForTransactionsAndERC1271(),
            true,
            "isRecoverySupportedForTransactionsAndERC1271 not set"
        );
        assertEq(
            harness.getTransactionAndERC1271RecoveryAddress(),
            TX_RECOVERY_ADDRESS,
            "transactionAndERC1271RecoveryAddress not set"
        );
        assertEq(harness.getTxRecoveryTimelockDuration(), TIMELOCK_DURATION, "txRecoveryTimelockDuration not set");
    }

    function test_initializeTxRecovery_revertsOnZeroTxRecoveryAddressWhenSupported() public {
        harness.resetRecoveryStorage();

        vm.expectRevert(IOrganizationTxRecovery.InvalidTxRecoveryAddress.selector);
        harness.initializeTxRecovery({
            isTxRecoverySupported: true,
            transactionAndERC1271RecoveryAddress: address(0),
            txRecoveryTimelockDuration: TIMELOCK_DURATION
        });
    }

    function test_initializeTxRecovery_revertsOnNonZeroTxRecoveryAddressWhenNotSupported() public {
        harness.resetRecoveryStorage();

        vm.expectRevert(IOrganizationTxRecovery.InvalidTxRecoveryAddress.selector);
        harness.initializeTxRecovery({
            isTxRecoverySupported: false,
            transactionAndERC1271RecoveryAddress: TX_RECOVERY_ADDRESS,
            txRecoveryTimelockDuration: 0
        });
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

    function test_initiateEnableTxRecovery_revertsIfNotSupported() public {
        harness.setRecoverySupportedForTransactionsAndERC1271(false);

        vm.expectRevert(IOrganizationTxRecovery.TxRecoveryNotSupported.selector);
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

    function test_validateRecoveryAccountTransactionAllowed_revertsIfNotSupported() public {
        harness.setRecoverySupportedForTransactionsAndERC1271(false);

        vm.expectRevert(IOrganizationTxRecovery.TxRecoveryNotSupported.selector);
        harness.validateRecoveryAccountTransactionAllowedOrRevert();
    }

    function test_validateRecoveryAccountTransactionAllowed_revertsIfNotEnabled() public {
        vm.expectRevert(IOrganizationTxRecovery.TxRecoveryNotEnabled.selector);
        harness.validateRecoveryAccountTransactionAllowedOrRevert();
    }
}
