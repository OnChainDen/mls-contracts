// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationAdmin} from "interfaces/organization/IOrganizationAdmin.sol";
import {IOrganizationMembers} from "interfaces/organization/IOrganizationMembers.sol";
import {OrganizationModifiers} from "organization/common/OrganizationModifiers.sol";
import {LibOrganizationAdmin} from "organization/libraries/LibOrganizationAdmin.sol";
import {LibOrganizationMembers} from "organization/libraries/LibOrganizationMembers.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";
import {OperationType} from "types/CommonTypes.sol";

/**
 * @title OrganizationMembersBase
 * @dev Abstract contract implementing IOrganizationMembers.
 *      Handles member management operations including adding/removing members and verifying membership.
 * @author Den Technologies Inc
 */
abstract contract OrganizationMembersBase is OrganizationModifiers, IOrganizationMembers {
    /// @inheritdoc IOrganizationMembers
    function modifyMembers(
        address[] calldata membersToAdd,
        address[] calldata membersToRemove,
        AdminAuthParams calldata authParams
    ) external override onlyGuardian {
        // Encode the operation data for validation
        bytes memory operationData =
            abi.encode(keccak256(abi.encode(membersToAdd)), keccak256(abi.encode(membersToRemove)));

        // Validate that the current admins have authorized this operation (isApproval = true for execution)
        uint256 nonce = LibOrganizationAdmin.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyMembers,
            operationData: operationData,
            isApproval: true,
            authParams: authParams
        });

        // Execute via low-level self-call so that a revert does not bubble up.
        /* solhint-disable avoid-low-level-calls */
        // slither-disable-next-line low-level-calls,reentrancy-events
        (bool success, bytes memory revertData) =
            address(this).call(abi.encodeCall(this.executeModifyMembers, (membersToAdd, membersToRemove)));
        /* solhint-enable avoid-low-level-calls */

        if (!success) {
            emit IOrganizationAdmin.AdminOperationExecutionReverted(OperationType.ModifyMembers, nonce, revertData);
        }
    }

    /// @inheritdoc IOrganizationMembers
    function executeModifyMembers(address[] calldata membersToAdd, address[] calldata membersToRemove)
        external
        override
        onlySelf
    {
        LibOrganizationMembers.modifyMembers(membersToAdd, membersToRemove);
    }

    /// @inheritdoc IOrganizationMembers
    function isMember(address memberAddress) external view override returns (bool) {
        return LibOrganizationMembers.isMember(memberAddress);
    }
}
