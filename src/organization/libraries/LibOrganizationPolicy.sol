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
     * @notice Thrown when a token transfer transaction is malformed
     */
    error MalformedTokenTransfer();

    /**
     * @notice Thrown when policy verification fails
     */
    error PolicyVerificationFailed();

    // ================================
    // MERKLE HELPERS
    // ================================

    /**
     * @notice Computes the merkle leaf for a policy
     * @dev Uses double hashing (hash of hash) for security against second preimage attacks
     * @param policyId The unique identifier of the policy
     * @param policy The policy data
     * @return The computed merkle leaf
     */
    function _computePolicyLeaf(uint256 policyId, Policies.Policy calldata policy) private pure returns (bytes32) {
        return keccak256(bytes.concat(keccak256(abi.encode(policyId, policy))));
    }

    /**
     * @notice Computes the merkle leaf for an address (used for source accounts and destinations)
     * @dev Uses double hashing for security
     * @param addr The address to compute the leaf for
     * @return The computed merkle leaf
     */
    function _computeAddressLeaf(address addr) private pure returns (bytes32) {
        return keccak256(bytes.concat(keccak256(abi.encode(addr))));
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

    // ================================
    // POLICY VERIFICATION
    // ================================

    /**
     * @notice Verifies that a policy exists in the global merkle tree (calldata version)
     * @param policyId The unique identifier of the policy
     * @param policy The policy data from calldata
     * @param proof The merkle proof for the policy
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
     * @notice Verifies that a policy exists in the global merkle tree (memory version)
     * @dev Used when policy data has been decoded into memory (e.g., in ERC-1271 validation)
     * @param policyId The unique identifier of the policy
     * @param policy The policy data from memory
     * @param proof The merkle proof for the policy
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
     *      Emits PoliciesUpdated event with the IPFS CID for disaster recovery.
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
     * @dev Performs comprehensive validation including:
     *      1. Policy existence (via merkle proof)
     *      2. Source account matching
     *      3. Initiator authorization
     *      4. Transaction type matching
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
        // 1. Verify policy exists in the global merkle tree
        bytes32 policyLeaf = _computePolicyLeaf(policyId, proofs.policy);
        bytes32 root = LibOrganizationPolicyStorage.layout().policiesRoot;
        if (!MerkleProof.verify(proofs.policyProof, root, policyLeaf)) {
            return false;
        }

        // 2. Check if the source account matches
        if (!_doesMatchSourceAccount(proofs.policy, sourceAccount, proofs.sourceAccountProof)) {
            return false;
        }

        // 3. Check if the initiator is authorized
        if (!_doesMatchInitiator(proofs.policy, initiator)) {
            return false;
        }

        // 4. Check if the transaction type matches
        if (!_doesMatchTransactionType(proofs.policy, to, value, data, proofs.functionProof, proofs.constraints)) {
            return false;
        }

        // 5. Check if the destination matches
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
     * @dev If anySourceAccount is true, always returns true.
     *      Otherwise, verifies the account is in the policy's source accounts merkle tree.
     * @param policy The policy to check against
     * @param sourceAccount The source account address
     * @param sourceAccountProof The merkle proof for the source account
     * @return True if the source account matches, false otherwise
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
        // Case: The policy matches transactions sent from any account
        if (policy.config.anySourceAccount) return true;

        // Case: The policy matches transactions sent from a list of specific source accounts
        // Verify this account is in the source accounts merkle tree
        bytes32 accountLeaf = _computeAddressLeaf(sourceAccount);
        return MerkleProof.verify(sourceAccountProof, policy.roots.sourceAccountsRoot, accountLeaf);
    }

    /**
     * @notice Checks if the initiator matches the policy's initiator filter (calldata version)
     * @dev If anyInitiator is true, always returns true.
     *      Otherwise, checks if the initiator is the specified member or in the specified group.
     * @param policy The policy to check against
     * @param initiatorAddress The address of the transaction initiator
     * @return True if the initiator matches, false otherwise
     */
    function _doesMatchInitiator(
        Policies.Policy calldata policy,
        address initiatorAddress
    )
        internal
        view
        returns (bool)
    {
        // Case: The policy matches transactions with any initiator
        if (policy.config.initiator.anyInitiator) return true;

        LibOrganizationMembersStorage.Layout storage membersLayout = LibOrganizationMembersStorage.layout();

        // Get the member ID for the initiator
        uint8 memberId = membersLayout.addressToMemberId[initiatorAddress];

        // Case: Initiator is not a member of the organization
        if (memberId == 0) return false;

        Policies.ApproverType initType = policy.config.initiator.initiatorType;
        uint8 initId = policy.config.initiator.initiatorId;

        // Case: The policy matches transactions made by a specific individual, and that individual
        //        is the initiator of this transaction
        if (initType == Policies.ApproverType.Member) {
            return memberId == initId;
        }

        // Case: The policy matches transactions made by any individual from a specific group, and the initiator
        //       is in that group
        if (initType == Policies.ApproverType.Group) {
            return _isMemberInGroup(initiatorAddress, initId);
        }

        // Case: The policy does not match this transaction
        return false;
    }

    /**
     * @notice Checks if the initiator matches the policy's initiator filter (memory version)
     * @dev Used when policy data is in memory (e.g., ERC-1271 validation)
     * @param policy The policy to check against
     * @param initiatorAddress The address of the transaction initiator
     * @return True if the initiator matches, false otherwise
     */
    function _doesMatchInitiatorMemory(
        Policies.Policy memory policy,
        address initiatorAddress
    )
        internal
        view
        returns (bool)
    {
        // Case: The policy matches transactions with any initiator
        if (policy.config.initiator.anyInitiator) return true;

        LibOrganizationMembersStorage.Layout storage membersLayout = LibOrganizationMembersStorage.layout();

        // Get the member ID for the initiator
        uint8 memberId = membersLayout.addressToMemberId[initiatorAddress];

        // Case: Initiator is not a member of the organization
        if (memberId == 0) return false;

        Policies.ApproverType initType = policy.config.initiator.initiatorType;
        uint8 initId = policy.config.initiator.initiatorId;

        // Case: The policy matches transactions made by a specific individual, and that individual
        //        is the initiator of this transaction
        if (initType == Policies.ApproverType.Member) {
            return memberId == initId;
        }

        // Case: The policy matches transactions made by any individual from a specific group, and the initiator
        //       is in that group
        if (initType == Policies.ApproverType.Group) {
            return _isMemberInGroup(initiatorAddress, initId);
        }

        // Case: The policy does not match this transaction
        return false;
    }

    /**
     * @notice Checks if the transaction type matches the policy's transaction type filter
     * @dev Handles different transaction types:
     *      - Any: Always matches
     *      - TokenTransfers: Must be a token transfer, optionally with token/amount constraints
     *      - ContractInteractions: Must not be a token transfer, optionally with function constraints
     * @param policy The policy to check against
     * @param to The transaction destination address
     * @param value The transaction value in wei
     * @param data The transaction calldata
     * @param functionProof The merkle proof for the function (for ContractInteractions)
     * @param constraints The parameter constraints (for ContractInteractions)
     * @return True if the transaction type matches, false otherwise
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
        Policies.TransactionType txType = policy.config.transactionType;

        // Case: The policy matches any type of transaction
        if (txType == Policies.TransactionType.Any) return true;

        // Case: Policy matches only transactions that are token transfers
        if (txType == Policies.TransactionType.TokenTransfers) {
            // Case: The transaction is not a token transfer
            if (!isTransactionTokenTransfer(data, value)) return false;

            // Case: The Policy matches only transactions that are token transfers that are of a
            //       specific token, and the transaction is not transferring that token
            if (!policy.config.token.anyToken) {
                address transferToken = extractTokenAddress(to, data);
                if (transferToken != policy.config.token.tokenAddress) return false;
            }

            // Case: The policy matches only transactions that are token transfers that are of a
            //       specific token, and the transaction is transferring that token, but the
            //       transaction amount is less than the amount threshold
            if (policy.config.token.hasAmountThreshold) {
                uint256 amount = extractTransferAmount(data, value);
                if (amount >= policy.config.token.amountThreshold) return false;
            }

            return true;
        }

        // Case: The policy matches only transactions that are contract interactions that are not token transfers
        if (txType == Policies.TransactionType.ContractInteractions) {
            // Case: The policy matches only transactions that are contract interactions that are not token transfers,
            //       but the transaction is a token transfer
            if (isTransactionTokenTransfer(data, value)) return false;

            // Case: The policy matches only transactions that are contract interactions that call a specific function,
            //       but the transaction is not calling that function
            if (!_doesMatchFunction(policy, data, functionProof, constraints)) {
                return false;
            }

            return true;
        }

        // Case: The policy does not fail to match the transaction based on the transaction type filters
        return true;
    }

    /**
     * @notice Checks if the destination matches the policy's destination filter
     * @dev Handles different destination types:
     *      - Any: Always matches
     *      - WhitelistedOnly: Must be in the organization's whitelist
     *      - NonWhitelistedOnly: Must NOT be in the organization's whitelist
     *      - CustomList: Must be in the policy's custom destinations merkle tree
     * @param policy The policy to check against
     * @param to The transaction destination address
     * @param value The transaction value in wei
     * @param data The transaction calldata
     * @param destinationProof The merkle proof for the destination (for CustomList)
     * @return True if the destination matches, false otherwise
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
        Policies.DestinationType destType = policy.config.destinationType;

        // Case: Policy matches transaction to any address
        if (destType == Policies.DestinationType.Any) return true;

        // Determine the actual destination address based on transaction type
        address actualDestination = getActualDestination(to, data, value);

        // Case: Policy matches only transactions that are sent to whitelisted addresses
        if (destType == Policies.DestinationType.WhitelistedOnly) {
            return _isAddressWhitelisted(actualDestination);
        }

        // Case: Policy matches only transactions that are sent to non-whitelisted addresses
        if (destType == Policies.DestinationType.NonWhitelistedOnly) {
            return !_isAddressWhitelisted(actualDestination);
        }

        // Case: Policy matches only transactions that are sent to a specific list of addresses
        // Verify via merkle proof that destination is in the custom destinations tree
        if (destType == Policies.DestinationType.CustomList) {
            bytes32 destLeaf = _computeAddressLeaf(actualDestination);
            return MerkleProof.verify(destinationProof, policy.roots.customDestinationsRoot, destLeaf);
        }

        // Case: The policy does not match the transaction destination
        return false;
    }

    /**
     * @notice Checks if the function matches the policy's allowed functions filter
     * @dev If anyFunction is true, always returns true.
     *      Otherwise, verifies the function selector and constraints are in the allowed functions merkle tree.
     * @param policy The policy to check against
     * @param data The transaction calldata
     * @param functionProof The merkle proof for the function
     * @param constraints The parameter constraints to verify
     * @return True if the function matches, false otherwise
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
        // Case: Policy matches any function
        if (policy.config.anyFunction) return true;

        // Case: Policy matches only transactions that call a specific function, but the transaction is not calling
        //       a function
        if (data.length < 4) return false;

        // Case: Policy matches only transactions that call a specific function, and the transaction is calling
        //       a function - verify via merkle proof
        bytes4 selector = bytes4(data[:4]);
        bytes32 constraintsHash = keccak256(constraints);

        // Verify function (selector + constraints hash) is in the allowed functions merkle tree
        bytes32 funcLeaf = _computeFunctionLeaf(selector, constraintsHash);
        if (!MerkleProof.verify(functionProof, policy.roots.allowedFunctionsRoot, funcLeaf)) {
            return false;
        }

        // Case: Parameter constraints defined - validate them
        // Verify parameters match constraints
        return doParametersMatchConstraints(constraints, data);
    }

    // ================================
    // APPROVER HELPERS
    // ================================

    /**
     * @notice Gets the number of required approvals for a policy (calldata version)
     * @dev For Member approver type, always returns 1.
     *      For Group approver type, returns the approval threshold.
     * @param policy The policy to check
     * @return The number of required approvals
     */
    function getRequiredApprovals(Policies.Policy calldata policy) internal pure returns (uint256) {
        // Case: Policy requires a single approval from a member
        if (policy.config.approval.approverType == Policies.ApproverType.Member) {
            return 1;
        }

        // Case: Policy requires a threshold number of approvals from any individual in a group
        return policy.config.approval.approvalThreshold;
    }

    /**
     * @notice Gets the number of required approvals for a policy (memory version)
     * @param policy The policy to check
     * @return The number of required approvals
     */
    function getRequiredApprovalsMemory(Policies.Policy memory policy) internal pure returns (uint256) {
        // Case: Policy requires a single approval from a member
        if (policy.config.approval.approverType == Policies.ApproverType.Member) {
            return 1;
        }

        // Case: Policy requires a threshold number of approvals from any individual in a group
        return policy.config.approval.approvalThreshold;
    }

    /**
     * @notice Checks if a signer is authorized to approve for a policy (calldata version)
     * @dev For Member approver type, the signer must be the specified member.
     *      For Group approver type, the signer must be in the specified group.
     * @param policy The policy to check against
     * @param signerAddress The address of the signer
     * @return True if the signer is authorized, false otherwise
     */
    function isSignerAuthorizedForPolicy(
        Policies.Policy calldata policy,
        address signerAddress
    )
        internal
        view
        returns (bool)
    {
        LibOrganizationMembersStorage.Layout storage membersLayout = LibOrganizationMembersStorage.layout();

        // Get the member ID for the signer
        uint8 memberId = membersLayout.addressToMemberId[signerAddress];

        // Case: Signer is not a member of the organization
        if (memberId == 0) return false;

        Policies.ApproverType appType = policy.config.approval.approverType;
        uint8 approverId = policy.config.approval.approverId;

        // Case: Policy requires approval from a specific member
        if (appType == Policies.ApproverType.Member) {
            return memberId == approverId;
        }

        // Case: Policy requires approval from any member of a specific group
        if (appType == Policies.ApproverType.Group) {
            return _isMemberInGroup(memberId, approverId);
        }

        return false;
    }

    /**
     * @notice Checks if a signer is authorized to approve for a policy (memory version)
     * @param policy The policy to check against
     * @param signerAddress The address of the signer
     * @return True if the signer is authorized, false otherwise
     */
    function isSignerAuthorizedForPolicyMemory(
        Policies.Policy memory policy,
        address signerAddress
    )
        internal
        view
        returns (bool)
    {
        LibOrganizationMembersStorage.Layout storage membersLayout = LibOrganizationMembersStorage.layout();

        // Get the member ID for the signer
        uint8 memberId = membersLayout.addressToMemberId[signerAddress];

        // Case: Signer is not a member of the organization
        if (memberId == 0) return false;

        Policies.ApproverType appType = policy.config.approval.approverType;
        uint8 approverId = policy.config.approval.approverId;

        // Case: Policy requires approval from a specific member
        if (appType == Policies.ApproverType.Member) {
            return memberId == approverId;
        }

        // Case: Policy requires approval from any member of a specific group
        if (appType == Policies.ApproverType.Group) {
            return _isMemberInGroup(memberId, approverId);
        }

        return false;
    }

    /**
     * @notice Counts valid approvals from a set of signatures (calldata version)
     * @dev Signatures must be ordered by signer address (ascending) to prevent duplicates.
     *      Each signature is verified against the message hash and checked for authorization.
     * @param policy The policy to check against
     * @param signatures The concatenated signatures (65 bytes each)
     * @param messageHash The message hash that was signed
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
        // Case: No signatures provided
        if (signatures.length == 0) return 0;

        // Each signature is 65 bytes (r: 32, s: 32, v: 1)
        uint8 signatureCount = uint8(signatures.length / 65);
        uint8 validApprovals = 0;

        // Track last signer to prevent duplicates (similar to Safe contracts)
        address lastSigner = address(0);

        // Iterate over signatures to count valid approvals
        for (uint8 i = 0; i < signatureCount; ++i) {
            bytes memory signature = SignatureUtils.extractSignature(signatures, i);

            // Extract signer address from signature
            address signer = LibOrganizationSignatures.extractSigner(signature);

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

            // Check if signer is authorized based on policy
            if (isSignerAuthorizedForPolicy(policy, signer)) {
                ++validApprovals;
            }
        }

        return validApprovals;
    }

    /**
     * @notice Counts valid approvals from a set of signatures (memory version)
     * @param policy The policy to check against
     * @param signatures The concatenated signatures (65 bytes each)
     * @param messageHash The message hash that was signed
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
        // Case: No signatures provided
        if (signatures.length == 0) return 0;

        // Each signature is 65 bytes (r: 32, s: 32, v: 1)
        uint8 signatureCount = uint8(signatures.length / 65);
        uint8 validApprovals = 0;

        // Track last signer to prevent duplicates (similar to Safe contracts)
        address lastSigner = address(0);

        // Iterate over signatures to count valid approvals
        for (uint8 i = 0; i < signatureCount; ++i) {
            bytes memory signature = SignatureUtils.extractSignature(signatures, i);

            // Extract signer address from signature
            address signer = LibOrganizationSignatures.extractSigner(signature);

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

            // Check if signer is authorized based on policy
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
        if (!isTransactionTokenTransfer(data, value)) return to;

        // Case: The transaction is an ERC-20 token transfer
        // Extract the recipient address from the transfer function call
        return extractTokenRecipient(data);
    }

    /**
     * @notice Extracts the token recipient from token transfer calldata
     * @dev Supports ERC20 transfer(address,uint256) and transferFrom(address,address,uint256)
     * @param data The transaction calldata
     * @return The recipient address, or address(0) if not a valid token transfer
     */
    function extractTokenRecipient(bytes calldata data) internal pure returns (address) {
        // Case: Transaction data is too short to contain a valid selector
        if (data.length < 36) return address(0);

        bytes4 selector = bytes4(data[:4]);

        // Case: The transaction is calling the `transfer` function
        // transfer(address to, uint256 amount)
        // The recipient is the first parameter after the selector
        if (selector == bytes4(keccak256("transfer(address,uint256)"))) {
            return address(bytes20(data[16:36]));
        }

        // Case: The transaction is calling the `transferFrom` function
        // transferFrom(address from, address to, uint256 amount)
        // Note: The recipient is the second address parameter after the selector
        if (selector == bytes4(keccak256("transferFrom(address,address,uint256)"))) {
            // Case: Transaction data is too short to contain a valid recipient
            if (data.length < 68) return address(0);
            return address(bytes20(data[48:68]));
        }

        // Case: The transaction is not a valid ERC-20 transfer
        return address(0);
    }

    /**
     * @notice Checks if a transaction is a token transfer
     * @dev A transaction is considered a token transfer if:
     *      1. It has value > 0 and no data (native token transfer), OR
     *      2. It calls transfer(address,uint256) or transferFrom(address,address,uint256)
     * @param data The transaction calldata
     * @param value The transaction value in wei
     * @return True if the transaction is a token transfer, false otherwise
     */
    function isTransactionTokenTransfer(bytes calldata data, uint256 value) internal pure returns (bool) {
        // Case: The transaction is a native token transfer
        if (data.length == 0 && value > 0) return true;

        // Case: The transaction data is too short to call a function
        if (data.length < 4) return false;

        // Case: The transaction is not a native token transfer, but the value is greater than zero
        if (value > 0) return false;

        // Case: The transaction is a token transfer
        bytes4 selector = bytes4(data[:4]);

        // Case: The transaction is a token transfer
        if (
            selector == bytes4(keccak256("transfer(address,uint256)"))
                || selector == bytes4(keccak256("transferFrom(address,address,uint256)"))
        ) {
            return true;
        }

        // Case: The transaction is not a token transfer
        return false;
    }

    /**
     * @notice Extracts the token contract address from a token transfer
     * @dev For ERC20 transfers, the token contract is the `to` address.
     *      For native transfers, returns address(0).
     * @param to The transaction `to` address
     * @param data The transaction calldata
     * @return The token contract address
     */
    function extractTokenAddress(address to, bytes calldata data) internal pure returns (address) {
        if (data.length == 0) {
            return address(0); // Native token
        }
        return to; // ERC20 token address
    }

    /**
     * @notice Extracts the transfer amount from a token transfer
     * @dev For native transfers, returns the transaction value.
     *      For ERC20 transfers, extracts the amount from calldata.
     * @param data The transaction calldata
     * @param value The transaction value in wei
     * @return The transfer amount
     */
    function extractTransferAmount(bytes calldata data, uint256 value) internal pure returns (uint256) {
        // Case: The transaction is a native token transfer
        if (data.length == 0) return value;

        // Case: The ERC-20 transaction is malformed
        // Note: 4 bytes selector + 32 bytes address + 32 bytes amount = 68 bytes
        if (data.length < 68) revert MalformedTokenTransfer();

        // Case: The ERC-20 transaction is transferring a non-zero value
        // ERC20 transfer - amount is second parameter (offset 36-68)
        return uint256(bytes32(data[36:68]));
    }

    // ================================
    // PARAMETER CONSTRAINTS
    // ================================

    /**
     * @notice Checks if transaction parameters match the specified constraints
     * @dev Iterates through each constraint and validates the corresponding parameter.
     *      Supports various parameter types (uint, int, address, bool, bytes, etc.) and
     *      constraint types (exact, range, list).
     * @param parameterConstraints ABI-encoded array of ParameterConstraint structs
     * @param data The transaction calldata
     * @return True if all constraints are satisfied, false otherwise
     */
    function doParametersMatchConstraints(
        bytes calldata parameterConstraints,
        bytes calldata data
    )
        internal
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

        // Validate each parameter against its constraint
        // Parameters start at byte 4 (after the selector)
        // Each basic parameter is 32 bytes in ABI encoding, but static arrays/structs may span multiple slots
        uint256 paramOffset = 4; // Start after the 4-byte selector

        for (uint256 i = 0; i < constraints.length; ++i) {
            Policies.ParameterConstraint memory constraint = constraints[i];

            // Determine how many 32-byte slots this parameter occupies (must be >= 1)
            uint256 slotsToSkip = uint256(constraint.slotsToSkip);
            if (slotsToSkip == 0) {
                return false; // Invalid constraint configuration
            }
            uint256 bytesToSkip = slotsToSkip * 32;

            // Case: Wildcard constraint - any value is accepted, skip all slots for this parameter
            if (constraint.constraintType == Policies.ConstraintType.Any) {
                paramOffset += bytesToSkip;
                continue;
            }

            // Case: The parameter is a static-sized array or struct but the ConstraintType is not Any
            // This is invalid configuration, so we return false (static-sized array and structs are
            // not allowed to have constraints other than Any)
            if (slotsToSkip > 1) {
                return false;
            }

            // Case: Transaction data is too short for this parameter
            if (data.length < paramOffset + 32) {
                return false;
            }

            // Extract the parameter value from the head section of the transaction data
            //
            // If the parameter is a static-sized type (e.g. uint, int, address, bool, bytes1-32),
            // the value in the head section of the transaction data is the value of the parameter itself,
            // and is stored in a single 32-byte slot.
            //
            // If the parameter is a dynamic-sized type (e.g. bytes, string, dynamic array),
            // the value in the head section of the transaction data is the offset location of the value. The offset
            // location is stored in a single 32-byte slot. The offset location is relative to the start of the encoded
            // parameters (after the selector). The actual value(s) is/are stored in the tail section of the
            // transaction data, starting at the offset location.
            //
            // If the parameter is a static-sized array or struct, the value in the head section of the transaction
            // data is the value of the parameter itself, but may take up multiple slots. We only allow
            // ConstraintType.Any for static-sized arrays and structs, so we would have skipped over them already.
            bytes32 paramHeadValue = bytes32(data[paramOffset:paramOffset + 32]);

            // Validate based on parameter type and constraint type
            // Note: Dynamic types (Bytes, String) need access to the full data to dereference offsets
            if (!_validateParameter(constraint, paramHeadValue, data)) {
                return false;
            }

            paramOffset += bytesToSkip; // Move past all slots for this parameter
        }

        return true;
    }

    /**
     * @notice Validates a single parameter against its constraint
     * @dev Handles different parameter types and constraint types
     * @param constraint The constraint to validate against
     * @param paramHeadValue The parameter value (first 32 bytes)
     * @param data The full transaction calldata (for dynamic types)
     * @return True if the parameter satisfies the constraint, false otherwise
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

        // Handle Bool type
        // Bool only supports Exact constraint
        if (pType == Policies.ParamType.Bool) {
            if (cType != Policies.ConstraintType.Exact) return false;
            bool expectedValue = abi.decode(comparisonData, (bool));
            bool actualValue = uint256(paramHeadValue) != 0;
            return actualValue == expectedValue;
        }

        // Handle Uint type (and enums which are treated as uint)
        if (pType == Policies.ParamType.Uint) {
            uint256 actualValue = uint256(paramHeadValue);
            if (cType == Policies.ConstraintType.Exact) {
                uint256 expectedValue = abi.decode(comparisonData, (uint256));
                return actualValue == expectedValue;
            }
            if (cType == Policies.ConstraintType.Range) {
                (uint256 minValue, uint256 maxValue) = abi.decode(comparisonData, (uint256, uint256));
                return actualValue >= minValue && actualValue <= maxValue;
            }
            // Uint doesn't support List constraint
            return false;
        }

        // Handle Int type
        if (pType == Policies.ParamType.Int) {
            int256 actualValue = int256(uint256(paramHeadValue));
            if (cType == Policies.ConstraintType.Exact) {
                int256 expectedValue = abi.decode(comparisonData, (int256));
                return actualValue == expectedValue;
            }
            if (cType == Policies.ConstraintType.Range) {
                (int256 minValue, int256 maxValue) = abi.decode(comparisonData, (int256, int256));
                return actualValue >= minValue && actualValue <= maxValue;
            }
            // Int doesn't support List constraint
            return false;
        }

        // Handle Address type
        if (pType == Policies.ParamType.Address) {
            address actualValue = address(uint160(uint256(paramHeadValue)));
            if (cType == Policies.ConstraintType.Exact) {
                address expectedValue = abi.decode(comparisonData, (address));
                return actualValue == expectedValue;
            }
            if (cType == Policies.ConstraintType.List) {
                address[] memory allowedAddresses = abi.decode(comparisonData, (address[]));
                for (uint256 i = 0; i < allowedAddresses.length; ++i) {
                    if (actualValue == allowedAddresses[i]) return true;
                }
                return false;
            }
            // Address doesn't support Range constraint
            return false;
        }

        // Handle FixedBytes type (bytes1-bytes32, stored inline)
        // FixedBytes only supports Exact constraint
        // For fixed-size bytes, the value is stored directly in the 32-byte slot (left-aligned)
        if (pType == Policies.ParamType.FixedBytes) {
            if (cType != Policies.ConstraintType.Exact) return false;
            bytes32 expectedValue = abi.decode(comparisonData, (bytes32));
            return paramHeadValue == expectedValue;
        }

        // Handle Bytes type (dynamic bytes, stored as offset)
        // Dynamic bytes only supports Exact constraint (hash comparison)
        // The paramHeadValue contains the offset to the data location in calldata.
        // The comparisonData should contain the keccak256 hash of the expected bytes.
        if (pType == Policies.ParamType.Bytes) {
            if (cType != Policies.ConstraintType.Exact) return false;

            // paramHeadValue is the offset (relative to start of encoded params, i.e., after selector)
            uint256 offset = uint256(paramHeadValue);

            // The offset is relative to the start of the encoded parameters (after selector)
            // So actual position in data = 4 (selector) + offset
            uint256 dataPosition = 4 + offset;

            // First 32 bytes at that position is the length
            if (data.length < dataPosition + 32) return false;

            uint256 bytesLength = uint256(bytes32(data[dataPosition:dataPosition + 32]));

            // Check we have enough data for the bytes content
            if (data.length < dataPosition + 32 + bytesLength) return false;

            // Hash the actual bytes content
            bytes32 actualHash = keccak256(data[dataPosition + 32:dataPosition + 32 + bytesLength]);
            bytes32 expectedHash = abi.decode(comparisonData, (bytes32));
            return actualHash == expectedHash;
        }

        // Handle String type (dynamic string, stored as offset)
        // String only supports Exact constraint (hash comparison)
        // The paramHeadValue contains the offset to the string data in calldata.
        // The comparisonData should contain the keccak256 hash of the expected string.
        if (pType == Policies.ParamType.String) {
            if (cType != Policies.ConstraintType.Exact) return false;

            // paramHeadValue is the offset (relative to start of encoded params, i.e., after selector)
            uint256 offset = uint256(paramHeadValue);

            // The offset is relative to the start of the encoded parameters (after selector)
            // So actual position in data = 4 (selector) + offset
            uint256 dataPosition = 4 + offset;

            // First 32 bytes at that position is the string length
            if (data.length < dataPosition + 32) return false;

            uint256 strLength = uint256(bytes32(data[dataPosition:dataPosition + 32]));

            // Check we have enough data for the string content
            if (data.length < dataPosition + 32 + strLength) return false;

            // Hash the actual string content
            bytes32 actualHash = keccak256(data[dataPosition + 32:dataPosition + 32 + strLength]);
            bytes32 expectedHash = abi.decode(comparisonData, (bytes32));
            return actualHash == expectedHash;
        }

        // Handle Array and Struct types - only Any constraint is valid
        // These types can only have Any constraint, which is handled earlier
        // If we reach here with a non-Any constraint, it's invalid configuration

        // Unknown type - fail safe
        return false;
    }

    // ================================
    // PRIVATE HELPERS
    // ================================

    /**
     * @notice Checks if a member is in a group (by member ID)
     * @param memberId The member's ID
     * @param groupId The group's ID
     * @return True if the member is in the group, false otherwise
     */
    function _isMemberInGroup(uint8 memberId, uint8 groupId) private view returns (bool) {
        LibOrganizationMembersStorage.Layout storage membersLayout = LibOrganizationMembersStorage.layout();
        LibOrganizationGroupsStorage.Layout storage groupsLayout = LibOrganizationGroupsStorage.layout();

        // Case: Member does not exist
        if (membersLayout.memberIdToAddress[memberId] == address(0)) return false;

        return groupsLayout.groupIdToMemberIdToInGroup[groupId][memberId];
    }

    /**
     * @notice Checks if a member is in a group (by member address)
     * @param memberAddress The member's address
     * @param groupId The group's ID
     * @return True if the member is in the group, false otherwise
     */
    function _isMemberInGroup(address memberAddress, uint8 groupId) private view returns (bool) {
        LibOrganizationMembersStorage.Layout storage membersLayout = LibOrganizationMembersStorage.layout();
        LibOrganizationGroupsStorage.Layout storage groupsLayout = LibOrganizationGroupsStorage.layout();
        uint8 memberId = membersLayout.addressToMemberId[memberAddress];

        // Case: Member does not exist
        if (memberId == 0) return false;

        return groupsLayout.groupIdToMemberIdToInGroup[groupId][memberId];
    }

    /**
     * @notice Checks if an address is in the organization's whitelist
     * @param addressToCheck The address to check
     * @return True if the address is whitelisted, false otherwise
     */
    function _isAddressWhitelisted(address addressToCheck) private view returns (bool) {
        return LibOrganizationWhitelistStorage.layout().whitelistedAddresses[addressToCheck];
    }

    // ================================
    // TIME-BASED LIMITS
    // ================================

    /**
     * @notice Computes the usage key for time-based limit tracking (calldata version)
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
        Policies.Policy calldata policy,
        address account,
        address destination,
        address initiator
    )
        internal
        pure
        returns (bytes32)
    {
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
     * @notice Computes the current time window for a policy (calldata version)
     * @dev Time windows are calculated as: block.timestamp / (timeIntervalHours * 3600)
     * @param policy The policy data
     * @return The current time window, or 0 if timeIntervalHours is 0
     */
    function computeTimeWindow(Policies.Policy calldata policy) internal view returns (uint256) {
        // Uses fixed time windows based on timeIntervalHours
        uint16 hours_ = policy.config.timeLimit.timeIntervalHours;

        // Avoid division by zero
        if (hours_ == 0) return 0;

        return block.timestamp / (uint256(hours_) * 3600);
    }

    /**
     * @notice Checks and updates time-based usage limits (calldata version)
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
        Policies.Policy calldata policy,
        address account,
        address destination,
        address initiator,
        uint256 usageAmount
    )
        internal
        returns (bool withinLimit)
    {
        // Skip check if no time-based limitation
        if (policy.config.timeLimit.limitation != Policies.PolicyLimitation.TimeInterval) return true;

        // Skip if time interval is not configured (0 hours)
        if (policy.config.timeLimit.timeIntervalHours == 0) return true;

        LibOrganizationPolicyStorage.Layout storage policyLayout = LibOrganizationPolicyStorage.layout();

        bytes32 usageKey = computeUsageKey(policyId, policy, account, destination, initiator);
        uint256 timeWindow = computeTimeWindow(policy);

        uint256 currentUsage = policyLayout.policyUsage[usageKey][timeWindow];

        // Check if adding usageAmount would exceed the limit
        if (currentUsage + usageAmount > policy.config.timeLimit.timeIntervalLimit) return false;

        // Update usage
        policyLayout.policyUsage[usageKey][timeWindow] = currentUsage + usageAmount;

        return true;
    }

    /**
     * @notice Gets the current usage for a time-based policy (calldata version)
     * @param policyId The policy ID
     * @param policy The policy data
     * @param account The source account address
     * @param destination The destination address
     * @param initiator The initiator address
     * @return The current usage amount within the current time window
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
        // Return 0 if no time-based limitation
        if (policy.config.timeLimit.limitation != Policies.PolicyLimitation.TimeInterval) return 0;

        // Return 0 if time interval is not configured
        if (policy.config.timeLimit.timeIntervalHours == 0) return 0;

        LibOrganizationPolicyStorage.Layout storage policyLayout = LibOrganizationPolicyStorage.layout();

        bytes32 usageKey = computeUsageKey(policyId, policy, account, destination, initiator);
        uint256 timeWindow = computeTimeWindow(policy);

        return policyLayout.policyUsage[usageKey][timeWindow];
    }

    // ================================
    // MEMORY VERSIONS FOR TESTS/INTERNAL USE
    // ================================

    /**
     * @notice Computes the usage key for time-based limit tracking (memory version)
     * @dev Used when policy data is in memory (e.g., in tests)
     * @param policyId The policy ID
     * @param policy The policy data
     * @param account The source account address
     * @param destination The destination address
     * @param initiator The initiator address
     * @return The computed usage key
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
     * @notice Computes the current time window for a policy (memory version)
     * @param policy The policy data
     * @return The current time window, or 0 if timeIntervalHours is 0
     */
    function computeTimeWindowMemory(Policies.Policy memory policy) internal view returns (uint256) {
        // Uses fixed time windows based on timeIntervalHours
        uint16 hours_ = policy.config.timeLimit.timeIntervalHours;

        // Avoid division by zero
        if (hours_ == 0) return 0;

        return block.timestamp / (uint256(hours_) * 3600);
    }

    /**
     * @notice Checks and updates time-based usage limits (memory version)
     * @dev Used when policy data is in memory (e.g., in tests)
     * @param policyId The policy ID
     * @param policy The policy data
     * @param account The source account address
     * @param destination The destination address
     * @param initiator The initiator address
     * @param usageAmount The amount to add to usage
     * @return withinLimit True if within limit (and usage was updated), false otherwise
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
        // Skip check if no time-based limitation
        if (policy.config.timeLimit.limitation != Policies.PolicyLimitation.TimeInterval) return true;

        // Skip if time interval is not configured (0 hours)
        if (policy.config.timeLimit.timeIntervalHours == 0) return true;

        LibOrganizationPolicyStorage.Layout storage policyLayout = LibOrganizationPolicyStorage.layout();

        bytes32 usageKey = computeUsageKeyMemory(policyId, policy, account, destination, initiator);
        uint256 timeWindow = computeTimeWindowMemory(policy);

        uint256 currentUsage = policyLayout.policyUsage[usageKey][timeWindow];

        // Check if adding usageAmount would exceed the limit
        if (currentUsage + usageAmount > policy.config.timeLimit.timeIntervalLimit) return false;

        // Update usage
        policyLayout.policyUsage[usageKey][timeWindow] = currentUsage + usageAmount;

        return true;
    }

    /**
     * @notice Gets the current usage for a time-based policy (memory version)
     * @param policyId The policy ID
     * @param policy The policy data
     * @param account The source account address
     * @param destination The destination address
     * @param initiator The initiator address
     * @return The current usage amount within the current time window
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
        // Return 0 if no time-based limitation
        if (policy.config.timeLimit.limitation != Policies.PolicyLimitation.TimeInterval) return 0;

        // Return 0 if time interval is not configured
        if (policy.config.timeLimit.timeIntervalHours == 0) return 0;

        LibOrganizationPolicyStorage.Layout storage policyLayout = LibOrganizationPolicyStorage.layout();

        bytes32 usageKey = computeUsageKeyMemory(policyId, policy, account, destination, initiator);
        uint256 timeWindow = computeTimeWindowMemory(policy);

        return policyLayout.policyUsage[usageKey][timeWindow];
    }
}
