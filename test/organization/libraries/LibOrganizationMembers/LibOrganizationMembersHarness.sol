// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {LibOrganizationAdmin} from "organization/libraries/LibOrganizationAdmin.sol";
import {LibOrganizationMembers} from "organization/libraries/LibOrganizationMembers.sol";
import {LibOrganizationAdminStorage} from "organization/libraries/storage/LibOrganizationAdminStorage.sol";
import {OrganizationAdminStateHarness} from "test/organization/shared/OrganizationAdminStateHarness.sol";

/**
 * @dev Library-focused test harness for `LibOrganizationMembers`.
 *      Exposes direct wrappers around members library entry points and select shared admin surfaces.
 */
contract LibOrganizationMembersHarness is OrganizationAdminStateHarness {
    /**
     * @dev Storage-backed `isMember` view wrapper.
     */
    function isMember(address account) external view returns (bool) {
        return LibOrganizationMembers.isMember(account);
    }

    /**
     * @dev Storage-backed `isAdmin` view wrapper.
     */
    function isAdmin(address account) external view returns (bool) {
        return LibOrganizationAdminStorage.layout().isAdmin[account];
    }

    /**
     * @dev Wrapper around direct members mutation library function.
     */
    function modifyMembersViaLibrary(address[] calldata membersToAdd, address[] calldata membersToRemove) external {
        // This bypasses auth checks on purpose so tests can focus only on mutation invariants.
        LibOrganizationMembers.modifyMembers(membersToAdd, membersToRemove);
    }

    /**
     * @dev Wrapper around direct admin mutation library function.
     */
    function modifyAdminsViaLibrary(
        address[] calldata adminsToAdd,
        address[] calldata adminsToRemove,
        uint256 newVotingThreshold
    ) external {
        // This bypasses auth checks on purpose so tests can isolate member/admin integration behavior.
        LibOrganizationAdmin.modifyAdmins(adminsToAdd, adminsToRemove, newVotingThreshold);
    }
}
