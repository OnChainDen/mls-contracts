// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationMembers} from "interfaces/organization/IOrganizationMembers.sol";
import {LibOrganizationAdminStorage} from "organization/libraries/storage/LibOrganizationAdminStorage.sol";
import {LibOrganizationMembersStorage} from "organization/libraries/storage/LibOrganizationMembersStorage.sol";

/**
 * @title Lib Organization Members
 * @dev Library for mapping-based member operations for Organization contracts.
 *      Members are stored in a mapping for O(1) membership checks.
 *      Removing a member who is an admin reverts — admin status must be removed first.
 * @author Den Technologies Inc
 */
library LibOrganizationMembers {
    /**
     * @dev Adds and/or removes members from the organization.
     *      Adding a duplicate member is a no-op.
     *      Removing a non-existent member is a no-op.
     *      Removing a member who is an admin reverts with MemberIsAdmin.
     * @param membersToAdd Addresses to add as members
     * @param membersToRemove Addresses to remove from members
     */
    function modifyMembers(address[] calldata membersToAdd, address[] calldata membersToRemove) public {
        LibOrganizationMembersStorage.Layout storage membersLayout = LibOrganizationMembersStorage.layout();
        LibOrganizationAdminStorage.Layout storage adminLayout = LibOrganizationAdminStorage.layout();

        // Process additions
        for (uint256 i = 0; i < membersToAdd.length; ++i) {
            address member = membersToAdd[i];
            if (member == address(0)) revert IOrganizationMembers.InvalidMemberAddress(member);

            // No-op if already a member
            if (membersLayout.isMember[member]) continue;

            membersLayout.isMember[member] = true;
            emit IOrganizationMembers.MemberAdded(member);
        }

        // Process removals
        for (uint256 i = 0; i < membersToRemove.length; ++i) {
            address member = membersToRemove[i];

            // No-op if member does not currently exist.
            if (!membersLayout.isMember[member]) continue;

            // Case: Member is an admin — must remove admin status first
            if (adminLayout.isAdmin[member]) revert IOrganizationMembers.MemberIsAdmin(member);

            membersLayout.isMember[member] = false;
            emit IOrganizationMembers.MemberRemoved(member);
        }
    }

    /**
     * @dev Checks if an address is a member of the organization
     * @param memberAddress The address to check
     * @return True if the address is a member, false otherwise
     */
    function isMember(address memberAddress) internal view returns (bool) {
        return LibOrganizationMembersStorage.layout().isMember[memberAddress];
    }
}
