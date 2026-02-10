// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {AdminAuthParams} from "types/AdminTypes.sol";
import {Policy} from "types/PolicyTypes.sol";

/**
 * @title IOrganizationPolicy
 * @notice Interface for policy-related operations in Organization contracts
 * @dev Maps to LibOrganizationPolicy library functionality
 * @author Den Technologies Inc
 */
interface IOrganizationPolicy {
    // ═══════════════════════════════════════════════════════════════════════════
    // Events
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Emitted when the policies merkle root is updated
     * @param newRoot The new merkle root
     * @param ipfsCid The IPFS CID where full policy data is stored for disaster recovery
     */
    event PoliciesUpdated(bytes32 indexed newRoot, string ipfsCid);

    // ═══════════════════════════════════════════════════════════════════════════
    // Errors
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Thrown when policy verification fails
     * @param policyId The ID of the policy that failed verification
     */
    error PolicyVerificationFailed(uint256 policyId);

    /**
     * @notice Thrown when signatures are not in ascending order by signer address or contain duplicates
     * @param signer The signer address that violated ordering
     * @param lastSigner The previous signer address
     */
    error DuplicateOrOutOfOrderSigner(address signer, address lastSigner);

    /**
     * @notice Thrown when an approver signer is not a member of the required group
     * @param signer The address that is not in the group
     * @param groupId The group ID that was checked
     */
    error ApproverSignerIsNotGroupMember(address signer, uint256 groupId);

    // ═══════════════════════════════════════════════════════════════════════════
    // Functions
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Updates the global policies merkle root
     * @dev This is the only way to set policies. All policy data is stored off-chain (IPFS).
     * @param newPoliciesRoot The new merkle root containing all policies
     * @param ipfsCid The IPFS CID where full policy data is stored for disaster recovery
     * @param authParams The authorization parameters (salt, expiration, signatures)
     */
    // forgefmt: disable-next-item
    function setPolicies(
        bytes32 newPoliciesRoot,
        string calldata ipfsCid,
        AdminAuthParams calldata authParams
    ) external;

    /**
     * @notice Returns the current global policies merkle root
     * @return The policies merkle root
     */
    function policiesRoot() external view returns (bytes32);

    /**
     * @notice Gets the current usage for a rate-limited policy within the current time window
     * @param policyId The ID of the policy
     * @param policy The policy data (from calldata)
     * @param account The source account address
     * @param destination The destination address
     * @param initiator The initiator address
     * @param policyProof The merkle proof verifying the policy exists
     * @return The current usage amount within the current time window
     */
    function getPolicyUsage(
        uint256 policyId,
        Policy calldata policy,
        address account,
        address destination,
        address initiator,
        bytes32[] calldata policyProof
    ) external view returns (uint256);
}
