// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {Vm} from "forge-std/Vm.sol";

import {IImplementationWhitelist} from "interfaces/IImplementationWhitelist.sol";
import {IOrganization} from "interfaces/IOrganization.sol";
import {IOrganizationAdmin} from "interfaces/organization/IOrganizationAdmin.sol";
import {IOrganizationGroups} from "interfaces/organization/IOrganizationGroups.sol";
import {IOrganizationGuardian} from "interfaces/organization/IOrganizationGuardian.sol";
import {IOrganizationInitialization} from "interfaces/organization/IOrganizationInitialization.sol";
import {IOrganizationMembers} from "interfaces/organization/IOrganizationMembers.sol";
import {TimelockUtils} from "libraries/TimelockUtils.sol";
import {OrganizationProxy} from "organization/OrganizationProxy.sol";
import {
    LibOrganizationInitializationHarness,
    OrganizationImplementationInitializationHarness
} from "test/organization/initialization/InitializationHarnesses.sol";
import {InitializationSuiteBase} from "test/organization/initialization/InitializationSuiteBase.sol";
import {ContractType, GroupModification, GroupModificationType, InitializationParams} from "types/CommonTypes.sol";

/**
 * @dev Base/library initialization tests.
 */
contract OrganizationInitializationAndLibTest is InitializationSuiteBase {
    /// @dev Verifies `OrganizationInitializationBase.initialize` rejects non-deployer callers on an uninitialized proxy.
    function test_OIB_INIT_1_uninitializedProxy_nonDeployerRevertsUnauthorizedDeployer() public {
        // Setup: Deploy an uninitialized proxy and prepare valid initialization params.
        vm.prank(AUTHORIZED_DEPLOYER);
        address proxy = address(new OrganizationProxy(address(implementation), address(whitelist)));
        InitializationParams memory params = _defaultInitializationParams();

        // Call: Attempt initialization from a non-deployer and expect `UnauthorizedDeployer`.
        vm.expectRevert(IOrganizationInitialization.UnauthorizedDeployer.selector);
        vm.prank(UNAUTHORIZED_CALLER);
        IOrganizationInitialization(proxy).initialize(params);

        // Verify: Failed initialization keeps the proxy in the uninitialized state.
        assertFalse(IOrganizationInitialization(proxy).isInitialized(), "failed initialize should keep proxy uninitialized");
    }

    /// @dev Verifies `OrganizationInitializationBase.initialize` succeeds for the deployer, preserves deployer storage, and emits one initialization event.
    function test_OIB_INIT_2__OIB_INIT_6__OIB_VIEW_1__OIB_VIEW_2__OIB_VIEW_3__OIB_VIEW_4__OIB_VIEW_5__CFI_FLOW_6_validInitialize_setsStateAndEmitsOneInitializedEvent() public {
        // Setup: Deploy a proxy, prepare valid params, assert pre-init views, and begin log recording.
        vm.prank(AUTHORIZED_DEPLOYER);
        address proxy = address(new OrganizationProxy(address(implementation), address(whitelist)));

        InitializationParams memory params = _defaultInitializationParams();
        IOrganization organization = IOrganization(proxy);

        assertEq(organization.getDeployerAddress(), AUTHORIZED_DEPLOYER, "proxy deployer storage mismatch before init");
        assertFalse(organization.isInitialized(), "proxy should start uninitialized");

        vm.recordLogs();

        // Call: Initialize the proxy through the authorized deployer.
        vm.prank(AUTHORIZED_DEPLOYER);
        organization.initialize(params);

        // Verify: Deployer and initialized status are correct, full state is configured, and one event is emitted.
        assertEq(organization.getDeployerAddress(), AUTHORIZED_DEPLOYER, "deployer should remain unchanged after init");
        assertTrue(organization.isInitialized(), "proxy should become initialized after successful initialize");
        _assertInitializedState(organization, params);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(_countTopic(logs, ORG_INITIALIZED_TOPIC), 1, "initialize should emit exactly one event");
    }

    /// @dev Verifies initialize guards for direct implementation calls, failed-init retry behavior, and post-success reinitialization attempts.
    function test_OIB_INIT_3__OIB_INIT_4__OIB_INIT_5__OIB_VIEW_6__CFI_FLOW_4__CFI_FLOW_5_reinitAndDirectImplementationPathsRevertAsExpected() public {
        // Setup: Build one valid and one invalid initialization payload.
        InitializationParams memory params = _defaultInitializationParams();
        InitializationParams memory invalidParams = _defaultInitializationParams();
        invalidParams.members = buildEmptyAddressArray();

        // Call: Exercise direct implementation initialize, failed proxy initialize, successful initialize, and both reinitialize paths.
        vm.expectRevert(IOrganizationInitialization.UnauthorizedDeployer.selector);
        implementation.initialize(params);

        // Verify: Direct implementation deployer stays zero and failed initialization does not lock subsequent valid initialization.
        assertEq(implementation.getDeployerAddress(), address(0), "implementation deployer slot should be zero");

        vm.prank(AUTHORIZED_DEPLOYER);
        address proxy = address(new OrganizationProxy(address(implementation), address(whitelist)));
        IOrganization organization = IOrganization(proxy);

        vm.expectRevert(IOrganizationInitialization.NoMembersProvided.selector);
        vm.prank(AUTHORIZED_DEPLOYER);
        organization.initialize(invalidParams);
        assertFalse(organization.isInitialized(), "failed initialize should not lock initialization");

        vm.prank(AUTHORIZED_DEPLOYER);
        organization.initialize(params);

        vm.expectRevert();
        vm.prank(UNAUTHORIZED_CALLER);
        organization.initialize(params);

        vm.expectRevert();
        vm.prank(AUTHORIZED_DEPLOYER);
        organization.initialize(params);
    }

    /// @dev Verifies `LibOrganizationInitialization.initialize` happy path configures members/admins/groups/guardian/recovery state and emits `OrganizationInitialized`.
    function test_LOI_HPS_1__LOI_HPS_2__LOI_HPS_3__LOI_HPS_4__LOI_HPS_5__LOI_HPS_6__LOI_HPS_7__LOI_HPS_9__LOI_REC_1__LOI_REC_2__LOI_REC_3__LOI_REC_4_initializeLibrary_happyPathConfiguresState() public {
        // Setup: Deploy a library harness, build valid params, and set the expected initialization event payload.
        LibOrganizationInitializationHarness harness = _newLibraryHarness();
        InitializationParams memory params = _defaultInitializationParams();

        vm.expectEmit(true, true, true, true, address(harness));
        emit IOrganizationInitialization.OrganizationInitialized(
            params.admins,
            params.votingThreshold,
            params.guardian,
            params.accountImplementation,
            params.adminOperationTimelockDurationSeconds,
            params.transactionAndERC1271RecoveryAddress,
            params.txRecoveryTimelockDurationSeconds,
            params.guardianRecoveryAddress,
            params.guardianRecoveryTimelockDurationSeconds
        );

        // Call: Initialize through the library harness with valid parameters.
        harness.initializeViaLibrary(params);

        // Verify: Sentinel state, membership/admin/group data, timelocks, account implementation, and recovery storage all match input.
        assertTrue(harness.isInitializedViaLibrary(), "library initialize should set initialized sentinel");

        for (uint256 i = 0; i < params.members.length; ++i) {
            assertTrue(harness.getMemberStatus(params.members[i]), "member should be initialized");
        }

        for (uint256 i = 0; i < params.admins.length; ++i) {
            assertTrue(harness.getAdminStatus(params.admins[i]), "admin should be initialized");
        }

        assertEq(harness.getAdminCountStorage(), params.admins.length, "adminCount mismatch");
        assertEq(harness.getVotingThresholdStorage(), params.votingThreshold, "votingThreshold mismatch");
        assertEq(harness.getGuardianStorage(), params.guardian, "guardian mismatch");
        assertEq(
            harness.getAdminOperationTimelockStorage(),
            params.adminOperationTimelockDurationSeconds,
            "admin operation timelock mismatch"
        );
        assertTrue(harness.getGroupStatus(GROUP_ID), "group should be created");
        assertTrue(harness.getGroupMemberStatus(GROUP_ID, MEMBER_1), "group member should be added");

        assertEq(harness.getAccountImplementationStorage(), params.accountImplementation, "account impl mismatch");

        assertEq(
            harness.getTxRecoveryStateViaStorage().recoveryAddress,
            params.transactionAndERC1271RecoveryAddress,
            "tx recovery address mismatch"
        );
        assertEq(
            harness.getTxRecoveryStateViaStorage().timelockDurationSeconds,
            params.txRecoveryTimelockDurationSeconds,
            "tx recovery timelock mismatch"
        );
        assertFalse(harness.getTxRecoveryStateViaStorage().isEnabled, "tx recovery should start disabled");

        assertEq(
            harness.getGuardianRecoveryStateViaStorage().recoveryAddress,
            params.guardianRecoveryAddress,
            "guardian recovery address mismatch"
        );
        assertEq(
            harness.getGuardianRecoveryStateViaStorage().timelockDurationSeconds,
            params.guardianRecoveryTimelockDurationSeconds,
            "guardian recovery timelock mismatch"
        );
    }

    /// @dev Verifies `LibOrganizationInitialization.initialize` handles boundary timelocks, duplicate members, empty groups, and deferred recovery configuration.
    function test_LOI_HPS_8__LOI_HPS_10__LOI_HPS_11__LOI_REC_5__LOI_REC_6__LOI_REC_7__LOI_REC_8__LOI_REC_9__LOI_REC_10__LOI_REC_11_initializeLibrary_boundaryAndDeferredRecoveryBehaviors() public {
        // Setup: Build one params set with duplicate members/max timelocks/empty groups and one deferred-recovery params set.
        LibOrganizationInitializationHarness harness = _newLibraryHarness();
        InitializationParams memory params = _defaultInitializationParams();

        params.members = buildArray(MEMBER_1, MEMBER_1, ADMIN_1, ADMIN_2);
        params.groups = new GroupModification[](0);
        params.adminOperationTimelockDurationSeconds = 30 days;
        params.guardianRecoveryTimelockDurationSeconds = 30 days;
        params.txRecoveryTimelockDurationSeconds = 30 days;

        // Call: Initialize first with boundary values and then initialize a second harness with zero recovery addresses.
        harness.initializeViaLibrary(params);

        // Verify: Duplicate membership is idempotent, empty groups are a no-op, max timelocks are accepted, and deferred recovery fields stay zeroed.
        assertTrue(harness.getMemberStatus(MEMBER_1), "duplicate member should still result in member=true");
        assertFalse(harness.getGroupStatus(GROUP_ID), "empty groups should be a valid no-op");

        assertEq(harness.getAdminOperationTimelockStorage(), 30 days, "max admin timelock should be accepted");
        assertEq(
            harness.getGuardianRecoveryStateViaStorage().timelockDurationSeconds,
            30 days,
            "max guardian recovery timelock should be accepted"
        );
        assertEq(
            harness.getTxRecoveryStateViaStorage().timelockDurationSeconds,
            30 days,
            "max tx recovery timelock should be accepted"
        );

        LibOrganizationInitializationHarness deferredHarness = _newLibraryHarness();
        InitializationParams memory deferredParams = _defaultInitializationParams();
        deferredParams.guardianRecoveryAddress = address(0);
        deferredParams.transactionAndERC1271RecoveryAddress = address(0);

        deferredHarness.initializeViaLibrary(deferredParams);

        assertEq(
            deferredHarness.getGuardianRecoveryStateViaStorage().recoveryAddress,
            address(0),
            "zero guardian recovery should defer config"
        );
        assertEq(
            deferredHarness.getTxRecoveryStateViaStorage().recoveryAddress,
            address(0),
            "zero tx recovery should defer config"
        );
        assertEq(
            deferredHarness.getGuardianRecoveryStateViaStorage().pendingInit.pendingRecoveryAddress,
            address(0),
            "deferred guardian recovery pending fields should be zeroed"
        );
        assertEq(
            deferredHarness.getTxRecoveryStateViaStorage().pendingInit.pendingRecoveryAddress,
            address(0),
            "deferred tx recovery pending fields should be zeroed"
        );
    }

    /// @dev Verifies `LibOrganizationInitialization.initialize` reverts for invalid member/admin/guardian/implementation/timelock inputs.
    function test_LOI_VAL_1__LOI_VAL_2__LOI_VAL_3__LOI_VAL_4__LOI_VAL_5__LOI_VAL_6__LOI_VAL_7__LOI_VAL_8__LOI_VAL_9__LOI_VAL_10__LOI_VAL_11__LOI_VAL_12__LOI_VAL_13__LOI_VAL_14_initializeLibrary_validationReverts() public {
        // Setup: Prepare reusable params and instantiate a fresh harness per validation failure branch.
        InitializationParams memory params = _defaultInitializationParams();

        // Call: Execute each invalid initialization variant and assert the expected row-specific revert selector/data.
        LibOrganizationInitializationHarness h1 = _newLibraryHarness();
        params.members = buildEmptyAddressArray();
        vm.expectRevert(IOrganizationInitialization.NoMembersProvided.selector);
        h1.initializeViaLibrary(params);

        LibOrganizationInitializationHarness h2 = _newLibraryHarness();
        params = _defaultInitializationParams();
        params.members[0] = address(0);
        vm.expectRevert(abi.encodeWithSelector(IOrganizationMembers.InvalidMemberAddress.selector, address(0)));
        h2.initializeViaLibrary(params);

        LibOrganizationInitializationHarness h3 = _newLibraryHarness();
        params = _defaultInitializationParams();
        params.admins = buildEmptyAddressArray();
        vm.expectRevert(IOrganizationAdmin.InvalidAdminConfig.selector);
        h3.initializeViaLibrary(params);

        LibOrganizationInitializationHarness h4 = _newLibraryHarness();
        params = _defaultInitializationParams();
        params.admins[0] = address(0);
        vm.expectRevert(abi.encodeWithSelector(IOrganizationMembers.InvalidMemberAddress.selector, address(0)));
        h4.initializeViaLibrary(params);

        LibOrganizationInitializationHarness h5 = _newLibraryHarness();
        params = _defaultInitializationParams();
        params.admins[0] = MEMBER_3;
        vm.expectRevert(abi.encodeWithSelector(IOrganizationAdmin.AdminNotMember.selector, MEMBER_3));
        h5.initializeViaLibrary(params);

        LibOrganizationInitializationHarness h6 = _newLibraryHarness();
        params = _defaultInitializationParams();
        params.admins = buildArray(ADMIN_1, ADMIN_1);
        vm.expectRevert(abi.encodeWithSelector(IOrganizationAdmin.AdminAlreadyExists.selector, ADMIN_1));
        h6.initializeViaLibrary(params);

        LibOrganizationInitializationHarness h7 = _newLibraryHarness();
        params = _defaultInitializationParams();
        params.votingThreshold = 0;
        vm.expectRevert(abi.encodeWithSelector(IOrganizationAdmin.InvalidAdminVotingThreshold.selector, 0, 2));
        h7.initializeViaLibrary(params);

        LibOrganizationInitializationHarness h8 = _newLibraryHarness();
        params = _defaultInitializationParams();
        params.votingThreshold = 3;
        vm.expectRevert(abi.encodeWithSelector(IOrganizationAdmin.InvalidAdminVotingThreshold.selector, 3, 2));
        h8.initializeViaLibrary(params);

        LibOrganizationInitializationHarness h9 = _newLibraryHarness();
        params = _defaultInitializationParams();
        params.guardian = address(0);
        vm.expectRevert(IOrganizationGuardian.InvalidGuardianAddress.selector);
        h9.initializeViaLibrary(params);

        LibOrganizationInitializationHarness h10 = _newLibraryHarness();
        params = _defaultInitializationParams();
        params.accountImplementation = address(new OrganizationImplementationInitializationHarness());
        vm.expectRevert(
            abi.encodeWithSelector(IImplementationWhitelist.ImplementationNotWhitelisted.selector, params.accountImplementation)
        );
        h10.initializeViaLibrary(params);

        LibOrganizationInitializationHarness h11 = _newLibraryHarness();
        params = _defaultInitializationParams();
        params.adminOperationTimelockDurationSeconds = 2 days - 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockUtils.InvalidTimelockDuration.selector,
                params.adminOperationTimelockDurationSeconds,
                TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS,
                TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
            )
        );
        h11.initializeViaLibrary(params);

        LibOrganizationInitializationHarness h12 = _newLibraryHarness();
        params = _defaultInitializationParams();
        params.adminOperationTimelockDurationSeconds = 30 days + 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockUtils.InvalidTimelockDuration.selector,
                params.adminOperationTimelockDurationSeconds,
                TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS,
                TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
            )
        );
        h12.initializeViaLibrary(params);

        LibOrganizationInitializationHarness h13 = _newLibraryHarness();
        params = _defaultInitializationParams();
        params.guardianRecoveryTimelockDurationSeconds = 2 days - 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockUtils.InvalidTimelockDuration.selector,
                params.guardianRecoveryTimelockDurationSeconds,
                TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS,
                TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
            )
        );
        h13.initializeViaLibrary(params);

        LibOrganizationInitializationHarness h14 = _newLibraryHarness();
        params = _defaultInitializationParams();
        params.txRecoveryTimelockDurationSeconds = 30 days + 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockUtils.InvalidTimelockDuration.selector,
                params.txRecoveryTimelockDurationSeconds,
                TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS,
                TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
            )
        );
        h14.initializeViaLibrary(params);

        // Verify: Each negative branch reverts with the expected error, covering all listed validation failures.
    }

    /// @dev Verifies `LibOrganizationInitialization.initialize` reverts for invalid group create/update/delete and membership operations.
    function test_LOI_VAL_15__LOI_VAL_16__LOI_VAL_17__LOI_VAL_18__LOI_VAL_20__LOI_VAL_21__LOI_VAL_22_initializeLibrary_groupValidationReverts() public {
        // Setup: Prepare reusable initialization params and group operation batches for each group-validation failure mode.
        InitializationParams memory params;
        GroupModification[] memory groups;

        // Call: Run each invalid group operation batch on a fresh harness and assert the corresponding revert.
        LibOrganizationInitializationHarness h15 = _newLibraryHarness();
        params = _defaultInitializationParams();
        groups = new GroupModification[](1);
        groups[0] = GroupModification({
            groupId: 1,
            modificationType: GroupModificationType.Create,
            membersToAdd: buildArray(MEMBER_1),
            membersToRemove: buildArray(MEMBER_2)
        });
        params.groups = groups;
        vm.expectRevert(abi.encodeWithSelector(IOrganizationGroups.InvalidGroupCreationOperation.selector, 1));
        h15.initializeViaLibrary(params);

        LibOrganizationInitializationHarness h16A = _newLibraryHarness();
        params = _defaultInitializationParams();
        groups = new GroupModification[](1);
        groups[0] = GroupModification({
            groupId: 2,
            modificationType: GroupModificationType.Update,
            membersToAdd: buildArray(MEMBER_1),
            membersToRemove: buildEmptyAddressArray()
        });
        params.groups = groups;
        vm.expectRevert(abi.encodeWithSelector(IOrganizationGroups.GroupDoesNotExist.selector, 2));
        h16A.initializeViaLibrary(params);

        LibOrganizationInitializationHarness h17 = _newLibraryHarness();
        params = _defaultInitializationParams();
        groups = new GroupModification[](1);
        groups[0] = GroupModification({
            groupId: 4,
            modificationType: GroupModificationType.Create,
            membersToAdd: buildArray(address(0)),
            membersToRemove: buildEmptyAddressArray()
        });
        params.groups = groups;
        vm.expectRevert(abi.encodeWithSelector(IOrganizationMembers.InvalidMemberAddress.selector, address(0)));
        h17.initializeViaLibrary(params);

        LibOrganizationInitializationHarness h18 = _newLibraryHarness();
        params = _defaultInitializationParams();
        groups = new GroupModification[](2);
        groups[0] = GroupModification({
            groupId: 5,
            modificationType: GroupModificationType.Create,
            membersToAdd: buildArray(MEMBER_1),
            membersToRemove: buildEmptyAddressArray()
        });
        groups[1] = groups[0];
        params.groups = groups;
        vm.expectRevert(abi.encodeWithSelector(IOrganizationGroups.GroupAlreadyExists.selector, 5));
        h18.initializeViaLibrary(params);

        LibOrganizationInitializationHarness h20 = _newLibraryHarness();
        params = _defaultInitializationParams();
        groups = new GroupModification[](1);
        groups[0] = GroupModification({
            groupId: 6,
            modificationType: GroupModificationType.Delete,
            membersToAdd: buildArray(MEMBER_1),
            membersToRemove: buildEmptyAddressArray()
        });
        params.groups = groups;
        vm.expectRevert(abi.encodeWithSelector(IOrganizationGroups.InvalidGroupDeletionOperation.selector, 6));
        h20.initializeViaLibrary(params);

        LibOrganizationInitializationHarness h21 = _newLibraryHarness();
        params = _defaultInitializationParams();
        groups = new GroupModification[](3);
        groups[0] = GroupModification({
            groupId: 7,
            modificationType: GroupModificationType.Create,
            membersToAdd: buildArray(MEMBER_1),
            membersToRemove: buildEmptyAddressArray()
        });
        groups[1] = GroupModification({
            groupId: 7,
            modificationType: GroupModificationType.Delete,
            membersToAdd: buildEmptyAddressArray(),
            membersToRemove: buildEmptyAddressArray()
        });
        groups[2] = GroupModification({
            groupId: 7,
            modificationType: GroupModificationType.Create,
            membersToAdd: buildArray(MEMBER_2),
            membersToRemove: buildEmptyAddressArray()
        });
        params.groups = groups;
        vm.expectRevert(abi.encodeWithSelector(IOrganizationGroups.GroupAlreadyDeleted.selector, 7));
        h21.initializeViaLibrary(params);

        LibOrganizationInitializationHarness h22 = _newLibraryHarness();
        params = _defaultInitializationParams();
        groups = new GroupModification[](1);
        groups[0] = GroupModification({
            groupId: 8,
            modificationType: GroupModificationType.Create,
            membersToAdd: buildArray(MEMBER_3),
            membersToRemove: buildEmptyAddressArray()
        });
        params.groups = groups;
        vm.expectRevert(abi.encodeWithSelector(IOrganizationMembers.MemberDoesNotExist.selector, MEMBER_3));
        h22.initializeViaLibrary(params);

        // Verify: Group operation validation branches all revert as expected for the targeted failure condition.
    }

    /// @dev Verifies `LibOrganizationInitialization.initialize` reverts when a delete operation targets a non-existent group.
    function test_LOI_VAL_16_deleteNonExistentGroup_revertsDesiredBehavior() public {
        // Setup: Build initialization params containing a delete operation for an undefined group id.
        LibOrganizationInitializationHarness harness = _newLibraryHarness();
        InitializationParams memory params = _defaultInitializationParams();

        GroupModification[] memory groups = new GroupModification[](1);
        groups[0] = GroupModification({
            groupId: 999,
            modificationType: GroupModificationType.Delete,
            membersToAdd: buildEmptyAddressArray(),
            membersToRemove: buildEmptyAddressArray()
        });
        params.groups = groups;

        // Call: Execute initialization and expect `GroupDoesNotExist` for the delete operation.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationGroups.GroupDoesNotExist.selector, 999));
        harness.initializeViaLibrary(params);

        // Verify: Non-existent group deletion is rejected during initialization.
    }

    /// @dev Verifies `LibOrganizationInitialization.initialize` reverts when an update removes a member not in the target group.
    function test_LOI_VAL_19_updateRemovingMissingGroupMember_revertsDesiredBehavior() public {
        // Setup: Build initialization params that create a group, then attempt to remove an address never added to that group.
        LibOrganizationInitializationHarness harness = _newLibraryHarness();
        InitializationParams memory params = _defaultInitializationParams();

        GroupModification[] memory groups = new GroupModification[](2);
        groups[0] = GroupModification({
            groupId: 1000,
            modificationType: GroupModificationType.Create,
            membersToAdd: buildArray(MEMBER_1),
            membersToRemove: buildEmptyAddressArray()
        });
        groups[1] = GroupModification({
            groupId: 1000,
            modificationType: GroupModificationType.Update,
            membersToAdd: buildEmptyAddressArray(),
            membersToRemove: buildArray(MEMBER_2)
        });
        params.groups = groups;

        // Call: Execute initialization with the invalid update sequence and expect a revert.
        vm.expectRevert();
        harness.initializeViaLibrary(params);

        // Verify: Update operations cannot remove members absent from the current group membership.
    }

    /// @dev Verifies library deployer/view helpers plus initialization atomicity, event suppression on revert, and one-way initialization transition.
    function test_LOI_AOG_1__LOI_AOG_2__LOI_AOG_3__LOI_AOG_4__LOI_AOG_5__LOI_AOG_6__LOI_VIEW_1__LOI_VIEW_2__LOI_VIEW_3__LOI_VIEW_4__LOI_VIEW_5_initializeLibrary_atomicityAndViewGuards() public {
        // Setup: Deploy a harness and seed deployer storage for enforce-only-deployer checks.
        LibOrganizationInitializationHarness harness = _newLibraryHarness();
        harness.setDeployerAddressStorage(AUTHORIZED_DEPLOYER);

        // Call: Exercise deployer guard checks, a reverting initialize path, a successful initialize path, and a reinitialize attempt.
        vm.prank(AUTHORIZED_DEPLOYER);
        harness.enforceOnlyDeployerViaLibrary();

        vm.expectRevert(IOrganizationInitialization.UnauthorizedDeployer.selector);
        vm.prank(UNAUTHORIZED_CALLER);
        harness.enforceOnlyDeployerViaLibrary();

        // Verify: View helpers, rollback guarantees, event behavior, and reinitialization guards match expected semantics.
        assertEq(harness.getDeployerAddressViaLibrary(), AUTHORIZED_DEPLOYER, "stored deployer mismatch");
        assertFalse(harness.isInitializedViaLibrary(), "adminCount=0 should report uninitialized");

        InitializationParams memory invalidGuardian = _defaultInitializationParams();
        invalidGuardian.guardian = address(0);

        vm.recordLogs();
        vm.expectRevert(IOrganizationGuardian.InvalidGuardianAddress.selector);
        harness.initializeViaLibrary(invalidGuardian);

        assertFalse(harness.isInitializedViaLibrary(), "failed initialization should roll back to uninitialized");
        assertFalse(harness.getMemberStatus(MEMBER_1), "member writes should roll back on revert");
        assertEq(_countTopic(vm.getRecordedLogs(), ORG_INITIALIZED_TOPIC), 0, "reverting initialize must not emit event");

        InitializationParams memory valid = _defaultInitializationParams();
        harness.initializeViaLibrary(valid);

        assertTrue(harness.isInitializedViaLibrary(), "successful init should flip initialized sentinel once");
        assertTrue(harness.getMemberStatus(ADMIN_1), "admins should remain members after success");

        vm.expectRevert(IOrganizationInitialization.AlreadyInitialized.selector);
        harness.initializeViaLibrary(valid);
    }

    /// @dev Deploys a library harness with deployer/whitelist/timelock storage primed for initialization tests.
    /// @return harness Configured library harness instance.
    function _newLibraryHarness() internal returns (LibOrganizationInitializationHarness harness) {
        // Seed prerequisite storage values expected by library guards and whitelist checks.
        harness = new LibOrganizationInitializationHarness();
        harness.setWhitelistAddressStorage(address(whitelist));
        harness.setDeployerAddressStorage(AUTHORIZED_DEPLOYER);
        harness.setAdminOperationTimelockStorage(2 days);
    }
}
