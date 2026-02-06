// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {SlotDerivation} from "@openzeppelin/contracts/utils/SlotDerivation.sol";
import {Test} from "forge-std/Test.sol";

import {IOrganizationGuardian} from "interfaces/organization/IOrganizationGuardian.sol";
import {IOrganizationGuardianRecovery} from "interfaces/organization/IOrganizationGuardianRecovery.sol";
import {LibOrganizationGuardian} from "organization/libraries/LibOrganizationGuardian.sol";
import {LibOrganizationGuardianRecovery} from "organization/libraries/LibOrganizationGuardianRecovery.sol";
import {LibOrganizationGuardianStorage} from "organization/libraries/storage/LibOrganizationGuardianStorage.sol";
import {LibOrganizationRecoveryStorage} from "organization/libraries/storage/LibOrganizationRecoveryStorage.sol";
import {
    LibOrganizationSecureTimelockStorage
} from "organization/libraries/storage/LibOrganizationSecureTimelockStorage.sol";

/**
 * @title Guardian Recovery Test Harness
 * @notice Wraps library functions for testing with proper msg.sender handling
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

    function getGuardianRecoveryAddress() external view returns (address) {
        return LibOrganizationGuardianRecovery.getGuardianRecoveryAddress();
    }

    function getGuardianRecoveryTimelockDurationSeconds() external view returns (uint256) {
        return LibOrganizationGuardianRecovery.getGuardianRecoveryTimelockDurationSeconds();
    }

    function getSecureTimelockDurationSeconds() external view returns (uint256) {
        return LibOrganizationSecureTimelockStorage.layout().secureTimelockDurationSeconds;
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

    // Pending initialization state
    function getPendingInitGuardianRecoveryAddress() external view returns (address) {
        return LibOrganizationGuardianRecovery.getPendingInitGuardianRecoveryAddress();
    }

    function getPendingInitGuardianRecoveryTimelockDurationSeconds() external view returns (uint256) {
        return LibOrganizationGuardianRecovery.getPendingInitGuardianRecoveryTimelockDurationSeconds();
    }

    function getPendingInitGuardianRecoveryTimestamp() external view returns (uint256) {
        return LibOrganizationGuardianRecovery.getPendingInitGuardianRecoveryTimestamp();
    }

    // ================================
    // Storage Direct Access (for reset/setup in tests)
    // ================================

    function setGuardian(address _guardian) external {
        LibOrganizationGuardianStorage.layout().guardian = _guardian;
    }

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
        layout.txRecovery.pendingInitRecoveryAddress = address(0);
        layout.txRecovery.pendingInitTimelockDurationSeconds = 0;
        layout.txRecovery.pendingInitTimestamp = 0;

        // Reset guardian recovery state
        layout.guardianRecovery.recoveryAddress = address(0);
        layout.guardianRecovery.timelockDurationSeconds = 0;
        layout.guardianRecovery.pendingGuardian = address(0);
        layout.guardianRecovery.pendingGuardianTimestamp = 0;
        layout.guardianRecovery.isUpdateReadyForAcceptance = false;
        layout.guardianRecovery.pendingInitRecoveryAddress = address(0);
        layout.guardianRecovery.pendingInitTimelockDurationSeconds = 0;
        layout.guardianRecovery.pendingInitTimestamp = 0;
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
 * @title Lib Organization Guardian Recovery Test
 * @notice Tests for guardian recovery functionality
 * @dev Tests initialization, timelocked guardian recovery flows, deferred initialization, and access control.
 *      Normal and recovery guardian update flows use SEPARATE storage and are NOT mutually exclusive.
 * @author Den Technologies Inc
 */
contract LibOrganizationGuardianRecoveryTest is Test {
    GuardianRecoveryTestHarness public harness;

    address constant GUARDIAN_RECOVERY_ADDRESS = address(0x200);
    address constant GUARDIAN = address(0x300);
    address constant NEW_GUARDIAN = address(0x400);
    address constant NEW_GUARDIAN_2 = address(0x500);

    uint256 constant TIMELOCK_DURATION = 1 days;
    uint256 constant SECURE_TIMELOCK_DURATION = 3 days;

    function setUp() public {
        harness = new GuardianRecoveryTestHarness();

        // Initialize secure timelock (organization-wide)
        harness.initializeSecureTimelock(SECURE_TIMELOCK_DURATION);

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
        assertEq(harness.getGuardianRecoveryAddress(), GUARDIAN_RECOVERY_ADDRESS, "guardianRecoveryAddress not set");
        assertEq(
            harness.getGuardianRecoveryTimelockDurationSeconds(),
            TIMELOCK_DURATION,
            "guardianRecoveryTimelockDurationSeconds not set"
        );
        assertEq(
            harness.getSecureTimelockDurationSeconds(),
            SECURE_TIMELOCK_DURATION,
            "secureTimelockDurationSeconds not set"
        );
    }

    function test_initializeGuardianRecovery_revertsOnZeroTimelockDurationSeconds() public {
        harness.resetRecoveryStorage();

        vm.expectRevert(IOrganizationGuardianRecovery.InvalidGuardianRecoveryTimelockDurationSeconds.selector);
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

        assertEq(harness.getRecoveryPendingGuardian(), NEW_GUARDIAN, "Recovery pending guardian not set");
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

        assertTrue(harness.getIsRecoveryGuardianUpdateReadyForAcceptance(), "Should be ready for acceptance");
    }

    function test_finalizeRecoveryGuardianUpdate_revertsIfNoPending() public {
        vm.expectRevert(IOrganizationGuardianRecovery.NoPendingRecoveryGuardianUpdate.selector);
        harness.finalizeRecoveryGuardianUpdate();
    }

    function test_finalizeRecoveryGuardianUpdate_revertsIfTimelockNotExpired() public {
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
        harness.initiateRecoveryGuardianUpdate(NEW_GUARDIAN);

        harness.cancelRecoveryGuardianUpdate();

        assertEq(harness.getRecoveryPendingGuardian(), address(0), "Recovery pending guardian not cleared");
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
        assertEq(harness.getRecoveryPendingGuardian(), address(0), "Recovery pending guardian not cleared");
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
        vm.warp(block.timestamp + SECURE_TIMELOCK_DURATION);

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
        vm.warp(block.timestamp + SECURE_TIMELOCK_DURATION);
        harness.finalizeGuardianUpdate();

        vm.prank(NEW_GUARDIAN);
        harness.acceptGuardian();

        assertEq(harness.getGuardian(), NEW_GUARDIAN, "Guardian not updated");
        assertEq(harness.getPendingGuardian(), address(0), "Pending guardian not cleared");
    }

    function test_acceptGuardian_revertsIfNotPendingGuardian() public {
        harness.initiateGuardianUpdate(NEW_GUARDIAN);
        vm.warp(block.timestamp + SECURE_TIMELOCK_DURATION);
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
        assertEq(harness.getRecoveryPendingGuardian(), NEW_GUARDIAN_2, "Recovery flow pending guardian not set");
    }

    function test_recoveryFlowCanCompleteWhileNormalFlowPending() public {
        // Start both flows
        harness.initiateGuardianUpdate(NEW_GUARDIAN);
        harness.initiateRecoveryGuardianUpdate(NEW_GUARDIAN_2);

        // Complete recovery flow
        vm.warp(block.timestamp + SECURE_TIMELOCK_DURATION);
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
        vm.warp(block.timestamp + SECURE_TIMELOCK_DURATION);
        harness.finalizeGuardianUpdate();
        vm.prank(NEW_GUARDIAN);
        harness.acceptGuardian();

        // Guardian should be updated to normal flow's NEW_GUARDIAN
        assertEq(harness.getGuardian(), NEW_GUARDIAN, "Guardian should be updated by normal flow");

        // Recovery flow should still have pending state
        assertEq(harness.getRecoveryPendingGuardian(), NEW_GUARDIAN_2, "Recovery flow pending should still exist");
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
        assertEq(harness.getGuardianRecoveryAddress(), address(0), "Recovery address should be zero");
        assertEq(harness.getGuardianRecoveryTimelockDurationSeconds(), 0, "Timelock should be zero");
    }

    function test_initializeGuardianRecovery_revertsOnZeroTimelockWhenAddressProvided() public {
        harness.resetRecoveryStorage();

        vm.expectRevert(IOrganizationGuardianRecovery.InvalidGuardianRecoveryTimelockDurationSeconds.selector);
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

        assertEq(harness.getPendingInitGuardianRecoveryAddress(), GUARDIAN_RECOVERY_ADDRESS, "Pending address not set");
        assertEq(
            harness.getPendingInitGuardianRecoveryTimelockDurationSeconds(),
            TIMELOCK_DURATION,
            "Pending timelock not set"
        );
        uint256 expectedCanFinalizeAt = block.timestamp + SECURE_TIMELOCK_DURATION;
        assertEq(harness.getPendingInitGuardianRecoveryTimestamp(), expectedCanFinalizeAt, "Pending timestamp not set");
    }

    function test_initiateInitializeGuardianRecovery_emitsEvent() public {
        harness.resetRecoveryStorage();

        uint256 expectedCanFinalizeAt = block.timestamp + SECURE_TIMELOCK_DURATION;

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

        vm.expectRevert(IOrganizationGuardianRecovery.InvalidGuardianRecoveryTimelockDurationSeconds.selector);
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

        vm.warp(block.timestamp + SECURE_TIMELOCK_DURATION);
        harness.finalizeInitializeGuardianRecovery();

        assertEq(harness.getGuardianRecoveryAddress(), GUARDIAN_RECOVERY_ADDRESS, "Recovery address not set");
        assertEq(harness.getGuardianRecoveryTimelockDurationSeconds(), TIMELOCK_DURATION, "Timelock duration not set");

        // Pending state should be cleared
        assertEq(harness.getPendingInitGuardianRecoveryAddress(), address(0), "Pending address not cleared");
        assertEq(harness.getPendingInitGuardianRecoveryTimelockDurationSeconds(), 0, "Pending timelock not cleared");
        assertEq(harness.getPendingInitGuardianRecoveryTimestamp(), 0, "Pending timestamp not cleared");
    }

    function test_finalizeInitializeGuardianRecovery_emitsEvent() public {
        harness.resetRecoveryStorage();

        harness.initiateInitializeGuardianRecovery({
            guardianRecoveryAddress: GUARDIAN_RECOVERY_ADDRESS,
            guardianRecoveryTimelockDurationSeconds: TIMELOCK_DURATION
        });

        vm.warp(block.timestamp + SECURE_TIMELOCK_DURATION);

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

        uint256 canFinalizeAt = harness.getPendingInitGuardianRecoveryTimestamp();

        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationGuardianRecovery.GuardianRecoveryInitializationTimelockNotExpired.selector,
                canFinalizeAt,
                block.timestamp
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

        assertEq(harness.getPendingInitGuardianRecoveryAddress(), address(0), "Pending address not cleared");
        assertEq(harness.getPendingInitGuardianRecoveryTimelockDurationSeconds(), 0, "Pending timelock not cleared");
        assertEq(harness.getPendingInitGuardianRecoveryTimestamp(), 0, "Pending timestamp not cleared");
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

        // Wait for secure timelock and finalize
        vm.warp(block.timestamp + SECURE_TIMELOCK_DURATION);
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
