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

/**
 * @title Lib Organization Policy
 * @notice Library for policy-related operations for Organization contracts
 * @dev This library should ONLY be used by Organization contracts
 * @author Den Technologies Inc
 */
library LibOrganizationPolicy {
    /**
     * @notice Emitted when new policies are added to the organization
     * @param policyIds The array of auto-assigned policy IDs for the newly created policies
     */
    event PoliciesAdded(uint256[] policyIds);

    /**
     * @notice Emitted when existing policies are modified
     * @param policyIds The array of policy IDs that were modified
     */
    event PoliciesModified(uint256[] policyIds);

    /**
     * @notice Emitted when policies are removed from the organization
     * @param policyIds The array of policy IDs that were removed
     */
    event PoliciesRemoved(uint256[] policyIds);

    /**
     * @notice Gets a policy by its ID
     * @param policyId The ID of the policy to retrieve
     * @return The policy with the given ID
     */
    function getPolicy(uint256 policyId) internal view returns (Policies.Policy memory) {
        LibOrganizationPolicyStorage.Layout storage policyLayout = LibOrganizationPolicyStorage.layout();
        require(policyLayout.policyExists[policyId], "Policy does not exist");
        return policyLayout.policies[policyId];
    }

    /**
     * @notice Checks if a policy exists
     * @param policyId The ID of the policy to check
     * @return True if the policy exists, false otherwise
     */
    function policyExists(uint256 policyId) internal view returns (bool) {
        return LibOrganizationPolicyStorage.layout().policyExists[policyId];
    }

    /**
     * @notice Modifies the organization's policies by adding, modifying, or removing policies
     * @dev - Adding policies: Provide policies in `addPolicies` array. IDs will be auto-assigned and emitted in event.
     *      - Modifying policies: Provide policy IDs in `modifyPolicyIds` and corresponding policies in
     * `policiesToModify`.
     *      - Removing policies: Provide policy IDs in `removePolicyIds` array.
     *      All three operations can be performed in a single transaction.
     * @param modifyPolicyIds The array of policy IDs to modify (must match length of policiesToModify)
     * @param policiesToModify The array of policies corresponding to modifyPolicyIds
     * @param addPolicies The array of new policies to add (IDs will be auto-assigned)
     * @param removePolicyIds The array of policy IDs to remove
     */
    function modifyPolicies(
        uint256[] memory modifyPolicyIds,
        Policies.Policy[] memory policiesToModify,
        Policies.Policy[] memory addPolicies,
        uint256[] memory removePolicyIds
    )
        internal
    {
        LibOrganizationPolicyStorage.Layout storage policyLayout = LibOrganizationPolicyStorage.layout();

        // Validation: modifyPolicyIds and policiesToModify must have matching lengths
        require(
            modifyPolicyIds.length == policiesToModify.length,
            "Modify policy IDs and policies arrays must have the same length"
        );

        // Validation: At least one operation must be performed
        require(
            modifyPolicyIds.length > 0 || addPolicies.length > 0 || removePolicyIds.length > 0,
            "At least one operation must be performed"
        );

        // Add new policies with auto-assigned IDs
        if (addPolicies.length > 0) {
            uint256[] memory addedPolicyIds = new uint256[](addPolicies.length);
            for (uint256 i = 0; i < addPolicies.length; ++i) {
                uint256 newPolicyId = policyLayout.nextPolicyId;
                policyLayout.policies[newPolicyId] = addPolicies[i];
                policyLayout.policyExists[newPolicyId] = true;
                addedPolicyIds[i] = newPolicyId;
                policyLayout.nextPolicyId++;
            }

            emit PoliciesAdded(addedPolicyIds);
        }

        // Modify existing policies
        if (modifyPolicyIds.length > 0) {
            for (uint256 i = 0; i < modifyPolicyIds.length; ++i) {
                require(policyLayout.policyExists[modifyPolicyIds[i]], "Policy to modify does not exist");
                uint256 policyId = modifyPolicyIds[i];
                policyLayout.policies[policyId] = policiesToModify[i];
            }

            emit PoliciesModified(modifyPolicyIds);
        }

        // Remove policies
        if (removePolicyIds.length > 0) {
            for (uint256 i = 0; i < removePolicyIds.length; ++i) {
                uint256 policyId = removePolicyIds[i];
                policyLayout.policyExists[policyId] = false;
            }

            emit PoliciesRemoved(removePolicyIds);
        }
    }

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
    function doesPolicyApplyToTransaction(
        Policies.Policy memory policy,
        address sourceAccount,
        address to,
        uint256 value,
        bytes memory data,
        address initiator
    )
        internal
        view
        returns (bool)
    {
        // Case: Transaction doesn't match policy's source accounts filter
        if (!doesTransactionMatchPolicySourceAccounts(policy, sourceAccount)) {
            return false;
        }

        // Case: Transaction doesn't match policy's transaction initiator filter
        if (!doesTransactionMatchPolicyInitiator(policy, initiator)) {
            return false;
        }

        // Case: Transaction doesn't match policy's transaction type filter
        if (!doesTransactionMatchPolicyTransactionType(policy, to, value, data)) {
            return false;
        }

        // Case: Transaction doesn't match policy's transaction destination filter
        if (!doesTransactionMatchPolicyDestination(policy, to, value, data)) {
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
    function doesTransactionMatchPolicySourceAccounts(
        Policies.Policy memory policy,
        address sourceAccount
    )
        internal
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
    function doesTransactionMatchPolicyInitiator(
        Policies.Policy memory policy,
        address initiatorAddress
    )
        internal
        view
        returns (bool)
    {
        // Case: The policy matches transactions with any initiator
        if (policy.anyInitiator) return true;

        LibOrganizationMembersStorage.Layout storage membersLayout = LibOrganizationMembersStorage.layout();

        // Get the member ID for the signer
        uint8 memberId = membersLayout.addressToMemberId[initiatorAddress];

        // Case: Signer is not a member of the organization
        if (memberId == 0) {
            return false;
        }

        // Case: The policy matches transactions made by a specific individual, and that individual
        //        is the initiator of this transaction
        if (policy.initiatorType == Policies.ApproverType.Member && memberId == policy.initiatorId) return true;

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
    function doesTransactionMatchPolicyTransactionType(
        Policies.Policy memory policy,
        address to,
        uint256 value,
        bytes memory data
    )
        internal
        pure
        returns (bool)
    {
        // Case: The policy matches any type of transaction
        if (policy.transactionType == Policies.TransactionType.Any) return true;

        // Case: Policy matches only transactions that are token transfers
        if (policy.transactionType == Policies.TransactionType.TokenTransfers) {
            // Case: The transaction is not a token transfer
            if (!isTransactionTokenTransfer(data, value)) return false;

            // Case: The Policy matches only transactions that are token transfers that are of a
            //       specific token, and the transaction is not transferring that token
            if (!doesTransactionMatchPolicyToken(policy, to, data)) {
                return false;
            }

            // Case: The policy matches only transactions that are token transfers that are of a
            //       specific token, and the transaction is transferring that token, but the
            //       transaction amount is less than the amount threshold
            if (!doesTransactionMatchPolicyTransferAmount(policy, data, value)) {
                return false;
            }
        }
        // Case: The policy matches only transactions that are contract interactions that are not token transfers
        else if (policy.transactionType == Policies.TransactionType.ContractInteractions) {
            // Case: The policy matches only transactions that are contract interactions that are not token transfers,
            //       but the transaction is a token transfer
            if (isTransactionTokenTransfer(data, value)) return false;

            // Case: The policy matches only transactions that are contract interactions that call a specific function,
            //       but the transaction is not calling that function
            if (!doesTransactionMatchPolicyFunction(policy, data)) {
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
    function doesTransactionMatchPolicyDestination(
        Policies.Policy memory policy,
        address to,
        uint256 value,
        bytes memory data
    )
        internal
        view
        returns (bool)
    {
        // Case: Policy matches transaction to any address
        if (policy.destinationType == Policies.DestinationType.Any) return true;

        // Determine the actual destination address based on transaction type
        address actualDestination = getActualDestination(to, data, value);

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
    function getRequiredApprovals(Policies.Policy memory policy) internal pure returns (uint256) {
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
    function isSignerAuthorizedForPolicy(Policies.Policy memory policy, address signer) internal view returns (bool) {
        LibOrganizationMembersStorage.Layout storage membersLayout = LibOrganizationMembersStorage.layout();

        // Get the member ID for the signer
        uint8 memberId = membersLayout.addressToMemberId[signer];

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
     * @notice Verifies signatures and returns the number of valid approvals for a policy
     * @dev This is a shared function used by both transaction validation and signature validation
     * @param policy The policy requiring approval
     * @param signatures The signatures to verify
     * @param messageHash The hash of the message that was signed
     * @return The number of valid approvals
     */
    function getValidApprovals(
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
            if (isSignerAuthorizedForPolicy(policy, signer)) {
                ++validApprovals;
            }
        }

        return validApprovals;
    }

    // ================================
    // HELPER FUNCTIONS
    // ================================

    /**
     * @notice Gets the actual destination address of a transaction
     * @dev For contract interactions and native transfers, returns the `to` address.
     *      For ERC-20 transfers, extracts and returns the recipient address from the transaction data.
     * @param to The destination address of the transaction
     * @param data The data of the transaction
     * @param value The value of the transaction
     * @return The actual destination address
     */
    function getActualDestination(address to, bytes memory data, uint256 value) internal pure returns (address) {
        // Case: The transaction is a native token transfer
        if (data.length == 0) {
            return to;
        }

        // Case: The transaction is a contract interaction
        if (!isTransactionTokenTransfer(data, value)) {
            return to;
        }

        // Case: The transaction is an ERC-20 token transfer
        // Extract the recipient address from the transfer function call
        return extractTokenRecipient(data);
    }

    /**
     * @notice Extracts the recipient address from an ERC-20 transfer transaction
     * @dev This function assumes that the transaction is an ERC-20 token transfer
     * @param data The data of the transaction
     * @return The recipient address
     */
    function extractTokenRecipient(bytes memory data) internal pure returns (address) {
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

    /**
     * @notice Checks if a transaction is a token transfer
     * @param data The data of the transaction
     * @param value The value of the transaction
     * @return True if the transaction is a token transfer, false otherwise
     */
    function isTransactionTokenTransfer(bytes memory data, uint256 value) internal pure returns (bool) {
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

    /**
     * @notice Checks if the transaction matches the token filter
     * @param policy The policy to check
     * @param to The destination address of the transaction
     * @param data The data of the transaction
     * @return True if the transaction matches the token filter, false otherwise
     */
    function doesTransactionMatchPolicyToken(
        Policies.Policy memory policy,
        address to,
        bytes memory data
    )
        internal
        pure
        returns (bool)
    {
        // Case: Policy matches transfers of any token
        if (policy.anyToken) return true;

        address transferToken = extractTokenAddress(to, data);

        // Case: Policy matches transfers of the same token the transaction is transferring
        if (transferToken == policy.tokenAddress) return true;

        // Case: The policy matches transfers of a specific token, but the transaction is transferring a different token
        return false;
    }

    /**
     * @notice Checks if the transaction amount meets the threshold requirements
     * @param policy The policy to check
     * @param data The data of the transaction
     * @param value The value of the transaction
     * @return True if the transaction matches the transfer amount filter, false otherwise
     */
    function doesTransactionMatchPolicyTransferAmount(
        Policies.Policy memory policy,
        bytes memory data,
        uint256 value
    )
        internal
        pure
        returns (bool)
    {
        // Case: Policy matches token transfers regardless of amount transferred
        if (!policy.hasAmountThreshold) return true;

        uint256 transferAmount = extractTransferAmount(data, value);

        // Case: Policy matches token transfers below an amount threshold, and the transaction is below the threshold
        if (transferAmount < policy.amountThreshold) return true;

        // Case: Policy matches token transfers below an amount threshold, and the transaction is above or equal to the
        //       threshold
        return false;
    }

    /**
     * @notice Checks if the transaction matches the function selector filter and parameter constraints
     * @param policy The policy to check
     * @param data The data of the transaction
     * @return True if the transaction matches the function selector filter and all parameter constraints, false
     * otherwise
     */
    function doesTransactionMatchPolicyFunction(
        Policies.Policy memory policy,
        bytes memory data
    )
        internal
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
        // Check if the transaction is calling any of the functions that are allowed by the policy
        bytes4 selector = bytes4(data);
        for (uint256 i = 0; i < policy.allowedFunctions.length; ++i) {
            // Case: The transaction is calling a function that's not the current function specified in the policy
            // Continue to the next function that's allowed in the policy
            if (policy.allowedFunctions[i].selector != selector) continue;

            // Selector matches - now validate parameter constraints
            bytes memory paramConstraints = policy.allowedFunctions[i].parameterConstraints;

            // Case: Parameter constraints defined - validate them
            if (doParametersMatchConstraints(paramConstraints, data)) {
                return true;
            }
            // If parameters don't match this allowed function entry, continue checking
            // other entries (there might be multiple entries for same selector with different constraints)
        }

        // Case: The policy matches only transactions that call a specific function, and the transaction is not calling
        //       the function specified in the policy (or parameters don't match any constraint set)
        return false;
    }

    /**
     * @notice Extracts the token address from a transfer transaction
     * @dev This function assumes that the transaction is a token transfer
     * @param to The destination address of the transaction
     * @param data The data of the transaction
     * @return The token address
     */
    function extractTokenAddress(address to, bytes memory data) internal pure returns (address) {
        if (data.length == 0) {
            return address(0); // Native token
        }
        return to; // ERC20 token address
    }

    /**
     * @notice Extracts the transfer amount from a transaction
     * @dev This function assumes that the transaction is a token transfer
     * @param data The data of the transaction
     * @param value The value of the transaction
     * @return The transfer amount
     */
    function extractTransferAmount(bytes memory data, uint256 value) internal pure returns (uint256) {
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

    // ================================
    // PARAMETER CONSTRAINT VALIDATION
    // ================================

    /**
     * @notice Validates that transaction parameters match the policy's parameter constraints
     * @dev Decodes the parameterConstraints bytes and validates each parameter against the transaction data
     * @param parameterConstraints ABI-encoded ParameterConstraint[] array
     * @param data The transaction calldata (including 4-byte selector)
     * @return True if all parameters match their constraints, false otherwise
     */
    function doParametersMatchConstraints(
        bytes memory parameterConstraints,
        bytes memory data
    )
        internal
        pure
        returns (bool)
    {
        // Case: No constraints defined, any parameters are accepted
        if (parameterConstraints.length == 0) {
            return true;
        }

        // Decode the constraints array
        Policies.ParameterConstraint[] memory constraints =
            abi.decode(parameterConstraints, (Policies.ParameterConstraint[]));

        // Case: No constraints in the array
        if (constraints.length == 0) {
            return true;
        }

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
            bytes32 paramHeadValue;
            /* solhint-disable no-inline-assembly */
            assembly {
                // data starts at data + 32 (length prefix), then add paramOffset
                paramHeadValue := mload(add(add(data, 32), paramOffset))
            }

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
     * @param constraint The constraint to validate against
     * @param paramHeadValue The value of the parameter in the head section of calldata.
     *                       For static types, this is the value itself.
     *                       For dynamic types, this is the offset to the value in the tail section.
     * @param data The full transaction calldata (needed for dynamic types to dereference offsets)
     * @return True if the parameter matches the constraint, false otherwise
     */
    function _validateParameter(
        Policies.ParameterConstraint memory constraint,
        bytes32 paramHeadValue,
        bytes memory data
    )
        private
        pure
        returns (bool)
    {
        Policies.ParamType pType = constraint.paramType;
        Policies.ConstraintType cType = constraint.constraintType;
        bytes memory comparisonData = constraint.comparisonData;

        // Handle Bool type
        if (pType == Policies.ParamType.Bool) {
            return _validateBool(cType, paramHeadValue, comparisonData);
        }

        // Handle Uint type (and enums which are treated as uint)
        if (pType == Policies.ParamType.Uint) {
            return _validateUint(cType, paramHeadValue, comparisonData);
        }

        // Handle Int type
        if (pType == Policies.ParamType.Int) {
            return _validateInt(cType, paramHeadValue, comparisonData);
        }

        // Handle Address type
        if (pType == Policies.ParamType.Address) {
            return _validateAddress(cType, paramHeadValue, comparisonData);
        }

        // Handle FixedBytes type (bytes1-bytes32, stored inline)
        if (pType == Policies.ParamType.FixedBytes) {
            return _validateFixedBytes(cType, paramHeadValue, comparisonData);
        }

        // Handle Bytes type (dynamic bytes, stored as offset)
        if (pType == Policies.ParamType.Bytes) {
            return _validateDynamicBytes(cType, paramHeadValue, comparisonData, data);
        }

        // Handle String type (dynamic string, stored as offset)
        if (pType == Policies.ParamType.String) {
            return _validateString(cType, paramHeadValue, comparisonData, data);
        }

        // Handle Array and Struct types - only Any constraint is valid
        if (pType == Policies.ParamType.Array || pType == Policies.ParamType.Struct) {
            // These types can only have Any constraint, which is handled earlier
            // If we reach here with a non-Any constraint, it's invalid configuration
            return false;
        }

        // Unknown type - fail safe
        return false;
    }

    /**
     * @notice Validates a boolean parameter
     * @param cType The constraint type (only Exact is valid for bool)
     * @param paramHeadValue The parameter value from the head section (0 or 1)
     * @param comparisonData ABI-encoded bool value
     * @return True if valid, false otherwise
     */
    function _validateBool(
        Policies.ConstraintType cType,
        bytes32 paramHeadValue,
        bytes memory comparisonData
    )
        private
        pure
        returns (bool)
    {
        // Bool only supports Exact constraint
        if (cType != Policies.ConstraintType.Exact) {
            return false;
        }

        bool expectedValue = abi.decode(comparisonData, (bool));
        bool actualValue = uint256(paramHeadValue) != 0;
        return actualValue == expectedValue;
    }

    /**
     * @notice Validates an unsigned integer parameter
     * @param cType The constraint type (Exact or Range)
     * @param paramHeadValue The parameter value from the head section
     * @param comparisonData ABI-encoded uint256 (Exact) or (uint256, uint256) for Range
     * @return True if valid, false otherwise
     */
    function _validateUint(
        Policies.ConstraintType cType,
        bytes32 paramHeadValue,
        bytes memory comparisonData
    )
        private
        pure
        returns (bool)
    {
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

    /**
     * @notice Validates a signed integer parameter
     * @param cType The constraint type (Exact or Range)
     * @param paramHeadValue The parameter value from the head section
     * @param comparisonData ABI-encoded int256 (Exact) or (int256, int256) for Range
     * @return True if valid, false otherwise
     */
    function _validateInt(
        Policies.ConstraintType cType,
        bytes32 paramHeadValue,
        bytes memory comparisonData
    )
        private
        pure
        returns (bool)
    {
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

    /**
     * @notice Validates an address parameter
     * @param cType The constraint type (Exact or List)
     * @param paramHeadValue The parameter value from the head section
     * @param comparisonData ABI-encoded address (Exact) or address[] (List)
     * @return True if valid, false otherwise
     */
    function _validateAddress(
        Policies.ConstraintType cType,
        bytes32 paramHeadValue,
        bytes memory comparisonData
    )
        private
        pure
        returns (bool)
    {
        address actualValue = address(uint160(uint256(paramHeadValue)));

        if (cType == Policies.ConstraintType.Exact) {
            address expectedValue = abi.decode(comparisonData, (address));
            return actualValue == expectedValue;
        }

        if (cType == Policies.ConstraintType.List) {
            address[] memory allowedAddresses = abi.decode(comparisonData, (address[]));
            for (uint256 i = 0; i < allowedAddresses.length; ++i) {
                if (actualValue == allowedAddresses[i]) {
                    return true;
                }
            }
            return false;
        }

        // Address doesn't support Range constraint
        return false;
    }

    /**
     * @notice Validates a fixed-size bytes parameter (bytes1-bytes32)
     * @dev For fixed-size bytes, the value is stored directly in the 32-byte slot (left-aligned)
     * @param cType The constraint type (only Exact is valid)
     * @param paramHeadValue The parameter value from the head section (stored directly)
     * @param comparisonData ABI-encoded bytes32 value
     * @return True if valid, false otherwise
     */
    function _validateFixedBytes(
        Policies.ConstraintType cType,
        bytes32 paramHeadValue,
        bytes memory comparisonData
    )
        private
        pure
        returns (bool)
    {
        // FixedBytes only supports Exact constraint
        if (cType != Policies.ConstraintType.Exact) {
            return false;
        }

        // For fixed-size bytes (bytes1-bytes32), compare directly
        bytes32 expectedValue = abi.decode(comparisonData, (bytes32));
        return paramHeadValue == expectedValue;
    }

    /**
     * @notice Validates a dynamic bytes parameter
     * @dev The paramHeadValue contains the offset to the data location in calldata.
     *      The comparisonData should contain the keccak256 hash of the expected bytes.
     * @param cType The constraint type (only Exact is valid)
     * @param paramHeadValue The offset to the bytes data in the tail section (relative to start of encoded params)
     * @param comparisonData ABI-encoded bytes32 hash of expected bytes
     * @param data The full transaction calldata
     * @return True if valid, false otherwise
     */
    function _validateDynamicBytes(
        Policies.ConstraintType cType,
        bytes32 paramHeadValue,
        bytes memory comparisonData,
        bytes memory data
    )
        private
        pure
        returns (bool)
    {
        // Dynamic bytes only supports Exact constraint (hash comparison)
        if (cType != Policies.ConstraintType.Exact) {
            return false;
        }

        // paramHeadValue is the offset (relative to start of encoded params, i.e., after selector)
        uint256 offset = uint256(paramHeadValue);

        // The offset is relative to the start of the encoded parameters (after selector)
        // So actual position in data = 4 (selector) + offset
        uint256 dataPosition = 4 + offset;

        // First 32 bytes at that position is the length
        if (data.length < dataPosition + 32) {
            return false;
        }

        uint256 bytesLength;
        /* solhint-disable no-inline-assembly */
        assembly {
            // data memory layout: first 32 bytes = length, then actual data
            // So data + 32 gives us the start of actual calldata content
            // Then add dataPosition to get to where the dynamic data length is stored
            bytesLength := mload(add(add(data, 32), dataPosition))
        }

        // Check we have enough data for the bytes content
        if (data.length < dataPosition + 32 + bytesLength) {
            return false;
        }

        // Hash the actual bytes content
        bytes32 actualHash;
        /* solhint-disable no-inline-assembly */
        assembly {
            // Start of bytes content = data + 32 (skip memory length) + dataPosition + 32 (skip bytes length)
            let bytesStart := add(add(data, 32), add(dataPosition, 32))
            actualHash := keccak256(bytesStart, bytesLength)
        }

        bytes32 expectedHash = abi.decode(comparisonData, (bytes32));
        return actualHash == expectedHash;
    }

    /**
     * @notice Validates a string parameter (hash comparison)
     * @dev The paramHeadValue contains the offset to the string data in calldata.
     *      The comparisonData should contain the keccak256 hash of the expected string.
     * @param cType The constraint type (only Exact is valid)
     * @param paramHeadValue The offset to the string data in the tail section (relative to start of encoded params)
     * @param comparisonData ABI-encoded bytes32 hash of expected string
     * @param data The full transaction calldata
     * @return True if valid, false otherwise
     */
    function _validateString(
        Policies.ConstraintType cType,
        bytes32 paramHeadValue,
        bytes memory comparisonData,
        bytes memory data
    )
        private
        pure
        returns (bool)
    {
        // String only supports Exact constraint (hash comparison)
        if (cType != Policies.ConstraintType.Exact) {
            return false;
        }

        // paramHeadValue is the offset (relative to start of encoded params, i.e., after selector)
        uint256 offset = uint256(paramHeadValue);

        // The offset is relative to the start of the encoded parameters (after selector)
        // So actual position in data = 4 (selector) + offset
        uint256 dataPosition = 4 + offset;

        // First 32 bytes at that position is the string length
        if (data.length < dataPosition + 32) {
            return false;
        }

        uint256 strLength;
        /* solhint-disable no-inline-assembly */
        assembly {
            // data memory layout: first 32 bytes = length, then actual data
            // So data + 32 gives us the start of actual calldata content
            // Then add dataPosition to get to where the string length is stored
            strLength := mload(add(add(data, 32), dataPosition))
        }

        // Check we have enough data for the string content
        if (data.length < dataPosition + 32 + strLength) {
            return false;
        }

        // Hash the actual string content
        bytes32 actualHash;
        /* solhint-disable no-inline-assembly */
        assembly {
            // Start of string content = data + 32 (skip memory length) + dataPosition + 32 (skip string length)
            let strStart := add(add(data, 32), add(dataPosition, 32))
            actualHash := keccak256(strStart, strLength)
        }

        bytes32 expectedHash = abi.decode(comparisonData, (bytes32));
        return actualHash == expectedHash;
    }

    // ================================
    // PRIVATE HELPER FUNCTIONS
    // ================================

    /**
     * @notice Internal helper to check if a member is in a group
     * @param memberId The ID of the member
     * @param groupId The ID of the group
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
     * @notice Internal helper to check if a member is in a group by address
     * @param memberAddress The address of the member
     * @param groupId The ID of the group
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
     * @notice Internal helper to check if an address is whitelisted
     * @param addressToCheck The address to check
     * @return True if the address is whitelisted, false otherwise
     */
    function _isAddressWhitelisted(address addressToCheck) private view returns (bool) {
        return LibOrganizationWhitelistStorage.layout().whitelistedAddresses[addressToCheck];
    }

    // ================================
    // TIME-BASED POLICY LIMIT FUNCTIONS
    // ================================

    /**
     * @notice Computes the usage key for time-based policy tracking
     * @dev The key is computed based on policyId and scoped entities.
     *      When scope is AcrossAll, address(0) is used for that entity.
     *      When scope is PerEntity, the actual address is used.
     * @param policyId The ID of the policy
     * @param policy The policy to compute the key for
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
    )
        internal
        pure
        returns (bytes32)
    {
        // Determine scoped values based on policy configuration
        address scopedAccount =
            policy.timeIntervalSourceScope == Policies.TimeIntervalScope.PerEntity ? account : address(0);

        address scopedDestination =
            policy.timeIntervalDestinationScope == Policies.TimeIntervalScope.PerEntity ? destination : address(0);

        address scopedInitiator =
            policy.timeIntervalInitiatorScope == Policies.TimeIntervalScope.PerEntity ? initiator : address(0);

        return keccak256(abi.encode(policyId, scopedAccount, scopedDestination, scopedInitiator));
    }

    /**
     * @notice Computes the current time window for a policy
     * @dev Uses fixed time windows based on timeIntervalHours
     * @param policy The policy to compute the time window for
     * @return The current time window ID
     */
    function computeTimeWindow(Policies.Policy memory policy) internal view returns (uint256) {
        // Avoid division by zero
        if (policy.timeIntervalHours == 0) {
            return 0;
        }
        return block.timestamp / (policy.timeIntervalHours * 3600);
    }

    /**
     * @notice Checks if usage is within time-based limit and updates storage if so
     * @dev This function should only be called when policy.limitation == TimeInterval
     * @param policyId The ID of the policy
     * @param policy The policy to check against
     * @param account The source account address
     * @param destination The destination address
     * @param initiator The initiator address
     * @param usageAmount The amount to add to usage (transfer amount for token transfers, 1 for
     * interactions/signatures)
     * @return withinLimit True if the usage is within the limit, false otherwise
     */
    function checkAndUpdateTimeBasedLimit(
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
        if (policy.limitation != Policies.PolicyLimitation.TimeInterval) {
            return true;
        }

        // Skip if time interval is not configured (0 hours)
        if (policy.timeIntervalHours == 0) {
            return true;
        }

        LibOrganizationPolicyStorage.Layout storage policyLayout = LibOrganizationPolicyStorage.layout();

        bytes32 usageKey = computeUsageKey(policyId, policy, account, destination, initiator);
        uint256 timeWindow = computeTimeWindow(policy);

        uint256 currentUsage = policyLayout.policyUsage[usageKey][timeWindow];

        // Check if adding usageAmount would exceed the limit
        if (currentUsage + usageAmount > policy.timeIntervalLimit) {
            return false;
        }

        // Update usage
        policyLayout.policyUsage[usageKey][timeWindow] = currentUsage + usageAmount;

        return true;
    }

    /**
     * @notice Gets the current usage for a policy within the current time window
     * @dev This is a view function for external queries
     * @param policyId The ID of the policy
     * @param policy The policy to check
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
    )
        internal
        view
        returns (uint256)
    {
        // Return 0 if no time-based limitation
        if (policy.limitation != Policies.PolicyLimitation.TimeInterval) {
            return 0;
        }

        // Return 0 if time interval is not configured
        if (policy.timeIntervalHours == 0) {
            return 0;
        }

        LibOrganizationPolicyStorage.Layout storage policyLayout = LibOrganizationPolicyStorage.layout();

        bytes32 usageKey = computeUsageKey(policyId, policy, account, destination, initiator);
        uint256 timeWindow = computeTimeWindow(policy);

        return policyLayout.policyUsage[usageKey][timeWindow];
    }
}
