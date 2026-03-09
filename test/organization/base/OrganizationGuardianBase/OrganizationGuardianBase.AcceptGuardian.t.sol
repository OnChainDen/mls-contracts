// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationGuardian} from "interfaces/organization/IOrganizationGuardian.sol";
import {
    OrganizationGuardianBaseSuiteBase
} from "test/organization/base/OrganizationGuardianBase/OrganizationGuardianBaseSuiteBase.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";

/**
 * @dev Unit tests for `OrganizationGuardianBase.acceptGuardian`.
 */
contract OrganizationGuardianBaseAcceptGuardianTest is OrganizationGuardianBaseSuiteBase {
    /// @dev Verifies `OrganizationGuardianBase.acceptGuardian` only allows the pending guardian to accept a finalized
    /// guardian update. [OGU-GU-6]
    function test_OGB_AG_1__OGU_GU_6_nonPendingGuardianCaller_revertsOnlyPendingGuardian() public {
        // Setup
        guardianStateHarness.setPendingGuardian(NEW_GUARDIAN_A);
        guardianStateHarness.setPendingGuardianUpdateTimestamp(block.timestamp);
        guardianStateHarness.setIsGuardianUpdateReadyForAcceptance(true);

        // Call
        _expectOnlyPendingGuardianRevert(NON_GUARDIAN, NEW_GUARDIAN_A);
        vm.prank(NON_GUARDIAN);
        harness.acceptGuardian();

        // Verify
        assertEq(harness.guardian(), GUARDIAN, "guardian should remain unchanged");
    }

    /// @dev Verifies OGB-AG-2: pending guardian caller delegates to library and completes acceptance.
    function test_OGB_AG_2_pendingGuardianCaller_delegatesAndAccepts() public {
        // Setup
        guardianStateHarness.setPendingGuardian(NEW_GUARDIAN_A);
        guardianStateHarness.setPendingGuardianUpdateTimestamp(block.timestamp);
        guardianStateHarness.setIsGuardianUpdateReadyForAcceptance(true);

        // Call
        vm.prank(NEW_GUARDIAN_A);
        harness.acceptGuardian();

        // Verify
        assertEq(harness.guardian(), NEW_GUARDIAN_A, "guardian should update to pending guardian");
        assertEq(harness.pendingGuardian(), address(0), "pending guardian should clear");
        assertEq(harness.pendingGuardianUpdateTimestamp(), 0, "pending timestamp should clear");
        assertFalse(harness.isGuardianUpdateReadyForAcceptance(), "ready flag should clear");
    }

    /// @dev Verifies OGB-AG-3: pending guardian caller before finalize reverts `GuardianUpdateNotReadyForAcceptance`.
    function test_OGB_AG_3_pendingGuardianBeforeFinalize_revertsGuardianUpdateNotReadyForAcceptance() public {
        // Setup
        guardianStateHarness.setPendingGuardian(NEW_GUARDIAN_A);
        guardianStateHarness.setPendingGuardianUpdateTimestamp(block.timestamp);
        guardianStateHarness.setIsGuardianUpdateReadyForAcceptance(false);

        // Call
        vm.expectRevert(IOrganizationGuardian.GuardianUpdateNotReadyForAcceptance.selector);
        vm.prank(NEW_GUARDIAN_A);
        harness.acceptGuardian();

        // Verify
        assertEq(harness.guardian(), GUARDIAN, "guardian should remain unchanged");
    }

    /// @dev Verifies OGB-AG-4: second accept call reverts and state does not mutate after successful acceptance.
    function test_OGB_AG_4_secondAcceptCall_revertsAndDoesNotMutateState() public {
        // Setup
        guardianStateHarness.setPendingGuardian(NEW_GUARDIAN_A);
        guardianStateHarness.setPendingGuardianUpdateTimestamp(block.timestamp);
        guardianStateHarness.setIsGuardianUpdateReadyForAcceptance(true);

        // Call
        vm.prank(NEW_GUARDIAN_A);
        harness.acceptGuardian();

        // Verify
        assertEq(harness.guardian(), NEW_GUARDIAN_A, "guardian should have transitioned");

        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationGuardian.UnauthorizedGuardianAcceptance.selector, NEW_GUARDIAN_A, address(0)
            )
        );
        vm.prank(NEW_GUARDIAN_A);
        harness.acceptGuardian();

        assertEq(harness.guardian(), NEW_GUARDIAN_A, "guardian should remain unchanged after second call");
        assertEq(harness.pendingGuardian(), address(0), "pending guardian should remain cleared");
        assertEq(harness.pendingGuardianUpdateTimestamp(), 0, "pending timestamp should remain cleared");
        assertFalse(harness.isGuardianUpdateReadyForAcceptance(), "ready flag should remain false");
    }

    /// @dev Verifies the normal guardian-update lifecycle succeeds end to end with guardian execution, admin auth,
    /// timelock expiry, and pending-guardian acceptance. [OGU-GU-1]
    function test_OGU_GU_1_normalGuardianUpdateFlow_initiateTimelockFinalizeAccept_succeedsWithGuardianAndAdminAuth()
        public
    {
        // Setup: configure one-admin authorization and stage a fresh normal guardian update toward
        // `NEW_GUARDIAN_A`.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
        (AdminAuthParams memory initiateAuth,) = _buildInitiateGuardianUpdateAuth({
            newGuardian: NEW_GUARDIAN_A,
            salt: 4_101,
            expiration: type(uint256).max,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        vm.prank(GUARDIAN);
        harness.initiateGuardianUpdate(NEW_GUARDIAN_A, initiateAuth);

        // Call: wait through the admin timelock, finalize as the current guardian, then accept as the pending
        // guardian.
        vm.warp(block.timestamp + ADMIN_OPERATION_TIMELOCK);
        (AdminAuthParams memory finalizeAuth,) = _buildFinalizeGuardianUpdateAuth({
            pendingGuardian: NEW_GUARDIAN_A,
            salt: 4_102,
            expiration: type(uint256).max,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        vm.prank(GUARDIAN);
        harness.finalizeGuardianUpdate(finalizeAuth);

        vm.prank(NEW_GUARDIAN_A);
        harness.acceptGuardian();

        // Verify: guardian ownership rotates to the pending guardian and all transitional state is cleared.
        assertEq(harness.guardian(), NEW_GUARDIAN_A, "guardian should rotate to the accepted pending guardian");
        assertEq(harness.pendingGuardian(), address(0), "pending guardian should clear after accept");
        assertEq(harness.pendingGuardianUpdateTimestamp(), 0, "pending timestamp should clear after accept");
        assertFalse(harness.isGuardianUpdateReadyForAcceptance(), "ready flag should clear after accept");
    }
}
