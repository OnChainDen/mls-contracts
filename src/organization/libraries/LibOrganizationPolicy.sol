// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationPolicy} from "interfaces/organization/IOrganizationPolicy.sol";
import {MerkleUtils} from "libraries/MerkleUtils.sol";
import {TokenTransferUtils} from "libraries/TokenTransferUtils.sol";
import {LibPolicyApproval} from "organization/libraries/policy/LibPolicyApproval.sol";
import {LibPolicyContractInteraction} from "organization/libraries/policy/LibPolicyContractInteraction.sol";
import {LibPolicyDestination} from "organization/libraries/policy/LibPolicyDestination.sol";
import {LibPolicyInitiator} from "organization/libraries/policy/LibPolicyInitiator.sol";
import {LibPolicyTimeBasedLimits} from "organization/libraries/policy/LibPolicyTimeBasedLimits.sol";
import {LibPolicyTokenTransfer} from "organization/libraries/policy/LibPolicyTokenTransfer.sol";
import {LibOrganizationPolicyStorage} from "organization/libraries/storage/LibOrganizationPolicyStorage.sol";
import {ApproverProofs, InitiatorProofs, Policy, TransactionType, ValidationProofs} from "types/PolicyTypes.sol";

import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/**
 * @title Lib Organization Policy
 * @dev Library for merkle-based policy operations.
 *      Policies are stored in a global merkle tree. Only the root is stored on-chain.
 *      Full policy data is provided via calldata and verified against the root.
 *      Members and Groups are also Merkle-based - membership is verified via proofs.
 *      This approach drastically reduces gas costs for policy creation/modification (1 SSTORE)
 *      while keeping validation costs reasonable (O(log n) hash operations).
 * @author Den Technologies Inc
 */
library LibOrganizationPolicy {
    /**
     * @dev Updates the global policies merkle root.
     *      This is the only way to set policies. All policy data is stored off-chain (IPFS).
     *      Emits PoliciesUpdated event with the IPFS CID for disaster recovery.
     * @param newPoliciesRoot The new merkle root containing all policies
     * @param ipfsCid The IPFS CID where full policy data is stored
     */
    function setPolicies(bytes32 newPoliciesRoot, string calldata ipfsCid) public {
        LibOrganizationPolicyStorage.layout().policiesRoot = newPoliciesRoot;
        emit IOrganizationPolicy.PoliciesUpdated(newPoliciesRoot, ipfsCid);
    }

    /**
     * @notice Checks and updates time-based usage limits
     * @dev Delegates to LibPolicyTimeBasedLimits.
     * @param policyId The policy ID
     * @param policy The policy data
     * @param account The source account address
     * @param destination The destination address
     * @param initiator The initiator address
     * @param usageAmount The amount to add to usage (transfer amount or 1 for non-transfers)
     * @return withinLimit True if within limit (and usage was updated), false otherwise
     */
    function checkAndUpdateTimeBasedLimit(
        uint256 policyId,
        Policy memory policy,
        address account,
        address destination,
        address initiator,
        uint256 usageAmount
    ) public returns (bool withinLimit) {
        return LibPolicyTimeBasedLimits.checkAndUpdateTimeBasedLimit({
            policyId: policyId,
            policy: policy,
            account: account,
            destination: destination,
            initiator: initiator,
            usageAmount: usageAmount
        });
    }

    /**
     * @dev Checks if a policy exists in the organization's policy merkle tree
     * @param policyId The unique identifier of the policy
     * @param policy The policy data
     * @param proof The merkle proof for the policy
     * @return True if the policy is in the tree, false otherwise
     */
    function isPolicyInOrg(uint256 policyId, Policy memory policy, bytes32[] memory proof) public view returns (bool) {
        bytes32 root = LibOrganizationPolicyStorage.layout().policiesRoot;
        bytes32 leaf = _computePolicyLeaf(policyId, policy);
        return MerkleProof.verify(proof, root, leaf);
    }

    /**
     * @dev Checks if a policy applies to a given transaction.
     *      Performs comprehensive validation including:
     *      1. Policy existence (via merkle proof)
     *      2. Source account matching
     *      3. Initiator authorization (via merkle proofs for membership)
     *      4. Transaction type matching (including token transfer and contract interaction checks)
     *      5. Destination matching
     * @param policyId The unique identifier of the policy
     * @param sourceAccount The account executing the transaction
     * @param to The transaction destination address
     * @param value The transaction value in wei
     * @param data The transaction calldata
     * @param initiator The address that initiated the transaction
     * @param proofs The validation proofs containing policy data and merkle proofs
     * @return True if the policy applies to this transaction, false otherwise
     */
    function isTransactionAllowedByPolicy(
        uint256 policyId,
        address sourceAccount,
        address to,
        uint256 value,
        bytes calldata data,
        address initiator,
        ValidationProofs calldata proofs
    ) public view returns (bool) {
        // Case: The policy does not exist in the organization
        if (!isPolicyInOrg(policyId, proofs.policy, proofs.policyProof)) return false;

        // Case: The source account is not allowed by the policy
        if (!isSourceAccountAllowedByPolicy(proofs.policy, sourceAccount, proofs.sourceAccountProof)) {
            return false;
        }

        // Case: The initiator is not authorized by the policy
        if (!LibPolicyInitiator.isInitiatorAuthorized(proofs.policy, initiator, proofs.initiatorProofs)) {
            return false;
        }

        TransactionType txType = proofs.policy.config.transactionType;

        // Case: Policy matches only transactions that are token transfers
        if (txType == TransactionType.TokenTransfers) {
            // Case: The transaction is not a token transfer
            if (!TokenTransferUtils.isTransactionTokenTransfer(data, value)) return false;

            return LibPolicyTokenTransfer.isTokenTransferAllowedByPolicy({
                policy: proofs.policy, to: to, value: value, data: data, destinationProof: proofs.destinationProof
            });
        }

        // Case: The policy matches only transactions that are contract interactions that are not token transfers
        if (txType == TransactionType.ContractInteractions) {
            // Case: The transaction is a token transfer (not a contract interaction)
            if (TokenTransferUtils.isTransactionTokenTransfer(data, value)) return false;

            return LibPolicyContractInteraction.isContractInteractionAllowedByPolicy({
                policy: proofs.policy,
                to: to,
                value: value,
                data: data,
                functionProof: proofs.functionProof,
                constraints: proofs.constraints,
                destinationProof: proofs.destinationProof
            });
        }

        // Case: The policy can be applied to any type of transaction (Token transfers or Contract interactions)
        // and the destination is allowed by the policy
        if (
            txType == TransactionType.Any
                && LibPolicyDestination.isDestinationAllowedByPolicy({
                    policy: proofs.policy, to: to, value: value, data: data, destinationProof: proofs.destinationProof
                })
        ) {
            return true;
        }

        return false;
    }

    /**
     * @dev Checks if there are enough valid approvals from signatures (using Merkle proofs).
     *      Supports both EOA (ECDSA) and ERC-1271 (smart contract) signatures.
     *      Delegates to LibPolicyApproval.
     * @param policy The policy to check against
     * @param signatures The concatenated signatures (variable length, hybrid format)
     * @param messageHash The message hash that was signed
     * @param approverProofs The proofs for approver membership verification
     * @return True if there are enough valid approvals, false otherwise
     */
    function areApprovalsValid(
        Policy memory policy,
        bytes memory signatures,
        bytes32 messageHash,
        ApproverProofs memory approverProofs
    ) public view returns (bool) {
        return LibPolicyApproval.areApprovalsValid({
            policy: policy, signatures: signatures, messageHash: messageHash, approverProofs: approverProofs
        });
    }

    /**
     * @dev Computes the current time window for a policy.
     *      Delegates to LibPolicyTimeBasedLimits.
     * @param policy The policy data
     * @return The current time window, or 0 if timeIntervalHours is 0
     */
    function computeTimeWindow(Policy memory policy) public view returns (uint256) {
        return LibPolicyTimeBasedLimits.computeTimeWindow(policy);
    }

    /**
     * @dev Gets the current usage for a time-based policy.
     *      Delegates to LibPolicyTimeBasedLimits.
     * @param policyId The policy ID
     * @param policy The policy data
     * @param account The source account address
     * @param destination The destination address
     * @param initiator The initiator address
     * @return The current usage amount within the current time window
     */
    function getCurrentUsage(
        uint256 policyId,
        Policy memory policy,
        address account,
        address destination,
        address initiator
    ) public view returns (uint256) {
        return LibPolicyTimeBasedLimits.getCurrentUsage({
            policyId: policyId, policy: policy, account: account, destination: destination, initiator: initiator
        });
    }

    /**
     * @dev Checks if the initiator is authorized by the policy.
     *      Delegates to LibPolicyInitiator.
     * @param policy The policy to check against
     * @param initiatorAddress The address of the transaction initiator
     * @param initiatorProofs The proofs for initiator membership verification
     * @return True if the initiator is authorized, false otherwise
     */
    function isInitiatorAuthorized(
        Policy memory policy,
        address initiatorAddress,
        InitiatorProofs memory initiatorProofs
    ) public view returns (bool) {
        return LibPolicyInitiator.isInitiatorAuthorized(policy, initiatorAddress, initiatorProofs);
    }

    /**
     * @dev Checks if the source account matches the policy's source account filter.
     *      If anySourceAccount is true, always returns true.
     *      Otherwise, verifies the account is in the policy's source accounts merkle tree.
     * @param policy The policy to check against
     * @param sourceAccount The source account address
     * @param sourceAccountProof The merkle proof for the source account
     * @return True if the source account matches, false otherwise
     */
    function isSourceAccountAllowedByPolicy(
        Policy memory policy,
        address sourceAccount,
        bytes32[] memory sourceAccountProof
    ) public pure returns (bool) {
        // Case: The policy matches transactions sent from any account
        if (policy.config.anySourceAccount) return true;

        // Case: The policy matches transactions sent from a list of specific source accounts
        // Verify this account is in the source accounts merkle tree
        bytes32 accountLeaf = MerkleUtils.computeAddressLeaf(sourceAccount);
        return MerkleProof.verify(sourceAccountProof, policy.roots.sourceAccountsRoot, accountLeaf);
    }

    /**
     * @dev Gets the number of required approvals for a policy.
     *      Delegates to LibPolicyApproval.
     * @param policy The policy to check
     * @return The number of required approvals
     */
    function getRequiredApprovals(Policy memory policy) public pure returns (uint256) {
        return LibPolicyApproval.getRequiredApprovals(policy);
    }

    /**
     * @dev Gets the actual destination address for a transaction.
     *      Delegates to LibPolicyDestination.
     * @param to The transaction `to` address
     * @param data The transaction calldata
     * @param value The transaction value in wei
     * @return The actual destination address
     */
    function getActualDestination(address to, bytes calldata data, uint256 value) public pure returns (address) {
        return LibPolicyDestination.getActualDestination(to, data, value);
    }

    /**
     * @notice Computes the usage key for time-based limit tracking
     * @dev Delegates to LibPolicyTimeBasedLimits.
     * @param policyId The policy ID
     * @param policy The policy data
     * @param account The source account address
     * @param destination The destination address
     * @param initiator The initiator address
     * @return The computed usage key
     */
    function computeUsageKey(
        uint256 policyId,
        Policy memory policy,
        address account,
        address destination,
        address initiator
    ) public pure returns (bytes32) {
        return LibPolicyTimeBasedLimits.computeUsageKey({
            policyId: policyId, policy: policy, account: account, destination: destination, initiator: initiator
        });
    }

    /**
     * @dev Computes the merkle leaf for a policy.
     *      Uses double hashing (hash of hash) for security against second preimage attacks.
     * @param policyId The unique identifier of the policy
     * @param policy The policy data
     * @return The computed merkle leaf
     */
    function _computePolicyLeaf(uint256 policyId, Policy memory policy) private pure returns (bytes32) {
        return keccak256(bytes.concat(keccak256(abi.encode(policyId, policy))));
    }
}
