// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {PolicyLibrariesSuiteBase} from "test/organization/libraries/policy/PolicyLibrariesSuiteBase.sol";
import {ApproverType, Policy} from "types/PolicyTypes.sol";

/**
 * @dev Unit tests for `LibPolicyInitiator` wrappers.
 */
contract LibPolicyInitiatorTest is PolicyLibrariesSuiteBase {
    /// @dev [LPI-1] Member-typed initiator returns true for exact configured member that is an org member.
    function test_isInitiatorAuthorized_memberTypedMatchingMemberAndOrgMember_returnsTrue() public {
        Policy memory policy = _buildBasePolicy();
        policy.config.initiator.anyInitiator = false;
        policy.config.initiator.initiatorType = ApproverType.Member;
        policy.config.initiator.initiatorMember = initiator1;

        _setMembersAsOrgMembers(buildArray(initiator1));

        bool authorized = harness.isInitiatorAuthorizedViaPolicyLibrary(policy, initiator1);
        assertTrue(authorized, "configured member initiator should be authorized");
    }

    /// @dev [LPI-2] Member-typed initiator returns false for non-matching address.
    function test_isInitiatorAuthorized_memberTypedNonMatchingAddress_returnsFalse() public {
        Policy memory policy = _buildBasePolicy();
        policy.config.initiator.anyInitiator = false;
        policy.config.initiator.initiatorType = ApproverType.Member;
        policy.config.initiator.initiatorMember = initiator1;

        _setMembersAsOrgMembers(buildArray(initiator1, initiator2));

        bool authorized = harness.isInitiatorAuthorizedViaPolicyLibrary(policy, initiator2);
        assertFalse(authorized, "non-configured member should not be authorized");
    }

    /// @dev [LPI-3] Member-typed initiator returns false when configured address is not an org member.
    function test_isInitiatorAuthorized_memberTypedMatchingAddressButNotOrgMember_returnsFalse() public {
        Policy memory policy = _buildBasePolicy();
        policy.config.initiator.anyInitiator = false;
        policy.config.initiator.initiatorType = ApproverType.Member;
        policy.config.initiator.initiatorMember = initiator1;

        policyStateHarness.setMemberStatus(initiator1, false);

        bool authorized = harness.isInitiatorAuthorizedViaPolicyLibrary(policy, initiator1);
        assertFalse(authorized, "configured initiator must still be an org member");
    }

    /// @dev [LPI-4] Group-typed initiator returns true for member of existing group.
    function test_isInitiatorAuthorized_groupTypedExistingGroupMember_returnsTrue() public {
        uint256 initiatorGroupId = 1101;
        Policy memory policy = _buildBasePolicy();
        policy.config.initiator.anyInitiator = false;
        policy.config.initiator.initiatorType = ApproverType.Group;
        policy.config.initiator.initiatorGroupId = initiatorGroupId;

        _setActiveGroupWithMembers(initiatorGroupId, buildArray(initiator1));

        bool authorized = harness.isInitiatorAuthorizedViaPolicyLibrary(policy, initiator1);
        assertTrue(authorized, "group member initiator should be authorized");
    }

    /// @dev [LPI-5] Group-typed initiator returns false for non-member of existing group.
    function test_isInitiatorAuthorized_groupTypedExistingGroupNonMember_returnsFalse() public {
        uint256 initiatorGroupId = 1102;
        Policy memory policy = _buildBasePolicy();
        policy.config.initiator.anyInitiator = false;
        policy.config.initiator.initiatorType = ApproverType.Group;
        policy.config.initiator.initiatorGroupId = initiatorGroupId;

        _setActiveGroupWithMembers(initiatorGroupId, buildArray(initiator1));
        _setMembersAsOrgMembers(buildArray(initiator2));

        bool authorized = harness.isInitiatorAuthorizedViaPolicyLibrary(policy, initiator2);
        assertFalse(authorized, "org member outside initiator group should not be authorized");
    }

    /// @dev [LPI-6] Group-typed initiator returns false for non-existent group.
    function test_isInitiatorAuthorized_groupTypedNonExistentGroup_returnsFalse() public {
        uint256 initiatorGroupId = 1103;
        Policy memory policy = _buildBasePolicy();
        policy.config.initiator.anyInitiator = false;
        policy.config.initiator.initiatorType = ApproverType.Group;
        policy.config.initiator.initiatorGroupId = initiatorGroupId;

        _setMembersAsOrgMembers(buildArray(initiator1));

        bool authorized = harness.isInitiatorAuthorizedViaPolicyLibrary(policy, initiator1);
        assertFalse(authorized, "non-existent initiator group should fail closed");
    }

    /// @dev [LPI-7] Desired behavior: `anyInitiator` should still require organization membership.
    function test_isInitiatorAuthorized_anyInitiatorStillRequiresOrgMembership_desired() public {
        Policy memory policy = _buildBasePolicy();
        policy.config.initiator.anyInitiator = true;

        address nonMember = address(0xA701);
        policyStateHarness.setMemberStatus(nonMember, false);

        bool authorized = harness.isInitiatorAuthorizedViaPolicyLibrary(policy, nonMember);
        assertFalse(authorized, "desired behavior: non-member should not be authorized even with anyInitiator");
    }

    /// @dev [LPI-8] Zero-address initiator fails closed.
    function test_isInitiatorAuthorized_zeroAddressInitiator_returnsFalse() public {
        Policy memory policy = _buildBasePolicy();
        policy.config.initiator.anyInitiator = false;
        policy.config.initiator.initiatorType = ApproverType.Member;
        policy.config.initiator.initiatorMember = initiator1;

        bool authorized = harness.isInitiatorAuthorizedViaPolicyLibrary(policy, address(0));
        assertFalse(authorized, "zero-address initiator should fail closed");
    }

    /// @dev [LPI-9] Unknown initiator enum fails closed.
    function test_isInitiatorAuthorized_invalidInitiatorEnum_returnsFalse() public {
        Policy memory policy = _buildBasePolicy();
        policy.config.initiator.anyInitiator = false;

        _setMembersAsOrgMembers(buildArray(initiator1));

        bool authorized =
            harness.isInitiatorAuthorizedViaPolicyLibraryRawInitiatorType(policy, type(uint256).max, initiator1);
        assertFalse(authorized, "invalid initiator type should fail closed");
    }
}
