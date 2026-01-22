// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {MerkleUtils} from "libraries/MerkleUtils.sol";
import {TokenTransferUtils} from "libraries/TokenTransferUtils.sol";
import {DestinationType, Policy} from "types/PolicyTypes.sol";

import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/**
 * @title Lib Policy Destination
 * @dev Library for validating transaction destinations against policies.
 *      Handles checking if a destination address is allowed by a policy.
 * @author Den Technologies Inc
 */
library LibPolicyDestination {
    /**
     * @dev Gets the actual destination address for a transaction.
     *      For ERC-20 token transfers, the actual destination is the token recipient (extracted from calldata).
     *      For native token transfers, the actual destination is the `to` address.
     *      For contract interactions, the actual destination is the `to` address.
     * @param to The transaction `to` address
     * @param data The transaction calldata
     * @param value The transaction value in wei
     * @return The actual destination address
     */
    function getActualDestination(address to, bytes calldata data, uint256 value) internal pure returns (address) {
        // Case: The transaction is a native token transfer
        if (data.length == 0) return to;

        // Case: The transaction is a contract interaction
        if (!TokenTransferUtils.isTransactionTokenTransfer(data, value)) return to;

        // Case: The transaction is an ERC-20 token transfer
        // Extract the recipient address from the transfer function call
        return TokenTransferUtils.extractERC20TransferRecipient(data);
    }

    /**
     * @dev Checks if the destination matches the policy's destination filter.
     *      Handles different destination types:
     *      - Any: Always matches
     *      - CustomList: Must be in the policy's custom destinations merkle tree
     * @param policy The policy to check against
     * @param to The transaction destination address
     * @param value The transaction value in wei
     * @param data The transaction calldata
     * @param destinationProof The merkle proof for the destination (for CustomList)
     * @return True if the destination matches, false otherwise
     */
    function isDestinationAllowedByPolicy(
        Policy calldata policy,
        address to,
        uint256 value,
        bytes calldata data,
        bytes32[] calldata destinationProof
    ) internal pure returns (bool) {
        DestinationType destType = policy.config.destinationType;

        // Case: Policy matches transaction to any address
        if (destType == DestinationType.Any) return true;

        // Determine the actual destination address based on transaction type
        address actualDestination = getActualDestination(to, data, value);

        // Case: Policy matches only transactions that are sent to a specific list of addresses
        // Verify via merkle proof that destination is in the custom destinations tree
        if (destType == DestinationType.CustomList) {
            bytes32 destLeaf = MerkleUtils.computeAddressLeaf(actualDestination);
            return MerkleProof.verify(destinationProof, policy.roots.customDestinationsRoot, destLeaf);
        }

        // Case: The policy does not match the transaction destination
        return false;
    }
}
