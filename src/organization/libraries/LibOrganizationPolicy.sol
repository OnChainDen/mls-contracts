// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { LibOrganizationPolicyStorage } from "./storage/LibOrganizationPolicyStorage.sol";
import { LibOrganizationMembersStorage } from "./storage/LibOrganizationMembersStorage.sol";
import { LibOrganizationGroupsStorage } from "./storage/LibOrganizationGroupsStorage.sol";
import { LibOrganizationWhitelistStorage } from "./storage/LibOrganizationWhitelistStorage.sol";
import { LibOrganizationSignatures } from "./LibOrganizationSignatures.sol";
import { Policies } from "../../libraries/Policies.sol";
import { SignatureUtils } from "../../libraries/SignatureUtils.sol";
import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/**
 * @title Lib Organization Policy
 * @notice Library for merkle-based policy operations
 * @dev Policies are stored in a global merkle tree. Only the root is stored on-chain.
 *      Full policy data is provided via calldata and verified against the root.
 *      This approach minimizes storage costs while maintaining security.
 * @author Den Technologies Inc
 */
library LibOrganizationPolicy {
    /**
     * @notice Emitted when the global policies merkle root is updated
     * @param newRoot The new merkle root containing all policies
     * @param ipfsCid The IPFS CID where full policy data is stored for disaster recovery
     */
    event PoliciesUpdated(bytes32 indexed newRoot, string ipfsCid);

    /**
     * @notice Thrown when a token transfer transaction has malformed data
     */
    error MalformedTokenTransfer();

    /**
     * @notice Thrown when policy verification against the merkle root fails
     */
    error PolicyVerificationFailed();

    // ================================
    // MERKLE HELPERS
    // ================================

    /**
     * @notice Computes the merkle leaf for a policy
     * @dev Uses double hashing (hash of hash) for security against second preimage attacks
     * @param policyId The ID of the policy
     * @param policy The policy data
     * @return The computed merkle leaf
     */
    function _computePolicyLeaf(uint256 policyId, Policies.Policy calldata policy) private pure returns (bytes32) {
        return keccak256(bytes.concat(keccak256(abi.encode(policyId, policy))));
    }

    /**
     * @notice Computes the merkle leaf for an address
     * @dev Used for source accounts and custom destinations merkle trees
     * @param addr The address to compute the leaf for
     * @return The computed merkle leaf
     */
    function _computeAddressLeaf(address addr) private pure returns (bytes32) {
        return keccak256(bytes.concat(keccak256(abi.encode(addr))));
    }

    /**
     * @notice Computes the merkle leaf for a function selector with constraints
     * @dev Used for allowed functions merkle tree
     * @param selector The function selector (first 4 bytes of calldata)
     * @param constraintsHash The hash of the parameter constraints for this function
     * @return The computed merkle leaf
     */
    function _computeFunctionLeaf(bytes4 selector, bytes32 constraintsHash) private pure returns (bytes32) {
        return keccak256(bytes.concat(keccak256(abi.encode(selector, constraintsHash))));
    }

    // ================================
    // POLICY VERIFICATION
    // ================================

    /**
     * @notice Verifies that a policy exists in the global merkle tree
     * @dev Uses merkle proof verification against the stored policies root
     * @param policyId The ID of the policy to verify
     * @param policy The policy data (from calldata)
     * @param proof The merkle proof for this policy
     * @return True if the policy exists in the tree, false otherwise
     */
    function policyExists(
        uint256 policyId,
        Policies.Policy calldata policy,
        bytes32[] calldata proof
    )
        internal
        view
        returns (bool)
    {
        bytes32 root = LibOrganizationPolicyStorage.layout().policiesRoot;
        bytes32 leaf = _computePolicyLeaf(policyId, policy);
        return MerkleProof.verify(proof, root, leaf);
    }

    /**
     * @notice Memory version of policyExists for internal calls
     * @dev Used when policy data is already in memory (e.g., after ABI decoding)
     * @param policyId The ID of the policy to verify
     * @param policy The policy data (from memory)
     * @param proof The merkle proof for this policy
     * @return True if the policy exists in the tree, false otherwise
     */
    function policyExistsMemory(
        uint256 policyId,
        Policies.Policy memory policy,
        bytes32[] memory proof
    )
        internal
        view
        returns (bool)
    {
        bytes32 root = LibOrganizationPolicyStorage.layout().policiesRoot;
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(policyId, policy))));
        return MerkleProof.verify(proof, root, leaf);
    }

    // ================================
    // MODIFY POLICIES
    // ================================

    /**
     * @notice Updates the global policies merkle root
     * @dev This is the only way to modify policies. All policy data is stored off-chain (IPFS).
     *      The IPFS CID is emitted in an event for disaster recovery purposes.
     * @param newPoliciesRoot The new merkle root containing all policies
     * @param ipfsCid The IPFS CID where full policy data is stored
     */
    function modifyPolicies(bytes32 newPoliciesRoot, string calldata ipfsCid) internal {
        LibOrganizationPolicyStorage.layout().policiesRoot = newPoliciesRoot;
        emit PoliciesUpdated(newPoliciesRoot, ipfsCid);
    }

    // ================================
    // POLICY VALIDATION
    // ================================

    /**
     * @notice Checks if a policy applies to a given transaction
     * @dev Verifies the policy exists and all its filters match the transaction
     * @param policyId The ID of the policy
     * @param sourceAccount The account initiating the transaction
     * @param to The destination address of the transaction
     * @param value The ETH value of the transaction
     * @param data The calldata of the transaction
     * @param initiator The address that initiated the transaction
     * @param proofs The validation proofs containing policy data and merkle proofs
     * @return True if the policy applies to this transaction, false otherwise
     */
    function doesPolicyApplyToTransaction(
        uint256 policyId,
        address sourceAccount,
        address to,
        uint256 value,
        bytes calldata data,
        address initiator,
        Policies.ValidationProofs calldata proofs
    )
        internal
        view
        returns (bool)
    {
        // First verify the policy exists in the merkle tree
        bytes32 policyLeaf = _computePolicyLeaf(policyId, proofs.policy);
        bytes32 root = LibOrganizationPolicyStorage.layout().policiesRoot;
        if (!MerkleProof.verify(proofs.policyProof, root, policyLeaf)) {
            return false;
        }

        // Check all policy filters
        if (!_doesMatchSourceAccount(proofs.policy, sourceAccount, proofs.sourceAccountProof)) {
            return false;
        }

        if (!_doesMatchInitiator(proofs.policy, initiator)) {
            return false;
        }

        if (!_doesMatchTransactionType(proofs.policy, to, value, data, proofs.functionProof, proofs.constraints)) {
            return false;
        }

        if (!_doesMatchDestination(proofs.policy, to, value, data, proofs.destinationProof)) {
            return false;
        }

        return true;
    }

    // ================================
    // FILTER MATCHING
    // ================================

    /**
     * @notice Checks if the source account matches the policy's source account filter
     * @dev If anySourceAccount is true, all accounts match. Otherwise, verifies via merkle proof.
     * @param policy The policy to check against
     * @param sourceAccount The source account address
     * @param sourceAccountProof The merkle proof for the source account
     * @return True if the source account matches the filter
     */
    function _doesMatchSourceAccount(
        Policies.Policy calldata policy,
        address sourceAccount,
        bytes32[] calldata sourceAccountProof
    )
        private
        pure
        returns (bool)
    {
        // If anySourceAccount flag is set, all accounts match
        if (Policies.anySourceAccountCalldata(policy)) return true;

        // Otherwise, verify the account is in the source accounts merkle tree
        bytes32 accountLeaf = _computeAddressLeaf(sourceAccount);
        return MerkleProof.verify(sourceAccountProof, policy.roots.sourceAccountsRoot, accountLeaf);
    }

    /**
     * @notice Checks if the initiator matches the policy's initiator filter
     * @dev If anyInitiator is true, all initiators match. Otherwise, checks member/group.
     * @param policy The policy to check against
     * @param initiatorAddress The initiator's address
     * @return True if the initiator matches the filter
     */
    function _doesMatchInitiator(
        Policies.Policy calldata policy,
        address initiatorAddress
    )
        private
        view
        returns (bool)
    {
        // If anyInitiator flag is set, all initiators match
        if (Policies.anyInitiatorCalldata(policy)) return true;

        // Get the member ID for this address
        LibOrganizationMembersStorage.Layout storage membersLayout = LibOrganizationMembersStorage.layout();
        uint8 memberId = membersLayout.addressToMemberId[initiatorAddress];

        // Address must be a registered member
        if (memberId == 0) return false;

        Policies.ApproverType initType = Policies.initiatorTypeCalldata(policy);
        uint8 initId = Policies.initiatorIdCalldata(policy);

        // Check if initiator matches based on type (Member or Group)
        if (initType == Policies.ApproverType.Member) {
            return memberId == initId;
        }

        if (initType == Policies.ApproverType.Group) {
            return _isMemberInGroup(initiatorAddress, initId);
        }

        return false;
    }

    /**
     * @notice Memory version of _doesMatchInitiator for internal calls
     * @param policy The policy to check against (from memory)
     * @param initiatorAddress The initiator's address
     * @return True if the initiator matches the filter
     */
    function _doesMatchInitiatorMemory(
        Policies.Policy memory policy,
        address initiatorAddress
    )
        private
        view
        returns (bool)
    {
        if (Policies.anyInitiator(policy)) return true;

        LibOrganizationMembersStorage.Layout storage membersLayout = LibOrganizationMembersStorage.layout();
        uint8 memberId = membersLayout.addressToMemberId[initiatorAddress];

        if (memberId == 0) return false;

        Policies.ApproverType initType = Policies.initiatorType(policy);
        uint8 initId = Policies.initiatorId(policy);

        if (initType == Policies.ApproverType.Member) {
            return memberId == initId;
        }

        if (initType == Policies.ApproverType.Group) {
            return _isMemberInGroup(initiatorAddress, initId);
        }

        return false;
    }

    /**
     * @notice Checks if the transaction type matches the policy's transaction type filter
     * @dev Handles Any, TokenTransfers, ContractInteractions, and Signatures types
     * @param policy The policy to check against
     * @param to The destination address
     * @param value The ETH value
     * @param data The transaction calldata
     * @param functionProof The merkle proof for the function (if ContractInteractions)
     * @param constraints The parameter constraints (if ContractInteractions)
     * @return True if the transaction type matches the filter
     */
    function _doesMatchTransactionType(
        Policies.Policy calldata policy,
        address to,
        uint256 value,
        bytes calldata data,
        bytes32[] calldata functionProof,
        bytes calldata constraints
    )
        private
        pure
        returns (bool)
    {
        Policies.TransactionType txType = Policies.transactionTypeCalldata(policy);

        // Any transaction type matches
        if (txType == Policies.TransactionType.Any) return true;

        // Token transfers (ETH or ERC20)
        if (txType == Policies.TransactionType.TokenTransfers) {
            // Must be a token transfer
            if (!isTransactionTokenTransfer(data, value)) return false;

            // Check token address filter
            if (!Policies.anyTokenCalldata(policy)) {
                address transferToken = extractTokenAddress(to, data);
                if (transferToken != policy.config.tokenAddress) return false;
            }

            // Check amount threshold
            if (Policies.hasAmountThresholdCalldata(policy)) {
                uint256 amount = extractTransferAmount(data, value);
                if (amount >= policy.config.amountThreshold) return false;
            }

            return true;
        }

        // Contract interactions (non-transfer function calls)
        if (txType == Policies.TransactionType.ContractInteractions) {
            // Must NOT be a token transfer
            if (isTransactionTokenTransfer(data, value)) return false;

            // Check function filter
            if (!_doesMatchFunction(policy, data, functionProof, constraints)) {
                return false;
            }

            return true;
        }

        return true;
    }

    /**
     * @notice Checks if the destination matches the policy's destination filter
     * @dev Handles Any, WhitelistedOnly, NonWhitelistedOnly, and CustomList types
     * @param policy The policy to check against
     * @param to The destination address
     * @param value The ETH value
     * @param data The transaction calldata
     * @param destinationProof The merkle proof for custom list destinations
     * @return True if the destination matches the filter
     */
    function _doesMatchDestination(
        Policies.Policy calldata policy,
        address to,
        uint256 value,
        bytes calldata data,
        bytes32[] calldata destinationProof
    )
        private
        view
        returns (bool)
    {
        Policies.DestinationType destType = Policies.destinationTypeCalldata(policy);

        // Any destination matches
        if (destType == Policies.DestinationType.Any) return true;

        // Get the actual destination (for token transfers, this is the recipient)
        address actualDestination = getActualDestination(to, data, value);

        // Destination must be on the organization's whitelist
        if (destType == Policies.DestinationType.WhitelistedOnly) {
            return _isAddressWhitelisted(actualDestination);
        }

        // Destination must NOT be on the organization's whitelist
        if (destType == Policies.DestinationType.NonWhitelistedOnly) {
            return !_isAddressWhitelisted(actualDestination);
        }

        // Destination must be in the policy's custom list (verified via merkle proof)
        if (destType == Policies.DestinationType.CustomList) {
            bytes32 destLeaf = _computeAddressLeaf(actualDestination);
            return MerkleProof.verify(destinationProof, policy.roots.customDestinationsRoot, destLeaf);
        }

        return false;
    }

    /**
     * @notice Checks if the function selector and constraints match the policy's function filter
     * @dev Verifies the function is in the allowed functions merkle tree and constraints match
     * @param policy The policy to check against
     * @param data The transaction calldata
     * @param functionProof The merkle proof for this function
     * @param constraints The parameter constraints to verify
     * @return True if the function matches the filter
     */
    function _doesMatchFunction(
        Policies.Policy calldata policy,
        bytes calldata data,
        bytes32[] calldata functionProof,
        bytes calldata constraints
    )
        private
        pure
        returns (bool)
    {
        // If anyFunction flag is set, all functions match
        if (Policies.anyFunctionCalldata(policy)) return true;

        // Must have at least 4 bytes for function selector
        if (data.length < 4) return false;

        bytes4 selector = bytes4(data[:4]);
        bytes32 constraintsHash = keccak256(constraints);

        // Verify the function is in the allowed functions merkle tree
        bytes32 funcLeaf = _computeFunctionLeaf(selector, constraintsHash);
        if (!MerkleProof.verify(functionProof, policy.roots.allowedFunctionsRoot, funcLeaf)) {
            return false;
        }

        // Verify the parameters match the constraints
        return doParametersMatchConstraints(constraints, data);
    }

    // ================================
    // APPROVER HELPERS
    // ================================

    /**
     * @notice Gets the number of required approvals for a policy
     * @dev For Member approvers, always returns 1. For Group approvers, returns the threshold.
     * @param policy The policy to check
     * @return The number of required approvals
     */
    function getRequiredApprovals(Policies.Policy calldata policy) internal pure returns (uint256) {
        if (Policies.approverTypeCalldata(policy) == Policies.ApproverType.Member) {
            return 1;
        }
        return Policies.approvalThresholdCalldata(policy);
    }

    /**
     * @notice Memory version of getRequiredApprovals
     * @param policy The policy to check (from memory)
     * @return The number of required approvals
     */
    function getRequiredApprovalsMemory(Policies.Policy memory policy) internal pure returns (uint256) {
        if (Policies.approverType(policy) == Policies.ApproverType.Member) {
            return 1;
        }
        return Policies.approvalThreshold(policy);
    }

    /**
     * @notice Checks if a signer is authorized to approve transactions for a policy
     * @dev Checks if the signer is the designated member or in the designated group
     * @param policy The policy to check against
     * @param signer The address of the signer
     * @return True if the signer is authorized
     */
    function isSignerAuthorizedForPolicy(
        Policies.Policy calldata policy,
        address signer
    )
        internal
        view
        returns (bool)
    {
        LibOrganizationMembersStorage.Layout storage membersLayout = LibOrganizationMembersStorage.layout();
        uint8 memberId = membersLayout.addressToMemberId[signer];

        // Signer must be a registered member
        if (memberId == 0) return false;

        Policies.ApproverType appType = Policies.approverTypeCalldata(policy);
        uint8 appId = Policies.approverIdCalldata(policy);

        if (appType == Policies.ApproverType.Member) {
            return memberId == appId;
        }

        if (appType == Policies.ApproverType.Group) {
            return _isMemberInGroup(memberId, appId);
        }

        return false;
    }

    /**
     * @notice Memory version of isSignerAuthorizedForPolicy
     * @param policy The policy to check against (from memory)
     * @param signer The address of the signer
     * @return True if the signer is authorized
     */
    function isSignerAuthorizedForPolicyMemory(
        Policies.Policy memory policy,
        address signer
    )
        internal
        view
        returns (bool)
    {
        LibOrganizationMembersStorage.Layout storage membersLayout = LibOrganizationMembersStorage.layout();
        uint8 memberId = membersLayout.addressToMemberId[signer];

        if (memberId == 0) return false;

        Policies.ApproverType appType = Policies.approverType(policy);
        uint8 appId = Policies.approverId(policy);

        if (appType == Policies.ApproverType.Member) {
            return memberId == appId;
        }

        if (appType == Policies.ApproverType.Group) {
            return _isMemberInGroup(memberId, appId);
        }

        return false;
    }

    /**
     * @notice Checks if an address matches the policy's initiator filter
     * @dev Public wrapper for _doesMatchInitiator
     * @param policy The policy to check against
     * @param initiatorAddress The address to check
     * @return True if the address matches the initiator filter
     */
    function doesTransactionMatchPolicyInitiator(
        Policies.Policy calldata policy,
        address initiatorAddress
    )
        internal
        view
        returns (bool)
    {
        return _doesMatchInitiator(policy, initiatorAddress);
    }

    /**
     * @notice Memory version of doesTransactionMatchPolicyInitiator
     * @param policy The policy to check against (from memory)
     * @param initiatorAddress The address to check
     * @return True if the address matches the initiator filter
     */
    function doesTransactionMatchPolicyInitiatorMemory(
        Policies.Policy memory policy,
        address initiatorAddress
    )
        internal
        view
        returns (bool)
    {
        return _doesMatchInitiatorMemory(policy, initiatorAddress);
    }

    /**
     * @notice Counts the number of valid approvals from a set of signatures
     * @dev Verifies each signature and checks if the signer is authorized for the policy
     * @param policy The policy to check against
     * @param signatures The concatenated signatures to verify
     * @param messageHash The hash that was signed
     * @return The number of valid approvals
     */
    function getValidApprovals(
        Policies.Policy calldata policy,
        bytes memory signatures,
        bytes32 messageHash
    )
        internal
        view
        returns (uint8)
    {
        if (signatures.length == 0) return 0;

        uint8 signatureCount = uint8(signatures.length / 65);
        uint8 validApprovals = 0;
        address lastSigner = address(0);

        for (uint8 i = 0; i < signatureCount; ++i) {
            bytes memory signature = SignatureUtils.extractSignature(signatures, i);
            address signer = LibOrganizationSignatures.extractSigner(signature);

            // Skip invalid signatures
            if (signer == address(0)) continue;

            // Signers must be in ascending order (prevents duplicates)
            if (signer <= lastSigner) continue;

            lastSigner = signer;

            // Verify the signature
            if (!SignatureChecker.isValidSignatureNow(signer, messageHash, signature)) {
                continue;
            }

            // Check if signer is authorized for this policy
            if (isSignerAuthorizedForPolicy(policy, signer)) {
                ++validApprovals;
            }
        }

        return validApprovals;
    }

    /**
     * @notice Memory version of getValidApprovals
     * @param policy The policy to check against (from memory)
     * @param signatures The concatenated signatures to verify
     * @param messageHash The hash that was signed
     * @return The number of valid approvals
     */
    function getValidApprovalsMemory(
        Policies.Policy memory policy,
        bytes memory signatures,
        bytes32 messageHash
    )
        internal
        view
        returns (uint8)
    {
        if (signatures.length == 0) return 0;

        uint8 signatureCount = uint8(signatures.length / 65);
        uint8 validApprovals = 0;
        address lastSigner = address(0);

        for (uint8 i = 0; i < signatureCount; ++i) {
            bytes memory signature = SignatureUtils.extractSignature(signatures, i);
            address signer = LibOrganizationSignatures.extractSigner(signature);

            if (signer == address(0)) continue;
            if (signer <= lastSigner) continue;

            lastSigner = signer;

            if (!SignatureChecker.isValidSignatureNow(signer, messageHash, signature)) {
                continue;
            }

            if (isSignerAuthorizedForPolicyMemory(policy, signer)) {
                ++validApprovals;
            }
        }

        return validApprovals;
    }

    // ================================
    // TRANSACTION HELPERS
    // ================================

    /**
     * @notice Gets the actual destination address for a transaction
     * @dev For token transfers, this returns the token recipient. For other transactions, returns `to`.
     * @param to The destination address of the transaction
     * @param data The transaction calldata
     * @param value The ETH value
     * @return The actual destination address
     */
    function getActualDestination(address to, bytes calldata data, uint256 value) internal pure returns (address) {
        if (data.length == 0) return to;
        if (!isTransactionTokenTransfer(data, value)) return to;
        return extractTokenRecipient(data);
    }

    /**
     * @notice Extracts the token recipient from ERC20 transfer calldata
     * @dev Handles both transfer(address,uint256) and transferFrom(address,address,uint256)
     * @param data The transaction calldata
     * @return The recipient address, or address(0) if not a recognized transfer
     */
    function extractTokenRecipient(bytes calldata data) internal pure returns (address) {
        if (data.length < 36) return address(0);

        bytes4 selector = bytes4(data[:4]);

        // transfer(address,uint256) - recipient is first parameter
        if (selector == bytes4(keccak256("transfer(address,uint256)"))) {
            return address(bytes20(data[16:36]));
        }

        // transferFrom(address,address,uint256) - recipient is second parameter
        if (selector == bytes4(keccak256("transferFrom(address,address,uint256)"))) {
            if (data.length < 68) return address(0);
            return address(bytes20(data[48:68]));
        }

        return address(0);
    }

    /**
     * @notice Checks if a transaction is a token transfer
     * @dev Returns true for ETH transfers (value > 0, no data) or ERC20 transfers
     * @param data The transaction calldata
     * @param value The ETH value
     * @return True if this is a token transfer
     */
    function isTransactionTokenTransfer(bytes calldata data, uint256 value) internal pure returns (bool) {
        // ETH transfer (no data, has value)
        if (data.length == 0 && value > 0) return true;

        // Must have at least 4 bytes for function selector
        if (data.length < 4) return false;

        // ERC20 transfers should not have ETH value
        if (value > 0) return false;

        bytes4 selector = bytes4(data[:4]);

        return selector == bytes4(keccak256("transfer(address,uint256)"))
            || selector == bytes4(keccak256("transferFrom(address,address,uint256)"));
    }

    /**
     * @notice Extracts the token address from a transaction
     * @dev For ERC20 transfers, the token address is the `to` address
     * @param to The destination address of the transaction
     * @param data The transaction calldata
     * @return The token address, or address(0) for ETH transfers
     */
    function extractTokenAddress(address to, bytes calldata data) internal pure returns (address) {
        if (data.length == 0) return address(0);
        return to;
    }

    /**
     * @notice Extracts the transfer amount from a transaction
     * @dev Handles ETH transfers and ERC20 transfers
     * @param data The transaction calldata
     * @param value The ETH value
     * @return The transfer amount
     */
    function extractTransferAmount(bytes calldata data, uint256 value) internal pure returns (uint256) {
        // ETH transfer
        if (data.length == 0) return value;

        // ERC20 transfer - amount is second parameter (at offset 36)
        if (data.length < 68) revert MalformedTokenTransfer();
        return uint256(bytes32(data[36:68]));
    }

    // ================================
    // PARAMETER CONSTRAINTS
    // ================================

    /**
     * @notice Checks if transaction parameters match the specified constraints
     * @dev Iterates through each constraint and validates the corresponding parameter
     * @param parameterConstraints ABI-encoded array of ParameterConstraint structs
     * @param data The transaction calldata
     * @return True if all parameters match their constraints
     */
    function doParametersMatchConstraints(
        bytes calldata parameterConstraints,
        bytes calldata data
    )
        internal
        pure
        returns (bool)
    {
        if (parameterConstraints.length == 0) return true;

        Policies.ParameterConstraint[] memory constraints =
            abi.decode(parameterConstraints, (Policies.ParameterConstraint[]));

        if (constraints.length == 0) return true;

        // Start after the 4-byte function selector
        uint256 paramOffset = 4;

        for (uint256 i = 0; i < constraints.length; ++i) {
            Policies.ParameterConstraint memory constraint = constraints[i];

            uint256 slotsToSkip = uint256(constraint.slotsToSkip);
            if (slotsToSkip == 0) return false;
            uint256 bytesToSkip = slotsToSkip * 32;

            // "Any" constraint type always matches
            if (constraint.constraintType == Policies.ConstraintType.Any) {
                paramOffset += bytesToSkip;
                continue;
            }

            // For non-Any constraints, we only support single-slot parameters
            if (slotsToSkip > 1) return false;
            if (data.length < paramOffset + 32) return false;

            bytes32 paramHeadValue = bytes32(data[paramOffset:paramOffset + 32]);

            if (!_validateParameter(constraint, paramHeadValue, data)) {
                return false;
            }

            paramOffset += bytesToSkip;
        }

        return true;
    }

    /**
     * @notice Validates a single parameter against its constraint
     * @dev Handles different parameter types (bool, uint, int, address, bytes, string)
     * @param constraint The constraint to validate against
     * @param paramHeadValue The first 32 bytes of the parameter
     * @param data The full transaction calldata (needed for dynamic types)
     * @return True if the parameter matches the constraint
     */
    function _validateParameter(
        Policies.ParameterConstraint memory constraint,
        bytes32 paramHeadValue,
        bytes calldata data
    )
        private
        pure
        returns (bool)
    {
        Policies.ParamType pType = constraint.paramType;
        Policies.ConstraintType cType = constraint.constraintType;
        bytes memory comparisonData = constraint.comparisonData;

        // Boolean parameters - only exact match supported
        if (pType == Policies.ParamType.Bool) {
            if (cType != Policies.ConstraintType.Exact) return false;
            return (uint256(paramHeadValue) != 0) == abi.decode(comparisonData, (bool));
        }

        // Unsigned integer parameters - exact and range supported
        if (pType == Policies.ParamType.Uint) {
            uint256 actualValue = uint256(paramHeadValue);
            if (cType == Policies.ConstraintType.Exact) {
                return actualValue == abi.decode(comparisonData, (uint256));
            }
            if (cType == Policies.ConstraintType.Range) {
                (uint256 minValue, uint256 maxValue) = abi.decode(comparisonData, (uint256, uint256));
                return actualValue >= minValue && actualValue <= maxValue;
            }
            return false;
        }

        // Signed integer parameters - exact and range supported
        if (pType == Policies.ParamType.Int) {
            int256 actualValue = int256(uint256(paramHeadValue));
            if (cType == Policies.ConstraintType.Exact) {
                return actualValue == abi.decode(comparisonData, (int256));
            }
            if (cType == Policies.ConstraintType.Range) {
                (int256 minValue, int256 maxValue) = abi.decode(comparisonData, (int256, int256));
                return actualValue >= minValue && actualValue <= maxValue;
            }
            return false;
        }

        // Address parameters - exact and list supported
        if (pType == Policies.ParamType.Address) {
            address actualValue = address(uint160(uint256(paramHeadValue)));
            if (cType == Policies.ConstraintType.Exact) {
                return actualValue == abi.decode(comparisonData, (address));
            }
            if (cType == Policies.ConstraintType.List) {
                address[] memory allowedAddresses = abi.decode(comparisonData, (address[]));
                for (uint256 i = 0; i < allowedAddresses.length; ++i) {
                    if (actualValue == allowedAddresses[i]) return true;
                }
                return false;
            }
            return false;
        }

        // Fixed bytes parameters - only exact match supported
        if (pType == Policies.ParamType.FixedBytes) {
            if (cType != Policies.ConstraintType.Exact) return false;
            return paramHeadValue == abi.decode(comparisonData, (bytes32));
        }

        // Dynamic bytes and string parameters - compared by hash
        if (pType == Policies.ParamType.Bytes || pType == Policies.ParamType.String) {
            if (cType != Policies.ConstraintType.Exact) return false;
            uint256 offset = uint256(paramHeadValue);
            uint256 dataPosition = 4 + offset;
            if (data.length < dataPosition + 32) return false;
            uint256 bytesLength = uint256(bytes32(data[dataPosition:dataPosition + 32]));
            if (data.length < dataPosition + 32 + bytesLength) return false;
            bytes32 actualHash = keccak256(data[dataPosition + 32:dataPosition + 32 + bytesLength]);
            return actualHash == abi.decode(comparisonData, (bytes32));
        }

        return false;
    }

    // ================================
    // PRIVATE HELPERS
    // ================================

    /**
     * @notice Checks if a member is in a group
     * @param memberId The member ID to check
     * @param groupId The group ID to check
     * @return True if the member is in the group
     */
    function _isMemberInGroup(uint8 memberId, uint8 groupId) private view returns (bool) {
        LibOrganizationMembersStorage.Layout storage membersLayout = LibOrganizationMembersStorage.layout();
        LibOrganizationGroupsStorage.Layout storage groupsLayout = LibOrganizationGroupsStorage.layout();

        // Member must exist
        if (membersLayout.memberIdToAddress[memberId] == address(0)) return false;

        return groupsLayout.groupIdToMemberIdToInGroup[groupId][memberId];
    }

    /**
     * @notice Checks if a member address is in a group
     * @param memberAddress The member's address to check
     * @param groupId The group ID to check
     * @return True if the member is in the group
     */
    function _isMemberInGroup(address memberAddress, uint8 groupId) private view returns (bool) {
        LibOrganizationMembersStorage.Layout storage membersLayout = LibOrganizationMembersStorage.layout();
        LibOrganizationGroupsStorage.Layout storage groupsLayout = LibOrganizationGroupsStorage.layout();
        uint8 memberId = membersLayout.addressToMemberId[memberAddress];

        // Address must be a registered member
        if (memberId == 0) return false;

        return groupsLayout.groupIdToMemberIdToInGroup[groupId][memberId];
    }

    /**
     * @notice Checks if an address is on the organization's whitelist
     * @param addressToCheck The address to check
     * @return True if the address is whitelisted
     */
    function _isAddressWhitelisted(address addressToCheck) private view returns (bool) {
        return LibOrganizationWhitelistStorage.layout().whitelistedAddresses[addressToCheck];
    }

    // ================================
    // TIME-BASED LIMITS
    // ================================

    /**
     * @notice Computes a unique key for tracking policy usage
     * @dev The key incorporates policy ID and scoped entities based on policy configuration
     * @param policyId The policy ID
     * @param policy The policy data
     * @param account The source account address
     * @param destination The destination address
     * @param initiator The initiator address
     * @return A unique bytes32 key for this usage combination
     */
    function computeUsageKey(
        uint256 policyId,
        Policies.Policy calldata policy,
        address account,
        address destination,
        address initiator
    )
        internal
        pure
        returns (bytes32)
    {
        // Apply scoping based on policy configuration
        address scopedAccount = Policies.timeIntervalSourceScopeCalldata(policy) == Policies.TimeIntervalScope.PerEntity
            ? account
            : address(0);
        address scopedDestination = Policies.timeIntervalDestinationScopeCalldata(policy)
            == Policies.TimeIntervalScope.PerEntity ? destination : address(0);
        address scopedInitiator = Policies.timeIntervalInitiatorScopeCalldata(policy)
            == Policies.TimeIntervalScope.PerEntity ? initiator : address(0);

        return keccak256(abi.encode(policyId, scopedAccount, scopedDestination, scopedInitiator));
    }

    /**
     * @notice Computes the current time window for a policy
     * @dev Time windows are based on hours since epoch
     * @param policy The policy data
     * @return The current time window number, or 0 if timeIntervalHours is 0
     */
    function computeTimeWindow(Policies.Policy calldata policy) internal view returns (uint256) {
        uint16 hours_ = Policies.timeIntervalHoursCalldata(policy);
        if (hours_ == 0) return 0;
        return block.timestamp / (uint256(hours_) * 3600);
    }

    /**
     * @notice Checks and updates time-based usage limits
     * @dev Only applies to policies with TimeInterval limitation
     * @param policyId The policy ID
     * @param policy The policy data
     * @param account The source account address
     * @param destination The destination address
     * @param initiator The initiator address
     * @param usageAmount The amount to add to usage
     * @return withinLimit True if the transaction is within the limit
     */
    function checkAndUpdateTimeBasedLimit(
        uint256 policyId,
        Policies.Policy calldata policy,
        address account,
        address destination,
        address initiator,
        uint256 usageAmount
    )
        internal
        returns (bool withinLimit)
    {
        // Skip if not a time-based policy
        if (Policies.limitationCalldata(policy) != Policies.PolicyLimitation.TimeInterval) return true;
        if (Policies.timeIntervalHoursCalldata(policy) == 0) return true;

        LibOrganizationPolicyStorage.Layout storage policyLayout = LibOrganizationPolicyStorage.layout();

        bytes32 usageKey = computeUsageKey(policyId, policy, account, destination, initiator);
        uint256 timeWindow = computeTimeWindow(policy);

        uint256 currentUsage = policyLayout.policyUsage[usageKey][timeWindow];

        // Check if adding this usage would exceed the limit
        if (currentUsage + usageAmount > policy.config.timeIntervalLimit) return false;

        // Update usage
        policyLayout.policyUsage[usageKey][timeWindow] = currentUsage + usageAmount;

        return true;
    }

    /**
     * @notice Gets the current usage for a time-based policy
     * @dev Returns 0 for non-time-based policies
     * @param policyId The policy ID
     * @param policy The policy data
     * @param account The source account address
     * @param destination The destination address
     * @param initiator The initiator address
     * @return The current usage amount in the current time window
     */
    function getCurrentUsage(
        uint256 policyId,
        Policies.Policy calldata policy,
        address account,
        address destination,
        address initiator
    )
        internal
        view
        returns (uint256)
    {
        if (Policies.limitationCalldata(policy) != Policies.PolicyLimitation.TimeInterval) return 0;
        if (Policies.timeIntervalHoursCalldata(policy) == 0) return 0;

        LibOrganizationPolicyStorage.Layout storage policyLayout = LibOrganizationPolicyStorage.layout();

        bytes32 usageKey = computeUsageKey(policyId, policy, account, destination, initiator);
        uint256 timeWindow = computeTimeWindow(policy);

        return policyLayout.policyUsage[usageKey][timeWindow];
    }

    // ================================
    // MEMORY VERSIONS FOR TESTS
    // ================================

    /**
     * @notice Memory version of computeUsageKey for testing
     * @param policyId The policy ID
     * @param policy The policy data (from memory)
     * @param account The source account address
     * @param destination The destination address
     * @param initiator The initiator address
     * @return A unique bytes32 key for this usage combination
     */
    function computeUsageKeyMemory(
        uint256 policyId,
        Policies.Policy memory policy,
        address account,
        address destination,
        address initiator
    )
        internal
        pure
        returns (bytes32)
    {
        address scopedAccount =
            Policies.timeIntervalSourceScope(policy) == Policies.TimeIntervalScope.PerEntity ? account : address(0);
        address scopedDestination = Policies.timeIntervalDestinationScope(policy)
            == Policies.TimeIntervalScope.PerEntity ? destination : address(0);
        address scopedInitiator =
            Policies.timeIntervalInitiatorScope(policy) == Policies.TimeIntervalScope.PerEntity ? initiator : address(0);

        return keccak256(abi.encode(policyId, scopedAccount, scopedDestination, scopedInitiator));
    }

    /**
     * @notice Memory version of computeTimeWindow for testing
     * @param policy The policy data (from memory)
     * @return The current time window number
     */
    function computeTimeWindowMemory(Policies.Policy memory policy) internal view returns (uint256) {
        uint16 hours_ = Policies.timeIntervalHours(policy);
        if (hours_ == 0) return 0;
        return block.timestamp / (uint256(hours_) * 3600);
    }

    /**
     * @notice Memory version of checkAndUpdateTimeBasedLimit for testing
     * @param policyId The policy ID
     * @param policy The policy data (from memory)
     * @param account The source account address
     * @param destination The destination address
     * @param initiator The initiator address
     * @param usageAmount The amount to add to usage
     * @return withinLimit True if the transaction is within the limit
     */
    function checkAndUpdateTimeBasedLimitMemory(
        uint256 policyId,
        Policies.Policy memory policy,
        address account,
        address destination,
        address initiator,
        uint256 usageAmount
    )
        internal
        returns (bool withinLimit)
    {
        if (Policies.limitation(policy) != Policies.PolicyLimitation.TimeInterval) return true;
        if (Policies.timeIntervalHours(policy) == 0) return true;

        LibOrganizationPolicyStorage.Layout storage policyLayout = LibOrganizationPolicyStorage.layout();

        bytes32 usageKey = computeUsageKeyMemory(policyId, policy, account, destination, initiator);
        uint256 timeWindow = computeTimeWindowMemory(policy);

        uint256 currentUsage = policyLayout.policyUsage[usageKey][timeWindow];

        if (currentUsage + usageAmount > policy.config.timeIntervalLimit) return false;

        policyLayout.policyUsage[usageKey][timeWindow] = currentUsage + usageAmount;

        return true;
    }

    /**
     * @notice Memory version of getCurrentUsage for testing
     * @param policyId The policy ID
     * @param policy The policy data (from memory)
     * @param account The source account address
     * @param destination The destination address
     * @param initiator The initiator address
     * @return The current usage amount in the current time window
     */
    function getCurrentUsageMemory(
        uint256 policyId,
        Policies.Policy memory policy,
        address account,
        address destination,
        address initiator
    )
        internal
        view
        returns (uint256)
    {
        if (Policies.limitation(policy) != Policies.PolicyLimitation.TimeInterval) return 0;
        if (Policies.timeIntervalHours(policy) == 0) return 0;

        LibOrganizationPolicyStorage.Layout storage policyLayout = LibOrganizationPolicyStorage.layout();

        bytes32 usageKey = computeUsageKeyMemory(policyId, policy, account, destination, initiator);
        uint256 timeWindow = computeTimeWindowMemory(policy);

        return policyLayout.policyUsage[usageKey][timeWindow];
    }
}
