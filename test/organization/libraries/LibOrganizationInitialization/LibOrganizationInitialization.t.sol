// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IImplementationWhitelist} from "interfaces/IImplementationWhitelist.sol";
import {IOrganizationAdmin} from "interfaces/organization/IOrganizationAdmin.sol";
import {IOrganizationGroups} from "interfaces/organization/IOrganizationGroups.sol";
import {IOrganizationGuardian} from "interfaces/organization/IOrganizationGuardian.sol";
import {IOrganizationInitialization} from "interfaces/organization/IOrganizationInitialization.sol";
import {IOrganizationMembers} from "interfaces/organization/IOrganizationMembers.sol";
import {TimelockUtils} from "libraries/TimelockUtils.sol";
import {
    LibOrganizationInitializationHarness,
    OrganizationImplementationHarness
} from "test/organization/OrganizationFactory/OrganizationFactoryHarnesses.sol";
import {
    InitializationSuiteBase
} from "test/organization/base/OrganizationInitializationBase/OrganizationInitializationBaseSuiteBase.sol";
import {GroupModification, GroupModificationType, InitializationParams} from "types/CommonTypes.sol";

/**
 * @dev LibOrganizationInitialization coverage.
 */
contract LibOrganizationInitializationTest is InitializationSuiteBase {
    /// @dev Verifies `LibOrganizationInitialization.initialize` happy path configures
    /// members/admins/groups/guardian/recovery state, emits `OrganizationInitialized`, and accepts the min-boundary
    /// guardian recovery timelock.
    function test_initializeLibrary_happyPathConfiguresState()
        public
    {
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

        // Verify: Sentinel state, membership/admin/group data, timelocks, account implementation, and recovery storage
        // all match input.
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

    /// @dev Verifies `LibOrganizationInitialization.initialize` handles max-boundary timelocks, duplicate members,
    /// empty groups, and deferred recovery configuration.
    function test_initializeLibrary_boundaryAndDeferredRecoveryBehaviors()
        public
    {
        // Setup: Build one params set with duplicate members/max timelocks/empty groups and one deferred-recovery
        // params set.
        LibOrganizationInitializationHarness harness = _newLibraryHarness();
        InitializationParams memory params = _defaultInitializationParams();

        params.members = buildArray(MEMBER_1, MEMBER_1, ADMIN_1, ADMIN_2);
        params.groups = new GroupModification[](0);
        params.adminOperationTimelockDurationSeconds = 30 days;
        params.guardianRecoveryTimelockDurationSeconds = 30 days;
        params.txRecoveryTimelockDurationSeconds = 30 days;

        // Call: Initialize first with boundary values and then initialize a second harness with zero recovery
        // addresses.
        harness.initializeViaLibrary(params);

        // Verify: Duplicate membership is idempotent, empty groups are a no-op, max timelocks are accepted, and
        // deferred recovery fields stay zeroed.
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

    /// @dev Verifies `LibOrganizationInitialization.initialize` reverts for invalid
    /// member/admin/guardian/implementation/timelock inputs.
    function test_initializeLibrary_validationReverts()
        public
    {
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
        params.accountImplementation = address(new OrganizationImplementationHarness());
        vm.expectRevert(
            abi.encodeWithSelector(
                IImplementationWhitelist.ImplementationNotWhitelisted.selector, params.accountImplementation
            )
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

    /// @dev Verifies `LibOrganizationInitialization.initialize` reverts for invalid group create/update/delete and
    /// membership operations.
    function test_initializeLibrary_groupValidationReverts()
        public
    {
        // Setup: Prepare reusable initialization params and group operation batches for each group-validation failure
        // mode.
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

    /// @dev Verifies `LibOrganizationInitialization.initialize` treats deleting a non-existent group as a no-op.
    function test_deleteNonExistentGroup_currentBehavior_isNoOp() public {
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

        // Call: Execute initialization with a delete for a non-existent group.
        harness.initializeViaLibrary(params);

        // Verify: Initialization succeeds, group 999 remains inactive, and initialized state is committed.
        assertTrue(
            harness.isInitializedViaLibrary(),
            "initialization should still succeed when delete targets non-existent group"
        );
        assertFalse(harness.getGroupStatus(999), "non-existent group should remain inactive");
        assertEq(harness.getAdminCountStorage(), params.admins.length, "successful init should persist admin state");
    }

    /// @dev Verifies `LibOrganizationInitialization.initialize` treats removing a non-member during group update as a
    /// no-op.
    function test_updateRemovingMissingGroupMember_currentBehavior_isNoOp() public {
        // Setup: Build initialization params that create a group, then attempt to remove an address never added to that
        // group.
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

        // Call: Execute initialization where update removes an address absent from the current group set.
        harness.initializeViaLibrary(params);

        // Verify: Initialization succeeds, existing group membership persists, and absent-member removal has no side
        // effects.
        assertTrue(harness.isInitializedViaLibrary(), "initialization should succeed for non-member removal updates");
        assertTrue(harness.getGroupStatus(1000), "group should remain active after update");
        assertTrue(harness.getGroupMemberStatus(1000, MEMBER_1), "existing member should remain in group");
        assertFalse(harness.getGroupMemberStatus(1000, MEMBER_2), "non-member removal should remain a no-op");
    }

    /// @dev Verifies library deployer/view helpers plus guardian-revert atomicity, event suppression on revert, and
    /// one-way initialization transition.
    function test_initializeLibrary_atomicityAndViewGuards()
        public
    {
        // Setup: Deploy a harness and seed deployer storage for enforce-only-deployer checks.
        LibOrganizationInitializationHarness harness = _newLibraryHarness();
        harness.setDeployerAddressStorage(AUTHORIZED_DEPLOYER);

        // Call: Exercise deployer guard checks, a reverting initialize path, a successful initialize path, and a
        // reinitialize attempt.
        vm.prank(AUTHORIZED_DEPLOYER);
        harness.enforceOnlyDeployerViaLibrary();

        vm.expectRevert(IOrganizationInitialization.UnauthorizedDeployer.selector);
        vm.prank(UNAUTHORIZED_CALLER);
        harness.enforceOnlyDeployerViaLibrary();

        // Verify: View helpers, rollback guarantees, event behavior, and reinitialization guards match expected
        // semantics.
        assertEq(harness.getDeployerAddressViaLibrary(), AUTHORIZED_DEPLOYER, "stored deployer mismatch");
        assertFalse(harness.isInitializedViaLibrary(), "adminCount=0 should report uninitialized");

        InitializationParams memory invalidGuardian = _defaultInitializationParams();
        invalidGuardian.guardian = address(0);

        vm.recordLogs();
        vm.expectRevert(IOrganizationGuardian.InvalidGuardianAddress.selector);
        harness.initializeViaLibrary(invalidGuardian);

        assertFalse(harness.isInitializedViaLibrary(), "failed initialization should roll back to uninitialized");
        assertFalse(harness.getMemberStatus(MEMBER_1), "member writes should roll back on revert");
        assertEq(
            _countTopic(vm.getRecordedLogs(), ORG_INITIALIZED_TOPIC), 0, "reverting initialize must not emit event"
        );

        InitializationParams memory valid = _defaultInitializationParams();
        harness.initializeViaLibrary(valid);

        assertTrue(harness.isInitializedViaLibrary(), "successful init should flip initialized sentinel once");
        assertTrue(harness.getMemberStatus(ADMIN_1), "admins should remain members after success");
        assertEq(
            harness.getAdminOperationTimelockStorage(),
            valid.adminOperationTimelockDurationSeconds,
            "successful init should persist the admin-operation timelock"
        );

        vm.expectRevert(IOrganizationInitialization.AlreadyInitialized.selector);
        harness.initializeViaLibrary(valid);
        assertEq(
            harness.getAdminOperationTimelockStorage(),
            valid.adminOperationTimelockDurationSeconds,
            "reinitialize revert must not change the stored admin-operation timelock"
        );
    }

    /// @dev Verifies `LibOrganizationInitialization.initialize` fully rolls back organization state when the
    /// admin-operation timelock is invalid.
    function test_initialize_invalidAdminOperationTimelock_rollsBackAllInitializationState() public {
        // Setup: build otherwise-valid initialization params with an out-of-range admin-operation timelock.
        LibOrganizationInitializationHarness harness = _newLibraryHarness();
        InitializationParams memory params = _defaultInitializationParams();
        params.adminOperationTimelockDurationSeconds = TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS - 1;
        uint256 timelockBeforeCall = harness.getAdminOperationTimelockStorage();

        // Call: attempt initialization and expect the exact invalid-timelock revert from the timelock validator.
        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockUtils.InvalidTimelockDuration.selector,
                params.adminOperationTimelockDurationSeconds,
                TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS,
                TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
            )
        );
        harness.initializeViaLibrary(params);

        // Verify: the reverted initialization leaves no persisted sentinel, membership, guardian, timelock, or event.
        assertFalse(harness.isInitializedViaLibrary(), "invalid admin-operation timelock should leave init unset");
        assertFalse(harness.getMemberStatus(MEMBER_1), "invalid admin-operation timelock should roll back members");
        assertFalse(harness.getAdminStatus(ADMIN_1), "invalid admin-operation timelock should roll back admins");
        assertFalse(harness.getGroupStatus(GROUP_ID), "invalid admin-operation timelock should roll back groups");
        assertEq(harness.getGuardianStorage(), address(0), "invalid admin-operation timelock should roll back guardian");
        assertEq(
            harness.getAdminOperationTimelockStorage(),
            timelockBeforeCall,
            "invalid admin-operation timelock should roll back to the pre-call timelock value"
        );
        assertEq(
            _countTopic(vm.getRecordedLogs(), ORG_INITIALIZED_TOPIC),
            0,
            "invalid admin-operation timelock must not emit initialized event"
        );
    }

    /// @dev Verifies `LibOrganizationInitialization.initialize` rolls back member/admin writes when the groups step
    /// reverts, leaving no partial initialization state.
    function test_initializeLibrary_revertInGroupsStep_rollsBackMembersAndAdmins() public {
        // Setup: Build params with valid members/admins but a group containing a non-member address to trigger
        // `MemberDoesNotExist` during group processing (step 3 of initialize).
        LibOrganizationInitializationHarness harness = _newLibraryHarness();
        InitializationParams memory params = _defaultInitializationParams();

        GroupModification[] memory groups = new GroupModification[](1);
        groups[0] = GroupModification({
            groupId: GROUP_ID,
            modificationType: GroupModificationType.Create,
            membersToAdd: buildArray(MEMBER_3),
            membersToRemove: buildEmptyAddressArray()
        });
        params.groups = groups;

        // Call: Attempt initialization that succeeds through members/admins but reverts at group processing.
        vm.recordLogs();
        vm.expectRevert(abi.encodeWithSelector(IOrganizationMembers.MemberDoesNotExist.selector, MEMBER_3));
        harness.initializeViaLibrary(params);

        // Verify: Member and admin writes from earlier steps are rolled back and no event is emitted.
        assertFalse(harness.isInitializedViaLibrary(), "groups revert should leave state uninitialized");
        assertFalse(harness.getMemberStatus(MEMBER_1), "member writes should roll back on groups revert");
        assertFalse(harness.getAdminStatus(ADMIN_1), "admin writes should roll back on groups revert");
        assertEq(
            _countTopic(vm.getRecordedLogs(), ORG_INITIALIZED_TOPIC), 0, "groups revert must not emit initialized event"
        );
    }

    /// @dev Verifies `LibOrganizationInitialization.initialize` rolls back all prior writes (members, admins, groups,
    /// guardian, timelock) when recovery setup reverts.
    function test_initializeLibrary_revertInRecoverySetup_rollsBackAllPriorWrites()
        public
    {
        // Setup: Build params with valid members/admins/groups/guardian but an invalid guardian recovery timelock to
        // trigger `InvalidTimelockDuration` during recovery initialization (step 7 of initialize).
        LibOrganizationInitializationHarness harness = _newLibraryHarness();
        InitializationParams memory params = _defaultInitializationParams();
        params.guardianRecoveryTimelockDurationSeconds = 2 days - 1;
        uint256 timelockBeforeCall = harness.getAdminOperationTimelockStorage();

        // Call: Attempt initialization that succeeds through all steps up to recovery but reverts at guardian recovery
        // timelock validation.
        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockUtils.InvalidTimelockDuration.selector,
                params.guardianRecoveryTimelockDurationSeconds,
                TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS,
                TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
            )
        );
        harness.initializeViaLibrary(params);

        // Verify: All prior initialization writes are rolled back and no event is emitted.
        assertFalse(harness.isInitializedViaLibrary(), "recovery revert should leave state uninitialized");
        assertFalse(harness.getMemberStatus(MEMBER_1), "member writes should roll back on recovery revert");
        assertFalse(harness.getAdminStatus(ADMIN_1), "admin writes should roll back on recovery revert");
        assertFalse(harness.getGroupStatus(GROUP_ID), "group writes should roll back on recovery revert");
        assertEq(harness.getGuardianStorage(), address(0), "guardian write should roll back on recovery revert");
        assertEq(
            harness.getAdminOperationTimelockStorage(),
            timelockBeforeCall,
            "admin-operation timelock write should roll back to the pre-call value on recovery revert"
        );
        assertEq(
            _countTopic(vm.getRecordedLogs(), ORG_INITIALIZED_TOPIC),
            0,
            "recovery revert must not emit initialized event"
        );
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
