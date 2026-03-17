// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationAdmin} from "interfaces/organization/IOrganizationAdmin.sol";
import {IOrganizationInitialization} from "interfaces/organization/IOrganizationInitialization.sol";
import {IOrganizationMembers} from "interfaces/organization/IOrganizationMembers.sol";
import {TimelockUtils} from "libraries/TimelockUtils.sol";
import {
    LibOrganizationInitializationHarness
} from "test/organization/OrganizationFactory/OrganizationFactoryHarnesses.sol";
import {
    InitializationSuiteBase
} from "test/organization/base/OrganizationInitializationBase/OrganizationInitializationBaseSuiteBase.sol";
import {GroupModification, GroupModificationType, InitializationParams} from "types/CommonTypes.sol";

/**
 * @dev Fuzz tests for `LibOrganizationInitialization`.
 */
contract LibOrganizationInitializationFuzzTest is InitializationSuiteBase {
    /// @dev Verifies valid randomized initialization params establish core organization invariants in one call.
    function testFuzz_FLOI_INIT_26_initialize_validRandomizedParamsEstablishCoreInvariants(
        uint256 seed,
        uint8 memberCountRaw,
        uint8 adminCountRaw,
        uint8 thresholdRaw,
        bool includeGroups,
        bool configureGuardianRecovery,
        bool configureTxRecovery,
        bool useMaxTimelocks
    ) public {
        // Setup: build a valid randomized initialization payload with optional groups and recovery configuration.
        uint256 memberCount = bound(uint256(memberCountRaw), 1, 8);
        uint256 adminCount = bound(uint256(adminCountRaw), 1, memberCount);
        uint256 threshold = bound(uint256(thresholdRaw), 1, adminCount);
        InitializationParams memory params = _buildFuzzParams(
            seed,
            memberCount,
            adminCount,
            threshold,
            includeGroups,
            configureGuardianRecovery,
            configureTxRecovery,
            useMaxTimelocks
        );
        LibOrganizationInitializationHarness harness = _newLibraryHarness();

        // Call: initialize the library harness with the randomized valid payload.
        harness.initializeViaLibrary(params);

        // Verify: initialization should succeed once and persist the expected member, admin, guardian, timelock, and
        // optional recovery state.
        assertTrue(harness.isInitializedViaLibrary(), "valid initialization should set the sentinel");
        assertEq(harness.getAdminCountStorage(), adminCount, "admin count should match randomized params");
        assertEq(harness.getVotingThresholdStorage(), threshold, "threshold should match randomized params");
        assertEq(harness.getGuardianStorage(), params.guardian, "guardian should persist exactly");
        assertEq(
            harness.getAdminOperationTimelockStorage(),
            params.adminOperationTimelockDurationSeconds,
            "admin-operation timelock should persist exactly"
        );
        assertEq(
            harness.getAccountImplementationStorage(),
            params.accountImplementation,
            "account implementation should persist exactly"
        );

        for (uint256 i = 0; i < params.members.length; ++i) {
            assertTrue(harness.getMemberStatus(params.members[i]), "every configured member should be persisted");
        }

        for (uint256 i = 0; i < params.admins.length; ++i) {
            assertTrue(harness.getAdminStatus(params.admins[i]), "every configured admin should be persisted");
            assertTrue(harness.getMemberStatus(params.admins[i]), "every admin should also be a persisted member");
        }

        if (includeGroups) {
            assertTrue(harness.getGroupStatus(GROUP_ID), "configured group should be created");
            assertTrue(
                harness.getGroupMemberStatus(GROUP_ID, params.members[0]), "configured group member should be persisted"
            );
        } else {
            assertFalse(harness.getGroupStatus(GROUP_ID), "omitted groups should remain unset");
        }

        if (configureGuardianRecovery) {
            assertEq(
                harness.getGuardianRecoveryStateViaStorage().recoveryAddress,
                params.guardianRecoveryAddress,
                "guardian recovery address should persist when configured"
            );
            assertEq(
                harness.getGuardianRecoveryStateViaStorage().timelockDurationSeconds,
                params.guardianRecoveryTimelockDurationSeconds,
                "guardian recovery timelock should persist when configured"
            );
        } else {
            assertEq(
                harness.getGuardianRecoveryStateViaStorage().recoveryAddress,
                address(0),
                "guardian recovery should remain deferred when omitted"
            );
            assertEq(
                harness.getGuardianRecoveryStateViaStorage().timelockDurationSeconds,
                0,
                "guardian recovery timelock should remain unset when omitted"
            );
        }

        if (configureTxRecovery) {
            assertEq(
                harness.getTxRecoveryStateViaStorage().recoveryAddress,
                params.transactionAndERC1271RecoveryAddress,
                "tx recovery address should persist when configured"
            );
            assertEq(
                harness.getTxRecoveryStateViaStorage().timelockDurationSeconds,
                params.txRecoveryTimelockDurationSeconds,
                "tx recovery timelock should persist when configured"
            );
        } else {
            assertEq(
                harness.getTxRecoveryStateViaStorage().recoveryAddress,
                address(0),
                "tx recovery should remain deferred when omitted"
            );
            assertEq(
                harness.getTxRecoveryStateViaStorage().timelockDurationSeconds,
                0,
                "tx recovery timelock should remain unset when omitted"
            );
        }
    }

    /// @dev Verifies failing member, admin, group, or recovery validation branches revert atomically with no partial
    /// persisted organization state.
    function testFuzz_FLOI_INIT_27_initialize_failingSubStepsRevertAtomically(
        uint256 seed,
        uint8 failureModeRaw,
        bool belowMinTimelock
    ) public {
        // Setup: build a valid baseline payload, then mutate one sub-step into a guaranteed failure branch.
        uint8 failureMode = uint8(failureModeRaw % 5);
        InitializationParams memory params = _buildFuzzParams(seed, 4, 2, 2, true, true, true, false);
        LibOrganizationInitializationHarness harness = _newLibraryHarness();

        bytes memory expectedRevertData;
        if (failureMode == 0) {
            params.members = buildEmptyAddressArray();
            expectedRevertData = abi.encodeWithSelector(IOrganizationInitialization.NoMembersProvided.selector);
        } else if (failureMode == 1) {
            address outsider = _deriveAddress(seed, 10_001);
            params.admins[0] = outsider;
            expectedRevertData = abi.encodeWithSelector(IOrganizationAdmin.AdminNotMember.selector, outsider);
        } else if (failureMode == 2) {
            address outsider = _deriveAddress(seed, 10_002);
            params.groups[0] = GroupModification({
                groupId: GROUP_ID,
                modificationType: GroupModificationType.Create,
                membersToAdd: buildArray(params.members[0], outsider),
                membersToRemove: buildEmptyAddressArray()
            });
            expectedRevertData = abi.encodeWithSelector(IOrganizationMembers.MemberDoesNotExist.selector, outsider);
        } else if (failureMode == 3) {
            uint256 invalidTimelock = belowMinTimelock ? 2 days - 1 : 30 days + 1;
            params.guardianRecoveryTimelockDurationSeconds = invalidTimelock;
            expectedRevertData = abi.encodeWithSelector(
                TimelockUtils.InvalidTimelockDuration.selector, invalidTimelock, 2 days, 30 days
            );
        } else {
            uint256 invalidTimelock = belowMinTimelock ? 2 days - 1 : 30 days + 1;
            params.txRecoveryTimelockDurationSeconds = invalidTimelock;
            expectedRevertData = abi.encodeWithSelector(
                TimelockUtils.InvalidTimelockDuration.selector, invalidTimelock, 2 days, 30 days
            );
        }

        // Call: execute the failing initialization branch and expect the exact row-specific revert.
        vm.recordLogs();
        vm.expectRevert(expectedRevertData);
        harness.initializeViaLibrary(params);

        // Verify: no partial member/admin/group/guardian/recovery writes or initialization events should persist.
        _assertRolledBackState(harness);
        assertEq(_countTopic(vm.getRecordedLogs(), ORG_INITIALIZED_TOPIC), 0, "reverted init should emit no event");
    }

    /// @dev Deploys a library harness with only the prerequisite deployer and whitelist storage seeded.
    /// @return harness Configured library harness instance.
    function _newLibraryHarness() internal returns (LibOrganizationInitializationHarness harness) {
        harness = new LibOrganizationInitializationHarness();
        harness.setWhitelistAddressStorage(address(whitelist));
        harness.setDeployerAddressStorage(AUTHORIZED_DEPLOYER);
    }

    /// @dev Builds valid randomized initialization params for library-level initialization coverage.
    function _buildFuzzParams(
        uint256 seed,
        uint256 memberCount,
        uint256 adminCount,
        uint256 threshold,
        bool includeGroups,
        bool configureGuardianRecovery,
        bool configureTxRecovery,
        bool useMaxTimelocks
    ) internal view returns (InitializationParams memory params) {
        // Setup: derive a unique member set and choose the first `adminCount` members as admins.
        params.members = _buildUniqueAddresses(seed, memberCount);
        params.admins = new address[](adminCount);
        for (uint256 i = 0; i < adminCount; ++i) {
            params.admins[i] = params.members[i];
        }

        // Setup: optionally create one deterministic group whose members are already in the org member set.
        if (includeGroups) {
            params.groups = new GroupModification[](1);
            params.groups[0] = GroupModification({
                groupId: GROUP_ID,
                modificationType: GroupModificationType.Create,
                membersToAdd: buildArray(params.members[0]),
                membersToRemove: buildEmptyAddressArray()
            });
        } else {
            params.groups = new GroupModification[](0);
        }

        // Setup: configure guardian, whitelisted account implementation, timelocks, and optional recovery addresses.
        uint256 durationSeconds = useMaxTimelocks ? 30 days : 2 days;
        params.votingThreshold = threshold;
        params.guardian = _deriveAddress(seed, 9001);
        params.accountImplementation = address(accountImplementation);
        params.adminOperationTimelockDurationSeconds = durationSeconds;
        params.guardianRecoveryAddress = configureGuardianRecovery ? _deriveAddress(seed, 9002) : address(0);
        params.guardianRecoveryTimelockDurationSeconds = configureGuardianRecovery ? durationSeconds : 0;
        params.transactionAndERC1271RecoveryAddress = configureTxRecovery ? _deriveAddress(seed, 9003) : address(0);
        params.txRecoveryTimelockDurationSeconds = configureTxRecovery ? durationSeconds : 0;
    }

    /// @dev Builds a deterministic array of unique non-zero addresses from a seed.
    function _buildUniqueAddresses(uint256 seed, uint256 count) internal pure returns (address[] memory values) {
        values = new address[](count);
        for (uint256 i = 0; i < count; ++i) {
            values[i] = _deriveAddress(seed, i + 1);
            for (uint256 j = 0; j < i; ++j) {
                if (values[j] == values[i]) {
                    values[i] = _deriveAddress(seed + 1, i + 1);
                }
            }
        }
    }

    /// @dev Derives a deterministic non-zero address from a seed/nonce pair.
    function _deriveAddress(uint256 seed, uint256 nonce) internal pure returns (address derivedAddress) {
        derivedAddress = address(uint160(uint256(keccak256(abi.encode(seed, nonce))) | uint256(1)));
    }

    /// @dev Asserts that all initialization state remained rolled back after a revert.
    /// @param harness Library harness whose storage should still be pristine.
    function _assertRolledBackState(LibOrganizationInitializationHarness harness) internal view {
        assertFalse(harness.isInitializedViaLibrary(), "reverted init should leave the sentinel unset");
        assertEq(harness.getAdminCountStorage(), 0, "reverted init should not persist admin count");
        assertEq(harness.getVotingThresholdStorage(), 0, "reverted init should not persist voting threshold");
        assertEq(harness.getGuardianStorage(), address(0), "reverted init should not persist guardian");
        assertEq(
            harness.getAdminOperationTimelockStorage(), 0, "reverted init should not persist admin-operation timelock"
        );
        assertEq(
            harness.getAccountImplementationStorage(),
            address(0),
            "reverted init should not persist account implementation"
        );
        assertFalse(harness.getGroupStatus(GROUP_ID), "reverted init should not create groups");
        assertEq(
            harness.getGuardianRecoveryStateViaStorage().recoveryAddress,
            address(0),
            "reverted init should not persist guardian recovery"
        );
        assertEq(
            harness.getTxRecoveryStateViaStorage().recoveryAddress,
            address(0),
            "reverted init should not persist tx recovery"
        );
    }
}
