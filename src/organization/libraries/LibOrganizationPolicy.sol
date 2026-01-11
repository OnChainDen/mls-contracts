// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ContractInteractionUtils} from "../../libraries/ContractInteractionUtils.sol";
import {MerkleUtils} from "../../libraries/MerkleUtils.sol";
import {Policies} from "../../libraries/Policies.sol";
import {SignatureUtils} from "../../libraries/SignatureUtils.sol";
import {TokenTransferUtils} from "../../libraries/TokenTransferUtils.sol";
import {LibOrganizationGroups} from "./LibOrganizationGroups.sol";
import {LibOrganizationMembers} from "./LibOrganizationMembers.sol";
import {LibOrganizationSignatures} from "./LibOrganizationSignatures.sol";
import {LibOrganizationPolicyStorage} from "./storage/LibOrganizationPolicyStorage.sol";

import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

/**
 * @title Lib Organization Policy
 * @notice Library for merkle-based policy operations
 * @dev Policies are stored in a global merkle tree. Only the root is stored on-chain.
 *      Full policy data is provided via calldata and verified against the root.
 *      Members and Groups are also Merkle-based - membership is verified via proofs.
 *      This approach drastically reduces gas costs for policy creation/modification (1 SSTORE)
 *      while keeping validation costs reasonable (O(log n) hash operations).
 * @author Den Technologies Inc
 */
library LibOrganizationPolicy {
    /**
     * @notice Emitted when the policies merkle root is updated
     * @param newRoot The new merkle root
     * @param ipfsCid The IPFS CID where full policy data is stored for disaster recovery
     */
    event PoliciesUpdated(bytes32 indexed newRoot, string ipfsCid);

    /**
     * @notice Thrown when policy verification fails
     * @param policyId The ID of the policy that failed verification
     */
    error PolicyVerificationFailed(uint256 policyId);

    /**
     * @notice Thrown when member proofs array length doesn't match signature count
     * @param expected The expected number of member proofs (signature count)
     * @param actual The actual number of member proofs provided
     */
    error MemberProofsLengthMismatch(uint256 expected, uint256 actual);

    /**
     * @notice Thrown when member-in-group proofs array length doesn't match signature count
     * @param expected The expected number of member-in-group proofs (signature count)
     * @param actual The actual number of member-in-group proofs provided
     */
    error MemberInGroupProofsLengthMismatch(uint256 expected, uint256 actual);

    /**
     * @notice Updates the global policies merkle root
     * @dev This is the only way to set policies. All policy data is stored off-chain (IPFS).
     *      Emits PoliciesUpdated event with the IPFS CID for disaster recovery.
     * @param newPoliciesRoot The new merkle root containing all policies
     * @param ipfsCid The IPFS CID where full policy data is stored
     */
    function setPolicies(bytes32 newPoliciesRoot, string calldata ipfsCid) internal {
        LibOrganizationPolicyStorage.layout().policiesRoot = newPoliciesRoot;
        emit PoliciesUpdated(newPoliciesRoot, ipfsCid);
    }

    /**
     * @notice Checks and updates time-based usage limits
     * @dev Checks if the usage amount would exceed the limit for the current time window.
     *      If within limit, updates the usage and returns true.
     *      If exceeding limit, returns false without updating.
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
        Policies.Policy memory policy,
        address account,
        address destination,
        address initiator,
        uint256 usageAmount
    ) internal returns (bool withinLimit) {
        // Skip check if no time-based limitation
        if (policy.config.timeLimit.limitation != Policies.PolicyLimitation.TimeInterval) return true;

        // Skip if time interval is not configured (0 hours)
        if (policy.config.timeLimit.timeIntervalHours == 0) return true;

        LibOrganizationPolicyStorage.Layout storage policyLayout = LibOrganizationPolicyStorage.layout();

        bytes32 usageKey = computeUsageKey({
            policyId: policyId,
            policy: policy,
            account: account,
            destination: destination,
            initiator: initiator
        });
        uint256 timeWindow = computeTimeWindow(policy);

        uint256 currentUsage = policyLayout.policyUsage[usageKey][timeWindow];

        // Check if adding usageAmount would exceed the limit
        if (currentUsage + usageAmount > policy.config.timeLimit.timeIntervalLimit) return false;

        // Update usage
        policyLayout.policyUsage[usageKey][timeWindow] = currentUsage + usageAmount;

        return true;
    }

    /**
     * @notice Checks if a policy exists in the organization's policy merkle tree
     * @param policyId The unique identifier of the policy
     * @param policy The policy data
     * @param proof The merkle proof for the policy
     * @return True if the policy is in the tree, false otherwise
     */
    function isPolicyInOrg(uint256 policyId, Policies.Policy memory policy, bytes32[] memory proof)
        internal
        view
        returns (bool)
    {
        bytes32 root = LibOrganizationPolicyStorage.layout().policiesRoot;
        bytes32 leaf = _computePolicyLeaf(policyId, policy);
        return MerkleProof.verify(proof, root, leaf);
    }

    /**
     * @notice Checks if a policy applies to a given transaction
     * @dev Performs comprehensive validation including:
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
        Policies.ValidationProofs calldata proofs
    ) internal view returns (bool) {
        // Case: The policy does not exist in the organization
        if (!isPolicyInOrg(policyId, proofs.policy, proofs.policyProof)) return false;

        // Case: The source account is not allowed by the policy
        if (!isSourceAccountAllowedByPolicy(proofs.policy, sourceAccount, proofs.sourceAccountProof)) {
            return false;
        }

        // Case: The initiator is not authorized by the policy
        if (!isInitiatorAuthorized(proofs.policy, initiator, proofs.initiatorProofs)) {
            return false;
        }

        Policies.TransactionType txType = proofs.policy.config.transactionType;

        // Case: Policy matches only transactions that are token transfers
        if (txType == Policies.TransactionType.TokenTransfers) {
            // Case: The transaction is not a token transfer
            if (!TokenTransferUtils.isTransactionTokenTransfer(data, value)) return false;

            return _isTokenTransferAllowedByPolicy({
                policy: proofs.policy,
                to: to,
                value: value,
                data: data,
                destinationProof: proofs.destinationProof
            });
        }

        // Case: The policy matches only transactions that are contract interactions that are not token transfers
        if (txType == Policies.TransactionType.ContractInteractions) {
            // Case: The transaction is a token transfer (not a contract interaction)
            if (TokenTransferUtils.isTransactionTokenTransfer(data, value)) return false;

            return _isContractInteractionAllowedByPolicy({
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
            txType == Policies.TransactionType.Any
                && _isDestinationAllowedByPolicy({
                    policy: proofs.policy,
                    to: to,
                    value: value,
                    data: data,
                    destinationProof: proofs.destinationProof
                })
        ) {
            return true;
        }

        return false;
    }

    /**
     * @notice Checks if the initiator is authorized by the policy
     * @dev If anyInitiator is true, always returns true.
     *      Otherwise, verifies the initiator is a member and matches policy requirements.
     *      Uses Merkle proofs for membership verification.
     * @param policy The policy to check against
     * @param initiatorAddress The address of the transaction initiator
     * @param initiatorProofs The proofs for initiator membership verification
     * @return True if the initiator is authorized, false otherwise
     */
    function isInitiatorAuthorized(
        Policies.Policy memory policy,
        address initiatorAddress,
        Policies.InitiatorProofs memory initiatorProofs
    ) internal view returns (bool) {
        // Case: The policy matches transactions with any initiator
        if (policy.config.initiator.anyInitiator) return true;

        // First, verify the initiator is a member of the organization
        if (!LibOrganizationMembers.isMemberInOrg(initiatorAddress, initiatorProofs.initiatorInOrgMembersTreeProof)) {
            return false;
        }

        Policies.ApproverType initType = policy.config.initiator.initiatorType;

        // Case: The policy matches transactions made by a specific individual
        if (initType == Policies.ApproverType.Member) {
            // Check if the initiator is the specified member address
            return initiatorAddress == policy.config.initiator.initiatorMember;
        }

        // Case: The policy matches transactions made by any individual from a specific group
        if (initType == Policies.ApproverType.Group) {
            // Check the group ID matches the policy's initiator group ID
            if (initiatorProofs.group.groupId != policy.config.initiator.initiatorGroupId) {
                return false;
            }

            // Verify the group exists and the initiator is in that group
            return LibOrganizationGroups.isMemberInGroupAndGroupInOrg(
                initiatorAddress,
                initiatorProofs.group,
                initiatorProofs.groupInOrgGroupsTreeProof,
                initiatorProofs.memberInGroupProof
            );
        }

        // Case: The policy does not match this transaction
        return false;
    }

    /**
     * @notice Counts valid approvals from a set of signatures (using Merkle proofs)
     * @dev Signatures must be ordered by signer address (ascending) to prevent duplicates.
     *      Each signature is verified against the message hash and checked for authorization.
     *      Optimized to cache storage reads and verify group existence once before the loop.
     * @param policy The policy to check against
     * @param signatures The concatenated signatures (65 bytes each)
     * @param messageHash The message hash that was signed
     * @param approverProofs The proofs for approver membership verification
     * @return The number of valid approvals
     */
    function getValidApprovals(
        Policies.Policy memory policy,
        bytes memory signatures,
        bytes32 messageHash,
        Policies.ApproverProofs memory approverProofs
    ) internal view returns (uint8) {
        // Case: No signatures provided
        if (signatures.length == 0) return 0;

        // Each signature is 65 bytes (r: 32, s: 32, v: 1)
        uint8 signatureCount = uint8(signatures.length / 65);

        // Validate approver proofs lengths
        _validateApproverProofsOrRevert(policy, approverProofs, signatureCount);

        // Cache membersRoot to avoid repeated storage reads in the loop
        bytes32 membersRoot = LibOrganizationMembers.getMembersRoot();

        // For Group approver type, verify group existence before the loop
        if (policy.config.approval.approverType == Policies.ApproverType.Group) {
            if (!LibOrganizationGroups.isGroupInOrg(approverProofs.group, approverProofs.groupInOrgGroupsTreeProof)) {
                return 0;
            }
        }

        uint8 validApprovals = 0;

        // Track last signer to prevent duplicates (similar to Safe contracts)
        address lastSigner = address(0);

        // Iterate over signatures to count valid approvals
        for (uint8 i = 0; i < signatureCount; ++i) {
            bytes memory signature = SignatureUtils.extractSignature(signatures, i);

            // Extract signer address from signature
            address signer = LibOrganizationSignatures.extractSignerAddress(signature);

            // Skip if signer is invalid
            if (signer == address(0)) continue;

            // Check for duplicate signers - signers must be unique and in ascending order
            if (signer <= lastSigner) continue;

            // Update last signer for next iteration
            lastSigner = signer;

            // Verify the signature using ERC-1271
            if (!SignatureChecker.isValidSignatureNow(signer, messageHash, signature)) {
                continue;
            }

            // Get the proofs for this signer
            bytes32[] memory memberProof = approverProofs.approverInOrgMembersTreeProofs[i];
            bytes32[] memory memberInGroupProof = approverProofs.memberInGroupProofs[i];

            // Check if signer is authorized based on policy (with Merkle proofs)
            // Note: Group existence already verified above, membersRoot passed to avoid storage reads
            if (
                isSignerAuthorizedForPolicy({
                    policy: policy,
                    signerAddress: signer,
                    membersRoot: membersRoot,
                    memberProof: memberProof,
                    group: approverProofs.group,
                    memberInGroupProof: memberInGroupProof
                })
            ) {
                ++validApprovals;
            }
        }

        return validApprovals;
    }

    /**
     * @notice Computes the current time window for a policy
     * @dev Time windows are calculated as: block.timestamp / (timeIntervalHours * 3600)
     * @param policy The policy data
     * @return The current time window, or 0 if timeIntervalHours is 0
     */
    function computeTimeWindow(Policies.Policy memory policy) internal view returns (uint256) {
        // Uses fixed time windows based on timeIntervalHours
        uint16 hours_ = policy.config.timeLimit.timeIntervalHours;

        // Avoid division by zero
        if (hours_ == 0) return 0;

        return block.timestamp / (uint256(hours_) * 3600);
    }

    /**
     * @notice Gets the current usage for a time-based policy
     * @param policyId The policy ID
     * @param policy The policy data
     * @param account The source account address
     * @param destination The destination address
     * @param initiator The initiator address
     * @return The current usage amount within the current time window
     */
    function getCurrentUsage(
        uint256 policyId,
        Policies.Policy memory policy,
        address account,
        address destination,
        address initiator
    ) internal view returns (uint256) {
        // Return 0 if no time-based limitation
        if (policy.config.timeLimit.limitation != Policies.PolicyLimitation.TimeInterval) return 0;

        // Return 0 if time interval is not configured
        if (policy.config.timeLimit.timeIntervalHours == 0) return 0;

        LibOrganizationPolicyStorage.Layout storage policyLayout = LibOrganizationPolicyStorage.layout();

        bytes32 usageKey = computeUsageKey({
            policyId: policyId,
            policy: policy,
            account: account,
            destination: destination,
            initiator: initiator
        });
        uint256 timeWindow = computeTimeWindow(policy);

        return policyLayout.policyUsage[usageKey][timeWindow];
    }

    /**
     * @notice Checks if the source account matches the policy's source account filter
     * @dev If anySourceAccount is true, always returns true.
     *      Otherwise, verifies the account is in the policy's source accounts merkle tree.
     * @param policy The policy to check against
     * @param sourceAccount The source account address
     * @param sourceAccountProof The merkle proof for the source account
     * @return True if the source account matches, false otherwise
     */
    function isSourceAccountAllowedByPolicy(
        Policies.Policy memory policy,
        address sourceAccount,
        bytes32[] memory sourceAccountProof
    ) internal pure returns (bool) {
        // Case: The policy matches transactions sent from any account
        if (policy.config.anySourceAccount) return true;

        // Case: The policy matches transactions sent from a list of specific source accounts
        // Verify this account is in the source accounts merkle tree
        bytes32 accountLeaf = MerkleUtils.computeAddressLeaf(sourceAccount);
        return MerkleProof.verify(sourceAccountProof, policy.roots.sourceAccountsRoot, accountLeaf);
    }

    /**
     * @notice Gets the number of required approvals for a policy
     * @dev For Member approver type, always returns 1.
     *      For Group approver type, returns the approval threshold.
     * @param policy The policy to check
     * @return The number of required approvals
     */
    function getRequiredApprovals(Policies.Policy memory policy) internal pure returns (uint256) {
        // Case: Policy requires a single approval from a member
        if (policy.config.approval.approverType == Policies.ApproverType.Member) {
            return 1;
        }

        // Case: Policy requires a threshold number of approvals from any individual in a group
        return policy.config.approval.approvalThreshold;
    }

    /**
     * @notice Checks if a signer is authorized to approve for a policy (using Merkle proofs)
     * @dev For Member approver type, the signer must be the specified member address.
     *      For Group approver type, the signer must be in the specified group.
     *      NOTE: Group existence must be verified by the caller before calling this function.
     *      This function only verifies member-in-org and member-in-group to avoid redundant checks.
     * @param policy The policy to check against
     * @param signerAddress The address of the signer
     * @param membersRoot The organization's members merkle root (cached by caller to avoid repeated storage reads)
     * @param memberProof Proof that the signer is a member of the organization
     * @param group The approver group data (if applicable)
     * @param memberInGroupProof Proof that the signer is in the approver group (if applicable)
     * @return True if the signer is authorized, false otherwise
     */
    function isSignerAuthorizedForPolicy(
        Policies.Policy memory policy,
        address signerAddress,
        bytes32 membersRoot,
        bytes32[] memory memberProof,
        Policies.GroupData memory group,
        bytes32[] memory memberInGroupProof
    ) internal pure returns (bool) {
        // First verify the signer is a member of the organization (using cached root)
        if (!LibOrganizationMembers.isMemberInTree(signerAddress, membersRoot, memberProof)) {
            return false;
        }

        Policies.ApproverType approverType = policy.config.approval.approverType;

        // Case: Policy requires approval from a specific member
        if (approverType == Policies.ApproverType.Member) {
            return signerAddress == policy.config.approval.approverMember;
        }

        // Case: Policy requires approval from any member of a specific group
        if (approverType == Policies.ApproverType.Group) {
            // Check the group ID matches the policy's approver group
            if (group.groupId != policy.config.approval.approverGroupId) {
                return false;
            }

            // Verify member is in the group (group existence and proofs length verified by caller)
            return LibOrganizationGroups.isMemberInGroup(signerAddress, group.groupMembersRoot, memberInGroupProof);
        }

        return false;
    }

    /**
     * @notice Gets the actual destination address for a transaction
     * @dev For token transfers, the actual destination is the token recipient (extracted from calldata).
     *      For other transactions, the actual destination is the `to` address.
     * @param to The transaction `to` address
     * @param data The transaction calldata
     * @param value The transaction value in wei
     * @return The actual destination address
     */
    function getActualDestination(address to, bytes calldata data, uint256 value) internal pure returns (address) {
        // Case: The transaction is a native token transfer
        if (data.length == 0) return to;

        // Case: The transaction is a contract interaction
        if (!TokenTransferUtils.isTransactionTokenTransfer(data, value)) return to;

        // Case: The transaction is an ERC-20 token transfer
        // Extract the recipient address from the transfer function call
        return TokenTransferUtils.extractERC20TransferRecipient(data);
    }

    /**
     * @notice Computes the usage key for time-based limit tracking
     * @dev The usage key is a hash of the policy ID and scoped entities.
     *      If a scope is AcrossAll, address(0) is used for that component.
     *      If a scope is PerEntity, the actual address is used.
     * @param policyId The policy ID
     * @param policy The policy data
     * @param account The source account address
     * @param destination The destination address
     * @param initiator The initiator address
     * @return The computed usage key
     */
    function computeUsageKey(
        uint256 policyId,
        Policies.Policy memory policy,
        address account,
        address destination,
        address initiator
    ) internal pure returns (bytes32) {
        // Determine scoped values based on policy configuration
        // When scope is AcrossAll, address(0) is used for that entity.
        // When scope is PerEntity, the actual address is used.
        address scopedAccount =
            policy.config.timeLimit.sourceScope == Policies.TimeIntervalScope.PerEntity ? account : address(0);

        address scopedDestination =
            policy.config.timeLimit.destinationScope == Policies.TimeIntervalScope.PerEntity ? destination : address(0);

        address scopedInitiator =
            policy.config.timeLimit.initiatorScope == Policies.TimeIntervalScope.PerEntity ? initiator : address(0);

        return keccak256(abi.encode(policyId, scopedAccount, scopedDestination, scopedInitiator));
    }

    /**
     * @notice Checks if the token is allowed by the policy for a token transfer
     * @dev If anyToken is true, always returns true.
     *      Otherwise, verifies the token address matches the policy's specified token.
     * @param policy The policy to check against
     * @param to The transaction destination address (token contract for ERC20)
     * @param data The transaction calldata
     * @return True if the token is allowed, false otherwise
     */
    function _isTokenAllowedByPolicy(Policies.Policy calldata policy, address to, bytes calldata data)
        private
        pure
        returns (bool)
    {
        // Case: The policy matches transfers of any token
        if (policy.config.token.anyToken) return true;

        // Case: The policy matches only transfers of a specific token
        address transferToken = TokenTransferUtils.extractTokenAddress(to, data);
        return transferToken == policy.config.token.tokenAddress;
    }

    /**
     * @notice Checks if the token amount is allowed by the policy for a token transfer
     * @dev If hasAmountThreshold is false, always returns true.
     *      Otherwise, verifies the amount is below the threshold.
     * @param policy The policy to check against
     * @param data The transaction calldata
     * @param value The transaction value in wei
     * @return True if the amount is allowed, false otherwise
     */
    function _isTokenAmountAllowedByPolicy(Policies.Policy calldata policy, bytes calldata data, uint256 value)
        private
        pure
        returns (bool)
    {
        // Case: The policy has no amount threshold
        if (!policy.config.token.hasAmountThreshold) return true;

        // Case: The policy has an amount threshold - verify amount is below it
        uint256 amount = TokenTransferUtils.extractTransferAmount(data, value);
        return amount < policy.config.token.amountThreshold;
    }

    /**
     * @notice Checks if the destination matches the policy's destination filter
     * @dev Handles different destination types:
     *      - Any: Always matches
     *      - CustomList: Must be in the policy's custom destinations merkle tree
     * @param policy The policy to check against
     * @param to The transaction destination address
     * @param value The transaction value in wei
     * @param data The transaction calldata
     * @param destinationProof The merkle proof for the destination (for CustomList)
     * @return True if the destination matches, false otherwise
     */
    function _isDestinationAllowedByPolicy(
        Policies.Policy calldata policy,
        address to,
        uint256 value,
        bytes calldata data,
        bytes32[] calldata destinationProof
    ) private pure returns (bool) {
        Policies.DestinationType destType = policy.config.destinationType;

        // Case: Policy matches transaction to any address
        if (destType == Policies.DestinationType.Any) return true;

        // Determine the actual destination address based on transaction type
        address actualDestination = getActualDestination(to, data, value);

        // Case: Policy matches only transactions that are sent to a specific list of addresses
        // Verify via merkle proof that destination is in the custom destinations tree
        if (destType == Policies.DestinationType.CustomList) {
            bytes32 destLeaf = MerkleUtils.computeAddressLeaf(actualDestination);
            return MerkleProof.verify(destinationProof, policy.roots.customDestinationsRoot, destLeaf);
        }

        // Case: The policy does not match the transaction destination
        return false;
    }

    /**
     * @notice Checks if a token transfer transaction is allowed by the policy
     * @dev Validates that:
     *      1. The token being transferred is allowed by the policy
     *      2. The amount being transferred is within policy limits
     *      3. The destination (token recipient) is allowed by the policy
     * @param policy The policy to check against
     * @param to The transaction destination address (token contract for ERC20)
     * @param value The transaction value in wei
     * @param data The transaction calldata
     * @param destinationProof The merkle proof for the destination
     * @return True if the token transfer is allowed, false otherwise
     */
    function _isTokenTransferAllowedByPolicy(
        Policies.Policy calldata policy,
        address to,
        uint256 value,
        bytes calldata data,
        bytes32[] calldata destinationProof
    ) private pure returns (bool) {
        // forgefmt: disable-next-item
        return _isTokenAllowedByPolicy(policy, to, data) 
            && _isTokenAmountAllowedByPolicy(policy, data, value)
            && _isDestinationAllowedByPolicy({
                policy: policy,
                to: to,
                value: value,
                data: data,
                destinationProof: destinationProof
            });
    }

    /**
     * @notice Checks if a contract interaction transaction is allowed by the policy
     * @dev Validates that:
     *      1. The function being called is allowed by the policy
     *      2. The transaction parameters match the policy's constraints
     *      3. The destination (contract being called) is allowed by the policy
     * @param policy The policy to check against
     * @param to The transaction destination address (contract being called)
     * @param value The transaction value in wei
     * @param data The transaction calldata
     * @param functionProof The merkle proof for the function
     * @param constraints The parameter constraints to verify
     * @param destinationProof The merkle proof for the destination
     * @return True if the contract interaction is allowed, false otherwise
     */
    function _isContractInteractionAllowedByPolicy(
        Policies.Policy calldata policy,
        address to,
        uint256 value,
        bytes calldata data,
        bytes32[] calldata functionProof,
        bytes calldata constraints,
        bytes32[] calldata destinationProof
    ) private pure returns (bool) {
        // forgefmt: disable-next-item
        return _isDestinationAllowedByPolicy({
                policy: policy,
                to: to,
                value: value,
                data: data,
                destinationProof: destinationProof
            })
            && _isFunctionAllowedByPolicy(policy, data, functionProof, constraints)
            && _areParametersAllowedByConstraints(constraints, data);
    }

    /**
     * @notice Checks if the function matches the policy's allowed functions filter
     * @dev If anyFunction is true, always returns true.
     *      Otherwise, verifies the function selector and constraints are in the allowed functions merkle tree.
     * @param policy The policy to check against
     * @param data The transaction calldata
     * @param functionProof The merkle proof for the function
     * @param constraints The parameter constraints to verify (used to compute the constraints hash)
     * @return True if the function matches, false otherwise
     */
    function _isFunctionAllowedByPolicy(
        Policies.Policy calldata policy,
        bytes calldata data,
        bytes32[] calldata functionProof,
        bytes calldata constraints
    ) private pure returns (bool) {
        // Case: Policy matches any function
        if (policy.config.anyFunction) return true;

        // Case: Policy matches only transactions that call a specific function, but the transaction is not calling
        //       a function
        if (data.length < 4) return false;

        // Case: Policy matches only transactions that call a specific function, and the transaction is calling
        //       a function - verify via merkle proof
        bytes4 selector = ContractInteractionUtils.extractFunctionSelector(data);
        bytes32 constraintsHash = keccak256(constraints);

        // Verify function (selector + constraints hash) is in the allowed functions merkle tree
        bytes32 funcLeaf = _computeFunctionLeaf(selector, constraintsHash);
        return MerkleProof.verify(functionProof, policy.roots.allowedFunctionsRoot, funcLeaf);
    }

    /**
     * @notice Checks if transaction parameters match the specified constraints
     * @dev Iterates through each constraint and validates the corresponding parameter.
     *      Supports various parameter types (uint, int, address, bool, bytes, etc.) and
     *      constraint types (exact, range, list). Each constraint contains its own proof
     *      for OneOf constraints, eliminating the need for separate proof arrays.
     * @param parameterConstraints ABI-encoded array of ParameterConstraint structs
     * @param data The transaction calldata
     * @return True if all constraints are satisfied, false otherwise
     */
    function _areParametersAllowedByConstraints(bytes calldata parameterConstraints, bytes calldata data)
        private
        pure
        returns (bool)
    {
        // Case: No constraints defined, any parameters are accepted
        if (parameterConstraints.length == 0) return true;

        // Decode the constraints array
        Policies.ParameterConstraint[] memory constraints =
            abi.decode(parameterConstraints, (Policies.ParameterConstraint[]));

        // Case: No constraints in the array
        if (constraints.length == 0) return true;

        // Use a helper function to process constraints (reduces stack depth)
        return _processConstraints(constraints, data);
    }

    /**
     * @notice Internal helper to process parameter constraints
     * @dev Separated to manage stack depth in the main function.
     *      Each constraint is self-contained with its own merkle proof for OneOf constraints.
     * @param constraints The array of parameter constraints to validate
     * @param data The full transaction calldata
     * @return True if all constraints are satisfied, false otherwise
     */
    function _processConstraints(Policies.ParameterConstraint[] memory constraints, bytes calldata data)
        private
        pure
        returns (bool)
    {
        // Validate each parameter against its constraint
        // Parameters start at byte 4 (after the selector)
        uint256 paramCalldataOffset = 4;

        for (uint256 i = 0; i < constraints.length; ++i) {
            // Number of bytes this parameter's head occupies in calldata
            uint256 paramCalldataHeadSize = uint256(constraints[i].paramCalldataHeadSlotCount) * 32;

            // Case: Constraint is not configured correctly (paramCalldataHeadSlotCount == 0)
            if (paramCalldataHeadSize == 0) {
                return false;
            }

            // Case: Transaction data is too short for this parameter (not enough data for the full parameter head)
            if (data.length < paramCalldataOffset + paramCalldataHeadSize) {
                return false;
            }

            // Extract the first 32 bytes of the parameter head for validation
            // Note: For multi-slot params like static arrays/structs, only "Any" constraint is supported,
            // so we don't need to extract the full parameter value
            bytes32 paramHeadValue = bytes32(data[paramCalldataOffset:paramCalldataOffset + 32]);

            // Case: The parameter does not satisfy its constraint
            // Each constraint carries its own proof for OneOf constraints
            if (!_isParameterAllowedByConstraint(constraints[i], paramHeadValue, data)) {
                return false;
            }

            // Move on to the next parameter in calldata
            paramCalldataOffset += paramCalldataHeadSize;
        }

        return true;
    }

    /**
     * @notice Validates a Bool parameter against its constraint
     * @dev Bool only supports Exact constraint
     * @param constraintType The type of constraint to apply
     * @param comparisonData The expected value encoded as bytes
     * @param paramHeadValue The parameter value (first 32 bytes)
     * @return True if the parameter satisfies the constraint, false otherwise
     */
    function _isBoolParameterAllowedByConstraint(
        Policies.ConstraintType constraintType,
        bytes memory comparisonData,
        bytes32 paramHeadValue
    ) private pure returns (bool) {
        if (constraintType != Policies.ConstraintType.Exact) return false;
        bool expectedValue = abi.decode(comparisonData, (bool));
        bool actualValue = uint256(paramHeadValue) != 0;
        return actualValue == expectedValue;
    }

    /**
     * @notice Validates a Uint parameter against its constraint
     * @dev Uint supports Exact and Range constraints (also used for enums)
     * @param constraintType The type of constraint to apply
     * @param comparisonData The expected value(s) encoded as bytes
     * @param paramHeadValue The parameter value (first 32 bytes)
     * @return True if the parameter satisfies the constraint, false otherwise
     */
    function _isUintParameterAllowedByConstraint(
        Policies.ConstraintType constraintType,
        bytes memory comparisonData,
        bytes32 paramHeadValue
    ) private pure returns (bool) {
        uint256 actualValue = uint256(paramHeadValue);
        if (constraintType == Policies.ConstraintType.Exact) {
            uint256 expectedValue = abi.decode(comparisonData, (uint256));
            return actualValue == expectedValue;
        }
        if (constraintType == Policies.ConstraintType.Range) {
            (uint256 minValue, uint256 maxValue) = abi.decode(comparisonData, (uint256, uint256));
            return actualValue >= minValue && actualValue <= maxValue;
        }
        // Uint doesn't support OneOf constraint
        return false;
    }

    /**
     * @notice Validates an Int parameter against its constraint
     * @dev Int supports Exact and Range constraints
     * @param constraintType The type of constraint to apply
     * @param comparisonData The expected value(s) encoded as bytes
     * @param paramHeadValue The parameter value (first 32 bytes)
     * @return True if the parameter satisfies the constraint, false otherwise
     */
    function _isIntParameterAllowedByConstraint(
        Policies.ConstraintType constraintType,
        bytes memory comparisonData,
        bytes32 paramHeadValue
    ) private pure returns (bool) {
        int256 actualValue = int256(uint256(paramHeadValue));
        if (constraintType == Policies.ConstraintType.Exact) {
            int256 expectedValue = abi.decode(comparisonData, (int256));
            return actualValue == expectedValue;
        }
        if (constraintType == Policies.ConstraintType.Range) {
            (int256 minValue, int256 maxValue) = abi.decode(comparisonData, (int256, int256));
            return actualValue >= minValue && actualValue <= maxValue;
        }
        // Int doesn't support OneOf constraint
        return false;
    }

    /**
     * @notice Validates an Address parameter against its constraint
     * @dev Address supports Exact and OneOf constraints
     * @param constraintType The type of constraint to apply
     * @param comparisonData The expected value or merkle root encoded as bytes
     * @param paramHeadValue The parameter value (first 32 bytes)
     * @param addressListProof Merkle proof for OneOf constraint (empty for Exact constraint)
     * @return True if the parameter satisfies the constraint, false otherwise
     */
    function _isAddressParameterAllowedByConstraint(
        Policies.ConstraintType constraintType,
        bytes memory comparisonData,
        bytes32 paramHeadValue,
        bytes32[] memory addressListProof
    ) private pure returns (bool) {
        address actualValue = address(uint160(uint256(paramHeadValue)));
        if (constraintType == Policies.ConstraintType.Exact) {
            address expectedValue = abi.decode(comparisonData, (address));
            return actualValue == expectedValue;
        }
        if (constraintType == Policies.ConstraintType.OneOf) {
            // comparisonData contains the merkle root of allowed addresses
            bytes32 allowedAddressesRoot = abi.decode(comparisonData, (bytes32));
            // Compute leaf for the actual address using double-hashing
            bytes32 addressLeaf = MerkleUtils.computeAddressLeaf(actualValue);
            // Verify the address is in the allowed addresses merkle tree
            return MerkleProof.verify(addressListProof, allowedAddressesRoot, addressLeaf);
        }
        // Address doesn't support Range constraint
        return false;
    }

    /**
     * @notice Validates a FixedBytes parameter against its constraint
     * @dev FixedBytes (bytes1-bytes32) only supports Exact constraint.
     *      For fixed-size bytes, the value is stored directly in the 32-byte slot (left-aligned).
     * @param constraintType The type of constraint to apply
     * @param comparisonData The expected value encoded as bytes
     * @param paramHeadValue The parameter value (first 32 bytes)
     * @return True if the parameter satisfies the constraint, false otherwise
     */
    function _isFixedBytesParameterAllowedByConstraint(
        Policies.ConstraintType constraintType,
        bytes memory comparisonData,
        bytes32 paramHeadValue
    ) private pure returns (bool) {
        if (constraintType != Policies.ConstraintType.Exact) return false;
        bytes32 expectedValue = abi.decode(comparisonData, (bytes32));
        return paramHeadValue == expectedValue;
    }

    /**
     * @notice Validates a dynamic Bytes or String parameter against its constraint
     * @dev Dynamic bytes and strings only support Exact constraint (hash comparison).
     *      Both types have identical ABI encoding (offset -> length -> data), so this
     *      function handles both ParamType.Bytes and ParamType.String.
     *      The paramHeadValue contains the offset to the data location in calldata.
     *      The comparisonData should contain the keccak256 hash of the expected bytes/string.
     * @param constraintType The type of constraint to apply
     * @param comparisonData The expected hash encoded as bytes
     * @param paramHeadValue The parameter value (offset to bytes/string data)
     * @param data The full transaction calldata
     * @return True if the parameter satisfies the constraint, false otherwise
     */
    function _isBytesOrStringParameterAllowedByConstraint(
        Policies.ConstraintType constraintType,
        bytes memory comparisonData,
        bytes32 paramHeadValue,
        bytes calldata data
    ) private pure returns (bool) {
        if (constraintType != Policies.ConstraintType.Exact) return false;

        // paramHeadValue is the offset (relative to start of encoded params, i.e., after selector)
        uint256 offset = uint256(paramHeadValue);

        // The offset is relative to the start of the encoded parameters (after selector)
        // So actual position in data = 4 (selector) + offset
        uint256 dataPosition = 4 + offset;

        // First 32 bytes at that position is the length
        if (data.length < dataPosition + 32) return false;

        uint256 length = uint256(bytes32(data[dataPosition:dataPosition + 32]));

        // Check we have enough data for the content
        if (data.length < dataPosition + 32 + length) return false;

        // Hash the actual content
        bytes32 actualHash = keccak256(data[dataPosition + 32:dataPosition + 32 + length]);
        bytes32 expectedHash = abi.decode(comparisonData, (bytes32));
        return actualHash == expectedHash;
    }

    /**
     * @notice Validates a single parameter against its constraint
     * @dev Dispatches to type-specific validation functions based on parameter type.
     *      For Address+OneOf constraints, the merkle proof is read from constraint.paramValueInListProof.
     * @param constraint The constraint to validate against (includes proof for OneOf constraints)
     * @param paramHeadValue The parameter value (first 32 bytes)
     * @param data The full transaction calldata (for dynamic types)
     * @return True if the parameter satisfies the constraint, false otherwise
     */
    function _isParameterAllowedByConstraint(
        Policies.ParameterConstraint memory constraint,
        bytes32 paramHeadValue,
        bytes calldata data
    ) private pure returns (bool) {
        Policies.ParamType pType = constraint.paramType;
        Policies.ConstraintType constraintType = constraint.constraintType;

        // Case: Constraint is a wildcard constraint (any value is accepted)
        if (constraintType == Policies.ConstraintType.Any) {
            return true;
        }

        bytes memory comparisonData = constraint.comparisonData;

        if (pType == Policies.ParamType.Bool) {
            return _isBoolParameterAllowedByConstraint(constraintType, comparisonData, paramHeadValue);
        }

        if (pType == Policies.ParamType.Uint) {
            return _isUintParameterAllowedByConstraint(constraintType, comparisonData, paramHeadValue);
        }

        if (pType == Policies.ParamType.Int) {
            return _isIntParameterAllowedByConstraint(constraintType, comparisonData, paramHeadValue);
        }

        if (pType == Policies.ParamType.Address) {
            return _isAddressParameterAllowedByConstraint(
                constraintType, comparisonData, paramHeadValue, constraint.paramValueInListProof
            );
        }

        if (pType == Policies.ParamType.FixedBytes) {
            return _isFixedBytesParameterAllowedByConstraint(constraintType, comparisonData, paramHeadValue);
        }

        // Bytes and String have identical ABI encoding, so we use the same validation function
        if (pType == Policies.ParamType.Bytes || pType == Policies.ParamType.String) {
            return _isBytesOrStringParameterAllowedByConstraint(constraintType, comparisonData, paramHeadValue, data);
        }

        // Case: The parameter is an Array or Struct type, which only support the "Any" constraint
        // If we reach here, the constraint type is not "Any", which is invalid for these types.
        if (pType == Policies.ParamType.Array || pType == Policies.ParamType.Struct) {
            return false;
        }

        // Case: The parameter is an unknown type
        return false;
    }

    /**
     * @notice Validates that approver proofs have correct lengths
     * @dev Reverts if proof arrays don't match signature count
     * @param policy The policy to check against
     * @param approverProofs The proofs for approver membership verification
     * @param signatureCount The number of signatures provided
     */
    function _validateApproverProofsOrRevert(
        Policies.Policy memory policy,
        Policies.ApproverProofs memory approverProofs,
        uint8 signatureCount
    ) private pure {
        if (approverProofs.approverInOrgMembersTreeProofs.length != signatureCount) {
            revert MemberProofsLengthMismatch(signatureCount, approverProofs.approverInOrgMembersTreeProofs.length);
        }

        if (policy.config.approval.approverType == Policies.ApproverType.Group) {
            if (approverProofs.memberInGroupProofs.length != signatureCount) {
                revert MemberInGroupProofsLengthMismatch(signatureCount, approverProofs.memberInGroupProofs.length);
            }
        }
    }

    /**
     * @notice Computes the merkle leaf for a policy
     * @dev Uses double hashing (hash of hash) for security against second preimage attacks
     * @param policyId The unique identifier of the policy
     * @param policy The policy data
     * @return The computed merkle leaf
     */
    function _computePolicyLeaf(uint256 policyId, Policies.Policy memory policy) private pure returns (bytes32) {
        return keccak256(bytes.concat(keccak256(abi.encode(policyId, policy))));
    }

    /**
     * @notice Computes the merkle leaf for an allowed function
     * @dev Combines function selector with constraints hash
     * @param selector The function selector (first 4 bytes of calldata)
     * @param constraintsHash The keccak256 hash of the parameter constraints
     * @return The computed merkle leaf
     */
    function _computeFunctionLeaf(bytes4 selector, bytes32 constraintsHash) private pure returns (bytes32) {
        return keccak256(bytes.concat(keccak256(abi.encode(selector, constraintsHash))));
    }
}
