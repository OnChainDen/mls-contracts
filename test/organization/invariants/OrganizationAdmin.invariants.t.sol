// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {LibOrganizationAdminHarness} from "test/organization/harness/LibOrganizationAdminHarness.sol";
import {OrganizationAdminInvariantHandler} from "test/organization/harness/OrganizationAdminInvariantHandler.sol";
import {OrganizationAdminStateHarness} from "test/organization/harness/OrganizationAdminStateHarness.sol";
import {OrganizationAdminTestBase} from "test/organization/helpers/OrganizationAdminTestBase.sol";

/**
 * @dev Stateful invariant tests for organization admin behavior.
 */
contract OrganizationAdminInvariants is OrganizationAdminTestBase {
    /// @dev Concrete harness under invariant test.
    LibOrganizationAdminHarness internal harness;

    /// @dev Stateful mutation handler.
    OrganizationAdminInvariantHandler internal handler;

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
            new OrganizationAdminInvariantHandler(harness, ADMIN_PK_1, ADMIN_PK_2, address(0xE301), address(0xE302));

        // Register only the handler as the stateful fuzz target.
        targetContract(address(handler));
    }

    /**
     * @dev adminCount is always at least 1.
     */
    function invariant_adminCountIsAlwaysAtLeastOne() public view {
        // Library code should never allow mutations that leave zero admins.
        assertGe(harness.adminCount(), 1, "adminCount must never be zero");
    }

    /**
     * @dev votingThreshold always stays within [1, adminCount].
     */
    function invariant_votingThresholdWithinBounds() public view {
        uint256 adminCount = harness.adminCount();
        uint256 threshold = harness.votingThreshold();

        // Threshold bounds are validated in every successful mutation path.
        assertGe(threshold, 1, "threshold must be >= 1");
        assertLe(threshold, adminCount, "threshold must be <= adminCount");
    }

    /**
     * @dev For tracked addresses, admin implies member.
     */
    function invariant_adminImpliesMemberForTrackedAddresses() public view {
        uint256 count = handler.trackedAddressCount();
        for (uint256 i = 0; i < count; i++) {
            address tracked = handler.trackedAddressAt(i);
            if (harness.isAdmin(tracked)) {
                // Any admin in the tracked set must remain a member.
                assertTrue(harness.getMemberStatus(tracked), "admin address must always be a member");
            }
        }
    }

    /**
     * @dev Once a tracked nonce is used, it never flips back to false.
     */
    function invariant_usedNonceMonotonicity() public view {
        uint256 nonceCount = handler.trackedUsedNonceCount();
        for (uint256 i = 0; i < nonceCount; i++) {
            uint256 nonce = handler.trackedUsedNonceAt(i);
            // Nonces tracked as used should stay true in both model and contract storage.
            assertTrue(harness.getUsedNonce(nonce), "used nonce must remain true once consumed");
            assertTrue(handler.modelNonceUsed(nonce), "model used nonce must remain true once consumed");
        }
    }

    /**
     * @dev Modeled admin-set cardinality matches on-chain `adminCount`.
     */
    function invariant_modelCardinalityMatchesOnchainAdminCount() public view {
        uint256 count = handler.trackedAddressCount();
        uint256 trackedCardinality = 0;

        for (uint256 i = 0; i < count; i++) {
            address tracked = handler.trackedAddressAt(i);
            // Reconstruct cardinality from the same tracked address universe as the model.
            if (harness.isAdmin(tracked)) {
                trackedCardinality++;
            }
        }

        assertEq(trackedCardinality, harness.adminCount(), "tracked cardinality must equal on-chain adminCount");
        assertEq(trackedCardinality, handler.modelAdminCount(), "tracked cardinality must equal model admin count");
    }
}
