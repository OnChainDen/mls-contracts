// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";

/**
 * @title IAccount
 * @notice Interface for Account contracts (used with BeaconProxy)
 * @dev This contract is used behind a BeaconProxy where the Organization acts as the beacon.
 *      Upgrades are handled by the beacon (Organization), not by this contract directly.
 *      Extends IERC1271 to support smart contract signature validation.
 * @author Den Technologies Inc
 */
interface IAccount is IERC1271 {
    // ═══════════════════════════════════════════════════════════════════════════
    // Events
    // ═══════════════════════════════════════════════════════════════════════════

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
     * @notice Native tokens were received
     * @param sender The address that sent the tokens
     * @param value The native token value that was received
     * @dev `value` is intentionally not indexed: indexing only supports exact-match filtering,
     *      not range queries, so filtering by amount is done in application code.
     */
    // solhint-disable-next-line gas-indexed-events
    event OnchainCustodyAccountNativeTokenReceived(address indexed sender, uint256 value);

    // ═══════════════════════════════════════════════════════════════════════════
    // Errors
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Thrown when a transaction execution fails
     */
    error TransactionExecutionFailed();

    /**
     * @notice Thrown when the caller is not the associated organization
     */
    error OnlyOrganization();

    /**
     * @notice Receives native tokens (ETH) sent to this account
     * @dev Emits OnchainCustodyAccountNativeTokenReceived event when native tokens are received
     */
    receive() external payable;

    /**
     * @notice Executes a transaction from this account
     * @dev Can only be called by the associated Organization contract
     * @param to The destination address of the transaction
     * @param value The value of the transaction
     * @param data The data of the transaction
     * @param nonce The nonce for this transaction (computed by Organization)
     * @param policyId The ID of the policy that governs this transaction
     */
    function executeTransaction(address to, uint256 value, bytes calldata data, uint256 nonce, uint256 policyId)
        external;

    /**
     * @notice Gets the organization address that this account is associated with (the beacon)
     * @return The organization address
     */
    function getOrganizationAddress() external view returns (address);

    // Note: isValidSignature is inherited from IERC1271
    // Implementation delegates signature validation to the associated Organization contract.
    // Time-based policy limits are NOT supported for ERC-1271 signatures because the standard
    // requires isValidSignature to be a view function (cannot modify storage to track usage).
}
