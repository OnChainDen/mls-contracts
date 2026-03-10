// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {LibOrganizationGroups} from "organization/libraries/LibOrganizationGroups.sol";
import {LibOrganizationAdminStorage} from "organization/libraries/storage/LibOrganizationAdminStorage.sol";
import {LibOrganizationGroupsStorage} from "organization/libraries/storage/LibOrganizationGroupsStorage.sol";
import {OrganizationGroupsStateHarness} from "test/organization/shared/OrganizationGroupsStateHarness.sol";
import {GroupModification} from "types/CommonTypes.sol";

/**
 * @dev Library-focused test harness for `LibOrganizationGroups`.
 *      Exposes direct wrappers around library entry points and internal helper functions.
 */
contract LibOrganizationGroupsHarness is OrganizationGroupsStateHarness {
    /**
     * @dev Wrapper around main batch entry point.
     */
    function modifyGroupsViaLibrary(GroupModification[] calldata modifications) external {
        LibOrganizationGroups.modifyGroups(modifications);
    }

    /**
     * @dev Wrapper around storage-backed `isGroup` view.
     */
    function isGroupViaLibrary(uint256 groupId) external view returns (bool) {
        return LibOrganizationGroups.isGroup(groupId);
    }

    /**
     * @dev Wrapper around storage-backed `isGroupMember` view.
     */
    function isGroupMemberViaLibrary(uint256 groupId, address memberAddress) external view returns (bool) {
        return LibOrganizationGroups.isGroupMember(groupId, memberAddress);
    }

    /**
     * @dev Wrapper around `_createGroup` helper.
     */
    function createGroupViaLibrary(GroupModification calldata mod) external {
        LibOrganizationGroups._createGroup(mod);
    }

    /**
     * @dev Wrapper around `_updateGroup` helper.
     */
    function updateGroupViaLibrary(GroupModification calldata mod) external {
        LibOrganizationGroups._updateGroup(mod);
    }

    /**
     * @dev Wrapper around `_deleteGroup` helper.
     */
    function deleteGroupViaLibrary(GroupModification calldata mod) external {
        LibOrganizationGroups._deleteGroup(mod);
    }

    /**
     * @dev Wrapper around `_addGroupMembers` helper.
     */
    function addGroupMembersViaLibrary(uint256 groupId, address[] calldata members) external {
        LibOrganizationGroups._addGroupMembers(LibOrganizationGroupsStorage.layout(), groupId, members);
    }

    /**
     * @dev Wrapper around `_removeGroupMembers` helper.
     */
    function removeGroupMembersViaLibrary(uint256 groupId, address[] calldata members) external {
        LibOrganizationGroups._removeGroupMembers(LibOrganizationGroupsStorage.layout(), groupId, members);
    }

    /**
     * @dev Reads admin count directly from storage for cross-library isolation checks.
     */
    function getAdminCount() external view returns (uint256) {
        return LibOrganizationAdminStorage.layout().adminCount;
    }

    /**
     * @dev Reads voting threshold directly from storage for cross-library isolation checks.
     */
    function getVotingThreshold() external view returns (uint256) {
        return LibOrganizationAdminStorage.layout().votingThreshold;
    }
}
