// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { OrganizationStorage } from "../storage/OrganizationStorage.sol";
import { Policies } from "../libraries/Policies.sol";
import { SignatureUtils } from "../libraries/SignatureUtils.sol";
import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/**
 * @title Policy Facet
 * @notice Handles policy-related operations for the OnchainCustodyOrganization diamond
 * @author Den Technologies Inc
 */
contract PolicyFacet {
    using OrganizationStorage for OrganizationStorage.Layout;

    /**
     * @notice Emitted when the organization's policies are modified
     * @param previousPoliciesHash The hash of the previous policies array
     * @param newPoliciesHash The hash of the new policies array
     * @param newPoliciesCount The number of policies in the new policies array
     */
    event PoliciesModified(bytes32 previousPoliciesHash, bytes32 newPoliciesHash, uint256 newPoliciesCount);

    /**
     * @notice Emitted when an admin operation is rejected due to insufficient authorization
     * @param reason The reason for the rejection
     */
    error AdminOperationRejected(string reason);

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
     * @notice Modifier to restrict function access to the guardian address only
     */
    modifier onlyGuardian() {
        OrganizationStorage.Layout storage l = OrganizationStorage.layout();
        if (msg.sender != l.guardian) {
            revert UnauthorizedCaller(msg.sender, l.guardian);
        }
        _;
    }

    /**
     * @notice Gets the policies for the organization
     * @return The policies for the organization
     */
    function getPolicies() public view returns (Policies.Policy[] memory) {
        return OrganizationStorage.layout().policies;
    }

    /**
     * @notice Computes a deterministic nonce for admin operations from operation data and salt
     * @param operationType The type of operation being performed
     * @param operationData The ABI-encoded data of the operation
     * @param salt A user-provided salt for nonce computation
     * @return The computed nonce
     */
    function computeAdminNonce(
        OrganizationStorage.AdminOperationType operationType,
        bytes memory operationData,
        uint256 salt
    )
        public
        view
        returns (uint256)
    {
        return uint256(keccak256(abi.encode(address(this), operationType, keccak256(operationData), salt)));
    }

    /**
     * @notice Modifies the organization's policies
     * @dev This function can only be called by the current admin (individual or group with sufficient signatures)
     *      The new policies array completely replaces the existing policies array, maintaining order importance.
     * @param newPolicies The new array of policies to set for the organization
     * @param salt A user-provided salt for nonce computation
     * @param chainId The chain ID for cross-chain replay protection - must match current chain ID
     * @param signatures The signatures from the current admin authorizing this operation
     */
    function modifyPolicies(
        Policies.Policy[] memory newPolicies,
        uint256 salt,
        uint256 chainId,
        bytes memory signatures
    )
        public
        onlyGuardian
    {
        // Encode the operation data for validation
        bytes memory operationData = abi.encode(newPolicies);

        // Validate that the current admin has authorized this operation
        _validateAdminAuthorization(
            OrganizationStorage.AdminOperationType.ModifyPolicies, operationData, salt, chainId, signatures
        );

        OrganizationStorage.Layout storage l = OrganizationStorage.layout();

        // Store hash of previous policies for the event
        bytes32 previousPoliciesHash = _getPoliciesHash(l.policies);

        // Replace the entire policies array with the new one
        delete l.policies;
        for (uint256 i = 0; i < newPolicies.length; ++i) {
            l.policies.push(newPolicies[i]);
        }

        // Compute hash of new policies for the event
        bytes32 newPoliciesHash = _getPoliciesHash(l.policies);

        // Emit event
        emit PoliciesModified(previousPoliciesHash, newPoliciesHash, newPolicies.length);
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
        external
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
        public
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
        public
        view
        returns (bool)
    {
        // Case: The policy matches transactions with any initiator
        if (policy.anyInitiator) return true;

        OrganizationStorage.Layout storage l = OrganizationStorage.layout();

        // Case: The policy matches transactions made by a specific individual, and that individual
        //        is the initiator of this transaction
        if (
            policy.initiatorType == Policies.ApproverType.Member
                && l.addressToMemberId[initiatorAddress] == policy.initiatorId
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
    function doesTransactionMatchPolicyTransactionType(
        Policies.Policy memory policy,
        address to,
        uint256 value,
        bytes memory data
    )
        public
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
        public
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
    function getRequiredApprovals(Policies.Policy memory policy) public pure returns (uint256) {
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
    function isSignerAuthorizedForPolicy(Policies.Policy memory policy, address signer) external view returns (bool) {
        OrganizationStorage.Layout storage l = OrganizationStorage.layout();

        // Get the member ID for the signer
        uint8 memberId = l.addressToMemberId[signer];

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
    function isSignerAuthorizedAsInitiator(
        Policies.Policy memory policy,
        address signer
    )
        external
        view
        returns (bool)
    {
        // Case: Policy allows any initiator
        if (policy.anyInitiator) return true;

        OrganizationStorage.Layout storage l = OrganizationStorage.layout();

        // Get the member ID for the signer
        uint8 memberId = l.addressToMemberId[signer];

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
    function getActualDestination(address to, bytes memory data, uint256 value) public pure returns (address) {
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
    function extractTokenRecipient(bytes memory data) public pure returns (address) {
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
    function isTransactionTokenTransfer(bytes memory data, uint256 value) public pure returns (bool) {
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
        public
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
        public
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
     * @notice Checks if the transaction matches the function selector filter
     * @param policy The policy to check
     * @param data The data of the transaction
     * @return True if the transaction matches the function selector filter, false otherwise
     */
    function doesTransactionMatchPolicyFunction(
        Policies.Policy memory policy,
        bytes memory data
    )
        public
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

    /**
     * @notice Extracts the token address from a transfer transaction
     * @dev This function assumes that the transaction is a token transfer
     * @param to The destination address of the transaction
     * @param data The data of the transaction
     * @return The token address
     */
    function extractTokenAddress(address to, bytes memory data) public pure returns (address) {
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
    function extractTransferAmount(bytes memory data, uint256 value) public pure returns (uint256) {
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

    /**
     * @notice Computes a hash of the policies array for event logging and comparison
     * @param policies The policies array to hash
     * @return The hash of the policies array
     */
    function _getPoliciesHash(Policies.Policy[] memory policies) internal pure returns (bytes32) {
        return keccak256(abi.encode(policies));
    }

    /**
     * @notice Internal helper to check if a member is in a group
     * @param memberId The ID of the member
     * @param groupId The ID of the group
     * @return True if the member is in the group, false otherwise
     */
    function _isMemberInGroup(uint8 memberId, uint8 groupId) internal view returns (bool) {
        OrganizationStorage.Layout storage l = OrganizationStorage.layout();

        // Case: Member does not exist
        if (l.memberIdToAddress[memberId] == address(0)) return false;

        return l.groupIdToMemberIdToInGroup[groupId][memberId];
    }

    /**
     * @notice Internal helper to check if a member is in a group by address
     * @param memberAddress The address of the member
     * @param groupId The ID of the group
     * @return True if the member is in the group, false otherwise
     */
    function _isMemberInGroup(address memberAddress, uint8 groupId) internal view returns (bool) {
        OrganizationStorage.Layout storage l = OrganizationStorage.layout();
        uint8 memberId = l.addressToMemberId[memberAddress];

        // Case: Member does not exist
        if (memberId == 0) return false;

        return l.groupIdToMemberIdToInGroup[groupId][memberId];
    }

    /**
     * @notice Internal helper to check if an address is whitelisted
     * @param addressToCheck The address to check
     * @return True if the address is whitelisted, false otherwise
     */
    function _isAddressWhitelisted(address addressToCheck) internal view returns (bool) {
        return OrganizationStorage.layout().whitelistedAddresses[addressToCheck];
    }

    /**
     * @notice Validates that the provided signatures meet the admin authorization requirements
     * @dev This function computes the nonce, verifies that the signatures are from authorized admin members/group
     *      and meet the required voting threshold, checks nonce and chainId for replay protection, and marks the nonce
     *      as used. This function will revert if authorization fails.
     * @param operationType The type of operation being performed
     * @param operationData The ABI-encoded data of the operation
     * @param salt A user-provided salt for nonce computation
     * @param chainId The chain ID for cross-chain replay protection - must match current chain ID
     * @param signatures The signatures to validate
     */
    function _validateAdminAuthorization(
        OrganizationStorage.AdminOperationType operationType,
        bytes memory operationData,
        uint256 salt,
        uint256 chainId,
        bytes memory signatures
    )
        internal
    {
        // Compute deterministic nonce from operation data and salt
        uint256 nonce = computeAdminNonce(operationType, operationData, salt);

        OrganizationStorage.Layout storage l = OrganizationStorage.layout();

        // Validate and check nonce for replay protection
        if (l.usedAdminNonces[nonce]) {
            revert AdminNonceAlreadyUsed(nonce);
        }

        // Validate chain ID for cross-chain replay protection
        if (chainId != block.chainid) {
            revert InvalidAdminChainId(block.chainid, chainId);
        }

        // Get operation hash for signature verification
        bytes32 operationHash = _getAdminOperationHash(operationType, operationData, salt, chainId);

        bool isAuthorized = false;

        // Case: Admin is an individual member
        if (l.adminPermission.adminType == OrganizationStorage.AdminType.Member) {
            isAuthorized = _hasValidAdminMemberSignature(signatures, operationHash);
        }
        // Case: Admin is a group
        else if (l.adminPermission.adminType == OrganizationStorage.AdminType.Group) {
            uint256 validSignatures = _getValidAdminGroupSignatures(signatures, operationHash);
            isAuthorized = validSignatures >= l.adminPermission.votingThreshold;
        }

        // Revert if not authorized
        if (!isAuthorized) {
            revert AdminOperationRejected("Insufficient authorization for admin operation");
        }

        // Mark nonce as used after successful validation
        l.usedAdminNonces[nonce] = true;
    }

    /**
     * @notice Checks if there is a valid signature from the admin member
     * @param signatures The signatures to verify
     * @param operationHash The hash of the admin operation
     * @return True if there is a valid signature from the admin member, false otherwise
     */
    function _hasValidAdminMemberSignature(
        bytes memory signatures,
        bytes32 operationHash
    )
        internal
        view
        returns (bool)
    {
        // Check that we have exactly one signature (65 bytes: r: 32, s: 32, v: 1)
        if (signatures.length != 65) return false;

        OrganizationStorage.Layout storage l = OrganizationStorage.layout();

        // Get the admin member's address
        address adminMemberAddress = l.memberIdToAddress[l.adminPermission.adminId];
        if (adminMemberAddress == address(0)) return false;

        // Extract signer address from signature using ERC-1271 compatible verification
        address signer = _getAdminSigner(signatures);

        // Check if signer is the admin member
        if (signer != adminMemberAddress) return false;

        // Verify the signature using ERC-1271
        return SignatureChecker.isValidSignatureNow(signer, operationHash, signatures);
    }

    /**
     * @notice Counts valid signatures from members of the admin group
     * @param signatures The signatures to verify
     * @param operationHash The hash of the admin operation
     * @return The number of valid signatures from admin group members
     */
    function _getValidAdminGroupSignatures(
        bytes memory signatures,
        bytes32 operationHash
    )
        internal
        view
        returns (uint256)
    {
        // Case: No signatures provided
        if (signatures.length == 0) return 0;

        // Each signature is 65 bytes (r: 32, s: 32, v: 1)
        uint8 signatureCount = uint8(signatures.length / 65);
        uint256 validSignatures = 0;

        // Track last signer to prevent duplicates (similar to Safe contracts)
        address lastSigner = address(0);

        OrganizationStorage.Layout storage l = OrganizationStorage.layout();

        // Iterate over signatures to count valid ones from admin group members
        for (uint8 i = 0; i < signatureCount; ++i) {
            bytes memory signature = SignatureUtils.extractSignature(signatures, i);

            // Extract signer address from signature using ERC-1271 compatible verification
            address signer = _getAdminSigner(signature);

            // Skip if signer is invalid
            if (signer == address(0)) continue;

            // Check for duplicate signers - signers must be unique and in ascending order
            // This prevents both duplicate signatures and replay attacks
            if (signer <= lastSigner) continue;

            // Update last signer for next iteration
            lastSigner = signer;

            // Verify the signature using ERC-1271
            if (!SignatureChecker.isValidSignatureNow(signer, operationHash, signature)) {
                continue;
            }

            // Check if signer is a member of the admin group
            uint8 memberId = l.addressToMemberId[signer];
            if (memberId != 0 && l.groupIdToMemberIdToInGroup[l.adminPermission.adminId][memberId]) {
                ++validSignatures;
            }
        }

        return validSignatures;
    }

    /**
     * @notice Gets the signer address from a signature for admin operations
     * @param signature The signature to extract the signer from
     * @return The signer address, or address(0) if invalid
     */
    function _getAdminSigner(bytes memory signature) internal pure returns (address) {
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
     * @notice Creates a hash of the admin operation for signature verification using EIP-712 typed data
     * @param operationType The type of operation being performed
     * @param operationData The ABI-encoded data of the operation
     * @param salt The user-provided salt for nonce computation
     * @param chainId The chain ID for cross-chain replay protection
     * @return The hash of the admin operation formatted for ERC-1271 signature verification
     */
    function _getAdminOperationHash(
        OrganizationStorage.AdminOperationType operationType,
        bytes memory operationData,
        uint256 salt,
        uint256 chainId
    )
        internal
        view
        returns (bytes32)
    {
        // Create EIP-712 structured data hash
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "AdminOperation(uint8 operationType,bytes operationData,uint256 salt,uint256 chainId,address organization)"
                ),
                uint8(operationType),
                keccak256(operationData),
                salt,
                chainId,
                address(this)
            )
        );

        // Return EIP-712 compatible hash for ERC-1271 signature verification
        return MessageHashUtils.toTypedDataHash(
            keccak256(
                abi.encode(
                    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                    keccak256("OnchainCustodyOrganization"),
                    keccak256("1"),
                    block.chainid,
                    address(this)
                )
            ),
            structHash
        );
    }
}
