// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganization} from "interfaces/IOrganization.sol";
import {IOrganizationFactory} from "interfaces/IOrganizationFactory.sol";
import {IOrganizationAdmin} from "interfaces/organization/IOrganizationAdmin.sol";
import {IOrganizationInitialization} from "interfaces/organization/IOrganizationInitialization.sol";
import {IOrganizationMembers} from "interfaces/organization/IOrganizationMembers.sol";
import {TimelockUtils} from "libraries/TimelockUtils.sol";
import {OrganizationFactoryHarness} from "test/organization/OrganizationFactory/OrganizationFactoryHarnesses.sol";
import {
    InitializationSuiteBase
} from "test/organization/base/OrganizationInitializationBase/OrganizationInitializationBaseSuiteBase.sol";
import {GroupModification, GroupModificationType, InitializationParams} from "types/CommonTypes.sol";

/**
 * @dev Fuzz coverage for initialization flows.
 */
contract OrganizationFactoryFuzzTest is InitializationSuiteBase {
    /// @dev Verifies valid randomized initialization params establish initialized state, keep admins inside the
    /// member set, and respect optional recovery configuration.
    /// @param seed Entropy seed used to derive deterministic member/admin/recovery addresses.
    /// @param memberCountRaw Fuzzed member-count seed bounded into the valid range.
    /// @param adminCountRaw Fuzzed admin-count seed bounded into the valid range.
    /// @param thresholdRaw Fuzzed voting-threshold seed bounded into the valid range.
    /// @param disableGuardianRecovery Whether guardian recovery should be omitted from initialization params.
    /// @param disableTxRecovery Whether transaction/ERC1271 recovery should be omitted from initialization params.
    /// @param salt Fuzzed CREATE2 salt used for deployment.
    function test_INIT_FUZZ_1__INIT_FUZZ_3__FLOI_INIT_26_fuzzValidParams_initializeSucceedsAndInvariantsHold(
        uint256 seed,
        uint8 memberCountRaw,
        uint8 adminCountRaw,
        uint8 thresholdRaw,
        bool disableGuardianRecovery,
        bool disableTxRecovery,
        bytes32 salt
    ) public {
        // Setup: Bound fuzzed member/admin/threshold values and build matching valid initialization params.
        uint256 memberCount = bound(uint256(memberCountRaw), 1, 8);
        uint256 adminCount = bound(uint256(adminCountRaw), 1, memberCount);
        uint256 threshold = bound(uint256(thresholdRaw), 1, adminCount);

        InitializationParams memory params = _buildFuzzParams(seed, memberCount, adminCount, threshold);
        if (disableGuardianRecovery) {
            params.guardianRecoveryAddress = address(0);
            params.guardianRecoveryTimelockDurationSeconds = 0;
        }
        if (disableTxRecovery) {
            params.transactionAndERC1271RecoveryAddress = address(0);
            params.txRecoveryTimelockDurationSeconds = 0;
        }

        // Call: Deploy an organization through the factory using the fuzzed valid params.
        address deployed = _deployOrganization(salt, params);
        IOrganization organization = IOrganization(deployed);

        // Verify: Initialization succeeds, core invariants hold, and optional recovery omission stays respected.
        assertTrue(organization.isInitialized(), "fuzz deployment should initialize organization");
        assertEq(organization.adminCount(), adminCount, "admin count invariant mismatch");
        assertEq(organization.votingThreshold(), threshold, "threshold invariant mismatch");
        _assertInitializedState(organization, params);

        for (uint256 i = 0; i < adminCount; ++i) {
            assertTrue(organization.isAdmin(params.admins[i]), "admin should be marked admin");
            assertTrue(organization.isMember(params.admins[i]), "every admin should also be a member");
        }
    }

    /// @dev Verifies duplicate members in fuzzed inputs are handled with set semantics during initialization.
    function test_INIT_FUZZ_2_fuzzDuplicateMembers_initializeUsesSetSemantics(uint256 seed, bytes32 salt) public {
        // Setup: Build params containing duplicate member entries and a valid single-admin configuration.
        address a = _deriveAddress(seed, 1);
        address b = _deriveAddress(seed, 2);

        InitializationParams memory params = _defaultInitializationParams();
        params.members = new address[](4);
        params.members[0] = a;
        params.members[1] = a;
        params.members[2] = b;
        params.members[3] = ADMIN_1;
        params.admins = buildArray(ADMIN_1);
        params.votingThreshold = 1;
        params.groups = new GroupModification[](0);

        // Call: Deploy an organization using the duplicate-member initialization params.
        address deployed = _deployOrganization(salt, params);
        IOrganization organization = IOrganization(deployed);

        // Verify: Both unique members exist and duplicate entries do not distort admin accounting.
        assertTrue(organization.isMember(a), "duplicate member should still be present");
        assertTrue(organization.isMember(b), "unique member should be present");
        assertEq(organization.adminCount(), 1, "duplicate members should not affect admin count");
    }

    /// @dev Verifies fuzzed invalid voting thresholds always revert and leave no deployed code.
    function test_INIT_FUZZ_4_fuzzInvalidThresholds_alwaysRevert(
        uint256 seed,
        uint8 adminCountRaw,
        uint8 deltaRaw,
        bool useZeroThreshold,
        bytes32 salt
    ) public {
        // Setup: Build valid params first, then overwrite the threshold with an invalid fuzzed value.
        uint256 adminCount = bound(uint256(adminCountRaw), 1, 6);
        uint256 memberCount = adminCount + 1;
        uint256 badThreshold = useZeroThreshold ? 0 : adminCount + 1 + bound(uint256(deltaRaw), 0, 8);

        InitializationParams memory params = _buildFuzzParams(seed, memberCount, adminCount, 1);
        params.votingThreshold = badThreshold;

        // Call: Attempt deployment with the invalid threshold and expect `InvalidAdminVotingThreshold`.
        vm.expectRevert(
            abi.encodeWithSelector(IOrganizationAdmin.InvalidAdminVotingThreshold.selector, badThreshold, adminCount)
        );
        vm.prank(AUTHORIZED_DEPLOYER);
        factory.deployOrganization(salt, address(implementation), address(whitelist), params);

        // Verify: Failed threshold inputs do not deploy code at the computed address.
        assertEq(_computeOrganizationAddress(salt).code.length, 0, "failed threshold fuzz case should leave no code");
    }

    /// @dev Verifies fuzzed timelocks inside the allowed range are accepted during initialization.
    function test_INIT_FUZZ_5_fuzzTimelocksInsideRange_accepted(
        uint256 seed,
        uint256 adminTimelockRaw,
        uint256 guardianTimelockRaw,
        uint256 txTimelockRaw,
        bytes32 salt
    ) public {
        // Setup: Build valid params and bound all timelock fields inside `[2 days, 30 days]`.
        InitializationParams memory params = _buildFuzzParams(seed, 4, 2, 2);
        params.adminOperationTimelockDurationSeconds = bound(
            adminTimelockRaw, TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS, TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
        );
        params.guardianRecoveryTimelockDurationSeconds = bound(
            guardianTimelockRaw,
            TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS,
            TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
        );
        params.txRecoveryTimelockDurationSeconds = bound(
            txTimelockRaw, TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS, TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
        );

        // Call: Deploy using in-range fuzzed timelocks.
        address deployed = _deployOrganization(salt, params);

        // Verify: Deployment succeeds and reports initialized state.
        assertTrue(IOrganization(deployed).isInitialized(), "in-range timelocks should initialize successfully");
    }

    /// @dev Verifies fuzzed timelocks outside the allowed range revert with `InvalidTimelockDuration`.
    function test_INIT_FUZZ_6_fuzzTimelocksOutsideRange_revertInvalidTimelockDuration(
        uint256 seed,
        uint256 outOfRangeRaw,
        bool belowMin,
        bytes32 salt
    ) public {
        // Setup: Derive an out-of-range timelock either below minimum or above maximum bounds.
        uint256 outOfRange = belowMin
            ? bound(outOfRangeRaw, 0, TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS - 1)
            : bound(
                outOfRangeRaw,
                TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS + 1,
                TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS + 365 days
            );

        InitializationParams memory params = _buildFuzzParams(seed, 4, 2, 2);
        params.adminOperationTimelockDurationSeconds = outOfRange;

        // Call: Attempt deployment with the invalid timelock and expect `InvalidTimelockDuration`.
        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockUtils.InvalidTimelockDuration.selector,
                outOfRange,
                TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS,
                TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
            )
        );
        vm.prank(AUTHORIZED_DEPLOYER);
        factory.deployOrganization(salt, address(implementation), address(whitelist), params);

        // Verify: Out-of-range timelocks prevent deployment code from being persisted.
        assertEq(_computeOrganizationAddress(salt).code.length, 0, "out-of-range timelock should prevent deployment");
    }

    /// @dev Verifies `OrganizationFactory.computeOrganizationAddress` stays deterministic and matches the deployed
    /// proxy address for fuzzed salts.
    /// @param salt Fuzzed CREATE2 salt used to precompute and deploy the organization address.
    function testFuzz_INIT_FUZZ_7__FOF_DEPLOY_129_fuzzComputeAddress_matchesActualDeployment(bytes32 salt) public {
        // Setup: Prepare valid initialization params and precompute the expected deployment address for the fuzzed
        // salt.
        InitializationParams memory params = _defaultInitializationParams();
        address expected = _computeOrganizationAddress(salt);
        address repeated = _computeOrganizationAddress(salt);

        // Call: Deploy the organization for the same fuzzed salt.
        address deployed = _deployOrganization(salt, params);

        // Verify: address computation should be deterministic and match the deployed address exactly.
        assertEq(expected, repeated, "computeOrganizationAddress should be deterministic");
        assertEq(deployed, expected, "computeAddress should match deployment for all salts");
    }

    /// @dev Verifies a failing initialization sub-step leaves no partial organization state and allows deterministic
    /// retry with the same tuple.
    /// @param salt Fuzzed CREATE2 salt reused across the failing and successful deployment attempts.
    /// @param thresholdDeltaRaw Fuzzed delta used to push the invalid voting threshold above the admin count.
    function testFuzz_INIT_FUZZ_8__FLOI_INIT_27__FOF_DINIT_131_fuzzFailedThenRetry_sameTupleCanSucceed(
        bytes32 salt,
        uint8 thresholdDeltaRaw
    ) public {
        // Setup: Build an invalid-threshold params set and a valid params set for the same deployment tuple.
        InitializationParams memory invalidParams = _defaultInitializationParams();
        invalidParams.votingThreshold = invalidParams.admins.length + 1 + bound(uint256(thresholdDeltaRaw), 0, 8);

        InitializationParams memory validParams = _defaultInitializationParams();

        // Call: Fail once with invalid params, then deploy again with valid params using the same salt.
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationAdmin.InvalidAdminVotingThreshold.selector,
                invalidParams.votingThreshold,
                invalidParams.admins.length
            )
        );
        vm.prank(AUTHORIZED_DEPLOYER);
        factory.deployOrganization(salt, address(implementation), address(whitelist), invalidParams);

        address deployed = _deployOrganization(salt, validParams);

        // Verify: Retry deployment remains deterministic and succeeds after the prior revert.
        assertEq(deployed, _computeOrganizationAddress(salt), "retry should keep deterministic address");
        assertTrue(IOrganization(deployed).isInitialized(), "retry should succeed after failed attempt");
    }

    /// @dev Verifies failing member/group/recovery validation branches revert atomically and leave the deployment
    /// tuple reusable.
    /// @param seed Entropy seed used to derive deterministic addresses.
    /// @param failureModeRaw Fuzzed selector choosing which initialization sub-step should fail.
    /// @param salt Fuzzed CREATE2 salt reused across the failing and retry deployment attempts.
    function testFuzz_FLOI_INIT_27_failingValidationSubsteps_revertAtomicallyAndAllowRetry(
        uint256 seed,
        uint8 failureModeRaw,
        bytes32 salt
    ) public {
        // Setup: derive one valid payload and one invalid payload for the same deployment tuple.
        InitializationParams memory invalidParams = _buildFuzzParams(seed, 4, 2, 2);
        InitializationParams memory validParams = _buildFuzzParams(seed, 4, 2, 2);
        uint256 failureMode = bound(uint256(failureModeRaw), 0, 4);
        bytes memory expectedRevertData;

        if (failureMode == 0) {
            invalidParams.members = buildEmptyAddressArray();
            expectedRevertData = abi.encodeWithSelector(IOrganizationInitialization.NoMembersProvided.selector);
        } else if (failureMode == 1) {
            address outsider = _deriveAddress(seed, 9001);
            for (uint256 i = 0; i < invalidParams.members.length; ++i) {
                if (outsider == invalidParams.members[i]) {
                    outsider = _deriveAddress(seed + 1, 9001);
                    break;
                }
            }
            invalidParams.admins[0] = outsider;
            expectedRevertData =
                abi.encodeWithSelector(IOrganizationAdmin.AdminNotMember.selector, invalidParams.admins[0]);
        } else if (failureMode == 2) {
            invalidParams.groups = new GroupModification[](1);
            invalidParams.groups[0] = GroupModification({
                groupId: GROUP_ID + 1,
                modificationType: GroupModificationType.Create,
                membersToAdd: buildArray(address(0)),
                membersToRemove: buildEmptyAddressArray()
            });
            expectedRevertData = abi.encodeWithSelector(IOrganizationMembers.InvalidMemberAddress.selector, address(0));
        } else if (failureMode == 3) {
            invalidParams.guardianRecoveryAddress = _deriveAddress(seed, 9002);
            invalidParams.guardianRecoveryTimelockDurationSeconds = 0;
            expectedRevertData = abi.encodeWithSelector(
                TimelockUtils.InvalidTimelockDuration.selector,
                0,
                TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS,
                TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
            );
        } else {
            invalidParams.transactionAndERC1271RecoveryAddress = _deriveAddress(seed, 9003);
            invalidParams.txRecoveryTimelockDurationSeconds = 0;
            expectedRevertData = abi.encodeWithSelector(
                TimelockUtils.InvalidTimelockDuration.selector,
                0,
                TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS,
                TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
            );
        }

        // Call: attempt deployment with the selected failing sub-step, then retry with the valid payload.
        vm.expectRevert(expectedRevertData);
        vm.prank(AUTHORIZED_DEPLOYER);
        factory.deployOrganization(salt, address(implementation), address(whitelist), invalidParams);

        // Verify: the failing path should leave no code behind at the deterministic address.
        assertEq(_computeOrganizationAddress(salt).code.length, 0, "failing initialize should leave no deployed code");

        address deployed = _deployOrganization(salt, validParams);

        // Verify: the same deployment tuple remains reusable after the revert.
        assertEq(deployed, _computeOrganizationAddress(salt), "retry should keep the deterministic deployment tuple");
        assertTrue(IOrganization(deployed).isInitialized(), "retry after failed validation should still initialize");
    }

    /// @dev Verifies only the configured deployer can successfully deploy organizations.
    /// @param caller Fuzzed caller constrained away from the authorized deployer.
    /// @param salt Fuzzed CREATE2 salt used in the failed deployment attempt.
    function testFuzz_FOF_DEPLOY_130_deployOrganization_onlyAuthorizedDeployerCanDeploy(address caller, bytes32 salt)
        public
    {
        // Setup: constrain the caller away from the configured authorized deployer.
        vm.assume(caller != AUTHORIZED_DEPLOYER);
        InitializationParams memory params = _defaultInitializationParams();

        // Call: attempt deployment from a non-deployer address, expecting `UnauthorizedDeployer`.
        vm.expectRevert(IOrganizationInitialization.UnauthorizedDeployer.selector);
        vm.prank(caller);
        factory.deployOrganization(salt, address(implementation), address(whitelist), params);

        // Verify: unauthorized callers should never be able to deploy organizations.
    }

    /// @dev Builds a valid initialization payload from fuzzed cardinalities and threshold values.
    /// @param seed Entropy seed used to derive deterministic participant/recovery addresses.
    /// @param memberCount Number of unique members to include.
    /// @param adminCount Number of admins selected from the member set.
    /// @param threshold Voting threshold constrained to the admin count.
    /// @return params Initialization payload suitable for successful deployment.
    function _buildFuzzParams(uint256 seed, uint256 memberCount, uint256 adminCount, uint256 threshold)
        internal
        view
        returns (InitializationParams memory params)
    {
        // Generate a unique member set, then choose the first `adminCount` members as admins.
        params.members = _buildUniqueAddresses(seed, memberCount);
        params.admins = new address[](adminCount);
        for (uint256 i = 0; i < adminCount; ++i) {
            params.admins[i] = params.members[i];
        }

        // Keep groups empty and apply deterministic guardian/recovery defaults for fuzz stability.
        params.votingThreshold = threshold;
        params.groups = new GroupModification[](0);
        params.guardian = _deriveAddress(seed, 7001);
        params.accountImplementation = address(accountImplementation);
        params.adminOperationTimelockDurationSeconds = 2 days;
        params.transactionAndERC1271RecoveryAddress = _deriveAddress(seed, 7002);
        params.txRecoveryTimelockDurationSeconds = 2 days;
        params.guardianRecoveryAddress = _deriveAddress(seed, 7003);
        params.guardianRecoveryTimelockDurationSeconds = 2 days;
    }

    /// @dev Builds a deterministic array of non-zero addresses while de-duplicating collisions.
    /// @param seed Entropy seed used for address derivation.
    /// @param count Number of unique addresses to return.
    /// @return values Array of unique derived addresses.
    function _buildUniqueAddresses(uint256 seed, uint256 count) internal pure returns (address[] memory values) {
        values = new address[](count);
        for (uint256 i = 0; i < count; ++i) {
            values[i] = _deriveAddress(seed, i + 1);
            // Resolve rare collisions by deriving from a shifted seed.
            for (uint256 j = 0; j < i; ++j) {
                if (values[j] == values[i]) {
                    values[i] = _deriveAddress(seed + 1, i + 1);
                }
            }
        }
    }

    /// @dev Derives a deterministic non-zero address from a seed/nonce pair.
    /// @param seed Entropy seed for derivation.
    /// @param nonce Per-seed nonce to produce distinct addresses.
    /// @return Derived non-zero address.
    function _deriveAddress(uint256 seed, uint256 nonce) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encode(seed, nonce))) | uint256(1)));
    }
}
