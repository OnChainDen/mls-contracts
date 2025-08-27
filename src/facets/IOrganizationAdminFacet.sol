// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { OrganizationStorage } from "../storage/OrganizationStorage.sol";

/**
 * @notice Interface for calling the organization admin validation function
 * @dev This interface allows other contracts to interact with the OrganizationAdminFacet
 * @author Den Technologies Inc
 */
interface IOrganizationAdminFacet {
    /**
     * @notice Validates that the provided signatures meet the admin authorization requirements
     * @param operationType The type of operation being performed
     * @param operationData The ABI-encoded data of the operation
     * @param salt A user-provided salt for nonce computation
     * @param chainId The chain ID for cross-chain replay protection - must match current chain ID
     * @param signatures The signatures to validate
     */
    function validateAdminAuthorization(
        OrganizationStorage.AdminOperationType operationType,
        bytes memory operationData,
        uint256 salt,
        uint256 chainId,
        bytes memory signatures
    )
        external;

    /**
     * @notice Gets the current guardian address
     * @return The current guardian address
     */
    function guardian() external view returns (address);
}
