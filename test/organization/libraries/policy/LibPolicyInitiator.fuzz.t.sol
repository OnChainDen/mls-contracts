// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {ApproverType, Policy} from "types/PolicyTypes.sol";

import {PolicyLibrariesFuzzTestBase} from "test/organization/libraries/policy/PolicyLibrariesFuzzTestBase.sol";

/**
 * @dev Fuzz tests for `LibPolicyInitiator`.
 */
contract LibPolicyInitiatorFuzzTest is PolicyLibrariesFuzzTestBase {
    /// @dev Verifies `LibPolicyInitiator.isInitiatorAuthorized` enforces any/member/group modes while keeping
    /// non-members unauthorized.
    /// @param rawGroupId The group identifier used for the group-based initiator branch.
    /// @param outsider An address kept outside the organization for the negative branch.
    function testFuzz_FLPI_INIT_81_isInitiatorAuthorized_enforcesAnyMemberAndGroupModes(
        uint256 rawGroupId,
        address outsider
    ) public {
        vm.assume(outsider != initiator1);
        vm.assume(outsider != initiator2);

        uint256 groupId = bound(rawGroupId, 1, type(uint32).max);

        // Setup: configure one any-initiator policy, one exact-member policy, and one group policy.
        Policy memory anyPolicy = _buildBasePolicy();
        anyPolicy.config.initiator.anyInitiator = true;

        Policy memory memberPolicy = _buildBasePolicy();
        memberPolicy.config.initiator.anyInitiator = false;
        memberPolicy.config.initiator.initiatorType = ApproverType.Member;
        memberPolicy.config.initiator.initiatorMember = initiator1;

        Policy memory groupPolicy = _buildBasePolicy();
        groupPolicy.config.initiator.anyInitiator = false;
        groupPolicy.config.initiator.initiatorType = ApproverType.Group;
        groupPolicy.config.initiator.initiatorGroupId = groupId;

        _setMembersAsOrgMembers(buildArray(initiator1, initiator2));
        _setActiveGroupWithMembers(groupId, buildArray(initiator2));
        policyStateHarness.setMemberStatus(outsider, false);

        // Call: evaluate all three policy modes across matching members, mismatching members, and a non-member.
        bool anyMemberAllowed = harness.isInitiatorAuthorizedViaPolicyLibrary(anyPolicy, initiator1);
        bool anyOutsiderAllowed = harness.isInitiatorAuthorizedViaPolicyLibrary(anyPolicy, outsider);

        bool memberExactAllowed = harness.isInitiatorAuthorizedViaPolicyLibrary(memberPolicy, initiator1);
        bool memberOtherAllowed = harness.isInitiatorAuthorizedViaPolicyLibrary(memberPolicy, initiator2);
        bool memberOutsiderAllowed = harness.isInitiatorAuthorizedViaPolicyLibrary(memberPolicy, outsider);

        bool groupMemberAllowed = harness.isInitiatorAuthorizedViaPolicyLibrary(groupPolicy, initiator2);
        bool groupOtherAllowed = harness.isInitiatorAuthorizedViaPolicyLibrary(groupPolicy, initiator1);
        bool groupOutsiderAllowed = harness.isInitiatorAuthorizedViaPolicyLibrary(groupPolicy, outsider);

        // Verify: any/member/group modes behave as configured and non-members always fail closed.
        assertTrue(anyMemberAllowed, "anyInitiator should allow organization members");
        assertFalse(anyOutsiderAllowed, "anyInitiator should still reject non-members");
        assertTrue(memberExactAllowed, "configured initiator member should be authorized");
        assertFalse(memberOtherAllowed, "other members should fail member-mode authorization");
        assertFalse(memberOutsiderAllowed, "non-members should fail member-mode authorization");
        assertTrue(groupMemberAllowed, "members of the configured initiator group should be authorized");
        assertFalse(groupOtherAllowed, "members outside the initiator group should fail");
        assertFalse(groupOutsiderAllowed, "non-members should fail group-mode authorization");
    }
}
