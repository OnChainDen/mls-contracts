// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { OnchainCustodyOrganization } from "./OnchainCustodyOrganization.sol";
import { Policies } from "./libraries/Policies.sol";
import { SignatureUtils } from "./libraries/SignatureUtils.sol";
import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/**
 * @title  Onchain Custody Smart Account
 * @notice An Onchain Custody Smart Account that can execute transactions according to policies
 * @author Den Technologies Inc
 */
contract OnchainCustodyAccount {
    enum Operation {
        Call,
        DelegateCall
    }

    /**
     * @notice The address of the onchain custody contract that this account is associated with
     */
    address public onchainCustodyAddress;

    /**
     * @notice Mapping of nonces for replay protection. Each nonce can only be used once.
     */
    mapping(uint256 => bool) private _usedNonces;

    /**
     * @notice Modifier to restrict function access to the guardian address only
     */
    modifier onlyGuardian() {
        OnchainCustodyOrganization organization = OnchainCustodyOrganization(onchainCustodyAddress);
        address guardian = organization.guardian();
        if (msg.sender != guardian) {
            revert UnauthorizedCaller(msg.sender, guardian);
        }
        _;
    }

    /**
     * @notice Emitted when a transaction is executed
     * @param to The destination address of the transaction
     * @param value The value of the transaction
     * @param data The data of the transaction
     * @param operation The operation of the transaction
     * @param nonce The nonce used for this transaction
     */
    event TransactionExecuted(
        address indexed to, uint256 value, bytes data, Operation operation, uint256 indexed nonce
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
     */
    event TransactionRejectedByUser(
        address indexed to, uint256 value, bytes data, Operation operation, uint256 indexed nonce, address rejectedBy
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
     * @notice Emitted when a function is called by an unauthorized address (not the guardian)
     * @param caller The address that attempted to call the function
     * @param guardian The current guardian address
     */
    error UnauthorizedCaller(address caller, address guardian);

    /**
     * @notice Checks if a nonce has been used
     * @param nonce The nonce to check
     * @return True if the nonce has been used, false otherwise
     */
    function isNonceUsed(uint256 nonce) external view returns (bool) {
        return _usedNonces[nonce];
    }

    /**
     * @notice Computes a deterministic nonce from transaction data and salt
     * @param to The destination address of the transaction
     * @param value The value of the transaction
     * @param data The data of the transaction
     * @param operation The operation of the transaction
     * @param salt A user-provided salt for nonce computation
     * @return The computed nonce
     */
    function computeNonce(
        address to,
        uint256 value,
        bytes calldata data,
        Operation operation,
        uint256 salt
    )
        public
        view
        returns (uint256)
    {
        return uint256(keccak256(abi.encode(address(this), to, value, keccak256(data), uint8(operation), salt)));
    }

    /**
     * @notice Executes a transaction from this account based on the policies of the onchain custody contract
     * @param to The destination address of the transaction
     * @param value The value of the transaction
     * @param data The data of the transaction
     * @param operation The operation of the transaction
     * @param salt A user-provided salt for nonce computation
     * @param chainId The chain ID for cross-chain replay protection - must match current chain ID
     * @param signatures The signatures of the transaction
     */
    function executeTransaction(
        address to,
        uint256 value,
        bytes calldata data,
        Operation operation,
        uint256 salt,
        uint256 chainId,
        bytes memory signatures
    )
        public
        onlyGuardian
    {
        // Validate chain ID for cross-chain replay protection
        if (chainId != block.chainid) {
            revert InvalidChainId(block.chainid, chainId);
        }

        // Compute deterministic nonce from transaction data and salt
        uint256 nonce = computeNonce(to, value, data, operation, salt);

        // Validate and consume nonce for replay protection
        if (_usedNonces[nonce]) {
            revert NonceAlreadyUsed(nonce);
        }

        // Mark nonce as used
        _usedNonces[nonce] = true;

        // Get the onchain custody contract that this account is associated with
        OnchainCustodyOrganization onchainCustody = OnchainCustodyOrganization(onchainCustodyAddress);

        // Get all policies from the onchain custody contract that this account is associated with
        Policies.Policy[] memory policies = onchainCustody.getPolicies();

        // Check policies to make sure this transaction can be executed
        _validateTransaction(onchainCustody, policies, to, value, data, operation, salt, chainId, signatures);

        // Execute the transaction
        _execute(to, value, data, operation, gasleft());

        emit TransactionExecuted(to, value, data, operation, nonce);
    }

    /**
     * @notice Rejects a transaction that has been signed but not yet executed
     * @param to The destination address of the transaction
     * @param value The value of the transaction
     * @param data The data of the transaction
     * @param operation The operation of the transaction
     * @param salt A user-provided salt for nonce computation
     * @param chainId The chain ID for cross-chain replay protection - must match current chain ID
     * @param signatures The signatures of the transaction
     */
    function rejectTransaction(
        address to,
        uint256 value,
        bytes calldata data,
        Operation operation,
        uint256 salt,
        uint256 chainId,
        bytes memory signatures
    )
        public
        onlyGuardian
    {
        // Validate chain ID for cross-chain replay protection
        if (chainId != block.chainid) {
            revert InvalidChainId(block.chainid, chainId);
        }

        // Compute deterministic nonce from transaction data and salt
        uint256 nonce = computeNonce(to, value, data, operation, salt);

        // Validate and consume nonce for replay protection
        if (_usedNonces[nonce]) {
            revert NonceAlreadyUsed(nonce);
        }

        // Mark nonce as used to prevent execution
        _usedNonces[nonce] = true;

        // Get the onchain custody contract that this account is associated with
        OnchainCustodyOrganization onchainCustody = OnchainCustodyOrganization(onchainCustodyAddress);

        // Get all policies from the onchain custody contract that this account is associated with
        Policies.Policy[] memory policies = onchainCustody.getPolicies();

        // Check if the caller is authorized to reject this transaction
        _validateRejectionAuthorization(onchainCustody, policies, to, value, data, operation, salt, chainId, signatures);

        emit TransactionRejectedByUser(to, value, data, operation, nonce, msg.sender);
    }

    /**
     * @notice Validates a transaction against all applicable policies
     * @param onchainCustody The custody contract instance
     * @param policies Array of all policies to check
     * @param to Transaction destination address
     * @param value Transaction value
     * @param data Transaction data
     * @param operation Transaction operation type
     * @param salt User-provided salt for nonce computation
     * @param chainId Transaction chain ID for cross-chain replay protection
     * @param signatures Signatures for approval verification
     */
    function _validateTransaction(
        OnchainCustodyOrganization onchainCustody,
        Policies.Policy[] memory policies,
        address to,
        uint256 value,
        bytes memory data,
        Operation operation,
        uint256 salt,
        uint256 chainId,
        bytes memory signatures
    )
        internal
        view
    {
        // Iterate over policies to find the first matching policy
        for (uint256 i = 0; i < policies.length; i++) {
            // Case: Current policy does not apply to transaction
            // Skip to next policy
            if (!onchainCustody.doesPolicyApplyToTransaction(policies[i], address(this), to, value, data, msg.sender)) {
                continue;
            }

            // Case: Current policy applies to transaction and is an automatic rejection policy
            // Revert the transaction
            if (policies[i].policyType == Policies.PolicyType.AutoReject) {
                revert TransactionRejectedByPolicy("Transaction automatically rejected by policy");
            }

            // Case: Current policy applies to transaction and is a manual approval policy
            // Check if the transaction has enough valid approvals
            if (policies[i].policyType == Policies.PolicyType.RequireManualApproval) {
                // Get transaction hash for signature verification
                bytes32 txHash = _getTransactionHash(to, value, data, operation, salt, chainId);
                uint256 requiredApprovals = onchainCustody.getRequiredApprovals(policies[i]);
                uint256 validApprovals = _getValidApprovals(onchainCustody, policies[i], signatures, txHash);

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
        }

        // Case: No policies match the transaction
        // If no policies match, reject the transaction
        revert TransactionRejectedByPolicy("No applicable policy found for transaction");
    }

    /**
     * @notice Validates that the caller is authorized to reject the given transaction
     * @param onchainCustody The custody contract instance
     * @param policies Array of all policies to check
     * @param to Transaction destination address
     * @param value Transaction value
     * @param data Transaction data
     * @param operation Transaction operation type
     * @param salt User-provided salt for nonce computation
     * @param chainId Transaction chain ID for cross-chain replay protection
     * @param signatures Signatures for approval verification
     */
    function _validateRejectionAuthorization(
        OnchainCustodyOrganization onchainCustody,
        Policies.Policy[] memory policies,
        address to,
        uint256 value,
        bytes memory data,
        Operation operation,
        uint256 salt,
        uint256 chainId,
        bytes memory signatures
    )
        internal
        view
    {
        // Iterate over policies to find the first matching policy
        for (uint256 i = 0; i < policies.length; i++) {
            // Case: Current policy does not apply to transaction
            // Skip to next policy
            if (!onchainCustody.doesPolicyApplyToTransaction(policies[i], address(this), to, value, data, msg.sender)) {
                continue;
            }

            // Case: Current policy applies to transaction and is an automatic approval policy
            // Only valid transaction initiators (as defined by policy) can reject it
            if (policies[i].policyType == Policies.PolicyType.AutoApprove) {
                // Get transaction hash for signature verification
                bytes32 txHash = _getTransactionHash(to, value, data, operation, salt, chainId);

                // Check if we have at least one valid signature from an authorized initiator
                if (_hasValidInitiatorSignature(onchainCustody, policies[i], signatures, txHash)) {
                    return;
                } else {
                    revert TransactionRejectedByPolicy("No valid signature from authorized transaction initiator");
                }
            }

            // Case: Current policy applies to transaction and is an automatic rejection policy
            // Only valid transaction initiators (as defined by policy) can reject it
            if (policies[i].policyType == Policies.PolicyType.AutoReject) {
                // Get transaction hash for signature verification
                bytes32 txHash = _getTransactionHash(to, value, data, operation, salt, chainId);

                // Check if we have at least one valid signature from an authorized initiator
                if (_hasValidInitiatorSignature(onchainCustody, policies[i], signatures, txHash)) {
                    return;
                } else {
                    revert TransactionRejectedByPolicy("No valid signature from authorized transaction initiator");
                }
            }

            // Case: Current policy applies to transaction and is a manual approval policy
            // Check if the caller has sufficient rejection authority
            if (policies[i].policyType == Policies.PolicyType.RequireManualApproval) {
                // Get transaction hash for signature verification
                bytes32 txHash = _getTransactionHash(to, value, data, operation, salt, chainId);
                uint256 requiredApprovals = onchainCustody.getRequiredApprovals(policies[i]);
                uint256 validApprovals = _getValidApprovals(onchainCustody, policies[i], signatures, txHash);

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

        // Case: No policies match the transaction
        // If no policies match, reject the rejection attempt
        revert TransactionRejectedByPolicy("No applicable policy found for transaction rejection");
    }

    /**
     * @notice Verifies signatures and returns the number of valid approvals
     * @param onchainCustody The custody contract instance
     * @param policy The policy requiring approval
     * @param signatures The signatures to verify
     * @param txHash The hash of the transaction
     * @return The number of valid approvals
     */
    function _getValidApprovals(
        OnchainCustodyOrganization onchainCustody,
        Policies.Policy memory policy,
        bytes memory signatures,
        bytes32 txHash
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
            if (onchainCustody.isSignerAuthorizedForPolicy(policy, signer)) {
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
    function _getSigner(bytes memory signature, bytes32 txHash) internal pure returns (address) {
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
     * @param onchainCustody The custody contract instance
     * @param policy The policy to check against
     * @param signatures The signatures to verify
     * @param txHash The hash of the transaction
     * @return True if there is at least one valid signature from an authorized initiator, false otherwise
     */
    function _hasValidInitiatorSignature(
        OnchainCustodyOrganization onchainCustody,
        Policies.Policy memory policy,
        bytes memory signatures,
        bytes32 txHash
    )
        internal
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
            if (onchainCustody.isSignerAuthorizedAsInitiator(policy, signer)) {
                return true;
            }
        }

        return false;
    }

    /**
     * @notice Creates a hash of the transaction for signature verification using EIP-712 typed data
     * @param to The destination address of the transaction
     * @param value The value of the transaction
     * @param data The data of the transaction
     * @param operation The operation of the transaction
     * @param salt The user-provided salt for nonce computation
     * @param chainId The chain ID for cross-chain replay protection
     * @return The hash of the transaction formatted for ERC-1271 signature verification
     */
    function _getTransactionHash(
        address to,
        uint256 value,
        bytes memory data,
        Operation operation,
        uint256 salt,
        uint256 chainId
    )
        internal
        view
        returns (bytes32)
    {
        // Validate chain ID matches current chain
        if (chainId != block.chainid) {
            revert InvalidChainId(block.chainid, chainId);
        }

        // Create EIP-712 structured data hash
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "ExecuteTransaction(address to,uint256 value,bytes data,uint8 operation,uint256 salt,uint256 chainId,address account)"
                ),
                to,
                value,
                keccak256(data),
                uint8(operation),
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
     * @notice Executes either a `CALL` or `DELEGATECALL` with provided parameters.
     * @dev This method doesn't perform any sanity check of the transaction, such as:
     *      - if the contract at `to` address has code or not
     *      It is the responsibility of the caller to perform such checks.
     * @param to Destination address.
     * @param value Ether value.
     * @param data Data payload.
     * @param operation Operation type (0 for `CALL`, 1 for `DELEGATECALL`).
     * @return success boolean flag indicating if the call succeeded.
     */
    function _execute(
        address to,
        uint256 value,
        bytes memory data,
        Operation operation,
        uint256 txGas
    )
        internal
        returns (bool success)
    {
        if (operation == Operation.DelegateCall) {
            /* solhint-disable no-inline-assembly */
            /// @solidity memory-safe-assembly
            assembly {
                success := delegatecall(txGas, to, add(data, 0x20), mload(data), 0, 0)
            }
        } else {
            /* solhint-disable no-inline-assembly */
            /// @solidity memory-safe-assembly
            assembly {
                success := call(txGas, to, value, add(data, 0x20), mload(data), 0, 0)
            }
        }
    }
}
