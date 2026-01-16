// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {SlotDerivation} from "@openzeppelin/contracts/utils/SlotDerivation.sol";
import {Test} from "forge-std/Test.sol";

import {IOrganizationGuardian} from "interfaces/organization/IOrganizationGuardian.sol";
import {IOrganizationGuardianRecovery} from "interfaces/organization/IOrganizationGuardianRecovery.sol";
import {IOrganizationTxRecovery} from "interfaces/organization/IOrganizationTxRecovery.sol";
import {LibOrganizationGuardian} from "organization/libraries/LibOrganizationGuardian.sol";
import {LibOrganizationGuardianRecovery} from "organization/libraries/LibOrganizationGuardianRecovery.sol";
import {LibOrganizationTxRecovery} from "organization/libraries/LibOrganizationTxRecovery.sol";
import {LibOrganizationGuardianStorage} from "organization/libraries/storage/LibOrganizationGuardianStorage.sol";
import {LibOrganizationRecoveryStorage} from "organization/libraries/storage/LibOrganizationRecoveryStorage.sol";

/**
 * @title Recovery Test Harness
 * @notice Wraps library functions for testing with proper msg.sender handling
 */
contract RecoveryTestHarness {
    // ================================
    // Guardian Recovery Library Functions
    // ================================

    function initializeGuardianRecovery(address guardianRecoveryAddress, uint256 recoveryTimelockDuration) external {
        LibOrganizationGuardianRecovery.initializeGuardianRecovery(guardianRecoveryAddress, recoveryTimelockDuration);
    }

    function initiateEnableGuardianRecovery() external {
        LibOrganizationGuardianRecovery.initiateEnableGuardianRecovery();
    }

    function finalizeEnableGuardianRecovery() external {
        LibOrganizationGuardianRecovery.finalizeEnableGuardianRecovery();
    }

    function cancelEnableGuardianRecovery() external {
        LibOrganizationGuardianRecovery.cancelEnableGuardianRecovery();
    }

    function disableGuardianRecovery() external {
        LibOrganizationGuardianRecovery.disableGuardianRecovery();
    }

    function initiateRecoveryGuardianUpdate(address newGuardian) external {
        LibOrganizationGuardianRecovery.initiateRecoveryGuardianUpdate(newGuardian);
    }

    function finalizeRecoveryGuardianUpdate() external {
        LibOrganizationGuardianRecovery.finalizeRecoveryGuardianUpdate();
    }

    function cancelRecoveryGuardianUpdate() external {
        LibOrganizationGuardianRecovery.cancelRecoveryGuardianUpdate();
    }

    function acceptGuardianRecovery() external {
        LibOrganizationGuardianRecovery.acceptGuardianRecovery();
    }

    function enforceOnlyGuardianRecoveryAddress() external view {
        LibOrganizationGuardianRecovery.enforceOnlyGuardianRecoveryAddress();
    }

    // ================================
    // Transaction Recovery Library Functions
    // ================================

    function initializeTxRecovery(
        bool isRecoverySupportedForTransactionsAndERC1271,
        address transactionAndERC1271RecoveryAddress
    ) external {
        LibOrganizationTxRecovery.initializeTxRecovery(
            isRecoverySupportedForTransactionsAndERC1271, transactionAndERC1271RecoveryAddress
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
    // Guardian Library Functions (Normal Flow)
    // ================================

    function initiateGuardianUpdate(address newGuardian) external {
        LibOrganizationGuardian.initiateGuardianUpdate(newGuardian);
    }

    function finalizeGuardianUpdate() external {
        LibOrganizationGuardian.finalizeGuardianUpdate();
    }

    function cancelGuardianUpdate() external {
        LibOrganizationGuardian.cancelGuardianUpdate();
    }

    function acceptGuardian() external {
        LibOrganizationGuardian.acceptGuardian();
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

    function isRecoveryEnabledForGuardianUpdate() external view returns (bool) {
        return LibOrganizationGuardianRecovery.isRecoveryEnabledForGuardianUpdate();
    }

    function getGuardianRecoveryAddress() external view returns (address) {
        return LibOrganizationGuardianRecovery.getGuardianRecoveryAddress();
    }

    function getRecoveryTimelockDuration() external view returns (uint256) {
        return LibOrganizationGuardianRecovery.getRecoveryTimelockDuration();
    }

    function getPendingTxRecoveryEnableTimestamp() external view returns (uint256) {
        return LibOrganizationTxRecovery.getPendingTxRecoveryEnableTimestamp();
    }

    function getPendingGuardianRecoveryEnableTimestamp() external view returns (uint256) {
        return LibOrganizationGuardianRecovery.getPendingGuardianRecoveryEnableTimestamp();
    }

    // Normal flow guardian state
    function getGuardian() external view returns (address) {
        return LibOrganizationGuardian.getGuardian();
    }

    function getPendingGuardian() external view returns (address) {
        return LibOrganizationGuardian.getPendingGuardian();
    }

    function getPendingGuardianUpdateTimestamp() external view returns (uint256) {
        return LibOrganizationGuardian.getPendingGuardianUpdateTimestamp();
    }

    function getIsGuardianUpdateReadyForAcceptance() external view returns (bool) {
        return LibOrganizationGuardian.getIsGuardianUpdateReadyForAcceptance();
    }

    // Recovery flow guardian state
    function getRecoveryPendingGuardian() external view returns (address) {
        return LibOrganizationGuardianRecovery.getRecoveryPendingGuardian();
    }

    function getRecoveryPendingGuardianTimestamp() external view returns (uint256) {
        return LibOrganizationGuardianRecovery.getRecoveryPendingGuardianTimestamp();
    }

    function getIsRecoveryGuardianUpdateReadyForAcceptance() external view returns (bool) {
        return LibOrganizationGuardianRecovery.getIsRecoveryGuardianUpdateReadyForAcceptance();
    }

    // ================================
    // Storage Direct Access (for reset in tests)
    // ================================

    function setGuardian(address _guardian) external {
        LibOrganizationGuardianStorage.layout().guardian = _guardian;
    }

    function setRecoverySupportedForTransactionsAndERC1271(bool supported) external {
        LibOrganizationRecoveryStorage.layout().isRecoverySupportedForTransactionsAndERC1271 = supported;
    }

    function resetRecoveryStorage() external {
        LibOrganizationRecoveryStorage.Layout storage layout = LibOrganizationRecoveryStorage.layout();
        layout.isRecoverySupportedForTransactionsAndERC1271 = false;
        layout.transactionAndERC1271RecoveryAddress = address(0);
        layout.guardianRecoveryAddress = address(0);
        layout.recoveryTimelockDuration = 0;
        layout.isRecoveryEnabledForTransactionsAndERC1271 = false;
        layout.isRecoveryEnabledForGuardianUpdate = false;
        layout.pendingTxRecoveryEnableTimestamp = 0;
        layout.pendingGuardianRecoveryEnableTimestamp = 0;
        layout.recoveryPendingGuardian = address(0);
        layout.recoveryPendingGuardianTimestamp = 0;
        layout.isRecoveryGuardianUpdateReadyForAcceptance = false;
    }
}

/**
 * @title Lib Organization Recovery Test
 * @notice Tests for disaster recovery functionality
 * @dev Tests initialization, timelocked enable flows, and access control.
 *      Normal and recovery guardian update flows use SEPARATE storage and are NOT mutually exclusive.
 * @author Den Technologies Inc
 */
contract LibOrganizationRecoveryTest is Test {
    RecoveryTestHarness public harness;

    address constant TX_RECOVERY_ADDRESS = address(0x100);
    address constant GUARDIAN_RECOVERY_ADDRESS = address(0x200);
    address constant GUARDIAN = address(0x300);
    address constant NEW_GUARDIAN = address(0x400);
    address constant NEW_GUARDIAN_2 = address(0x500);

    uint256 constant TIMELOCK_DURATION = 1 days;

    function setUp() public {
        harness = new RecoveryTestHarness();

        // Initialize guardian in storage
        harness.setGuardian(GUARDIAN);

        // Initialize guardian recovery configuration
        harness.initializeGuardianRecovery({
            guardianRecoveryAddress: GUARDIAN_RECOVERY_ADDRESS, recoveryTimelockDuration: TIMELOCK_DURATION
        });

        // Initialize tx recovery configuration
        harness.initializeTxRecovery({
            isRecoverySupportedForTransactionsAndERC1271: true,
            transactionAndERC1271RecoveryAddress: TX_RECOVERY_ADDRESS
        });
    }

    // ================================
    // Storage Slot Tests
    // ================================

    function test_recoveryStorage_slotIsCorrect() public pure {
        assertEq(
            LibOrganizationRecoveryStorage.STORAGE_LOCATION,
            SlotDerivation.erc7201Slot("den.mls-wallet.organization.recovery"),
            "LibOrganizationRecoveryStorage slot mismatch"
        );
    }

    function test_recoveryStorage_slotEndsWithZeroByte() public pure {
        assertEq(
            uint8(uint256(LibOrganizationRecoveryStorage.STORAGE_LOCATION) & 0xff),
            0,
            "Storage slot does not end with 0x00 (ERC-7201 violation)"
        );
    }

    // ================================
    // Initialization Tests
    // ================================

    function test_initializeRecovery_setsCorrectValues() public view {
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
        assertEq(harness.getGuardianRecoveryAddress(), GUARDIAN_RECOVERY_ADDRESS, "guardianRecoveryAddress not set");
        assertEq(harness.getRecoveryTimelockDuration(), TIMELOCK_DURATION, "recoveryTimelockDuration not set");
    }

    function test_initializeGuardianRecovery_revertsOnZeroTimelockDuration() public {
        harness.resetRecoveryStorage();

        vm.expectRevert(IOrganizationGuardianRecovery.InvalidRecoveryTimelockDuration.selector);
        harness.initializeGuardianRecovery({
            guardianRecoveryAddress: GUARDIAN_RECOVERY_ADDRESS, recoveryTimelockDuration: 0
        });
    }

    function test_initializeGuardianRecovery_revertsOnZeroGuardianRecoveryAddress() public {
        harness.resetRecoveryStorage();

        vm.expectRevert(IOrganizationGuardianRecovery.InvalidGuardianRecoveryAddress.selector);
        harness.initializeGuardianRecovery({
            guardianRecoveryAddress: address(0), recoveryTimelockDuration: TIMELOCK_DURATION
        });
    }

    function test_initializeTxRecovery_revertsOnZeroTxRecoveryAddressWhenSupported() public {
        harness.resetRecoveryStorage();

        vm.expectRevert(IOrganizationTxRecovery.InvalidTxRecoveryAddress.selector);
        harness.initializeTxRecovery({
            isRecoverySupportedForTransactionsAndERC1271: true, transactionAndERC1271RecoveryAddress: address(0)
        });
    }

    function test_initializeTxRecovery_revertsOnNonZeroTxRecoveryAddressWhenNotSupported() public {
        harness.resetRecoveryStorage();

        vm.expectRevert(IOrganizationTxRecovery.InvalidTxRecoveryAddress.selector);
        harness.initializeTxRecovery({
            isRecoverySupportedForTransactionsAndERC1271: false,
            transactionAndERC1271RecoveryAddress: TX_RECOVERY_ADDRESS
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
    // Guardian Recovery Enable Flow Tests (Timelocked)
    // ================================

    function test_initiateEnableGuardianRecovery_setsPendingTimestamp() public {
        harness.initiateEnableGuardianRecovery();

        uint256 expectedCanFinalizeAt = block.timestamp + TIMELOCK_DURATION;
        assertEq(
            harness.getPendingGuardianRecoveryEnableTimestamp(),
            expectedCanFinalizeAt,
            "Pending timestamp not set correctly"
        );
    }

    function test_initiateEnableGuardianRecovery_revertsIfAlreadyPending() public {
        harness.initiateEnableGuardianRecovery();

        vm.expectRevert(IOrganizationGuardianRecovery.GuardianRecoveryEnableAlreadyPending.selector);
        harness.initiateEnableGuardianRecovery();
    }

    function test_finalizeEnableGuardianRecovery_enablesRecovery() public {
        harness.initiateEnableGuardianRecovery();
        vm.warp(block.timestamp + TIMELOCK_DURATION);
        harness.finalizeEnableGuardianRecovery();

        assertTrue(harness.isRecoveryEnabledForGuardianUpdate(), "Recovery not enabled after finalize");
        assertEq(harness.getPendingGuardianRecoveryEnableTimestamp(), 0, "Pending timestamp not cleared");
    }

    function test_finalizeEnableGuardianRecovery_revertsIfNoPending() public {
        vm.expectRevert(IOrganizationGuardianRecovery.NoGuardianRecoveryEnablePending.selector);
        harness.finalizeEnableGuardianRecovery();
    }

    function test_finalizeEnableGuardianRecovery_revertsIfTimelockNotExpired() public {
        harness.initiateEnableGuardianRecovery();

        uint256 canFinalizeAt = harness.getPendingGuardianRecoveryEnableTimestamp();

        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationGuardianRecovery.GuardianRecoveryTimelockNotExpired.selector,
                canFinalizeAt,
                block.timestamp
            )
        );
        harness.finalizeEnableGuardianRecovery();
    }

    function test_cancelEnableGuardianRecovery_clearsPendingState() public {
        harness.initiateEnableGuardianRecovery();
        harness.cancelEnableGuardianRecovery();

        assertEq(harness.getPendingGuardianRecoveryEnableTimestamp(), 0, "Pending timestamp not cleared");
    }

    function test_disableGuardianRecovery_disablesImmediately() public {
        harness.initiateEnableGuardianRecovery();
        vm.warp(block.timestamp + TIMELOCK_DURATION);
        harness.finalizeEnableGuardianRecovery();
        assertTrue(harness.isRecoveryEnabledForGuardianUpdate(), "Recovery should be enabled");

        harness.disableGuardianRecovery();

        assertFalse(harness.isRecoveryEnabledForGuardianUpdate(), "Recovery should be disabled");
    }

    // ================================
    // Recovery Guardian Update Flow Tests (Separate Storage)
    // ================================

    function test_initiateRecoveryGuardianUpdate_setsPendingGuardian() public {
        _enableGuardianRecovery();

        harness.initiateRecoveryGuardianUpdate(NEW_GUARDIAN);

        assertEq(harness.getRecoveryPendingGuardian(), NEW_GUARDIAN, "Recovery pending guardian not set");
    }

    function test_initiateRecoveryGuardianUpdate_revertsIfNotEnabled() public {
        vm.expectRevert(IOrganizationGuardianRecovery.GuardianRecoveryNotEnabled.selector);
        harness.initiateRecoveryGuardianUpdate(NEW_GUARDIAN);
    }

    function test_initiateRecoveryGuardianUpdate_revertsIfAlreadyPending() public {
        _enableGuardianRecovery();
        harness.initiateRecoveryGuardianUpdate(NEW_GUARDIAN);

        vm.expectRevert(IOrganizationGuardianRecovery.RecoveryGuardianUpdateAlreadyPending.selector);
        harness.initiateRecoveryGuardianUpdate(address(0x999));
    }

    function test_initiateRecoveryGuardianUpdate_revertsOnZeroAddress() public {
        _enableGuardianRecovery();

        vm.expectRevert(IOrganizationGuardianRecovery.InvalidNewGuardianAddress.selector);
        harness.initiateRecoveryGuardianUpdate(address(0));
    }

    function test_finalizeRecoveryGuardianUpdate_setsReadyForAcceptance() public {
        _enableGuardianRecovery();
        harness.initiateRecoveryGuardianUpdate(NEW_GUARDIAN);
        vm.warp(block.timestamp + TIMELOCK_DURATION);

        harness.finalizeRecoveryGuardianUpdate();

        assertTrue(harness.getIsRecoveryGuardianUpdateReadyForAcceptance(), "Should be ready for acceptance");
    }

    function test_finalizeRecoveryGuardianUpdate_revertsIfNoPending() public {
        vm.expectRevert(IOrganizationGuardianRecovery.NoPendingRecoveryGuardianUpdate.selector);
        harness.finalizeRecoveryGuardianUpdate();
    }

    function test_finalizeRecoveryGuardianUpdate_revertsIfTimelockNotExpired() public {
        _enableGuardianRecovery();
        harness.initiateRecoveryGuardianUpdate(NEW_GUARDIAN);

        uint256 canFinalizeAt = harness.getRecoveryPendingGuardianTimestamp();

        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationGuardianRecovery.GuardianRecoveryTimelockNotExpired.selector,
                canFinalizeAt,
                block.timestamp
            )
        );
        harness.finalizeRecoveryGuardianUpdate();
    }

    function test_cancelRecoveryGuardianUpdate_clearsPendingState() public {
        _enableGuardianRecovery();
        harness.initiateRecoveryGuardianUpdate(NEW_GUARDIAN);

        harness.cancelRecoveryGuardianUpdate();

        assertEq(harness.getRecoveryPendingGuardian(), address(0), "Recovery pending guardian not cleared");
    }

    function test_cancelRecoveryGuardianUpdate_revertsIfNoPending() public {
        vm.expectRevert(IOrganizationGuardianRecovery.NoPendingRecoveryGuardianUpdate.selector);
        harness.cancelRecoveryGuardianUpdate();
    }

    function test_acceptGuardianRecovery_updatesGuardian() public {
        _enableGuardianRecovery();
        harness.initiateRecoveryGuardianUpdate(NEW_GUARDIAN);
        vm.warp(block.timestamp + TIMELOCK_DURATION);
        harness.finalizeRecoveryGuardianUpdate();

        vm.prank(NEW_GUARDIAN);
        harness.acceptGuardianRecovery();

        assertEq(harness.getGuardian(), NEW_GUARDIAN, "Guardian not updated");
        assertEq(harness.getRecoveryPendingGuardian(), address(0), "Recovery pending guardian not cleared");
    }

    function test_acceptGuardianRecovery_revertsIfNotPendingGuardian() public {
        _enableGuardianRecovery();
        harness.initiateRecoveryGuardianUpdate(NEW_GUARDIAN);
        vm.warp(block.timestamp + TIMELOCK_DURATION);
        harness.finalizeRecoveryGuardianUpdate();

        address wrongCaller = address(0x999);
        vm.prank(wrongCaller);

        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationGuardianRecovery.UnauthorizedRecoveryGuardianAcceptance.selector, wrongCaller, NEW_GUARDIAN
            )
        );
        harness.acceptGuardianRecovery();
    }

    function test_acceptGuardianRecovery_revertsIfNotReadyForAcceptance() public {
        _enableGuardianRecovery();
        harness.initiateRecoveryGuardianUpdate(NEW_GUARDIAN);

        vm.prank(NEW_GUARDIAN);
        vm.expectRevert(IOrganizationGuardianRecovery.RecoveryGuardianUpdateNotReadyForAcceptance.selector);
        harness.acceptGuardianRecovery();
    }

    function test_acceptGuardianRecovery_revertsIfNoPending() public {
        vm.prank(NEW_GUARDIAN);
        vm.expectRevert(IOrganizationGuardianRecovery.NoPendingRecoveryGuardianUpdate.selector);
        harness.acceptGuardianRecovery();
    }

    // ================================
    // Normal Guardian Update Flow Tests (Timelocked 3-Step)
    // ================================

    function test_initiateGuardianUpdate_setsPendingState() public {
        harness.initiateGuardianUpdate(NEW_GUARDIAN);

        assertEq(harness.getPendingGuardian(), NEW_GUARDIAN, "Pending guardian not set");
    }

    function test_initiateGuardianUpdate_revertsOnZeroAddress() public {
        vm.expectRevert(IOrganizationGuardian.InvalidGuardianAddress.selector);
        harness.initiateGuardianUpdate(address(0));
    }

    function test_initiateGuardianUpdate_revertsIfAlreadyPending() public {
        harness.initiateGuardianUpdate(NEW_GUARDIAN);

        vm.expectRevert(IOrganizationGuardian.GuardianUpdateAlreadyPending.selector);
        harness.initiateGuardianUpdate(address(0x999));
    }

    function test_finalizeGuardianUpdate_setsReadyForAcceptance() public {
        harness.initiateGuardianUpdate(NEW_GUARDIAN);
        vm.warp(block.timestamp + TIMELOCK_DURATION);

        harness.finalizeGuardianUpdate();

        assertTrue(harness.getIsGuardianUpdateReadyForAcceptance(), "Should be ready for acceptance");
    }

    function test_finalizeGuardianUpdate_revertsIfTimelockNotExpired() public {
        harness.initiateGuardianUpdate(NEW_GUARDIAN);

        uint256 canFinalizeAt = harness.getPendingGuardianUpdateTimestamp();

        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationGuardian.GuardianUpdateTimelockNotExpired.selector, canFinalizeAt, block.timestamp
            )
        );
        harness.finalizeGuardianUpdate();
    }

    function test_finalizeGuardianUpdate_revertsIfNoPending() public {
        vm.expectRevert(IOrganizationGuardian.NoPendingGuardianUpdate.selector);
        harness.finalizeGuardianUpdate();
    }

    function test_cancelGuardianUpdate_clearsPendingState() public {
        harness.initiateGuardianUpdate(NEW_GUARDIAN);

        harness.cancelGuardianUpdate();

        assertEq(harness.getPendingGuardian(), address(0), "Pending guardian not cleared");
    }

    function test_cancelGuardianUpdate_revertsIfNoPending() public {
        vm.expectRevert(IOrganizationGuardian.NoPendingGuardianUpdate.selector);
        harness.cancelGuardianUpdate();
    }

    function test_acceptGuardian_updatesGuardian() public {
        harness.initiateGuardianUpdate(NEW_GUARDIAN);
        vm.warp(block.timestamp + TIMELOCK_DURATION);
        harness.finalizeGuardianUpdate();

        vm.prank(NEW_GUARDIAN);
        harness.acceptGuardian();

        assertEq(harness.getGuardian(), NEW_GUARDIAN, "Guardian not updated");
        assertEq(harness.getPendingGuardian(), address(0), "Pending guardian not cleared");
    }

    function test_acceptGuardian_revertsIfNotPendingGuardian() public {
        harness.initiateGuardianUpdate(NEW_GUARDIAN);
        vm.warp(block.timestamp + TIMELOCK_DURATION);
        harness.finalizeGuardianUpdate();

        address wrongCaller = address(0x999);
        vm.prank(wrongCaller);

        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationGuardian.UnauthorizedGuardianAcceptance.selector, wrongCaller, NEW_GUARDIAN
            )
        );
        harness.acceptGuardian();
    }

    function test_acceptGuardian_revertsIfNotReadyForAcceptance() public {
        harness.initiateGuardianUpdate(NEW_GUARDIAN);

        vm.prank(NEW_GUARDIAN);
        vm.expectRevert(IOrganizationGuardian.GuardianUpdateNotReadyForAcceptance.selector);
        harness.acceptGuardian();
    }

    // ================================
    // Parallel Flows Tests (Non-Mutually Exclusive)
    // ================================

    function test_bothFlowsCanRunInParallel() public {
        _enableGuardianRecovery();

        // Initiate both flows with different new guardians
        harness.initiateGuardianUpdate(NEW_GUARDIAN);
        harness.initiateRecoveryGuardianUpdate(NEW_GUARDIAN_2);

        // Both should have pending state
        assertEq(harness.getPendingGuardian(), NEW_GUARDIAN, "Normal flow pending guardian not set");
        assertEq(harness.getRecoveryPendingGuardian(), NEW_GUARDIAN_2, "Recovery flow pending guardian not set");
    }

    function test_recoveryFlowCanCompleteWhileNormalFlowPending() public {
        _enableGuardianRecovery();

        // Start both flows
        harness.initiateGuardianUpdate(NEW_GUARDIAN);
        harness.initiateRecoveryGuardianUpdate(NEW_GUARDIAN_2);

        // Complete recovery flow
        vm.warp(block.timestamp + TIMELOCK_DURATION);
        harness.finalizeRecoveryGuardianUpdate();
        vm.prank(NEW_GUARDIAN_2);
        harness.acceptGuardianRecovery();

        // Guardian should be updated to recovery's NEW_GUARDIAN_2
        assertEq(harness.getGuardian(), NEW_GUARDIAN_2, "Guardian should be updated by recovery flow");

        // Normal flow should still have pending state
        assertEq(harness.getPendingGuardian(), NEW_GUARDIAN, "Normal flow pending should still exist");
    }

    function test_normalFlowCanCompleteWhileRecoveryFlowPending() public {
        _enableGuardianRecovery();

        // Start both flows
        harness.initiateGuardianUpdate(NEW_GUARDIAN);
        harness.initiateRecoveryGuardianUpdate(NEW_GUARDIAN_2);

        // Complete normal flow
        vm.warp(block.timestamp + TIMELOCK_DURATION);
        harness.finalizeGuardianUpdate();
        vm.prank(NEW_GUARDIAN);
        harness.acceptGuardian();

        // Guardian should be updated to normal flow's NEW_GUARDIAN
        assertEq(harness.getGuardian(), NEW_GUARDIAN, "Guardian should be updated by normal flow");

        // Recovery flow should still have pending state
        assertEq(harness.getRecoveryPendingGuardian(), NEW_GUARDIAN_2, "Recovery flow pending should still exist");
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

    // ================================
    // Helper Functions
    // ================================

    function _enableGuardianRecovery() internal {
        harness.initiateEnableGuardianRecovery();
        vm.warp(block.timestamp + TIMELOCK_DURATION);
        harness.finalizeEnableGuardianRecovery();
    }
}
