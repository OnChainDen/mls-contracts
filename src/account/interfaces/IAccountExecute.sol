// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IAccountExecute
 * @notice Interface for the Account contract's execute function
 * @author Den Technologies Inc
 */
interface IAccountExecute {
    /**
     * @notice Executes a transaction from this account
     * @param to The destination address of the transaction
     * @param value The value of the transaction in wei
     * @param data The calldata for the transaction
     * @param nonce The nonce for this transaction
     * @param policyId The ID of the policy that governs this transaction
     */
    function executeTransaction(address to, uint256 value, bytes calldata data, uint256 nonce, uint256 policyId)
        external;
}
