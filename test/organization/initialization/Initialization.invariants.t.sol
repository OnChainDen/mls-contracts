// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";

import {IOrganization} from "interfaces/IOrganization.sol";
import {OrganizationFactoryInitializationHarness} from "test/organization/initialization/InitializationHarnesses.sol";
import {
    InitializationInvariantHandler
} from "test/organization/initialization/InitializationInvariantHandler.sol";
import {GuardianRecoveryState, TxRecoveryState} from "types/RecoveryTypes.sol";

/**
 * @dev Invariant checks for initialization atomicity, permanence, and cross-module consistency.
 */
contract InitializationInvariantsTest is Test {
    InitializationInvariantHandler internal handler;

    /// @dev Deploys the invariant handler, seeds baseline action coverage, and sets it as the fuzz target.
    function setUp() public {
        handler = new InitializationInvariantHandler();

        // Seed baseline states so each invariant has data even if the fuzzer doesn't hit every action.
        handler.deployFactoryOrganization(bytes32(uint256(1)), 11);
        handler.deployDirectProxyAndInitialize(12);
        handler.attemptFailedFactoryDeployment(bytes32(uint256(2)), 13);
        handler.attemptFailedDirectInitialization(14);
        handler.attemptReinitializeExisting(0, 15);

        targetContract(address(handler));
    }

    /// @dev Verifies INIT-INV-1: `isInitialized()` only transitions false -> true and never back.
    function invariant_INIT_INV_1_isInitialized_canOnlyTransitionFalseToTrue() public view {
        assertFalse(handler.reinitializeSucceeded(), "reinitialize unexpectedly succeeded");

        uint256 successfulLength = handler.deploymentRecordsLength();
        for (uint256 i = 0; i < successfulLength; ++i) {
            InitializationInvariantHandler.DeploymentRecord memory record = handler.deploymentRecordAt(i);
            assertTrue(
                IOrganization(record.organization).isInitialized(),
                "successful deployment must remain initialized"
            );
        }

        uint256 failedDirectLength = handler.failedDirectInitRecordsLength();
        for (uint256 i = 0; i < failedDirectLength; ++i) {
            InitializationInvariantHandler.FailedDirectInitRecord memory record =
                handler.failedDirectInitRecordAt(i);
            assertFalse(
                IOrganization(record.proxy).isInitialized(),
                "failed direct initialize must remain uninitialized"
            );
        }
    }

    /// @dev Verifies INIT-INV-2: initialized organizations keep admin/member consistency invariants.
    function invariant_INIT_INV_2_initializedAdminMemberConsistency_holds() public view {
        uint256 length = handler.deploymentRecordsLength();
        for (uint256 i = 0; i < length; ++i) {
            InitializationInvariantHandler.DeploymentRecord memory record = handler.deploymentRecordAt(i);
            IOrganization organization = IOrganization(record.organization);

            assertTrue(organization.isInitialized(), "recorded organization should be initialized");
            assertTrue(organization.isAdmin(record.adminA), "admin A should be set");
            assertTrue(organization.isAdmin(record.adminB), "admin B should be set");
            assertTrue(organization.isMember(record.adminA), "admin A must remain member");
            assertTrue(organization.isMember(record.adminB), "admin B must remain member");
            assertGt(organization.adminCount(), 0, "initialized org must keep at least one admin");
            assertGe(
                organization.adminCount(),
                organization.votingThreshold(),
                "adminCount must remain >= votingThreshold"
            );
            assertEq(
                organization.votingThreshold(),
                record.votingThreshold,
                "threshold should remain the initialized value"
            );
        }
    }

    /// @dev Verifies INIT-INV-3: successful factory deployments always match CREATE2 precompute.
    function invariant_INIT_INV_3_factoryDeployments_alwaysMatchComputedAddress() public view {
        OrganizationFactoryInitializationHarness factory =
            OrganizationFactoryInitializationHarness(handler.factoryAddress());
        address implementation = handler.implementationAddress();
        address whitelist = handler.whitelistAddress();

        uint256 length = handler.deploymentRecordsLength();
        for (uint256 i = 0; i < length; ++i) {
            InitializationInvariantHandler.DeploymentRecord memory record = handler.deploymentRecordAt(i);
            if (!record.viaFactory) {
                continue;
            }

            address computed = factory.computeOrganizationAddress(record.salt, implementation, whitelist);
            assertEq(computed, record.organization, "factory deployment must match computed address");
        }
    }

    /// @dev Verifies INIT-INV-4: reverting direct initialization leaves no partial persisted init state.
    function invariant_INIT_INV_4_failedDirectInitialization_leavesNoPartialState() public view {
        assertFalse(handler.unexpectedFailedDirectInitSuccess(), "invalid direct initialize unexpectedly succeeded");

        uint256 length = handler.failedDirectInitRecordsLength();
        for (uint256 i = 0; i < length; ++i) {
            InitializationInvariantHandler.FailedDirectInitRecord memory record =
                handler.failedDirectInitRecordAt(i);
            IOrganization organization = IOrganization(record.proxy);

            assertFalse(organization.isInitialized(), "failed initialize must keep uninitialized sentinel");
            assertEq(organization.adminCount(), 0, "adminCount should roll back to zero");
            assertEq(organization.votingThreshold(), 0, "voting threshold should roll back to zero");
            assertEq(organization.guardian(), address(0), "guardian should roll back to zero");

            assertFalse(organization.isMember(record.memberA), "member A write should roll back");
            assertFalse(organization.isMember(record.memberB), "member B write should roll back");
            assertFalse(organization.isAdmin(record.adminA), "admin A write should roll back");
            assertFalse(organization.isAdmin(record.adminB), "admin B write should roll back");
            assertFalse(organization.isGroup(record.groupId), "group create should roll back");

            TxRecoveryState memory txRecovery = organization.getTxRecoveryState();
            assertEq(txRecovery.recoveryAddress, address(0), "tx recovery address should roll back");
            assertEq(txRecovery.timelockDurationSeconds, 0, "tx recovery timelock should roll back");
            assertFalse(txRecovery.isEnabled, "tx recovery should remain disabled");

            GuardianRecoveryState memory guardianRecovery = organization.getGuardianRecoveryState();
            assertEq(guardianRecovery.recoveryAddress, address(0), "guardian recovery address should roll back");
            assertEq(
                guardianRecovery.timelockDurationSeconds,
                0,
                "guardian recovery timelock should roll back"
            );
        }
    }

    /// @dev Verifies INIT-INV-5: deployer written by proxy constructor stays immutable.
    function invariant_INIT_INV_5_proxyDeployerAddress_remainsImmutable() public view {
        uint256 successfulLength = handler.deploymentRecordsLength();
        for (uint256 i = 0; i < successfulLength; ++i) {
            InitializationInvariantHandler.DeploymentRecord memory record = handler.deploymentRecordAt(i);
            assertEq(
                IOrganization(record.organization).getDeployerAddress(),
                record.expectedDeployer,
                "successful proxy deployer changed unexpectedly"
            );
        }

        uint256 failedDirectLength = handler.failedDirectInitRecordsLength();
        for (uint256 i = 0; i < failedDirectLength; ++i) {
            InitializationInvariantHandler.FailedDirectInitRecord memory record =
                handler.failedDirectInitRecordAt(i);
            assertEq(
                IOrganization(record.proxy).getDeployerAddress(),
                record.expectedDeployer,
                "failed direct proxy deployer changed unexpectedly"
            );
        }
    }

    /// @dev Verifies INIT-INV-6: tx recovery is never initialized as enabled.
    function invariant_INIT_INV_6_txRecoveryDefaultSafety_startsDisabled() public view {
        uint256 length = handler.deploymentRecordsLength();
        for (uint256 i = 0; i < length; ++i) {
            InitializationInvariantHandler.DeploymentRecord memory record = handler.deploymentRecordAt(i);
            TxRecoveryState memory txRecovery = IOrganization(record.organization).getTxRecoveryState();
            assertFalse(txRecovery.isEnabled, "tx recovery must remain disabled after initialization");
        }
    }

    /// @dev Verifies INIT-INV-7: active group members are always organization members.
    function invariant_INIT_INV_7_groupMembers_areOrganizationMembers() public view {
        uint256 length = handler.deploymentRecordsLength();
        for (uint256 i = 0; i < length; ++i) {
            InitializationInvariantHandler.DeploymentRecord memory record = handler.deploymentRecordAt(i);
            IOrganization organization = IOrganization(record.organization);

            assertTrue(organization.isGroup(record.groupId), "tracked group should remain active");
            assertTrue(
                organization.isGroupMember(record.groupId, record.groupMemberA),
                "tracked group member A should remain in group"
            );
            assertTrue(
                organization.isGroupMember(record.groupId, record.groupMemberB),
                "tracked group member B should remain in group"
            );
            assertTrue(
                organization.isMember(record.groupMemberA),
                "tracked group member A must remain organization member"
            );
            assertTrue(
                organization.isMember(record.groupMemberB),
                "tracked group member B must remain organization member"
            );
        }
    }

    /// @dev Verifies INIT-INV-8: failed factory deployment during init revert leaves no deployed proxy code.
    function invariant_INIT_INV_8_failedFactoryInitialization_keepsComputedAddressEmpty() public view {
        assertFalse(handler.unexpectedFailedFactorySuccess(), "invalid factory deployment unexpectedly succeeded");
        assertFalse(handler.failedFactoryRevertLeftCode(), "failed factory initialize left deployed code");
    }
}
