// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IBatchedTransaction} from "interfaces/IBatchedTransaction.sol";

/**
 * @title BatchedTransaction
 * @notice Secure batched transaction execution for Safe modules
 * @dev A security-focused batched transaction contract designed to be delegatecalled
 *      from a Safe via SafeExecutorModule. Prevents common attack vectors:
 *
 *      Security Features:
 *      - No value field in encoding (hardcoded to 0, prevents ETH transfers)
 *      - address(this) validation (blocks calls to the Safe when delegatecalled from a
 *        Safe, so that sub-transactions can't call the Safe to modify owners/modules)
 *      - Atomic execution (reverts entire batch on any failure)
 *
 *      Transaction Format (packed, repeating):
 *      [to (20 bytes)][dataLength (8 bytes)][data (N bytes)]...
 * @author Den Technologies Inc
 */
contract BatchedTransaction is IBatchedTransaction {
    /// @inheritdoc IBatchedTransaction
    function execute(bytes calldata transactions) external override {
        // Process packed transactions using assembly for gas efficiency
        // solhint-disable-next-line no-inline-assembly
        // slither-disable-next-line assembly
        assembly {
            // Cache address(this) - when delegatecalled from a Safe, this is the Safe address
            let safe := address()
            // Get the start and end offset of the transactions calldata
            let currentOffset := transactions.offset
            let endOffset := add(currentOffset, transactions.length)

            // Process each transaction in the batch
            for {} lt(currentOffset, endOffset) {} {
                // Extract address from first 20 bytes (shift right by 96 bits)
                let to := shr(96, calldataload(currentOffset))
                // Load dataLength from currentOffset+20 (8 bytes = uint64, shift right 192 bits)
                let dataLength := shr(192, calldataload(add(currentOffset, 20)))

                // Advance currentOffset past the header (20 + 8 = 28 bytes)
                currentOffset := add(currentOffset, 28)

                // Security check: block calls to address(this) (the Safe when delegatecalled)
                // This prevents sub-transactions from calling the Safe to modify owners/modules
                if eq(to, safe) {
                    // Store error selector and parameter for CannotCallSafe(address)
                    // Shift left by 224 bits (28 bytes) to position selector in first 4 bytes
                    mstore(0x00, shl(224, 0xba5cc8c9))
                    mstore(0x04, to)
                    revert(0x00, 0x24)
                }

                // Copy sub-transaction's calldata to memory scratch space for the call
                let data := 0x00
                calldatacopy(data, currentOffset, dataLength)

                // Execute the call with value=0 (hardcoded for security)
                // call(gas, to, value, inOffset, inSize, outOffset, outSize)
                let success := call(gas(), to, 0, data, dataLength, 0x00, 0x00)

                // Revert if sub-transaction failed (consistent with Safe's MultiSendCallOnly)
                if iszero(success) {
                    revert(0x00, 0x00)
                }

                // Advance to the next transaction
                currentOffset := add(currentOffset, dataLength)
            }
        }
    }
}
