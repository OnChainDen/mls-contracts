// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { LibAccountTransactionStorage } from "./storage/LibAccountTransactionStorage.sol";
import { LibAccountOrganizationAddressStorage } from "./storage/LibAccountOrganizationAddressStorage.sol";
import { LibOrganizationPolicyStorage } from "../../organization/libraries/storage/LibOrganizationPolicyStorage.sol";
import { LibOrganizationMembersStorage } from "../../organization/libraries/storage/LibOrganizationMembersStorage.sol";
import { LibOrganizationGroupsStorage } from "../../organization/libraries/storage/LibOrganizationGroupsStorage.sol";
import { LibOrganizationWhitelistStorage } from
    "../../organization/libraries/storage/LibOrganizationWhitelistStorage.sol";
import { Policies } from "../../libraries/Policies.sol";
import { SignatureUtils } from "../../libraries/SignatureUtils.sol";
import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { LibAccountGuardian } from "./LibAccountGuardian.sol";
import { IOrganizationMembersFacet } from "../../organization/interfaces/IOrganizationMembersFacet.sol";

/**
 * @title Lib Account Transaction
 * @notice Library for transaction-related operations for Account contracts
 * @dev This library should ONLY be used by Account contracts
 * @author Den Technologies Inc
 */
library LibAccountTransaction {
    /**
     * @notice Emitted when a transaction is executed
     * @param to The destination address of the transaction
     * @param value The value of the transaction
     * @param data The data of the transaction
     * @param nonce The nonce used for this transaction
     * @param policyId The policy ID that governed this transaction
     */
    event TransactionExecuted(
        address indexed to, uint256 value, bytes data, uint256 indexed nonce, uint256 indexed policyId
    );

    /**
     * @notice Emitted when a transaction is rejected
     * @param reason The reason for the rejection
     */
    event TransactionRejected(string reason);

    /**
     * @notice Emitted when a transaction is rejected by a policy
     * @param reason The reason for the rejection
     */
    error TransactionRejectedByPolicy(string reason);

    /**
     * @notice Emitted when a transaction is rejected by authorized users
     * @param to The destination address of the transaction
     * @param value The value of the transaction
     * @param data The data of the transaction
     * @param operation The operation of the transaction
     * @param nonce The nonce used for this transaction
     * @param rejectedBy The address that rejected the transaction
     * @param policyId The policy ID that governed this transaction
     */
    event TransactionRejectedByUser(
        address indexed to,
        uint256 value,
        bytes data,
        LibAccountTransactionStorage.Operation operation,
        uint256 indexed nonce,
        address rejectedBy,
        uint256 indexed policyId
    );

    /**
     * @notice Emitted when a transaction is rejected because it has insufficient approvals
     * @param required The number of required approvals
     * @param provided The number of provided approvals
     */
    error InsufficientApprovals(uint256 required, uint256 provided);

    /**
     * @notice Emitted when a transaction is rejected because it has an invalid signature
     */
    error InvalidSignature();

    /**
     * @notice Emitted when a transaction is rejected because the nonce provided has already been used
     * @param nonce The nonce that was attempted to be used
     */
    error NonceAlreadyUsed(uint256 nonce);

    /**
     * @notice Emitted when a transaction is rejected because of wrong chain ID
     * @param expected The expected chain ID
     * @param provided The provided chain ID
     */
    error InvalidChainId(uint256 expected, uint256 provided);

    /**
     * @notice Emitted when a transaction is rejected because the policy does not exist
     * @param policyId The policy ID that was not found
     */
    error PolicyNotFound(uint256 policyId);

    /**
     * @notice Emitted when a transaction is rejected because the policy does not apply to the transaction
     * @param policyId The policy ID that does not apply
     */
    error PolicyDoesNotApply(uint256 policyId);

    /**
     * @notice Checks if a nonce has been used
     * @param nonce The nonce to check
     * @return True if the nonce has been used, false otherwise
     */
    function isNonceUsed(uint256 nonce) internal view returns (bool) {
        return LibAccountTransactionStorage.layout().usedNonces[nonce];
    }

    /**
     * @notice Computes a deterministic nonce from transaction data and salt
     * @param to The destination address of the transaction
     * @param value The value of the transaction
     * @param data The data of the transaction
     * @param salt A user-provided salt for nonce computation
     * @param policyId The policy ID governing this transaction
     * @return The computed nonce
     */
    function computeNonce(
        address to,
        uint256 value,
        bytes calldata data,
        uint256 salt,
        uint256 policyId
    )
        internal
        view
        returns (uint256)
    {
        return uint256(keccak256(abi.encode(address(this), to, value, keccak256(data), salt, policyId)));
    }

    /**
     * @notice Executes a transaction from this account based on the policies of the onchain custody contract
     * @param to The destination address of the transaction
     * @param value The value of the transaction
     * @param data The data of the transaction
     * @param salt A user-provided salt for nonce computation
     * @param policyId The ID of the policy that governs this transaction
     * @param signatures The signatures of the transaction
     */
    function executeTransaction(
        address to,
        uint256 value,
        bytes calldata data,
        uint256 salt,
        uint256 policyId,
        bytes memory signatures
    )
        internal
    {
        LibAccountGuardian.enforceOnlyGuardian();

        // Compute deterministic nonce from transaction data, salt, and policyId
        uint256 nonce = computeNonce(to, value, data, salt, policyId);

        LibAccountTransactionStorage.Layout storage txLayout = LibAccountTransactionStorage.layout();

        // Validate and consume nonce for replay protection
        if (txLayout.usedNonces[nonce]) {
            revert NonceAlreadyUsed(nonce);
        }

        // Mark nonce as used
        txLayout.usedNonces[nonce] = true;

        // Check policies to make sure this transaction can be executed
        _validateTransaction(policyId, to, value, data, salt, signatures);

        // Execute the transaction
        _execute(to, value, data, gasleft());

        emit TransactionExecuted(to, value, data, nonce, policyId);
    }

    /**
     * @notice Rejects a transaction that has been signed but not yet executed
     * @param to The destination address of the transaction
     * @param value The value of the transaction
     * @param data The data of the transaction
     * @param operation The operation of the transaction
     * @param salt A user-provided salt for nonce computation
     * @param policyId The ID of the policy that governs this transaction
     * @param chainId The chain ID for cross-chain replay protection - must match current chain ID
     * @param signatures The signatures of the transaction
     */
    function rejectTransaction(
        address to,
        uint256 value,
        bytes calldata data,
        LibAccountTransactionStorage.Operation operation,
        uint256 salt,
        uint256 policyId,
        uint256 chainId,
        bytes memory signatures
    )
        internal
    {
        LibAccountGuardian.enforceOnlyGuardian();

        // Validate chain ID for cross-chain replay protection
        if (chainId != block.chainid) {
            revert InvalidChainId(block.chainid, chainId);
        }

        // Compute deterministic nonce from transaction data, salt, and policyId
        uint256 nonce = computeNonce(to, value, data, salt, policyId);

        LibAccountTransactionStorage.Layout storage txLayout = LibAccountTransactionStorage.layout();

        // Validate and consume nonce for replay protection
        if (txLayout.usedNonces[nonce]) {
            revert NonceAlreadyUsed(nonce);
        }

        // Mark nonce as used to prevent execution
        txLayout.usedNonces[nonce] = true;

        // Check if the caller is authorized to reject this transaction
        _validateRejectionAuthorization(policyId, to, value, data, salt, signatures);

        emit TransactionRejectedByUser(to, value, data, operation, nonce, msg.sender, policyId);
    }

    /**
     * @notice Validates a transaction against the specified policy
     * @param policyId The ID of the policy to validate against
     * @param to Transaction destination address
     * @param value Transaction value
     * @param data Transaction data
     * @param salt User-provided salt for nonce computation
     * @param signatures Signatures for approval verification
     */
    function _validateTransaction(
        uint256 policyId,
        address to,
        uint256 value,
        bytes memory data,
        uint256 salt,
        bytes memory signatures
    )
        private
        view
    {
        LibOrganizationPolicyStorage.Layout storage policyStorage = LibOrganizationPolicyStorage.layout();

        // Validate that policy exists
        if (!policyStorage.policyExists[policyId]) {
            revert PolicyNotFound(policyId);
        }

        // Look up policy directly
        Policies.Policy memory policy = policyStorage.policies[policyId];

        // Validate that policy applies to transaction
        if (!_doesPolicyApplyToTransaction(policy, address(this), to, value, data, msg.sender)) {
            revert PolicyDoesNotApply(policyId);
        }

        // Case: Policy is a manual approval policy
        // Check if the transaction has enough valid approvals
        if (policy.policyType == Policies.PolicyType.RequireManualApproval) {
            // Get transaction hash for signature verification
            bytes32 txHash = _getTransactionHash(to, value, data, salt, policyId, true);
            uint256 requiredApprovals = _getRequiredApprovals(policy);
            uint256 validApprovals = _getValidApprovals(policy, signatures, txHash);

            // Case: Transaction does not have enough valid approvals
            // Revert the transaction
            if (validApprovals < requiredApprovals) {
                revert InsufficientApprovals(requiredApprovals, validApprovals);
            }
            // Case: Transaction has enough valid approvals
            // Return
            else {
                return;
            }
        }

        // Case: Policy is AutoApprove
        // Require a single signature from any organization member
        if (policy.policyType == Policies.PolicyType.AutoApprove) {
            bytes32 txHash = _getTransactionHash(to, value, data, salt, policyId, true);

            // Check if we have a valid signature from any organization member
            if (!_hasValidMemberSignature(signatures, txHash)) {
                revert TransactionRejectedByPolicy(
                    "AutoApprove policy requires a signature from an organization member"
                );
            }
            return;
        }
    }

    /**
     * @notice Validates that the caller is authorized to reject the given transaction
     * @param policyId The ID of the policy to validate against
     * @param to Transaction destination address
     * @param value Transaction value
     * @param data Transaction data
     * @param salt User-provided salt for nonce computation
     * @param signatures Signatures for approval verification
     */
    function _validateRejectionAuthorization(
        uint256 policyId,
        address to,
        uint256 value,
        bytes memory data,
        uint256 salt,
        bytes memory signatures
    )
        private
        view
    {
        LibOrganizationPolicyStorage.Layout storage policyStorage = LibOrganizationPolicyStorage.layout();

        // Validate that policy exists
        if (!policyStorage.policyExists[policyId]) {
            revert PolicyNotFound(policyId);
        }

        // Look up policy directly
        Policies.Policy memory policy = policyStorage.policies[policyId];

        // Validate that policy applies to transaction
        if (!_doesPolicyApplyToTransaction(policy, address(this), to, value, data, msg.sender)) {
            revert PolicyDoesNotApply(policyId);
        }

        // Case: Policy is an automatic approval policy
        // Only valid transaction initiators (as defined by policy) can reject it
        if (policy.policyType == Policies.PolicyType.AutoApprove) {
            // Get transaction hash for signature verification
            bytes32 txHash = _getTransactionHash(to, value, data, salt, policyId, false);

            // Check if we have at least one valid signature from an authorized initiator
            if (_hasValidInitiatorSignature(policy, signatures, txHash)) {
                return;
            } else {
                revert TransactionRejectedByPolicy("No valid signature from authorized transaction initiator");
            }
        }

        // Case: Policy is a manual approval policy
        // Check if the caller has sufficient rejection authority
        if (policy.policyType == Policies.PolicyType.RequireManualApproval) {
            // Get transaction hash for signature verification
            bytes32 txHash = _getTransactionHash(to, value, data, salt, policyId, false);
            uint256 requiredApprovals = _getRequiredApprovals(policy);
            uint256 validApprovals = _getValidApprovals(policy, signatures, txHash);

            // Case: Transaction does not have enough valid rejections
            // Revert the transaction
            if (validApprovals < requiredApprovals) {
                revert InsufficientApprovals(requiredApprovals, validApprovals);
            }
            // Case: Transaction has enough valid rejections
            // Return
            else {
                return;
            }
        }
    }

    /**
     * @notice Verifies signatures and returns the number of valid approvals
     * @param policy The policy requiring approval
     * @param signatures The signatures to verify
     * @param txHash The hash of the transaction
     * @return The number of valid approvals
     */
    function _getValidApprovals(
        Policies.Policy memory policy,
        bytes memory signatures,
        bytes32 txHash
    )
        private
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

            // Extract signer address from signature using ERC-1271 compatible verification
            address signer = _getSigner(signature, txHash);

            // Skip if signer is invalid
            if (signer == address(0)) continue;

            // Check for duplicate signers - signers must be unique and in ascending order
            // This prevents both duplicate signatures and replay attacks
            if (signer <= lastSigner) continue;

            // Update last signer for next iteration
            lastSigner = signer;

            // Verify the signature using ERC-1271
            if (!SignatureChecker.isValidSignatureNow(signer, txHash, signature)) {
                continue;
            }

            // Check if signer is authorized based on policy
            if (_isSignerAuthorizedForPolicy(policy, signer)) {
                ++validApprovals;
            }
        }

        return validApprovals;
    }

    /**
     * @notice Gets the signer address from a signature
     * @param signature The signature to extract the signer from
     * @param txHash The hash that was signed (unused for ERC-1271 signatures with signer prefix)
     * @return The signer address, or address(0) if invalid
     */
    function _getSigner(bytes memory signature, bytes32 txHash) private pure returns (address) {
        // Silence unused parameter warning
        txHash;
        // For ERC-1271, we assume the first 20 bytes of the signature contain the signer address
        // This is a common pattern where the signature is prefixed with the signer address
        if (signature.length < 20) {
            return address(0);
        }

        address signer;
        /* solhint-disable no-inline-assembly */
        assembly {
            signer := mload(add(signature, 20))
        }
        return signer;
    }

    /**
     * @notice Checks if there is at least one valid signature from an authorized transaction initiator
     * @param policy The policy to check against
     * @param signatures The signatures to verify
     * @param txHash The hash of the transaction
     * @return True if there is at least one valid signature from an authorized initiator, false otherwise
     */
    function _hasValidInitiatorSignature(
        Policies.Policy memory policy,
        bytes memory signatures,
        bytes32 txHash
    )
        private
        view
        returns (bool)
    {
        // Case: No signatures provided
        if (signatures.length == 0) return false;

        // Each signature is 65 bytes (r: 32, s: 32, v: 1)
        uint8 signatureCount = uint8(signatures.length / 65);

        // Iterate over signatures to find at least one valid initiator signature
        for (uint8 i = 0; i < signatureCount; ++i) {
            bytes memory signature = SignatureUtils.extractSignature(signatures, i);

            // Extract signer address from signature using ERC-1271 compatible verification
            address signer = _getSigner(signature, txHash);

            // Skip if signer is invalid
            if (signer == address(0)) continue;

            // Verify the signature using ERC-1271
            if (!SignatureChecker.isValidSignatureNow(signer, txHash, signature)) {
                continue;
            }

            // Check if signer is authorized as a transaction initiator based on policy
            if (_isSignerAuthorizedAsInitiator(policy, signer)) {
                return true;
            }
        }

        return false;
    }

    /**
     * @notice Checks if there is a valid signature from any organization member
     * @dev For AutoApprove policies, assumes a single signature (65 bytes)
     * @param signatures The signature to verify (expected to be exactly 65 bytes)
     * @param txHash The hash of the transaction
     * @return True if there is a valid signature from any organization member, false otherwise
     */
    function _hasValidMemberSignature(bytes memory signatures, bytes32 txHash) private view returns (bool) {
        // Case: No signature provided or incorrect length (must be exactly 65 bytes)
        if (signatures.length != 65) return false;

        // Extract signer address from signature using ERC-1271 compatible verification
        address signer = _getSigner(signatures, txHash);

        // Case: Signer is invalid
        if (signer == address(0)) return false;

        // Verify the signature using ERC-1271
        if (!SignatureChecker.isValidSignatureNow(signer, txHash, signatures)) {
            return false;
        }

        // Get the organization address
        LibAccountOrganizationAddressStorage.Layout storage orgLayout = LibAccountOrganizationAddressStorage.layout();
        address organizationAddress = orgLayout.organizationAddress;

        // Case: Organization address is not set
        if (organizationAddress == address(0)) return false;

        // Check if signer is a member of the organization by calling the organization contract
        // Note: addressToMemberId returns 0 if the address is not a member, or the member ID if it is
        try IOrganizationMembersFacet(organizationAddress).addressToMemberId(signer) returns (uint8 memberId) {
            return memberId != 0;
        } catch {
            // If the call fails, assume the signer is not a member
            return false;
        }
    }

    /**
     * @notice Creates a hash of the transaction for signature verification using EIP-712 typed data
     * @param to The destination address of the transaction
     * @param value The value of the transaction
     * @param data The data of the transaction
     * @param salt The user-provided salt for nonce computation
     * @param policyId The policy ID governing this transaction
     * @param isApproval Whether the signature is for an approval or a rejection
     * @return The hash of the transaction formatted for ERC-1271 signature verification
     */
    function _getTransactionHash(
        address to,
        uint256 value,
        bytes memory data,
        uint256 salt,
        uint256 policyId,
        bool isApproval
    )
        private
        view
        returns (bytes32)
    {
        // Create EIP-712 structured data hash
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "ExecuteTransaction(address account,address to,uint256 value,bytes data,uint256 salt,uint256 policyId,bool isApproval,uint256 chainId)"
                ),
                address(this),
                to,
                value,
                keccak256(data),
                salt,
                policyId,
                isApproval,
                block.chainid
            )
        );

        // Return EIP-712 compatible hash for ERC-1271 signature verification
        return MessageHashUtils.toTypedDataHash(
            keccak256(
                abi.encode(
                    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                    keccak256("OnchainCustodyAccount"),
                    keccak256("1"),
                    block.chainid,
                    address(this)
                )
            ),
            structHash
        );
    }

    /**
     * @notice Executes a `CALL` with provided parameters.
     * @dev This method doesn't perform any sanity check of the transaction, such as:
     *      - if the contract at `to` address has code or not
     *      It is the responsibility of the caller to perform such checks.
     * @param to Destination address.
     * @param value Ether value.
     * @param data Data payload.
     * @return success boolean flag indicating if the call succeeded.
     */
    function _execute(address to, uint256 value, bytes memory data, uint256 txGas) private returns (bool success) {
        /* solhint-disable no-inline-assembly */
        /// @solidity memory-safe-assembly
        assembly {
            success := call(txGas, to, value, add(data, 0x20), mload(data), 0, 0)
        }
    }

    // ================================
    // POLICY HELPER FUNCTIONS
    // ================================

    /**
     * @notice Checks if a policy applies to the given transaction
     * @param policy The policy to check
     * @param sourceAccount The source account address (smart account executing the transaction)
     * @param to The destination address of the transaction
     * @param value The value of the transaction
     * @param data The data of the transaction
     * @param initiator The initiator of the transaction
     * @return True if the policy applies to the transaction, false otherwise
     */
    function _doesPolicyApplyToTransaction(
        Policies.Policy memory policy,
        address sourceAccount,
        address to,
        uint256 value,
        bytes memory data,
        address initiator
    )
        private
        view
        returns (bool)
    {
        // Case: Transaction doesn't match policy's source accounts filter
        if (!_doesTransactionMatchPolicySourceAccounts(policy, sourceAccount)) {
            return false;
        }

        // Case: Transaction doesn't match policy's transaction initiator filter
        if (!_doesTransactionMatchPolicyInitiator(policy, initiator)) {
            return false;
        }

        // Case: Transaction doesn't match policy's transaction type filter
        if (!_doesTransactionMatchPolicyTransactionType(policy, to, value, data)) {
            return false;
        }

        // Case: Transaction doesn't match policy's transaction destination filter
        if (!_doesTransactionMatchPolicyDestination(policy, to, value, data)) {
            return false;
        }

        // Case: Transaction matches all filters
        return true;
    }

    /**
     * @notice Checks if the transaction matches the source account filter
     * @param policy The policy to check
     * @param sourceAccount The source account address (smart account executing the transaction)
     * @return True if the transaction matches the source account filter, false otherwise
     */
    function _doesTransactionMatchPolicySourceAccounts(
        Policies.Policy memory policy,
        address sourceAccount
    )
        private
        pure
        returns (bool)
    {
        // Case: The policy matches transactions sent from any account
        if (policy.anySourceAccount) return true;

        // Case: The policy matches transactions sent from a list of specific source accounts
        // Check if this account is in the list of specific source accounts
        for (uint8 i = 0; i < policy.sourceAccountAddresses.length; ++i) {
            address policySourceAccount = policy.sourceAccountAddresses[i];
            // Case: The policy matches transactions sent from a list of specific source accounts,
            //       and this account is in the list
            if (policySourceAccount == sourceAccount) return true;
        }

        // Case: The policy matches transactions sent from a list of specific source accounts,
        //       but this account is not in the list
        return false;
    }

    /**
     * @notice Checks if the transaction matches the initiator filter
     * @param policy The policy to check
     * @param initiatorAddress The address of the initiator of the transaction
     * @return True if the transaction matches the initiator filter, false otherwise
     */
    function _doesTransactionMatchPolicyInitiator(
        Policies.Policy memory policy,
        address initiatorAddress
    )
        private
        view
        returns (bool)
    {
        // Case: The policy matches transactions with any initiator
        if (policy.anyInitiator) return true;

        LibOrganizationMembersStorage.Layout storage membersStorage = LibOrganizationMembersStorage.layout();

        // Case: The policy matches transactions made by a specific individual, and that individual
        //        is the initiator of this transaction
        if (
            policy.initiatorType == Policies.ApproverType.Member
                && membersStorage.addressToMemberId[initiatorAddress] == policy.initiatorId
        ) return true;

        // Case: The policy matches transactions made by any individual from a specific group, and the initiator
        //       is in that group
        if (
            policy.initiatorType == Policies.ApproverType.Group
                && _isMemberInGroup(initiatorAddress, policy.initiatorId)
        ) return true;

        // Case: The policy does not match this transaction
        return false;
    }

    /**
     * @notice Checks if the transaction matches the transaction type filter
     * @param policy The policy to check
     * @param to The destination address of the transaction
     * @param value The value of the transaction
     * @param data The data of the transaction
     * @return True if the transaction matches the transaction type filter, false otherwise
     */
    function _doesTransactionMatchPolicyTransactionType(
        Policies.Policy memory policy,
        address to,
        uint256 value,
        bytes memory data
    )
        private
        pure
        returns (bool)
    {
        // Case: The policy matches any type of transaction
        if (policy.transactionType == Policies.TransactionType.Any) return true;

        // Case: Policy matches only transactions that are token transfers
        if (policy.transactionType == Policies.TransactionType.TokenTransfers) {
            // Case: The transaction is not a token transfer
            if (!_isTransactionTokenTransfer(data, value)) return false;

            // Case: The Policy matches only transactions that are token transfers that are of a
            //       specific token, and the transaction is not transferring that token
            if (!_doesTransactionMatchPolicyToken(policy, to, data)) {
                return false;
            }

            // Case: The policy matches only transactions that are token transfers that are of a
            //       specific token, and the transaction is transferring that token, but the
            //       transaction amount is less than the amount threshold
            if (!_doesTransactionMatchPolicyTransferAmount(policy, data, value)) {
                return false;
            }
        }
        // Case: The policy matches only transactions that are contract interactions that are not token transfers
        else if (policy.transactionType == Policies.TransactionType.ContractInteractions) {
            // Case: The policy matches only transactions that are contract interactions that are not token transfers,
            //       but the transaction is a token transfer
            if (_isTransactionTokenTransfer(data, value)) return false;

            // Case: The policy matches only transactions that are contract interactions that call a specific function,
            //       but the transaction is not calling that function
            if (!_doesTransactionMatchPolicyFunction(policy, data)) {
                return false;
            }
        }

        // Case: The policy does not fail to match the transaction based on the transaction type filters
        return true;
    }

    /**
     * @notice Checks if the transaction matches the destination filter
     * @param policy The policy to check
     * @param to The destination address of the transaction
     * @param value The value of the transaction
     * @param data The data of the transaction
     * @return True if the transaction matches the destination filter, false otherwise
     */
    function _doesTransactionMatchPolicyDestination(
        Policies.Policy memory policy,
        address to,
        uint256 value,
        bytes memory data
    )
        private
        view
        returns (bool)
    {
        // Case: Policy matches transaction to any address
        if (policy.destinationType == Policies.DestinationType.Any) return true;

        // Determine the actual destination address based on transaction type
        address actualDestination = _getActualDestination(to, data, value);

        // Case: Policy matches only transactions that are sent to whitelisted addresses
        if (policy.destinationType == Policies.DestinationType.WhitelistedOnly) {
            return _isAddressWhitelisted(actualDestination);
        }

        // Case: Policy matches only transactions that are sent to non-whitelisted addresses
        if (policy.destinationType == Policies.DestinationType.NonWhitelistedOnly) {
            return !_isAddressWhitelisted(actualDestination);
        }

        // Case: Policy matches only transactions that are sent to a specific list of addresses
        if (policy.destinationType == Policies.DestinationType.CustomList) {
            for (uint256 i = 0; i < policy.customDestinations.length; ++i) {
                if (policy.customDestinations[i] == actualDestination) {
                    return true;
                }
            }
        }

        // Case: The policy does not match the transaction destination
        return false;
    }

    /**
     * @notice Gets the number of required approvals for a policy
     * @param policy The policy to check
     * @return The number of required approvals for the policy
     */
    function _getRequiredApprovals(Policies.Policy memory policy) private pure returns (uint256) {
        // Case: Policy requires a single approval from a member
        if (policy.approverType == Policies.ApproverType.Member) {
            return 1;
        }

        // Case: Policy requires a threshold number of approvals from any individual
        return policy.approvalThreshold;
    }

    /**
     * @notice Checks if a signer is authorized for the given policy
     * @param policy The policy to check against
     * @param signer The signer address to validate
     * @return True if the signer is authorized, false otherwise
     */
    function _isSignerAuthorizedForPolicy(Policies.Policy memory policy, address signer) private view returns (bool) {
        LibOrganizationMembersStorage.Layout storage membersStorage = LibOrganizationMembersStorage.layout();

        // Get the member ID for the signer
        uint8 memberId = membersStorage.addressToMemberId[signer];

        // Case: Signer is not a member of the organization
        if (memberId == 0) {
            return false;
        }

        // Case: Policy requires approval from a specific member
        if (policy.approverType == Policies.ApproverType.Member) {
            return memberId == policy.approverId;
        }

        // Case: Policy requires approval from any member of a specific group
        if (policy.approverType == Policies.ApproverType.Group) {
            return _isMemberInGroup(memberId, policy.approverId);
        }

        return false;
    }

    /**
     * @notice Checks if a signer is authorized as a transaction initiator for the given policy
     * @param policy The policy to check against
     * @param signer The signer address to validate
     * @return True if the signer is authorized as an initiator, false otherwise
     */
    function _isSignerAuthorizedAsInitiator(
        Policies.Policy memory policy,
        address signer
    )
        private
        view
        returns (bool)
    {
        // Case: Policy allows any initiator
        if (policy.anyInitiator) return true;

        LibOrganizationMembersStorage.Layout storage membersStorage = LibOrganizationMembersStorage.layout();

        // Get the member ID for the signer
        uint8 memberId = membersStorage.addressToMemberId[signer];

        // Case: Signer is not a member of the organization
        if (memberId == 0) {
            return false;
        }

        // Case: Policy requires initiation by a specific member
        if (policy.initiatorType == Policies.ApproverType.Member) {
            return memberId == policy.initiatorId;
        }

        // Case: Policy requires initiation by any member of a specific group
        if (policy.initiatorType == Policies.ApproverType.Group) {
            return _isMemberInGroup(memberId, policy.initiatorId);
        }

        return false;
    }

    // Helper functions for transaction analysis

    function _getActualDestination(address to, bytes memory data, uint256 value) private pure returns (address) {
        // Case: The transaction is a native token transfer
        if (data.length == 0) {
            return to;
        }

        // Case: The transaction is a contract interaction
        if (!_isTransactionTokenTransfer(data, value)) {
            return to;
        }

        // Case: The transaction is an ERC-20 token transfer
        // Extract the recipient address from the transfer function call
        return _extractTokenRecipient(data);
    }

    function _extractTokenRecipient(bytes memory data) private pure returns (address) {
        // Case: Transaction data is too short to contain a valid selector
        if (data.length < 36) {
            return address(0);
        }

        bytes4 selector = bytes4(data);

        // Case: The transaction is calling the `transfer` function
        if (selector == bytes4(keccak256("transfer(address,uint256)"))) {
            // transfer(address to, uint256 amount)
            // The recipient is the first parameter after the selector
            address recipient;
            /* solhint-disable no-inline-assembly */
            assembly {
                // Load recipient (memory location of `data` + 4 bytes to skip the function selector )
                recipient := mload(add(data, 4))
            }
            return recipient;
        }

        // Case: The transaction is calling the `transferFrom` function
        if (selector == bytes4(keccak256("transferFrom(address,address,uint256)"))) {
            // Case: Transaction data is too short to contain a valid recipient
            // Note: The recipient is the second address parameter after the selector
            if (data.length < 68) {
                return address(0);
            }
            address recipient;
            /* solhint-disable no-inline-assembly */
            assembly {
                recipient := mload(add(data, 36)) // Skip selector (4) + from address (32)
            }
            return recipient;
        }

        // Case: The transaction is not a valid ERC-20 transfer
        return address(0);
    }

    function _isTransactionTokenTransfer(bytes memory data, uint256 value) private pure returns (bool) {
        // Case: The transaction is a native token transfer
        if (data.length == 0 && value > 0) {
            return true;
        }

        // Case: The transaction data is too short to call a function
        if (data.length < 4) {
            return false;
        }

        // Case: The transaction is not a native token transfer, but the value is greater than zero
        if (value > 0) {
            return false;
        }

        // Case: The transaction is a token transfer
        bytes4 selector = bytes4(data);

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

    function _doesTransactionMatchPolicyToken(
        Policies.Policy memory policy,
        address to,
        bytes memory data
    )
        private
        pure
        returns (bool)
    {
        // Case: Policy matches transfers of any token
        if (policy.anyToken) return true;

        address transferToken = _extractTokenAddress(to, data);

        // Case: Policy matches transfers of the same token the transaction is transferring
        if (transferToken == policy.tokenAddress) return true;

        // Case: The policy matches transfers of a specific token, but the transaction is transferring a different token
        return false;
    }

    function _doesTransactionMatchPolicyTransferAmount(
        Policies.Policy memory policy,
        bytes memory data,
        uint256 value
    )
        private
        pure
        returns (bool)
    {
        // Case: Policy matches token transfers regardless of amount transferred
        if (!policy.hasAmountThreshold) return true;

        uint256 transferAmount = _extractTransferAmount(data, value);

        // Case: Policy matches token transfers below an amount threshold, and the transaction is below the threshold
        if (transferAmount < policy.amountThreshold) return true;

        // Case: Policy matches token transfers below an amount threshold, and the transaction is above or equal to the
        //       threshold
        return false;
    }

    function _doesTransactionMatchPolicyFunction(
        Policies.Policy memory policy,
        bytes memory data
    )
        private
        pure
        returns (bool)
    {
        // Case: Policy matches any function
        if (policy.anyFunction) return true;

        // Case: Policy matches only transactions that call a specific function, but the transaction is not calling
        //       a function
        if (data.length < 4) return false;

        // Case: Policy matches only transactions that call a specific function, and the transaction is calling
        //       a function
        // Check if the transaction is calling the function specified in the policy
        bytes4 selector = bytes4(data);
        for (uint256 i = 0; i < policy.allowedFunctions.length; i++) {
            // Case: The transaction is calling the function specified in the policy
            if (policy.allowedFunctions[i].selector == selector) {
                return true;
            }
        }

        // Case: The policy matches only transactions that call a specific function, and the transaction is not calling
        //       the function specified in the policy
        return false;
    }

    function _extractTokenAddress(address to, bytes memory data) private pure returns (address) {
        if (data.length == 0) {
            return address(0); // Native token
        }
        return to; // ERC20 token address
    }

    function _extractTransferAmount(bytes memory data, uint256 value) private pure returns (uint256) {
        // Case: The transaction is a native token transfer
        if (data.length == 0) {
            return value; // Native token transfer
        }

        // Case: The ERC-20 transaction is transfering a value of zero
        // Note: 4 bytes selector + 32 bytes address + 32 bytes amount = 68 bytes
        if (data.length < 68) {
            return 0;
        }

        // Case: The ERC-20 transaction is transfering a non-zero value
        bytes32 amount;

        /* solhint-disable no-inline-assembly */
        assembly {
            amount := mload(add(data, 68)) // Skip selector (4) + address (32) + read amount (32)
        }
        return uint256(amount);
    }

    function _isMemberInGroup(uint8 memberId, uint8 groupId) private view returns (bool) {
        LibOrganizationMembersStorage.Layout storage membersStorage = LibOrganizationMembersStorage.layout();
        LibOrganizationGroupsStorage.Layout storage groupsStorage = LibOrganizationGroupsStorage.layout();

        // Case: Member does not exist
        if (membersStorage.memberIdToAddress[memberId] == address(0)) return false;

        return groupsStorage.groupIdToMemberIdToInGroup[groupId][memberId];
    }

    function _isMemberInGroup(address memberAddress, uint8 groupId) private view returns (bool) {
        LibOrganizationMembersStorage.Layout storage membersStorage = LibOrganizationMembersStorage.layout();
        LibOrganizationGroupsStorage.Layout storage groupsStorage = LibOrganizationGroupsStorage.layout();
        uint8 memberId = membersStorage.addressToMemberId[memberAddress];

        // Case: Member does not exist
        if (memberId == 0) return false;

        return groupsStorage.groupIdToMemberIdToInGroup[groupId][memberId];
    }

    function _isAddressWhitelisted(address addressToCheck) private view returns (bool) {
        return LibOrganizationWhitelistStorage.layout().whitelistedAddresses[addressToCheck];
    }
}
