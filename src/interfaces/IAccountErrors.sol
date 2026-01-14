// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IAccountErrors
 * @notice Custom errors for Account contracts
 * @dev Consolidates all Account-related errors for audit clarity
 * @author Den Technologies Inc
 */
interface IAccountErrors {
    /**
     * @notice Thrown when a transaction execution fails
     */
    error TransactionExecutionFailed();

    /**
     * @notice Thrown when the caller is not the associated organization
     */
    error OnlyOrganization();
}
