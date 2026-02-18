// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {
    LibOrganizationAdminHarness
} from "test/organization/libraries/LibOrganizationAdmin/LibOrganizationAdminHarness.sol";
import {
    LibOrganizationAdminInvariantHandler
} from "test/organization/libraries/LibOrganizationAdmin/LibOrganizationAdminInvariantHandler.sol";
import {OrganizationAdminStateHarness} from "test/organization/shared/OrganizationAdminStateHarness.sol";
import {OrganizationAdminTestBase} from "test/organization/shared/OrganizationAdminTestBase.sol";

/**
 * @dev Stateful invariant tests for `LibOrganizationAdmin` behavior.
 */
contract LibOrganizationAdminInvariants is OrganizationAdminTestBase {
    /// @dev Concrete harness under invariant test.
    LibOrganizationAdminHarness internal harness;

    /// @dev Stateful mutation handler.
    LibOrganizationAdminInvariantHandler internal handler;

    /**
     * @dev Deploys the library-focused harness for this suite.
     */
    function _deployHarness() internal override returns (OrganizationAdminStateHarness) {
        harness = new LibOrganizationAdminHarness();
        return OrganizationAdminStateHarness(address(harness));
    }

    /**
     * @dev Deploys handler and registers it as fuzz target.
     */
    function setUp() public override {
        super.setUp();

        // Handler mutates the same harness instance so invariant checks observe real state transitions.
        handler =
            new LibOrganizationAdminInvariantHandler(harness, ADMIN_PK_1, ADMIN_PK_2, address(0xE301), address(0xE302));

        // Register only the handler as the stateful fuzz target.
        targetContract(address(handler));
    }

    /**
     * @dev Verifies that `adminCount` is always at least one.
     */
    function invariant_adminCountIsAlwaysAtLeastOne() public view {
        // Setup: no special preconditions; assert against whatever state fuzzing reached.
        // Call: read current admin count from the harness under invariant testing.
        // Library code should never allow mutations that leave zero admins.
        // Verify: assert the postconditions for this scenario.
        assertGe(harness.adminCount(), 1, "adminCount must never be zero");
    }

    /**
     * @dev Verifies that `votingThreshold` always stays within [1, adminCount].
     */
    function invariant_votingThresholdWithinBounds() public view {
        // Setup: prepare local snapshots of the current on-chain admin state.
        // Call: read on-chain admin count and voting threshold snapshots.
        uint256 adminCount = harness.adminCount();
        uint256 threshold = harness.votingThreshold();

        // Threshold bounds are validated in every successful mutation path.
        // Verify: assert the postconditions for this scenario.
        assertGe(threshold, 1, "threshold must be >= 1");
        // Verify: assert the postconditions for this scenario.
        assertLe(threshold, adminCount, "threshold must be <= adminCount");
    }

    /**
     * @dev Verifies that admin status implies member status for all tracked addresses.
     */
    function invariant_adminImpliesMemberForTrackedAddresses() public view {
        // Setup: iterate over the tracked-address universe from the handler model.
        uint256 count = handler.trackedAddressCount();
        for (uint256 i = 0; i < count; i++) {
            address tracked = handler.trackedAddressAt(i);
            // Call: read admin/member status for each tracked address.
            if (harness.isAdmin(tracked)) {
                // Any admin in the tracked set must remain a member.
                // Verify: assert the postconditions for this scenario.
                assertTrue(harness.getMemberStatus(tracked), "admin address must always be a member");
            }
        }
    }

    /**
     * @dev Verifies that once a tracked nonce is consumed, it never reverts to unused.
     */
    function invariant_usedNonceMonotonicity() public view {
        // Setup: iterate through all nonces the handler model has marked as touched.
        uint256 nonceCount = handler.trackedUsedNonceCount();
        for (uint256 i = 0; i < nonceCount; i++) {
            uint256 nonce = handler.trackedUsedNonceAt(i);
            // Call: read nonce flags from on-chain storage and handler model.
            // Nonces tracked as used should stay true in both model and contract storage.
            // Verify: assert the postconditions for this scenario.
            assertTrue(harness.getUsedNonce(nonce), "used nonce must remain true once consumed");
            // Verify: assert the postconditions for this scenario.
            assertTrue(handler.modelNonceUsed(nonce), "model used nonce must remain true once consumed");
        }
    }

    /**
     * @dev Verifies that the modeled admin-set cardinality matches on-chain `adminCount`.
     */
    function invariant_modelCardinalityMatchesOnchainAdminCount() public view {
        // Setup: reconstruct cardinality over the model's tracked address universe.
        uint256 count = handler.trackedAddressCount();
        uint256 actualTrackedCardinality = 0;

        for (uint256 i = 0; i < count; i++) {
            address tracked = handler.trackedAddressAt(i);
            // Reconstruct cardinality from the same tracked address universe as the model.
            if (harness.isAdmin(tracked)) {
                actualTrackedCardinality++;
            }
        }

        uint256 expectOnchainAdminCount = harness.adminCount();
        uint256 expectModelAdminCount = handler.modelAdminCount();

        // Call: use the reconstructed cardinality and both model/on-chain counts for comparison.
        // Verify: assert the postconditions for this scenario.

        assertEq(
            actualTrackedCardinality, expectOnchainAdminCount, "tracked cardinality must equal on-chain adminCount"
        );
        // Verify: assert the postconditions for this scenario.
        assertEq(actualTrackedCardinality, expectModelAdminCount, "tracked cardinality must equal model admin count");
    }
}
