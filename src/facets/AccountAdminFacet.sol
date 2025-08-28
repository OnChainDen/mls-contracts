// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { AccountStorage } from "../storage/AccountStorage.sol";
import { OrganizationStorage } from "../storage/OrganizationStorage.sol";
import { IOrganizationAdminFacet } from "./IOrganizationAdminFacet.sol";

/**
 * @title Account Admin Facet
 * @notice Handles admin-related operations for the OnchainCustodyAccount diamond by forwarding to the organization
 * @author Den Technologies Inc
 */
contract AccountAdminFacet {
    using AccountStorage for AccountStorage.Layout;

    /**
     * @notice Emitted when an admin operation is rejected due to insufficient authorization
     * @param reason The reason for the rejection
     */
    error AdminOperationRejected(string reason);

    /**
     * @notice Emitted when an admin operation has insufficient signatures
     * @param required The number of required signatures
     * @param provided The number of provided signatures
     */
    error InsufficientAdminSignatures(uint256 required, uint256 provided);

    /**
     * @notice Emitted when an admin operation has an invalid signature
     */
    error InvalidAdminSignature();

    /**
     * @notice Emitted when an admin operation uses a nonce that has already been used
     * @param nonce The nonce that was attempted to be used
     */
    error AdminNonceAlreadyUsed(uint256 nonce);

    /**
     * @notice Emitted when an admin operation has wrong chain ID
     * @param expected The expected chain ID
     * @param provided The provided chain ID
     */
    error InvalidAdminChainId(uint256 expected, uint256 provided);

    /**
     * @notice Emitted when a function is called by an unauthorized address (not the guardian)
     * @param caller The address that attempted to call the function
     * @param guardian The current guardian address
     */
    error UnauthorizedCaller(address caller, address guardian);

    /**
     * @notice Error thrown when the organization address is not set
     */
    error OrganizationNotSet();

    /**
     * @notice Error thrown when the call to the organization contract fails
     */
    error OrganizationCallFailed();

    /**
     * @notice Modifier to restrict function access to the guardian address only
     */
    modifier onlyGuardian() {
        AccountStorage.Layout storage l = AccountStorage.layout();

        // Get guardian from organization contract
        if (l.organizationAddress == address(0)) {
            revert OrganizationNotSet();
        }

        address organizationGuardian = IOrganizationAdminFacet(l.organizationAddress).guardian();
        if (msg.sender != organizationGuardian) {
            revert UnauthorizedCaller(msg.sender, organizationGuardian);
        }
        _;
    }

    /**
     * @notice Gets the current guardian address from the organization
     * @return The current guardian address
     */
    function guardian() external view returns (address) {
        AccountStorage.Layout storage l = AccountStorage.layout();
        if (l.organizationAddress == address(0)) {
            revert OrganizationNotSet();
        }
        return IOrganizationAdminFacet(l.organizationAddress).guardian();
    }

    /**
     * @notice Gets the organization address that this account is associated with
     * @return The organization address
     */
    function getOrganizationAddress() external view returns (address) {
        return AccountStorage.layout().organizationAddress;
    }

    /**
     * @notice Validates that the provided signatures meet the admin authorization requirements by forwarding to
     * organization
     * @dev This function forwards the call to the associated organization contract's validateAdminAuthorization
     * function
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
        public
    {
        AccountStorage.Layout storage l = AccountStorage.layout();

        // Ensure organization address is set
        if (l.organizationAddress == address(0)) {
            revert OrganizationNotSet();
        }

        // Forward the call to the organization contract
        try IOrganizationAdminFacet(l.organizationAddress).validateAdminAuthorization(
            operationType, operationData, salt, chainId, signatures
        ) {
            return;
            // Call succeeded - authorization is valid
        } catch Error(string memory reason) {
            // Re-throw the specific error from the organization
            revert AdminOperationRejected(reason);
        } catch {
            // Generic failure
            revert OrganizationCallFailed();
        }
    }
}
