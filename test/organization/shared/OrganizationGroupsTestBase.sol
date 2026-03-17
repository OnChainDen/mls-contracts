// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {OrganizationAdminStateHarness} from "test/organization/shared/OrganizationAdminStateHarness.sol";
import {OrganizationAdminTestBase} from "test/organization/shared/OrganizationAdminTestBase.sol";
import {OrganizationGroupsStateHarness} from "test/organization/shared/OrganizationGroupsStateHarness.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";
import {GroupModification, GroupModificationType, OperationType} from "types/CommonTypes.sol";

/**
 * @dev Shared setup/helpers for organization groups tests.
 *      Builds on admin test helpers and adds group-modification constructors + auth builders.
 */
abstract contract OrganizationGroupsTestBase is OrganizationAdminTestBase {
    /// @dev Typed view over the shared state harness with groups-specific storage helpers.
    OrganizationGroupsStateHarness internal groupsStateHarness;

    /**
     * @dev Initializes typed groups-state harness after common setup is complete.
     */
    function setUp() public virtual override {
        super.setUp();
        groupsStateHarness = OrganizationGroupsStateHarness(address(stateHarness));

        // Most group-focused positive-path tests use these deterministic addresses as valid members.
        groupsStateHarness.setMemberStatus(admin1, true);
        groupsStateHarness.setMemberStatus(admin2, true);
        groupsStateHarness.setMemberStatus(admin3, true);
    }

    /**
     * @dev Builds a single `GroupModification` object.
     */
    function _buildGroupModification(
        uint256 groupId,
        GroupModificationType modificationType,
        address[] memory membersToAdd,
        address[] memory membersToRemove
    ) internal pure returns (GroupModification memory modification) {
        modification = GroupModification({
            groupId: groupId,
            modificationType: modificationType,
            membersToAdd: membersToAdd,
            membersToRemove: membersToRemove
        });
    }

    /**
     * @dev Builds a one-element modifications array.
     */
    function _buildModificationsArray(GroupModification memory modification)
        internal
        pure
        returns (GroupModification[] memory modifications)
    {
        modifications = new GroupModification[](1);
        modifications[0] = modification;
    }

    /**
     * @dev Builds a two-element modifications array.
     */
    function _buildModificationsArray(GroupModification memory first, GroupModification memory second)
        internal
        pure
        returns (GroupModification[] memory modifications)
    {
        modifications = new GroupModification[](2);
        modifications[0] = first;
        modifications[1] = second;
    }

    /**
     * @dev Builds a three-element modifications array.
     */
    function _buildModificationsArray(
        GroupModification memory first,
        GroupModification memory second,
        GroupModification memory third
    ) internal pure returns (GroupModification[] memory modifications) {
        modifications = new GroupModification[](3);
        modifications[0] = first;
        modifications[1] = second;
        modifications[2] = third;
    }

    /**
     * @dev Builds a four-element modifications array.
     */
    function _buildModificationsArray(
        GroupModification memory first,
        GroupModification memory second,
        GroupModification memory third,
        GroupModification memory fourth
    ) internal pure returns (GroupModification[] memory modifications) {
        modifications = new GroupModification[](4);
        modifications[0] = first;
        modifications[1] = second;
        modifications[2] = third;
        modifications[3] = fourth;
    }

    /**
     * @dev Convenience builder for create modifications.
     */
    function _createModification(uint256 groupId, address[] memory membersToAdd)
        internal
        pure
        returns (GroupModification memory)
    {
        return _buildGroupModification(groupId, GroupModificationType.Create, membersToAdd, buildEmptyAddressArray());
    }

    /**
     * @dev Convenience builder for update modifications.
     */
    function _updateModification(uint256 groupId, address[] memory membersToAdd, address[] memory membersToRemove)
        internal
        pure
        returns (GroupModification memory)
    {
        return _buildGroupModification(groupId, GroupModificationType.Update, membersToAdd, membersToRemove);
    }

    /**
     * @dev Convenience builder for delete modifications.
     */
    function _deleteModification(uint256 groupId) internal pure returns (GroupModification memory) {
        return _buildGroupModification(
            groupId, GroupModificationType.Delete, buildEmptyAddressArray(), buildEmptyAddressArray()
        );
    }

    /**
     * @dev Builds auth for `modifyGroups` using base-contract operation-data encoding.
     */
    function _buildModifyGroupsAuth(
        GroupModification[] memory modifications,
        uint256 salt,
        uint256 expiration,
        bool isApproval,
        uint256[] memory privateKeys
    ) internal view returns (AdminAuthParams memory auth, bytes memory operationData) {
        operationData = _encodeOperationDataForModifyGroups(modifications);
        auth = _buildAdminAuthParamsForEOA({
            operationType: OperationType.ModifyGroups,
            operationData: operationData,
            isApproval: isApproval,
            salt: salt,
            expirationTimestamp: expiration,
            privateKeys: privateKeys
        });
    }

    /**
     * @dev Encodes operation data exactly as `OrganizationGroupsBase.modifyGroups`.
     */
    function _encodeOperationDataForModifyGroups(GroupModification[] memory modifications)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(keccak256(abi.encode(modifications)));
    }

    /**
     * @dev Unsafely mutates enum backing value for one memory struct to test malformed calldata behavior.
     */
    function _unsafeSetModificationType(GroupModification memory modification, uint256 rawValue)
        internal
        pure
        returns (GroupModification memory)
    {
        assembly {
            mstore(add(modification, 0x20), rawValue)
        }
        return modification;
    }

    /**
     * @dev Unsafely mutates enum backing value for one memory array element to test malformed calldata behavior.
     */
    function _unsafeSetModificationType(GroupModification[] memory modifications, uint256 index, uint256 rawValue)
        internal
        pure
    {
        assembly {
            let element := add(add(modifications, 0x20), mul(index, 0x80))
            mstore(add(element, 0x20), rawValue)
        }
    }

    /**
     * @dev Computes nonce for a `modifyGroups` operation.
     */
    function _computeModifyGroupsNonce(bytes memory operationData, uint256 salt) internal view returns (uint256) {
        return groupsStateHarness.computeNonce(OperationType.ModifyGroups, operationData, salt);
    }

    /**
     * @dev Deploys the concrete harness for the current suite.
     */
    function _deployHarness() internal virtual override returns (OrganizationAdminStateHarness);
}
