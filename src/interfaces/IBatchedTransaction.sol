// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

/**
 * @title IBatchedTransaction
 * @notice Interface for secure batched transaction execution
 * @dev A security-focused alternative to MultiSendCallOnly that prevents:
 *      - ETH transfers via non-zero value fields (value is hardcoded to 0)
 *      - Calls to the Safe (address(this) check prevents Safe self-calls when delegatecalled)
 *
 *      Transaction encoding format (packed, no padding):
 *      [to (20 bytes)][dataLength (8 bytes)][data (N bytes)]...
 *
 *      Benefits over MultiSendCallOnly:
 *      - No value field in encoding (hardcoded to 0, saves gas and prevents ETH transfers)
 *      - address(this) validation (when delegatecalled, address(this) is the Safe)
 *      - More efficient encoding (28 + N bytes per tx vs 85 + N bytes)
 *
 * @author Den Technologies Inc
 */
interface IBatchedTransaction {
    /// @notice Error thrown when a sub-transaction targets the delegatecaller (the Safe when delegatecalled)
    /// @param target The target address that was blocked
    error CannotCallSafe(address target);

    /**
     * @notice Executes a batch of transactions
     * @dev Designed to be called via DELEGATECALL from a Safe.
     *      When delegatecalled, address(this) is the Safe, which we use to block self-calls.
     *
     *      Transaction encoding (packed, repeating):
     *      - to: 20 bytes (target address)
     *      - dataLength: 8 bytes (uint64, length of calldata)
     *      - data: N bytes (calldata)
     *
     *      Security guarantees:
     *      - All calls use value=0 (no ETH transfers)
     *      - Calls to address(this) (the Safe when delegatecalled) are blocked
     *      - Reverts on any sub-transaction failure
     *
     * @param transactions Packed transaction data in the format described above
     */
    function execute(bytes calldata transactions) external;
}
