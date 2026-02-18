// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {LibOrganizationGroupsStorage} from "organization/libraries/storage/LibOrganizationGroupsStorage.sol";
import {OrganizationAdminStateHarness} from "test/organization/shared/OrganizationAdminStateHarness.sol";
import {GroupModification} from "types/CommonTypes.sol";

/**
 * @dev Shared groups test harness state surface.
 *      Extends admin/auth helpers with direct group storage accessors used across suite types.
 */
contract OrganizationGroupsStateHarness is OrganizationAdminStateHarness {
    /**
     * @dev Sets active-group status for a group ID.
     */
    function setGroupStatus(uint256 groupId, bool isActive) external {
        LibOrganizationGroupsStorage.layout().isGroup[groupId] = isActive;
    }

    /**
     * @dev Reads active-group status for a group ID.
     */
    function getGroupStatus(uint256 groupId) external view returns (bool) {
        return LibOrganizationGroupsStorage.layout().isGroup[groupId];
    }

    /**
     * @dev Sets group-member status for a `(groupId, member)` pair.
     */
    function setGroupMemberStatus(uint256 groupId, address member, bool isGroupMember) external {
        LibOrganizationGroupsStorage.layout().isGroupMember[groupId][member] = isGroupMember;
    }

    /**
     * @dev Reads group-member status for a `(groupId, member)` pair.
     */
    function getGroupMemberStatus(uint256 groupId, address member) external view returns (bool) {
        return LibOrganizationGroupsStorage.layout().isGroupMember[groupId][member];
    }

    /**
     * @dev Sets deleted-group marker for a group ID.
     */
    function setWasGroupDeletedStatus(uint256 groupId, bool wasDeleted) external {
        LibOrganizationGroupsStorage.layout().wasGroupDeleted[groupId] = wasDeleted;
    }

    /**
     * @dev Reads deleted-group marker for a group ID.
     */
    function getWasGroupDeletedStatus(uint256 groupId) external view returns (bool) {
        return LibOrganizationGroupsStorage.layout().wasGroupDeleted[groupId];
    }

    /**
     * @dev Encodes operation data exactly as `OrganizationGroupsBase.modifyGroups`.
     */
    function encodeModifyGroupsOperationData(GroupModification[] calldata modifications)
        external
        pure
        returns (bytes memory)
    {
        return abi.encode(keccak256(abi.encode(modifications)));
    }
}
