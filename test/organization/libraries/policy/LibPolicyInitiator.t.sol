// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {PolicyLibrariesSuiteBase} from "test/organization/libraries/policy/PolicyLibrariesSuiteBase.sol";
import {ApproverType, Policy} from "types/PolicyTypes.sol";

/**
 * @dev Unit tests for `LibPolicyInitiator` wrappers.
 */
contract LibPolicyInitiatorTest is PolicyLibrariesSuiteBase {
    /// @dev Verifies that member-typed initiator returns true for exact configured member that is an org member.
    function test_isInitiatorAuthorized_memberTypedMatchingMemberAndOrgMember_returnsTrue() public {
        // Setup: configure a valid fixture for member-typed initiator returns true for exact configured member that is
        // an org member.
        Policy memory policy = _buildBasePolicy();
        policy.config.initiator.anyInitiator = false;
        policy.config.initiator.initiatorType = ApproverType.Member;
        policy.config.initiator.initiatorMember = initiator1;

        _setMembersAsOrgMembers(buildArray(initiator1));

        // Call: execute `isInitiatorAuthorizedViaPolicyLibrary` with the happy-path payload.
        bool authorized = harness.isInitiatorAuthorizedViaPolicyLibrary(policy, initiator1);
        // Verify: assert the expected success result and state updates.
        assertTrue(authorized, "configured member initiator should be authorized");
    }

    /// @dev Verifies that member-typed initiator returns false for non-matching address.
    function test_isInitiatorAuthorized_memberTypedNonMatchingAddress_returnsFalse() public {
        // Setup: build fixture inputs where member-typed initiator returns false for non-matching address should be
        // denied.
        Policy memory policy = _buildBasePolicy();
        policy.config.initiator.anyInitiator = false;
        policy.config.initiator.initiatorType = ApproverType.Member;
        policy.config.initiator.initiatorMember = initiator1;

        _setMembersAsOrgMembers(buildArray(initiator1, initiator2));

        // Call: execute `isInitiatorAuthorizedViaPolicyLibrary` and capture the authorization decision.
        bool authorized = harness.isInitiatorAuthorizedViaPolicyLibrary(policy, initiator2);
        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(authorized, "non-configured member should not be authorized");
    }

    /// @dev Verifies that member-typed initiator returns false when configured address is not an org member.
    function test_isInitiatorAuthorized_memberTypedMatchingAddressButNotOrgMember_returnsFalse() public {
        // Setup: build fixture inputs where member-typed initiator returns false when configured address is not an org
        // member should be denied.
        Policy memory policy = _buildBasePolicy();
        policy.config.initiator.anyInitiator = false;
        policy.config.initiator.initiatorType = ApproverType.Member;
        policy.config.initiator.initiatorMember = initiator1;

        policyStateHarness.setMemberStatus(initiator1, false);

        // Call: execute `isInitiatorAuthorizedViaPolicyLibrary` and capture the authorization decision.
        bool authorized = harness.isInitiatorAuthorizedViaPolicyLibrary(policy, initiator1);
        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(authorized, "configured initiator must still be an org member");
    }

    /// @dev Verifies that group-typed initiator returns true for member of existing group.
    function test_isInitiatorAuthorized_groupTypedExistingGroupMember_returnsTrue() public {
        // Setup: configure a valid fixture for group-typed initiator returns true for member of existing group.
        uint256 initiatorGroupId = 1101;
        Policy memory policy = _buildBasePolicy();
        policy.config.initiator.anyInitiator = false;
        policy.config.initiator.initiatorType = ApproverType.Group;
        policy.config.initiator.initiatorGroupId = initiatorGroupId;

        _setActiveGroupWithMembers(initiatorGroupId, buildArray(initiator1));

        // Call: execute `isInitiatorAuthorizedViaPolicyLibrary` with the happy-path payload.
        bool authorized = harness.isInitiatorAuthorizedViaPolicyLibrary(policy, initiator1);
        // Verify: assert the expected success result and state updates.
        assertTrue(authorized, "group member initiator should be authorized");
    }

    /// @dev Verifies that group-typed initiator returns false for non-member of existing group.
    function test_isInitiatorAuthorized_groupTypedExistingGroupNonMember_returnsFalse() public {
        // Setup: build fixture inputs where group-typed initiator returns false for non-member of existing group should
        // be denied.
        uint256 initiatorGroupId = 1102;
        Policy memory policy = _buildBasePolicy();
        policy.config.initiator.anyInitiator = false;
        policy.config.initiator.initiatorType = ApproverType.Group;
        policy.config.initiator.initiatorGroupId = initiatorGroupId;

        _setActiveGroupWithMembers(initiatorGroupId, buildArray(initiator1));
        _setMembersAsOrgMembers(buildArray(initiator2));

        // Call: execute `isInitiatorAuthorizedViaPolicyLibrary` and capture the authorization decision.
        bool authorized = harness.isInitiatorAuthorizedViaPolicyLibrary(policy, initiator2);
        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(authorized, "org member outside initiator group should not be authorized");
    }

    /// @dev Verifies that group-typed initiator returns false for non-existent group.
    function test_isInitiatorAuthorized_groupTypedNonExistentGroup_returnsFalse() public {
        // Setup: build fixture inputs where group-typed initiator returns false for non-existent group should be
        // denied.
        uint256 initiatorGroupId = 1103;
        Policy memory policy = _buildBasePolicy();
        policy.config.initiator.anyInitiator = false;
        policy.config.initiator.initiatorType = ApproverType.Group;
        policy.config.initiator.initiatorGroupId = initiatorGroupId;

        _setMembersAsOrgMembers(buildArray(initiator1));

        // Call: execute `isInitiatorAuthorizedViaPolicyLibrary` and capture the authorization decision.
        bool authorized = harness.isInitiatorAuthorizedViaPolicyLibrary(policy, initiator1);
        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(authorized, "non-existent initiator group should fail closed");
    }

    /// @dev Verifies that desired behavior: `anyInitiator` should still require organization membership.
    function test_isInitiatorAuthorized_anyInitiatorStillRequiresOrgMembership_desired() public {
        // Setup: build fixture inputs where desired behavior: `anyInitiator` should still require organization
        // membership should be denied.
        Policy memory policy = _buildBasePolicy();
        policy.config.initiator.anyInitiator = true;

        address nonMember = address(0xA701);
        policyStateHarness.setMemberStatus(nonMember, false);

        // Call: execute `isInitiatorAuthorizedViaPolicyLibrary` and capture the authorization decision.
        bool authorized = harness.isInitiatorAuthorizedViaPolicyLibrary(policy, nonMember);
        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(authorized, "desired behavior: non-member should not be authorized even with anyInitiator");
    }

    /// @dev Verifies that zero-address initiator fails closed.
    function test_isInitiatorAuthorized_zeroAddressInitiator_returnsFalse() public {
        // Setup: build fixture inputs where zero-address initiator fails closed should be denied.
        Policy memory policy = _buildBasePolicy();
        policy.config.initiator.anyInitiator = false;
        policy.config.initiator.initiatorType = ApproverType.Member;
        policy.config.initiator.initiatorMember = initiator1;

        // Call: execute `isInitiatorAuthorizedViaPolicyLibrary` and capture the authorization decision.
        bool authorized = harness.isInitiatorAuthorizedViaPolicyLibrary(policy, address(0));
        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(authorized, "zero-address initiator should fail closed");
    }

    /// @dev Verifies that unknown initiator enum fails closed.
    function test_isInitiatorAuthorized_invalidInitiatorEnum_returnsFalse() public {
        // Setup: build fixture inputs where unknown initiator enum fails closed should be denied.
        Policy memory policy = _buildBasePolicy();
        policy.config.initiator.anyInitiator = false;

        _setMembersAsOrgMembers(buildArray(initiator1));

        // Call: execute `isInitiatorAuthorizedViaPolicyLibraryRawInitiatorType` and capture the authorization decision.
        bool authorized =
            harness.isInitiatorAuthorizedViaPolicyLibraryRawInitiatorType(policy, type(uint256).max, initiator1);
        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(authorized, "invalid initiator type should fail closed");
    }
}
