// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IAccount} from "interfaces/IAccount.sol";
import {
    LibOrganizationAccountFactoryInvariantHandler
} from "test/organization/libraries/LibOrganizationAccountFactory/LibOrganizationAccountFactoryInvariantHandler.sol";
import {
    LibOrganizationAccountFactorySuiteBase
} from "test/organization/libraries/LibOrganizationAccountFactory/LibOrganizationAccountFactorySuiteBase.sol";

/**
 * @dev Invariant tests for account-factory deployment tracking and whitelist enforcement.
 */
contract LibOrganizationAccountFactoryInvariants is LibOrganizationAccountFactorySuiteBase {
    LibOrganizationAccountFactoryInvariantHandler internal handler;

    /**
     * @dev Initializes invariant handler and stable fixture prerequisites.
     */
    function setUp() public override {
        super.setUp();

        // Setup: seed valid implementation so deployment attempts can succeed.
        harness.setAccountImplementationStorage(accountImplementationV1);

        handler = new LibOrganizationAccountFactoryInvariantHandler({
            harness_: harness,
            whitelist_: whitelist,
            implementationA_: accountImplementationV1,
            implementationB_: accountImplementationV2
        });

        // Setup: route invariant fuzz calls to the account-factory handler.
        targetContract(address(handler));
    }

    /// @dev Verifies invariant: every successful deploy marks `deployedAccounts[addr] = true`.
    function invariant_AF_IT_1_everySuccessfulDeploy_setsDeploymentTrackingTrue() public view {
        // Setup: read tracked successful deployment count from invariant handler.
        uint256 length = handler.trackedDeployedAccountsLength();
        // Call: iterate tracked deployments and query current deployment status.
        for (uint256 i = 0; i < length; ++i) {
            address deployedAccount = handler.trackedDeployedAccountAt(i);
            // Verify: each tracked deployment remains marked as organization-deployed.
            assertTrue(
                harness.isAccountDeployedByOrganizationViaLibrary(deployedAccount),
                "tracked deployed account must remain marked true"
            );
        }
    }

    /// @dev Verifies invariant: deployed account beacon binding (organization address) never changes.
    function invariant_AF_IT_2_deployedAccount_beaconBindingRemainsOrganization() public view {
        // Setup: read tracked successful deployment count from invariant handler.
        uint256 length = handler.trackedDeployedAccountsLength();
        // Call: iterate tracked deployed accounts and read organization binding through proxy.
        for (uint256 i = 0; i < length; ++i) {
            address deployedAccount = handler.trackedDeployedAccountAt(i);
            address organization = IAccount(payable(deployedAccount)).getOrganizationAddress();
            // Verify: account beacon binding remains fixed to deploying organization.
            assertEq(organization, address(harness), "deployed account beacon binding should remain organization");
        }
    }

    /// @dev Verifies invariant: implementation updates cannot succeed unless target implementation is whitelisted.
    function invariant_AF_IT_3_whitelistEnforcement_noSuccessfulUnwhitelistedImplementationUpdate() public view {
        // Setup: read handler flag tracking unauthorized successful implementation updates.
        // Call: evaluate whether an un-whitelisted update ever succeeded during fuzzing.
        // Verify: un-whitelisted implementation updates should never succeed.
        assertFalse(
            handler.successfulSetWithoutWhitelist(), "implementation update succeeded while implementation unwhitelisted"
        );
    }

    /// @dev Verifies invariant: computed address always matches tracked deployment address for each successful salt.
    function invariant_AF_IT_4_computeAccountAddress_matchesTrackedDeploymentAddressForSuccessfulSalts() public view {
        // Setup: read tracked successful deployment count from invariant handler.
        uint256 length = handler.trackedDeployedAccountsLength();
        // Call: recompute CREATE2 destination for each tracked salt.
        for (uint256 i = 0; i < length; ++i) {
            bytes32 salt = handler.trackedDeployedSaltAt(i);
            address trackedDeployed = handler.trackedDeployedAccountAt(i);
            address computed = harness.computeAccountAddressViaLibrary(salt);
            // Verify: recomputed address always equals tracked deployed address.
            assertEq(computed, trackedDeployed, "computed address should match tracked deployed address");
        }
    }

    /// @dev Verifies invariant: `deployedAccounts` mapping is monotonic and never flips true back to false.
    function invariant_AF_IT_5_deployedAccountsMapping_monotonicTrueState() public view {
        // Setup: read count of addresses previously observed with `deployedAccounts == true`.
        uint256 length = handler.trackedObservedTrueAccountsLength();
        // Call: iterate each observed-true account and re-read deployment status.
        for (uint256 i = 0; i < length; ++i) {
            address observedTrueAccount = handler.trackedObservedTrueAccountAt(i);
            // Verify: once observed true, deployment tracking never flips back to false.
            assertTrue(
                harness.isAccountDeployedByOrganizationViaLibrary(observedTrueAccount),
                "observed true deployment flag must remain true"
            );
        }
    }
}
