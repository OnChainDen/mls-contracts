// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity >=0.7.0 <0.9.0;

import {ISafe} from "script/libraries/ISafe.sol";
import {Logger} from "script/libraries/Logger.sol";
import {StringUtils} from "script/libraries/StringUtils.sol";

/**
 * @title SafeTransactionUtils
 * @notice Helpers for Safe owner operations that use onchain approvals (approveHash) rather
 *         than offchain signatures.
 * @dev Shared by scripts where Safe owners must approve and execute a transaction targeting
 *      either the Safe itself (e.g. module management) or another contract (e.g. the
 *      ImplementationWhitelist proxy owned by the Admin Safe).
 *
 *      All Safe transactions built here use the canonical "owner operation" shape: value = 0 and
 *      all gas/refund parameters set to zero (the operation type — Call or DelegateCall — is
 *      supplied by the caller).
 *
 *      This library uses a floating pragma (>=0.7.0 <0.9.0) to allow reuse by both
 *      platform scripts (0.8.33) and Safe deployment scripts (0.7.6).
 *
 * @author Den Technologies Inc
 */
library SafeTransactionUtils {
    /// @dev Submits the caller's onchain approval (approveHash) for a Safe transaction and, when
    ///      `executeIfReady` is true and the approval threshold is met, executes it via the Safe.
    ///      The transaction uses the canonical owner-operation shape (value 0, zero gas/refund params).
    ///
    ///      Must be invoked within an active broadcast (vm.startBroadcast) so the approval and the
    ///      optional execution are actually sent. The caller (msg.sender) must be an owner of the Safe.
    ///      Progress is logged via Logger; callers are expected to log their own surrounding header/footer.
    /// @param safe The Safe contract
    /// @param to The transaction target (the Safe itself, or another contract it controls)
    /// @param data The transaction calldata
    /// @param operation The Safe operation type (0 = Call, 1 = DelegateCall)
    /// @param executeIfReady If true, execute the transaction when the threshold is met after approval
    // solhint-disable-next-line code-complexity
    function approveAndExecuteIfReady(ISafe safe, address to, bytes memory data, uint8 operation, bool executeIfReady)
        internal
    {
        bytes32 txHash = getTransactionHash(safe, to, data, operation);
        uint256 threshold = safe.getThreshold();
        address[] memory owners = safe.getOwners();

        // The caller must be a Safe owner to approve
        bool isOwner = false;
        for (uint256 i = 0; i < owners.length; ++i) {
            if (owners[i] == msg.sender) {
                isOwner = true;
                break;
            }
        }
        require(isOwner, "Sender is not a Safe owner");

        // Approve the hash if this owner has not already done so
        if (safe.approvedHashes(msg.sender, txHash) == 1) {
            Logger.logIndented("Already approved by this owner");
        } else {
            Logger.logIndented("Submitting approval...");
            safe.approveHash(txHash);
            Logger.logIndented("Approval submitted successfully");
        }

        // Count approvals (includes the one just submitted)
        uint256 approvalCount = countApprovals(safe, txHash, owners);
        Logger.logKeyValue("Approvals after this", approvalCount);

        // Execute if requested and the threshold is met
        if (executeIfReady && approvalCount >= threshold) {
            Logger.logEmptyLine();
            Logger.logIndented("Threshold met - executing transaction...");

            bytes memory signatures = buildApprovedSignatures(safe, txHash, owners, threshold);

            bool success = safe.execTransaction({
                to: to,
                value: 0,
                data: data,
                operation: operation, // 0 = Call, 1 = DelegateCall
                safeTxGas: 0,
                baseGas: 0,
                gasPrice: 0,
                gasToken: address(0),
                refundReceiver: payable(address(0)),
                signatures: signatures
            });

            require(success, "Transaction execution failed");
            Logger.logIndented("Transaction executed successfully!");
        } else if (approvalCount < threshold) {
            Logger.logEmptyLine();
            Logger.logIndented(
                string(
                    abi.encodePacked(
                        "Need ", StringUtils.toString(threshold - approvalCount), " more approval(s) to execute"
                    )
                )
            );
        }
    }

    /// @dev Computes the Safe transaction hash for an owner operation at the Safe's current nonce
    /// @param safe The Safe contract
    /// @param to The transaction target (the Safe itself for module management, or another contract)
    /// @param data The transaction calldata
    /// @param operation The Safe operation type (0 = Call, 1 = DelegateCall)
    /// @return The Safe transaction hash to approve
    function getTransactionHash(ISafe safe, address to, bytes memory data, uint8 operation)
        internal
        view
        returns (bytes32)
    {
        uint256 safeNonce = safe.nonce();
        return safe.getTransactionHash({
            to: to,
            value: 0,
            data: data,
            operation: operation, // 0 = Call, 1 = DelegateCall
            safeTxGas: 0,
            baseGas: 0,
            gasPrice: 0,
            gasToken: address(0),
            refundReceiver: address(0),
            _nonce: safeNonce
        });
    }

    /// @dev Counts the number of owners who have approved the given hash
    /// @param safe The Safe contract
    /// @param txHash The Safe transaction hash
    /// @param owners The Safe owners
    /// @return count The number of owners that have approved
    function countApprovals(ISafe safe, bytes32 txHash, address[] memory owners) internal view returns (uint256 count) {
        for (uint256 i = 0; i < owners.length; ++i) {
            // slither-disable-next-line calls-loop
            if (safe.approvedHashes(owners[i], txHash) == 1) {
                ++count;
            }
        }
    }

    /// @dev Builds Safe signatures from approved hashes (sorted by owner address)
    /// @param safe The Safe contract
    /// @param txHash The Safe transaction hash
    /// @param owners The Safe owners
    /// @param threshold The number of signatures required
    /// @return signatures The packed signatures using the approved-hash signature type
    function buildApprovedSignatures(ISafe safe, bytes32 txHash, address[] memory owners, uint256 threshold)
        internal
        view
        returns (bytes memory signatures)
    {
        // Collect approving owners
        address[] memory approvers = new address[](threshold);
        uint256 approverCount = 0;

        for (uint256 i = 0; i < owners.length && approverCount < threshold; ++i) {
            // slither-disable-next-line calls-loop
            if (safe.approvedHashes(owners[i], txHash) == 1) {
                approvers[approverCount] = owners[i];
                ++approverCount;
            }
        }

        require(approverCount >= threshold, "Not enough approvals");

        // Sort approvers by address (ascending) - Safe requires sorted signatures
        for (uint256 i = 0; i < threshold - 1; ++i) {
            for (uint256 j = i + 1; j < threshold; ++j) {
                if (approvers[i] > approvers[j]) {
                    address temp = approvers[i];
                    approvers[i] = approvers[j];
                    approvers[j] = temp;
                }
            }
        }

        // Build signatures using approved hash signature type
        // For pre-approved hashes: r = owner address, s = 0, v = 1
        signatures = new bytes(threshold * 65);
        for (uint256 i = 0; i < threshold; ++i) {
            // r = padded owner address (32 bytes)
            // s = 0 (32 bytes)
            // v = 1 (1 byte) - indicates approved hash
            bytes32 r = bytes32(uint256(uint160(approvers[i])));
            bytes32 s = bytes32(0);
            uint8 v = 1;

            // slither-disable-next-line assembly
            assembly {
                let sigPos := add(signatures, add(32, mul(i, 65)))
                mstore(sigPos, r)
                mstore(add(sigPos, 32), s)
                mstore8(add(sigPos, 64), v)
            }
        }
    }
}
