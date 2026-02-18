// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {
    LibOrganizationMembersHarness
} from "test/organization/libraries/LibOrganizationMembers/LibOrganizationMembersHarness.sol";
import {
    LibOrganizationMembersInvariantHandler
} from "test/organization/libraries/LibOrganizationMembers/LibOrganizationMembersInvariantHandler.sol";
import {OrganizationAdminStateHarness} from "test/organization/shared/OrganizationAdminStateHarness.sol";
import {OrganizationAdminTestBase} from "test/organization/shared/OrganizationAdminTestBase.sol";

/**
 * @dev Stateful invariant tests for `LibOrganizationMembers` behavior.
 */
contract LibOrganizationMembersInvariants is OrganizationAdminTestBase {
    /// @dev Concrete harness under invariant test.
    LibOrganizationMembersHarness internal harness;

    /// @dev Stateful mutation handler.
    LibOrganizationMembersInvariantHandler internal handler;

    /**
     * @dev Deploys the library-focused harness for this suite.
     */
    function _deployHarness() internal override returns (OrganizationAdminStateHarness) {
        harness = new LibOrganizationMembersHarness();
        return OrganizationAdminStateHarness(address(harness));
    }

    /**
     * @dev Deploys handler and registers it as fuzz target.
     */
    function setUp() public override {
        super.setUp();

        // Handler mutates the same harness instance so invariant checks observe real state transitions.
        handler = new LibOrganizationMembersInvariantHandler(harness, admin1, admin2, address(0xE501), address(0xE502));

        // Register only the handler as the stateful fuzz target.
        targetContract(address(handler));
    }

    /**
     * @dev Verifies that every tracked admin is always also a member.
     */
    function invariant_adminMustAlwaysBeMember() public view {
        uint256 count = handler.trackedAddressCount();
        for (uint256 i = 0; i < count; i++) {
            address tracked = handler.trackedAddressAt(i);
            // Call: read admin/member status for each tracked address.
            if (harness.isAdmin(tracked)) {
                // Verify: admin-membership implication must hold.
                assertTrue(harness.isMember(tracked), "admin address must always be a member");
            }
        }
    }

    /**
     * @dev Verifies that zero address membership is always false.
     */
    function invariant_zeroAddressIsNeverMember() public view {
        // Call: read member status for zero address.
        bool actualIsMember = harness.isMember(address(0));
        // Verify: zero address should never become a member.
        assertFalse(actualIsMember, "zero address should never be a member");
    }

    /**
     * @dev Verifies that idempotent add-existing probes never revert and never change state.
     */
    function invariant_idempotentAddExistingNeverRevertsOrChangesState() public view {
        // Call: read violation flag tracked by handler probe operations.
        bool sawViolation = handler.addExistingViolation();
        // Verify: add-existing behavior should remain idempotent across all stateful sequences.
        assertFalse(sawViolation, "adding an existing member should be non-reverting and state-preserving");
    }

    /**
     * @dev Verifies that idempotent remove-non-member probes never revert and never change state.
     */
    function invariant_idempotentRemoveNonMemberNeverRevertsOrChangesState() public view {
        // Call: read violation flag tracked by handler probe operations.
        bool sawViolation = handler.removeNonMemberViolation();
        // Verify: remove-non-member behavior should remain idempotent across all stateful sequences.
        assertFalse(sawViolation, "removing a non-member should be non-reverting and state-preserving");
    }
}
