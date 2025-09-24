// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @notice Enum to specify whether admin permission is granted to an individual member or a group
 */
enum AdminType {
    Member,
    Group
}

/**
 * @notice Enum to specify the type of admin operation being performed
 */
enum AdminOperationType {
    UpdateAdmin,
    CreateGroup,
    ModifyGroup,
    RemoveGroup,
    AddMembers,
    ModifyMember,
    RemoveMembers,
    ModifyPolicies,
    UpdateGuardian,
    ModifyWhitelist,
    DiamondCut,
    DeployAccount
}

/**
 * @notice Interface for calling admin validation functions
 * @dev This interface allows other contracts to interact with admin facets
 * @author Den Technologies Inc
 */
interface IAdminFacet {
    /**
     * @notice Validates that the provided signatures meet the admin authorization requirements
     * @param operationType The type of operation being performed
     * @param operationData The ABI-encoded data of the operation
     * @param salt A user-provided salt for nonce computation
     * @param signatures The signatures to validate
     */
    function validateAdminAuthorization(
        AdminOperationType operationType,
        bytes memory operationData,
        uint256 salt,
        bytes memory signatures
    )
        external;
}
