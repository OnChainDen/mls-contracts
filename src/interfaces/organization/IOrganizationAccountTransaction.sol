// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ValidationProofs} from "../../types/PolicyTypes.sol";

/**
 * @title IOrganizationAccountTransaction
 * @notice Interface for account transaction execution in Organization contracts
 * @dev Maps to LibOrganizationAccountTransaction library functionality
 * @author Den Technologies Inc
 */
interface IOrganizationAccountTransaction {
    // ═══════════════════════════════════════════════════════════════════════════
    // Events
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Emitted when a transaction is executed on an account
     * @param account The account that executed the transaction
     * @param to The destination address of the transaction
     * @param value The value of the transaction
     * @param data The data of the transaction
     * @param nonce The nonce used for this transaction
     * @param policyId The policy ID that governed this transaction
     */
    event AccountTransactionExecuted(
        address indexed account, address indexed to, uint256 value, bytes data, uint256 indexed nonce, uint256 policyId
    );

    /**
     * @notice Emitted when a transaction is rejected by authorized users
     * @param account The account for which the transaction was rejected
     * @param to The destination address of the transaction
     * @param value The value of the transaction
     * @param data The data of the transaction
     * @param nonce The nonce used for this transaction
     * @param policyId The policy ID that governed this transaction
     */
    event AccountTransactionRejected(
        address indexed account, address indexed to, uint256 value, bytes data, uint256 indexed nonce, uint256 policyId
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // Errors
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Thrown when a transaction is rejected by policy
     * @param reason The reason for rejection
     */
    error TransactionRejectedByPolicy(string reason);

    /**
     * @notice Thrown when a transaction rejection is not allowed
     * @param reason The reason rejection is not allowed
     */
    error TransactionRejectionNotAllowed(string reason);

    /**
     * @notice Thrown when there are insufficient approvals for a transaction
     * @param required The number of required approvals
     * @param provided The number of provided approvals
     */
    error InsufficientApprovals(uint256 required, uint256 provided);

    /**
     * @notice Thrown when a policy does not apply to a transaction
     * @param policyId The policy ID that does not apply
     */
    error PolicyDoesNotApply(uint256 policyId);

    /**
     * @notice Thrown when a transaction has expired
     * @param expirationTimestamp The expiration timestamp
     * @param currentTimestamp The current timestamp
     */
    error TransactionExpired(uint256 expirationTimestamp, uint256 currentTimestamp);

    /**
     * @notice Thrown when signatures length is insufficient
     */
    error InsufficientSignaturesLength();

    /**
     * @notice Thrown when a time-based limit is exceeded
     * @param policyId The policy ID that exceeded the limit
     */
    error TimeBasedLimitExceeded(uint256 policyId);

    // ═══════════════════════════════════════════════════════════════════════════
    // Functions
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Executes a transaction on an account through the organization
     * @dev Policy is verified via merkle proof in the proofs parameter
     * @param account The account to execute the transaction from
     * @param to The destination address of the transaction
     * @param value The value of the transaction
     * @param data The data of the transaction
     * @param salt A user-provided salt for nonce computation
     * @param expirationTimestamp The timestamp after which the signatures are no longer valid
     * @param policyId The ID of the policy that governs this transaction
     * @param signatures The signatures authorizing the transaction
     * @param proofs The validation proofs containing policy data and merkle proofs
     */
    function executeAccountTransaction(
        address account,
        address to,
        uint256 value,
        bytes calldata data,
        uint256 salt,
        uint256 expirationTimestamp,
        uint256 policyId,
        bytes calldata signatures,
        ValidationProofs calldata proofs
    ) external;

    /**
     * @notice Rejects a transaction that has been signed but not yet executed
     * @dev Policy is verified via merkle proof in the proofs parameter
     * @param account The account for which to reject the transaction
     * @param to The destination address of the transaction
     * @param value The value of the transaction
     * @param data The data of the transaction
     * @param salt A user-provided salt for nonce computation
     * @param expirationTimestamp The timestamp after which the signatures are no longer valid
     * @param policyId The ID of the policy that governs this transaction
     * @param signatures The signatures authorizing the rejection
     * @param proofs The validation proofs containing policy data and merkle proofs
     */
    function rejectAccountTransaction(
        address account,
        address to,
        uint256 value,
        bytes calldata data,
        uint256 salt,
        uint256 expirationTimestamp,
        uint256 policyId,
        bytes calldata signatures,
        ValidationProofs calldata proofs
    ) external;
}
