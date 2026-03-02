// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganization} from "interfaces/IOrganization.sol";
import {IOrganizationAdmin} from "interfaces/organization/IOrganizationAdmin.sol";
import {IOrganizationInitialization} from "interfaces/organization/IOrganizationInitialization.sol";
import {TimelockUtils} from "libraries/TimelockUtils.sol";
import {
    InitializationSuiteBase
} from "test/organization/base/OrganizationInitializationBase/OrganizationInitializationBaseSuiteBase.sol";
import {GroupModification, InitializationParams} from "types/CommonTypes.sol";

/**
 * @dev Fuzz coverage for initialization flows.
 */
contract OrganizationFactoryFuzzTest is InitializationSuiteBase {
    /// @dev Verifies fuzzed valid initialization params deploy successfully and preserve admin/member invariants.
    function test_INIT_FUZZ_1__INIT_FUZZ_3_fuzzValidParams_initializeSucceedsAndInvariantsHold(
        uint256 seed,
        uint8 memberCountRaw,
        uint8 adminCountRaw,
        uint8 thresholdRaw,
        bytes32 salt
    ) public {
        // Setup: Bound fuzzed member/admin/threshold values and build matching valid initialization params.
        uint256 memberCount = bound(uint256(memberCountRaw), 1, 8);
        uint256 adminCount = bound(uint256(adminCountRaw), 1, memberCount);
        uint256 threshold = bound(uint256(thresholdRaw), 1, adminCount);

        InitializationParams memory params = _buildFuzzParams(seed, memberCount, adminCount, threshold);

        // Call: Deploy an organization through the factory using the fuzzed valid params.
        address deployed = _deployOrganization(salt, params);
        IOrganization organization = IOrganization(deployed);

        // Verify: Initialization succeeds and admin/threshold/member invariants hold for all fuzzed values.
        assertTrue(organization.isInitialized(), "fuzz deployment should initialize organization");
        assertEq(organization.adminCount(), adminCount, "admin count invariant mismatch");
        assertEq(organization.votingThreshold(), threshold, "threshold invariant mismatch");

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

    /// @dev Verifies fuzzed salts keep `computeOrganizationAddress` aligned with actual deployment addresses.
    function test_INIT_FUZZ_7_fuzzComputeAddress_matchesActualDeployment(bytes32 salt) public {
        // Setup: Prepare valid initialization params and precompute the expected deployment address for the fuzzed
        // salt.
        InitializationParams memory params = _defaultInitializationParams();
        address expected = _computeOrganizationAddress(salt);

        // Call: Deploy the organization for the same fuzzed salt.
        address deployed = _deployOrganization(salt, params);

        // Verify: The deployed address always matches the precomputed CREATE2 address.
        assertEq(deployed, expected, "computeAddress should match deployment for all salts");
    }

    /// @dev Verifies a failed initialization attempt can be retried successfully with the same fuzzed tuple.
    function test_INIT_FUZZ_8_fuzzFailedThenRetry_sameTupleCanSucceed(bytes32 salt, uint8 thresholdDeltaRaw) public {
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
