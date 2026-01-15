// SPDX-License-Identifier: MIT
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
     * @notice Thrown when member proofs length doesn't match signature count
     * @param expected The expected length (signature count)
     * @param actual The actual length of proofs array
     */
    error MemberProofsLengthMismatch(uint256 expected, uint256 actual);

    /**
     * @notice Thrown when member in group proofs length doesn't match signature count
     * @param expected The expected length (signature count)
     * @param actual The actual length of proofs array
     */
    error MemberInGroupProofsLengthMismatch(uint256 expected, uint256 actual);

    // ═══════════════════════════════════════════════════════════════════════════
    // Functions
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Updates the global policies merkle root
     * @dev This is the only way to set policies. All policy data is stored off-chain (IPFS).
     * @param newPoliciesRoot The new merkle root containing all policies
     * @param ipfsCid The IPFS CID where full policy data is stored for disaster recovery
     * @param authParams The authorization parameters (salt, expiration, signatures, and admin proofs)
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
     * @notice Gets the current usage for a time-based policy within the current time window
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
