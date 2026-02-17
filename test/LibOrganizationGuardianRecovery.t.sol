// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {SlotDerivation} from "@openzeppelin/contracts/utils/SlotDerivation.sol";
import {Test} from "forge-std/Test.sol";

import {IOrganizationAdminOperationTimelock} from "interfaces/organization/IOrganizationAdminOperationTimelock.sol";
import {IOrganizationGuardian} from "interfaces/organization/IOrganizationGuardian.sol";
import {IOrganizationGuardianRecovery} from "interfaces/organization/IOrganizationGuardianRecovery.sol";
import {TimelockUtils} from "libraries/TimelockUtils.sol";
import {LibOrganizationGuardian} from "organization/libraries/LibOrganizationGuardian.sol";
import {LibOrganizationGuardianRecovery} from "organization/libraries/LibOrganizationGuardianRecovery.sol";
import {
    LibOrganizationAdminOperationTimelockStorage
} from "organization/libraries/storage/LibOrganizationAdminOperationTimelockStorage.sol";
import {LibOrganizationGuardianStorage} from "organization/libraries/storage/LibOrganizationGuardianStorage.sol";
import {LibOrganizationRecoveryStorage} from "organization/libraries/storage/LibOrganizationRecoveryStorage.sol";
import {GuardianRecoveryState} from "types/RecoveryTypes.sol";

/**
 * @dev Guardian Recovery Test Harness
 *      Wraps library functions for testing with proper msg.sender handling
 */
contract GuardianRecoveryTestHarness {
    // ================================
    // Guardian Recovery Library Functions
    // ================================

    function initializeGuardianRecovery(
        address guardianRecoveryAddress,
        uint256 guardianRecoveryTimelockDurationSeconds
    ) external {
        // Simulate what LibOrganizationInitialization does:
        // Only call the library if address is non-zero (defer setup if zero)
        if (guardianRecoveryAddress != address(0)) {
            LibOrganizationGuardianRecovery.initializeGuardianRecovery(
                guardianRecoveryAddress, guardianRecoveryTimelockDurationSeconds
            );
        }
    }

    function initiateInitializeGuardianRecovery(
        address guardianRecoveryAddress,
        uint256 guardianRecoveryTimelockDurationSeconds
    ) external {
        LibOrganizationGuardianRecovery.initiateInitializeGuardianRecovery(
            guardianRecoveryAddress, guardianRecoveryTimelockDurationSeconds
        );
    }

    function finalizeInitializeGuardianRecovery() external {
        LibOrganizationGuardianRecovery.finalizeInitializeGuardianRecovery();
    }

    function cancelInitializeGuardianRecovery() external {
        LibOrganizationGuardianRecovery.cancelInitializeGuardianRecovery();
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
        LibOrganizationGuardianRecovery.enforceOnlyRecoveryPendingGuardian();
        LibOrganizationGuardianRecovery.acceptGuardianRecovery();
    }

    function enforceOnlyGuardianRecoveryAddress() external view {
        LibOrganizationGuardianRecovery.enforceOnlyGuardianRecoveryAddress();
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
        LibOrganizationGuardian.enforceOnlyPendingGuardian();
        LibOrganizationGuardian.acceptGuardian();
    }

    // ================================
    // View Functions
    // ================================

    function getGuardianRecoveryState() external view returns (GuardianRecoveryState memory) {
        return LibOrganizationRecoveryStorage.layout().guardianRecovery;
    }

    function getAdminOperationTimelockDurationSeconds() external view returns (uint256) {
        return LibOrganizationAdminOperationTimelockStorage.layout().adminOperationTimelockDurationSeconds;
    }

    // Normal flow guardian state (uses LibOrganizationGuardian getters -- separate from recovery)
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

    // ================================
    // Storage Direct Access (for reset/setup in tests)
    // ================================

    function setGuardian(address _guardian) external {
        LibOrganizationGuardianStorage.layout().guardian = _guardian;
    }

    function initializeAdminOperationTimelock(uint256 adminOperationTimelockDurationSeconds) external {
        LibOrganizationAdminOperationTimelockStorage.layout().adminOperationTimelockDurationSeconds =
        adminOperationTimelockDurationSeconds;
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

    function resetGuardianStorage() external {
        LibOrganizationGuardianStorage.Layout storage layout = LibOrganizationGuardianStorage.layout();
        layout.guardian = address(0);
        layout.pendingGuardian = address(0);
        layout.pendingGuardianUpdateTimestamp = 0;
        layout.isGuardianUpdateReadyForAcceptance = false;
    }

    function initializeGuardian(address guardian) external {
        LibOrganizationGuardian.initializeGuardian(guardian);
    }
}

/**
 * @dev Lib Organization Guardian Recovery Test
 *      Tests for guardian recovery functionality
 *      Tests initialization, timelocked guardian recovery flows, deferred initialization, and access control.
 *      Normal and recovery guardian update flows use SEPARATE storage and are NOT mutually exclusive.
 * @author Den Technologies Inc
 */
contract LibOrganizationGuardianRecoveryTest is Test {
    GuardianRecoveryTestHarness public harness;

    address constant GUARDIAN_RECOVERY_ADDRESS = address(0x200);
    address constant GUARDIAN = address(0x300);
    address constant NEW_GUARDIAN = address(0x400);
    address constant NEW_GUARDIAN_2 = address(0x500);

    uint256 constant TIMELOCK_DURATION = 2 days;
    uint256 constant ADMIN_OPERATION_TIMELOCK_DURATION = 3 days;

    function setUp() public {
        harness = new GuardianRecoveryTestHarness();

        // Initialize admin operation timelock (organization-wide)
        harness.initializeAdminOperationTimelock(ADMIN_OPERATION_TIMELOCK_DURATION);

        // Initialize guardian configuration (sets guardian address)
        harness.initializeGuardian(GUARDIAN);

        // Initialize guardian recovery configuration
        harness.initializeGuardianRecovery({
            guardianRecoveryAddress: GUARDIAN_RECOVERY_ADDRESS,
            guardianRecoveryTimelockDurationSeconds: TIMELOCK_DURATION
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

    function test_initializeGuardianRecovery_setsCorrectValues() public view {
        GuardianRecoveryState memory state = harness.getGuardianRecoveryState();
        assertEq(state.recoveryAddress, GUARDIAN_RECOVERY_ADDRESS, "guardianRecoveryAddress not set");
        assertEq(state.timelockDurationSeconds, TIMELOCK_DURATION, "guardianRecoveryTimelockDurationSeconds not set");
        assertEq(
            harness.getAdminOperationTimelockDurationSeconds(),
            ADMIN_OPERATION_TIMELOCK_DURATION,
            "adminOperationTimelockDurationSeconds not set"
        );
    }

    function test_initializeGuardianRecovery_revertsOnZeroTimelockDurationSeconds() public {
        harness.resetRecoveryStorage();

        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockUtils.InvalidTimelockDuration.selector,
                0,
                TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS,
                TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
            )
        );
        harness.initializeGuardianRecovery({
            guardianRecoveryAddress: GUARDIAN_RECOVERY_ADDRESS, guardianRecoveryTimelockDurationSeconds: 0
        });
    }

    // Note: test_initializeGuardianRecovery_revertsOnZeroGuardianRecoveryAddress was removed
    // because zero address is now allowed to defer guardian recovery setup to a later time

    // ================================
    // Recovery Guardian Update Flow Tests (Single Timelock)
    // ================================

    function test_initiateRecoveryGuardianUpdate_setsPendingGuardian() public {
        harness.initiateRecoveryGuardianUpdate(NEW_GUARDIAN);

        assertEq(harness.getGuardianRecoveryState().pendingGuardian, NEW_GUARDIAN, "Recovery pending guardian not set");
    }

    function test_initiateRecoveryGuardianUpdate_revertsIfAlreadyPending() public {
        harness.initiateRecoveryGuardianUpdate(NEW_GUARDIAN);

        vm.expectRevert(IOrganizationGuardianRecovery.RecoveryGuardianUpdateAlreadyPending.selector);
        harness.initiateRecoveryGuardianUpdate(address(0x999));
    }

    function test_initiateRecoveryGuardianUpdate_revertsOnZeroAddress() public {
        vm.expectRevert(IOrganizationGuardianRecovery.InvalidNewGuardianAddress.selector);
        harness.initiateRecoveryGuardianUpdate(address(0));
    }

    function test_finalizeRecoveryGuardianUpdate_setsReadyForAcceptance() public {
        harness.initiateRecoveryGuardianUpdate(NEW_GUARDIAN);
        vm.warp(block.timestamp + TIMELOCK_DURATION);

        harness.finalizeRecoveryGuardianUpdate();

        assertTrue(harness.getGuardianRecoveryState().isUpdateReadyForAcceptance, "Should be ready for acceptance");
    }

    function test_finalizeRecoveryGuardianUpdate_revertsIfNoPending() public {
        vm.expectRevert(IOrganizationGuardianRecovery.NoPendingRecoveryGuardianUpdate.selector);
        harness.finalizeRecoveryGuardianUpdate();
    }

    function test_finalizeRecoveryGuardianUpdate_revertsIfTimelockNotExpired() public {
        harness.initiateRecoveryGuardianUpdate(NEW_GUARDIAN);

        uint256 canFinalizeAt = harness.getGuardianRecoveryState().pendingGuardianTimestamp;

        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationAdminOperationTimelock.TimelockNotExpired.selector, canFinalizeAt, block.timestamp
            )
        );
        harness.finalizeRecoveryGuardianUpdate();
    }

    function test_cancelRecoveryGuardianUpdate_clearsPendingState() public {
        harness.initiateRecoveryGuardianUpdate(NEW_GUARDIAN);

        harness.cancelRecoveryGuardianUpdate();

        assertEq(
            harness.getGuardianRecoveryState().pendingGuardian, address(0), "Recovery pending guardian not cleared"
        );
    }

    function test_cancelRecoveryGuardianUpdate_revertsIfNoPending() public {
        vm.expectRevert(IOrganizationGuardianRecovery.NoPendingRecoveryGuardianUpdate.selector);
        harness.cancelRecoveryGuardianUpdate();
    }

    function test_acceptGuardianRecovery_updatesGuardian() public {
        harness.initiateRecoveryGuardianUpdate(NEW_GUARDIAN);
        vm.warp(block.timestamp + TIMELOCK_DURATION);
        harness.finalizeRecoveryGuardianUpdate();

        vm.prank(NEW_GUARDIAN);
        harness.acceptGuardianRecovery();

        assertEq(harness.getGuardian(), NEW_GUARDIAN, "Guardian not updated");
        assertEq(
            harness.getGuardianRecoveryState().pendingGuardian, address(0), "Recovery pending guardian not cleared"
        );
    }

    function test_acceptGuardianRecovery_revertsIfNotPendingGuardian() public {
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
        harness.initiateRecoveryGuardianUpdate(NEW_GUARDIAN);

        vm.prank(NEW_GUARDIAN);
        vm.expectRevert(IOrganizationGuardianRecovery.RecoveryGuardianUpdateNotReadyForAcceptance.selector);
        harness.acceptGuardianRecovery();
    }

    function test_acceptGuardianRecovery_revertsIfNoPending() public {
        // When there's no pending guardian, pendingGuardianAddr is address(0)
        // The modifier check fails first with UnauthorizedRecoveryGuardianAcceptance
        vm.prank(NEW_GUARDIAN);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationGuardianRecovery.UnauthorizedRecoveryGuardianAcceptance.selector, NEW_GUARDIAN, address(0)
            )
        );
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
        vm.warp(block.timestamp + ADMIN_OPERATION_TIMELOCK_DURATION);

        harness.finalizeGuardianUpdate();

        assertTrue(harness.getIsGuardianUpdateReadyForAcceptance(), "Should be ready for acceptance");
    }

    function test_finalizeGuardianUpdate_revertsIfTimelockNotExpired() public {
        harness.initiateGuardianUpdate(NEW_GUARDIAN);

        uint256 canFinalizeAt = harness.getPendingGuardianUpdateTimestamp();

        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationAdminOperationTimelock.TimelockNotExpired.selector, canFinalizeAt, block.timestamp
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
        vm.warp(block.timestamp + ADMIN_OPERATION_TIMELOCK_DURATION);
        harness.finalizeGuardianUpdate();

        vm.prank(NEW_GUARDIAN);
        harness.acceptGuardian();

        assertEq(harness.getGuardian(), NEW_GUARDIAN, "Guardian not updated");
        assertEq(harness.getPendingGuardian(), address(0), "Pending guardian not cleared");
    }

    function test_acceptGuardian_revertsIfNotPendingGuardian() public {
        harness.initiateGuardianUpdate(NEW_GUARDIAN);
        vm.warp(block.timestamp + ADMIN_OPERATION_TIMELOCK_DURATION);
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
        // Initiate both flows with different new guardians
        harness.initiateGuardianUpdate(NEW_GUARDIAN);
        harness.initiateRecoveryGuardianUpdate(NEW_GUARDIAN_2);

        // Both should have pending state
        assertEq(harness.getPendingGuardian(), NEW_GUARDIAN, "Normal flow pending guardian not set");
        assertEq(
            harness.getGuardianRecoveryState().pendingGuardian, NEW_GUARDIAN_2, "Recovery flow pending guardian not set"
        );
    }

    function test_recoveryFlowCanCompleteWhileNormalFlowPending() public {
        // Start both flows
        harness.initiateGuardianUpdate(NEW_GUARDIAN);
        harness.initiateRecoveryGuardianUpdate(NEW_GUARDIAN_2);

        // Complete recovery flow
        vm.warp(block.timestamp + ADMIN_OPERATION_TIMELOCK_DURATION);
        harness.finalizeRecoveryGuardianUpdate();
        vm.prank(NEW_GUARDIAN_2);
        harness.acceptGuardianRecovery();

        // Guardian should be updated to recovery's NEW_GUARDIAN_2
        assertEq(harness.getGuardian(), NEW_GUARDIAN_2, "Guardian should be updated by recovery flow");

        // Normal flow should still have pending state
        assertEq(harness.getPendingGuardian(), NEW_GUARDIAN, "Normal flow pending should still exist");
    }

    function test_normalFlowCanCompleteWhileRecoveryFlowPending() public {
        // Start both flows
        harness.initiateGuardianUpdate(NEW_GUARDIAN);
        harness.initiateRecoveryGuardianUpdate(NEW_GUARDIAN_2);

        // Complete normal flow
        vm.warp(block.timestamp + ADMIN_OPERATION_TIMELOCK_DURATION);
        harness.finalizeGuardianUpdate();
        vm.prank(NEW_GUARDIAN);
        harness.acceptGuardian();

        // Guardian should be updated to normal flow's NEW_GUARDIAN
        assertEq(harness.getGuardian(), NEW_GUARDIAN, "Guardian should be updated by normal flow");

        // Recovery flow should still have pending state
        assertEq(
            harness.getGuardianRecoveryState().pendingGuardian,
            NEW_GUARDIAN_2,
            "Recovery flow pending should still exist"
        );
    }

    // ================================
    // Optional Guardian Recovery Setup Tests (Deferred Initialization)
    // ================================

    function test_initializeGuardianRecovery_allowsDeferredSetup() public {
        harness.resetRecoveryStorage();

        // Initialize with zero address (defer setup) - should not revert, but nothing is set
        harness.initializeGuardianRecovery({
            guardianRecoveryAddress: address(0), guardianRecoveryTimelockDurationSeconds: 0
        });

        // Verify nothing was set (deferred)
        GuardianRecoveryState memory state = harness.getGuardianRecoveryState();
        assertEq(state.recoveryAddress, address(0), "Recovery address should be zero");
        assertEq(state.timelockDurationSeconds, 0, "Timelock should be zero");
    }

    function test_initializeGuardianRecovery_revertsOnZeroTimelockWhenAddressProvided() public {
        harness.resetRecoveryStorage();

        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockUtils.InvalidTimelockDuration.selector,
                0,
                TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS,
                TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
            )
        );
        harness.initializeGuardianRecovery({
            guardianRecoveryAddress: GUARDIAN_RECOVERY_ADDRESS, guardianRecoveryTimelockDurationSeconds: 0
        });
    }

    // ================================
    // Deferred Initialization (Timelocked) Tests
    // ================================

    function test_initiateInitializeGuardianRecovery_setsPendingState() public {
        harness.resetRecoveryStorage();

        harness.initiateInitializeGuardianRecovery({
            guardianRecoveryAddress: GUARDIAN_RECOVERY_ADDRESS,
            guardianRecoveryTimelockDurationSeconds: TIMELOCK_DURATION
        });

        GuardianRecoveryState memory state = harness.getGuardianRecoveryState();
        assertEq(state.pendingInit.pendingRecoveryAddress, GUARDIAN_RECOVERY_ADDRESS, "Pending address not set");
        assertEq(state.pendingInit.pendingTimelockDurationSeconds, TIMELOCK_DURATION, "Pending timelock not set");
        uint256 expectedCanFinalizeAt = block.timestamp + ADMIN_OPERATION_TIMELOCK_DURATION;
        assertEq(state.pendingInit.pendingTimestamp, expectedCanFinalizeAt, "Pending timestamp not set");
    }

    function test_initiateInitializeGuardianRecovery_emitsEvent() public {
        harness.resetRecoveryStorage();

        uint256 expectedCanFinalizeAt = block.timestamp + ADMIN_OPERATION_TIMELOCK_DURATION;

        vm.expectEmit(true, true, true, true);
        emit IOrganizationGuardianRecovery.GuardianRecoveryInitializationInitiated(
            GUARDIAN_RECOVERY_ADDRESS, TIMELOCK_DURATION, expectedCanFinalizeAt
        );

        harness.initiateInitializeGuardianRecovery({
            guardianRecoveryAddress: GUARDIAN_RECOVERY_ADDRESS,
            guardianRecoveryTimelockDurationSeconds: TIMELOCK_DURATION
        });
    }

    function test_initiateInitializeGuardianRecovery_revertsIfAlreadyConfigured() public {
        // setUp already configured recovery, so this should revert
        vm.expectRevert(IOrganizationGuardianRecovery.GuardianRecoveryAlreadyConfigured.selector);
        harness.initiateInitializeGuardianRecovery({
            guardianRecoveryAddress: address(0x999), guardianRecoveryTimelockDurationSeconds: TIMELOCK_DURATION
        });
    }

    function test_initiateInitializeGuardianRecovery_revertsIfAlreadyPending() public {
        harness.resetRecoveryStorage();

        harness.initiateInitializeGuardianRecovery({
            guardianRecoveryAddress: GUARDIAN_RECOVERY_ADDRESS,
            guardianRecoveryTimelockDurationSeconds: TIMELOCK_DURATION
        });

        vm.expectRevert(IOrganizationGuardianRecovery.GuardianRecoveryInitializationAlreadyPending.selector);
        harness.initiateInitializeGuardianRecovery({
            guardianRecoveryAddress: address(0x999), guardianRecoveryTimelockDurationSeconds: TIMELOCK_DURATION
        });
    }

    function test_initiateInitializeGuardianRecovery_revertsOnZeroAddress() public {
        harness.resetRecoveryStorage();

        vm.expectRevert(IOrganizationGuardianRecovery.InvalidGuardianRecoveryAddress.selector);
        harness.initiateInitializeGuardianRecovery({
            guardianRecoveryAddress: address(0), guardianRecoveryTimelockDurationSeconds: TIMELOCK_DURATION
        });
    }

    function test_initiateInitializeGuardianRecovery_revertsOnZeroTimelock() public {
        harness.resetRecoveryStorage();

        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockUtils.InvalidTimelockDuration.selector,
                0,
                TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS,
                TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
            )
        );
        harness.initiateInitializeGuardianRecovery({
            guardianRecoveryAddress: GUARDIAN_RECOVERY_ADDRESS, guardianRecoveryTimelockDurationSeconds: 0
        });
    }

    function test_finalizeInitializeGuardianRecovery_configuresRecovery() public {
        harness.resetRecoveryStorage();

        harness.initiateInitializeGuardianRecovery({
            guardianRecoveryAddress: GUARDIAN_RECOVERY_ADDRESS,
            guardianRecoveryTimelockDurationSeconds: TIMELOCK_DURATION
        });

        vm.warp(block.timestamp + ADMIN_OPERATION_TIMELOCK_DURATION);
        harness.finalizeInitializeGuardianRecovery();

        GuardianRecoveryState memory state = harness.getGuardianRecoveryState();
        assertEq(state.recoveryAddress, GUARDIAN_RECOVERY_ADDRESS, "Recovery address not set");
        assertEq(state.timelockDurationSeconds, TIMELOCK_DURATION, "Timelock duration not set");

        // Pending state should be cleared
        assertEq(state.pendingInit.pendingRecoveryAddress, address(0), "Pending address not cleared");
        assertEq(state.pendingInit.pendingTimelockDurationSeconds, 0, "Pending timelock not cleared");
        assertEq(state.pendingInit.pendingTimestamp, 0, "Pending timestamp not cleared");
    }

    function test_finalizeInitializeGuardianRecovery_emitsEvent() public {
        harness.resetRecoveryStorage();

        harness.initiateInitializeGuardianRecovery({
            guardianRecoveryAddress: GUARDIAN_RECOVERY_ADDRESS,
            guardianRecoveryTimelockDurationSeconds: TIMELOCK_DURATION
        });

        vm.warp(block.timestamp + ADMIN_OPERATION_TIMELOCK_DURATION);

        vm.expectEmit(true, true, true, true);
        emit IOrganizationGuardianRecovery.GuardianRecoveryInitializationFinalized(
            GUARDIAN_RECOVERY_ADDRESS, TIMELOCK_DURATION
        );

        harness.finalizeInitializeGuardianRecovery();
    }

    function test_finalizeInitializeGuardianRecovery_revertsIfNoPending() public {
        vm.expectRevert(IOrganizationGuardianRecovery.NoGuardianRecoveryInitializationPending.selector);
        harness.finalizeInitializeGuardianRecovery();
    }

    function test_finalizeInitializeGuardianRecovery_revertsIfTimelockNotExpired() public {
        harness.resetRecoveryStorage();

        harness.initiateInitializeGuardianRecovery({
            guardianRecoveryAddress: GUARDIAN_RECOVERY_ADDRESS,
            guardianRecoveryTimelockDurationSeconds: TIMELOCK_DURATION
        });

        uint256 canFinalizeAt = harness.getGuardianRecoveryState().pendingInit.pendingTimestamp;

        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationAdminOperationTimelock.TimelockNotExpired.selector, canFinalizeAt, block.timestamp
            )
        );
        harness.finalizeInitializeGuardianRecovery();
    }

    function test_cancelInitializeGuardianRecovery_clearsPendingState() public {
        harness.resetRecoveryStorage();

        harness.initiateInitializeGuardianRecovery({
            guardianRecoveryAddress: GUARDIAN_RECOVERY_ADDRESS,
            guardianRecoveryTimelockDurationSeconds: TIMELOCK_DURATION
        });

        harness.cancelInitializeGuardianRecovery();

        GuardianRecoveryState memory state = harness.getGuardianRecoveryState();
        assertEq(state.pendingInit.pendingRecoveryAddress, address(0), "Pending address not cleared");
        assertEq(state.pendingInit.pendingTimelockDurationSeconds, 0, "Pending timelock not cleared");
        assertEq(state.pendingInit.pendingTimestamp, 0, "Pending timestamp not cleared");
    }

    function test_cancelInitializeGuardianRecovery_emitsEvent() public {
        harness.resetRecoveryStorage();

        harness.initiateInitializeGuardianRecovery({
            guardianRecoveryAddress: GUARDIAN_RECOVERY_ADDRESS,
            guardianRecoveryTimelockDurationSeconds: TIMELOCK_DURATION
        });

        vm.expectEmit(true, true, true, true);
        emit IOrganizationGuardianRecovery.GuardianRecoveryInitializationCancelled();

        harness.cancelInitializeGuardianRecovery();
    }

    function test_cancelInitializeGuardianRecovery_revertsIfNoPending() public {
        vm.expectRevert(IOrganizationGuardianRecovery.NoGuardianRecoveryInitializationPending.selector);
        harness.cancelInitializeGuardianRecovery();
    }

    function test_deferredInitializeGuardianRecovery_allowsRecoveryFlowAfterSetup() public {
        harness.resetRecoveryStorage();
        harness.resetGuardianStorage();

        // Initialize guardian (required for the recovery flow)
        harness.initializeGuardian(GUARDIAN);

        // Initiate deferred initialization
        harness.initiateInitializeGuardianRecovery({
            guardianRecoveryAddress: GUARDIAN_RECOVERY_ADDRESS,
            guardianRecoveryTimelockDurationSeconds: TIMELOCK_DURATION
        });

        // Wait for admin operation timelock and finalize
        vm.warp(block.timestamp + ADMIN_OPERATION_TIMELOCK_DURATION);
        harness.finalizeInitializeGuardianRecovery();

        // Now use the recovery flow
        harness.initiateRecoveryGuardianUpdate(NEW_GUARDIAN);
        vm.warp(block.timestamp + TIMELOCK_DURATION);
        harness.finalizeRecoveryGuardianUpdate();

        vm.prank(NEW_GUARDIAN);
        harness.acceptGuardianRecovery();

        assertEq(harness.getGuardian(), NEW_GUARDIAN, "Guardian not updated via recovery");
    }
}
