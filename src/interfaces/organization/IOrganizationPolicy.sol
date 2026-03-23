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
     * @notice Thrown when a signer is not authorized to approve for a policy
     * @param signer The address that is not authorized
     */
    error UnauthorizedApprovalSigner(address signer);

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
     * @dev The `destination` parameter must be the **canonical** destination that the execution
     *      path would derive for the transaction. During actual transaction execution, the system
     *      calls `LibPolicyDestination.getActualDestination(to, data, value)` to canonicalize the
     *      destination before computing the rate-limit usage key:
     *        - For ERC-20 token transfers (`transfer`): the canonical destination
     *          is the **token recipient** extracted from calldata, NOT the token contract address.
     *        - For native ETH transfers (empty calldata): the canonical destination is the `to` address.
     *        - For contract interactions (non-token calldata): the canonical destination is the `to` address.
     *
     *      When the policy's `destinationScope` is `RateLimitScope.PerEntity`, the destination is
     *      incorporated into the usage key. Passing a non-canonical destination (e.g., the token
     *      contract address instead of the token recipient for an ERC-20 transfer) will query a
     *      different rate-limit bucket than the one enforcement actually uses.
     *
     *      When `destinationScope` is `RateLimitScope.AcrossAll`, the destination is not
     *      incorporated into the usage key, so any value will return the correct result.
     * @param policyId The ID of the policy
     * @param policy The policy data (from calldata)
     * @param account The source account address
     * @param destination The canonical destination address (see @dev for derivation rules)
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
