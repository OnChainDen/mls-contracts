// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {TokenTransferUtils} from "libraries/TokenTransferUtils.sol";
import {LibPolicyDestination} from "organization/libraries/policy/LibPolicyDestination.sol";
import {Policy} from "types/PolicyTypes.sol";

/**
 * @title Lib Policy Token Transfer
 * @dev Library for validating token transfer transactions against policies.
 *      Handles validation of token transfers including token type, amount, and destination checks.
 * @author Den Technologies Inc
 */
library LibPolicyTokenTransfer {
    /**
     * @dev Checks if a token transfer transaction is allowed by the policy.
     *      Assumes the caller has already validated that `(to, value, data)` describes
     *      a token transfer (native or ERC-20).
     *      Validates that:
     *      1. The token being transferred is allowed by the policy
     *      2. The amount being transferred is within policy limits
     *      3. The destination (token recipient) is allowed by the policy
     * @param policy The policy to check against
     * @param to The transaction destination address (token contract for ERC20)
     * @param value The transaction value in wei
     * @param data The transaction calldata
     * @param destinationProof The merkle proof for the destination
     * @return True if the token transfer is allowed, false otherwise
     */
    function isTokenTransferAllowedByPolicy(
        Policy calldata policy,
        address to,
        uint256 value,
        bytes calldata data,
        bytes32[] calldata destinationProof
    ) internal pure returns (bool) {
        // forgefmt: disable-next-item
        return _isTokenAllowedByPolicy(policy, to, data) 
            && _isTokenAmountAllowedByPolicy(policy, data, value)
            && LibPolicyDestination.isDestinationAllowedByPolicy({
                policy: policy,
                to: to,
                value: value,
                data: data,
                destinationProof: destinationProof
            });
    }

    /**
     * @dev Checks if the token is allowed by the policy for a token transfer.
     *      If anyToken is true, always returns true.
     *      Otherwise, verifies the token address matches the policy's specified token.
     * @param policy The policy to check against
     * @param to The transaction destination address (token contract for ERC20)
     * @param data The transaction calldata
     * @return True if the token is allowed, false otherwise
     */
    function _isTokenAllowedByPolicy(Policy calldata policy, address to, bytes calldata data)
        internal
        pure
        returns (bool)
    {
        // Case: The policy matches transfers of any token
        if (policy.config.token.anyToken) return true;

        // Case: The policy matches only transfers of a specific token
        address transferToken = TokenTransferUtils.extractTokenAddress(to, data);
        return transferToken == policy.config.token.tokenAddress;
    }

    /**
     * @dev Checks if the token amount is allowed by the policy for a token transfer.
     *      Assumes the caller has already validated that `(value, data)` describes
     *      a token transfer (native or ERC-20).
     *      If hasAmountThreshold is false, always returns true.
     *      Otherwise, verifies the amount does not exceed the threshold.
     * @param policy The policy to check against
     * @param data The transaction calldata
     * @param value The transaction value in wei
     * @return True if the amount is allowed, false otherwise
     */
    function _isTokenAmountAllowedByPolicy(Policy calldata policy, bytes calldata data, uint256 value)
        internal
        pure
        returns (bool)
    {
        // Case: The policy has no amount threshold
        if (!policy.config.token.hasAmountThreshold) return true;

        uint256 amount = TokenTransferUtils.extractTransferAmount(data, value);

        // Case: The policy has an amount threshold - verify amount is at or below it (inclusive max).
        return amount <= policy.config.token.amountThreshold;
    }
}
