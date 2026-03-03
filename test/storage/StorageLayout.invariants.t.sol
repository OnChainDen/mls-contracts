// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {StorageLayoutInvariantHandler} from "test/helpers/storage/StorageLayoutHarnesses.sol";
import {StorageLayoutTestBase} from "test/helpers/storage/StorageLayoutTestBase.sol";
import {ContractType} from "types/CommonTypes.sol";
import {GuardianRecoveryState, TxRecoveryState} from "types/RecoveryTypes.sol";

/**
 * @dev Storage Layout Invariant Test
 *      Stateful invariants for slot-collision safety and namespace isolation.
 */
contract StorageLayoutInvariants is StorageLayoutTestBase {
    /// @dev Stateful handler with one-namespace-at-a-time mutators.
    StorageLayoutInvariantHandler internal handler;

    /**
     * @dev Deploys invariant handler and configures fuzz target contract.
     */
    function setUp() public override {
        super.setUp();
        handler = new StorageLayoutInvariantHandler(harness);

        targetContract(address(handler));
    }

    /**
     * @dev Invariant: no project namespace collides with ERC-1967 slots.
     */
    function invariant_namespaceSlotsDoNotCollideWithERC1967Slots() public pure {
        bytes32[] memory slots = _allProjectStorageSlots();

        for (uint256 i = 0; i < slots.length; i++) {
            assertTrue(slots[i] != ERC1967_IMPLEMENTATION_SLOT, "Collision with ERC-1967 implementation slot");
            assertTrue(slots[i] != ERC1967_ADMIN_SLOT, "Collision with ERC-1967 admin slot");
            assertTrue(slots[i] != ERC1967_BEACON_SLOT, "Collision with ERC-1967 beacon slot");
        }
    }

    /**
     * @dev Invariant: one-namespace writes do not mutate tracked values in other namespaces.
     */
    function invariant_namespaceWritesAreIsolated() public view {
        assertEq(
            harness.isImplementationWhitelisted(ContractType.Account, handler.TRACKED_IMPLEMENTATION()),
            handler.expectedWhitelistAccount(),
            "Tracked whitelist(Account) value mutated unexpectedly"
        );
        assertEq(
            harness.isImplementationWhitelisted(ContractType.Organization, handler.TRACKED_IMPLEMENTATION()),
            handler.expectedWhitelistOrganization(),
            "Tracked whitelist(Organization) value mutated unexpectedly"
        );

        assertEq(
            harness.isDeployedAccount(handler.TRACKED_ACCOUNT()),
            handler.expectedTrackedAccountDeployed(),
            "Tracked deployedAccounts value mutated unexpectedly"
        );
        assertEq(
            harness.getAccountImplementation(),
            handler.expectedAccountImplementation(),
            "accountImplementation scalar mutated unexpectedly"
        );

        assertEq(
            harness.getAdminOperationTimelockDurationSeconds(),
            handler.expectedAdminOperationTimelockDurationSeconds(),
            "adminOperationTimelockDurationSeconds scalar mutated unexpectedly"
        );

        assertEq(
            harness.getAdminStatus(handler.TRACKED_ADMIN()),
            handler.expectedTrackedAdminStatus(),
            "Tracked isAdmin value mutated unexpectedly"
        );
        assertEq(harness.getAdminCount(), handler.expectedAdminCount(), "adminCount scalar mutated unexpectedly");
        assertEq(
            harness.getVotingThreshold(),
            handler.expectedVotingThreshold(),
            "votingThreshold scalar mutated unexpectedly"
        );

        assertEq(
            harness.getDeployerAddress(),
            handler.expectedDeployerAddress(),
            "deployerAddress scalar mutated unexpectedly"
        );

        assertEq(
            harness.isGroup(handler.TRACKED_GROUP_ID()),
            handler.expectedTrackedGroupExists(),
            "Tracked isGroup value mutated unexpectedly"
        );
        assertEq(
            harness.isGroupMember(handler.TRACKED_GROUP_ID(), handler.TRACKED_MEMBER()),
            handler.expectedTrackedGroupMember(),
            "Tracked isGroupMember value mutated unexpectedly"
        );
        assertEq(
            harness.wasGroupDeleted(handler.TRACKED_GROUP_ID()),
            handler.expectedTrackedGroupWasDeleted(),
            "Tracked wasGroupDeleted value mutated unexpectedly"
        );

        (address guardian, bool isReady, address pendingGuardian, uint256 pendingTimestamp) = harness.getGuardianState();
        assertEq(guardian, handler.expectedGuardian(), "guardian scalar mutated unexpectedly");
        assertEq(
            isReady,
            handler.expectedGuardianReadyForAcceptance(),
            "isGuardianUpdateReadyForAcceptance scalar mutated unexpectedly"
        );
        assertEq(pendingGuardian, handler.expectedPendingGuardian(), "pendingGuardian scalar mutated unexpectedly");
        assertEq(
            pendingTimestamp,
            handler.expectedPendingGuardianUpdateTimestamp(),
            "pendingGuardianUpdateTimestamp scalar mutated unexpectedly"
        );

        assertEq(
            harness.getMemberStatus(handler.TRACKED_MEMBER()),
            handler.expectedTrackedMemberStatus(),
            "Tracked isMember value mutated unexpectedly"
        );

        assertEq(harness.getPoliciesRoot(), handler.expectedPoliciesRoot(), "policiesRoot scalar mutated unexpectedly");
        assertEq(
            harness.getPolicyUsage(handler.TRACKED_POLICY_USAGE_KEY(), handler.TRACKED_POLICY_WINDOW()),
            handler.expectedTrackedPolicyUsage(),
            "Tracked policyUsage value mutated unexpectedly"
        );

        assertEq(
            harness.getUsedNonce(handler.TRACKED_NONCE()),
            handler.expectedTrackedNonceUsed(),
            "Tracked usedNonces value mutated unexpectedly"
        );

        (address whitelistAddress, address authorizedUpgradeImplementation) = harness.getUpgradeState();
        assertEq(
            whitelistAddress, handler.expectedUpgradeWhitelistAddress(), "whitelistAddress scalar mutated unexpectedly"
        );
        assertEq(
            authorizedUpgradeImplementation,
            handler.expectedAuthorizedUpgradeImplementation(),
            "authorizedUpgradeImplementation scalar mutated unexpectedly"
        );

        TxRecoveryState memory txRecovery = harness.getTxRecoveryState();
        assertEq(txRecovery.recoveryAddress, handler.expectedTxRecoveryAddress(), "txRecovery.recoveryAddress mismatch");
        assertEq(txRecovery.isEnabled, handler.expectedTxRecoveryEnabled(), "txRecovery.isEnabled mismatch");
        assertEq(
            txRecovery.timelockDurationSeconds,
            handler.expectedTxRecoveryTimelockDurationSeconds(),
            "txRecovery.timelockDurationSeconds mismatch"
        );
        assertEq(
            txRecovery.pendingEnableTimestamp,
            handler.expectedTxRecoveryPendingEnableTimestamp(),
            "txRecovery.pendingEnableTimestamp mismatch"
        );
        assertEq(
            txRecovery.pendingInit.pendingRecoveryAddress,
            handler.expectedTxPendingInitRecoveryAddress(),
            "txRecovery.pendingInit.pendingRecoveryAddress mismatch"
        );
        assertEq(
            txRecovery.pendingInit.pendingTimelockDurationSeconds,
            handler.expectedTxPendingInitTimelockDurationSeconds(),
            "txRecovery.pendingInit.pendingTimelockDurationSeconds mismatch"
        );
        assertEq(
            txRecovery.pendingInit.pendingTimestamp,
            handler.expectedTxPendingInitTimestamp(),
            "txRecovery.pendingInit.pendingTimestamp mismatch"
        );

        GuardianRecoveryState memory guardianRecovery = harness.getGuardianRecoveryState();
        assertEq(
            guardianRecovery.recoveryAddress,
            handler.expectedGuardianRecoveryAddress(),
            "guardianRecovery.recoveryAddress mismatch"
        );
        assertEq(
            guardianRecovery.isUpdateReadyForAcceptance,
            handler.expectedGuardianRecoveryReadyForAcceptance(),
            "guardianRecovery.isUpdateReadyForAcceptance mismatch"
        );
        assertEq(
            guardianRecovery.pendingGuardian,
            handler.expectedGuardianRecoveryPendingGuardian(),
            "guardianRecovery.pendingGuardian mismatch"
        );
        assertEq(
            guardianRecovery.timelockDurationSeconds,
            handler.expectedGuardianRecoveryTimelockDurationSeconds(),
            "guardianRecovery.timelockDurationSeconds mismatch"
        );
        assertEq(
            guardianRecovery.pendingGuardianTimestamp,
            handler.expectedGuardianRecoveryPendingGuardianTimestamp(),
            "guardianRecovery.pendingGuardianTimestamp mismatch"
        );
        assertEq(
            guardianRecovery.pendingInit.pendingRecoveryAddress,
            handler.expectedGuardianPendingInitRecoveryAddress(),
            "guardianRecovery.pendingInit.pendingRecoveryAddress mismatch"
        );
        assertEq(
            guardianRecovery.pendingInit.pendingTimelockDurationSeconds,
            handler.expectedGuardianPendingInitTimelockDurationSeconds(),
            "guardianRecovery.pendingInit.pendingTimelockDurationSeconds mismatch"
        );
        assertEq(
            guardianRecovery.pendingInit.pendingTimestamp,
            handler.expectedGuardianPendingInitTimestamp(),
            "guardianRecovery.pendingInit.pendingTimestamp mismatch"
        );
    }
}
