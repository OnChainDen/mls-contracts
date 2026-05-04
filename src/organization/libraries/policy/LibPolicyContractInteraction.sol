// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {ContractInteractionUtils} from "libraries/ContractInteractionUtils.sol";
import {LibPolicyDestination} from "organization/libraries/policy/LibPolicyDestination.sol";
import {LibPolicyParameterConstraints} from "organization/libraries/policy/LibPolicyParameterConstraints.sol";
import {Policy} from "types/PolicyTypes.sol";

import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/**
 * @title Lib Policy Contract Interaction
 * @dev Library for validating contract interaction transactions against policies.
 *      Handles validation of contract calls including function selector, parameters, and destination checks.
 * @author Den Technologies Inc
 */
library LibPolicyContractInteraction {
    /**
     * @dev Checks if a contract interaction transaction is allowed by the policy.
     *      Validates that:
     *      1. The function being called is allowed by the policy
     *      2. The native-token value is at or below the policy threshold
     *      3. The transaction parameters match the policy's constraints
     *      4. The destination (contract being called) is allowed by the policy
     *
     *      Parameter constraint validation does not enforce ABI canonical encoding for
     *      dynamic types (Bytes, String). It is the responsibility of admins and the
     *      Guardian to ensure that policies and the calldata submitted to the Organization
     *      contain correctly ABI-encoded parameters. See
     *      LibPolicyParameterConstraints._isBytesOrStringParameterAllowedByConstraint
     *      for details.
     * @param policy The policy to check against
     * @param to The transaction destination address (contract being called)
     * @param value The transaction value in wei
     * @param data The transaction calldata
     * @param functionProof The merkle proof for the function
     * @param constraints The parameter constraints to verify
     * @param constraintOneOfProofs ABI-encoded `bytes32[][]` of merkle inclusion proofs for
     *        `Address+OneOf` parameter constraints (compact, traversal-ordered). May be empty
     *        when the constraints array contains no `Address+OneOf` constraints. See
     *        `LibPolicyParameterConstraints` for the full layout contract.
     * @param destinationProof The merkle proof for the destination
     * @return True if the contract interaction is allowed, false otherwise
     */
    function isContractInteractionAllowedByPolicy(
        Policy calldata policy,
        address to,
        uint256 value,
        bytes calldata data,
        bytes32[] calldata functionProof,
        bytes calldata constraints,
        bytes calldata constraintOneOfProofs,
        bytes32[] calldata destinationProof
    ) internal pure returns (bool) {
        // forgefmt: disable-next-item
        return LibPolicyDestination.isDestinationAllowedByPolicy({
                policy: policy,
                to: to,
                value: value,
                data: data,
                destinationProof: destinationProof
            })
            && _isValueAllowedByPolicy(policy, value)
            && _isFunctionAllowedByPolicy(policy, data, functionProof, constraints)
            && LibPolicyParameterConstraints.areParametersAllowedByConstraints(
                constraints, constraintOneOfProofs, data
            );
    }

    /**
     * @dev Checks if the native-token value is allowed by a contract-interaction policy.
     *      The threshold is always enforced for `TransactionType.ContractInteractions`.
     *      Use `type(uint256).max` in policy config to represent no practical limit.
     * @param policy The policy to check against
     * @param value The transaction value in wei
     * @return True if the value is at or below the inclusive threshold, false otherwise
     */
    function _isValueAllowedByPolicy(Policy calldata policy, uint256 value) internal pure returns (bool) {
        return value <= policy.config.valueThresholdForContractCalls;
    }

    /**
     * @dev Checks if the function matches the policy's allowed functions filter.
     *      If anyFunction is true, always returns true.
     *      Otherwise, verifies the function selector and constraints are in the allowed functions merkle tree.
     * @param policy The policy to check against
     * @param data The transaction calldata
     * @param functionProof The merkle proof for the function
     * @param constraints The parameter constraints to verify (used to compute the constraints hash)
     * @return True if the function matches, false otherwise
     */
    function _isFunctionAllowedByPolicy(
        Policy calldata policy,
        bytes calldata data,
        bytes32[] calldata functionProof,
        bytes calldata constraints
    ) internal pure returns (bool) {
        // Case: Policy matches any function
        if (policy.config.anyFunction) return true;

        // Case: Policy matches only transactions that call a specific function, but the transaction is not calling
        //       a function
        if (data.length < ContractInteractionUtils.SELECTOR_LENGTH) return false;

        // Case: Policy matches only transactions that call a specific function, and the transaction is calling
        //       a function - verify via merkle proof
        bytes4 selector = ContractInteractionUtils.extractFunctionSelector(data);
        bytes32 constraintsHash = keccak256(constraints);

        // Verify function (selector + constraints hash) is in the allowed functions merkle tree
        bytes32 funcLeaf = _computeFunctionLeaf(selector, constraintsHash);
        return MerkleProof.verify(functionProof, policy.roots.allowedFunctionsRoot, funcLeaf);
    }

    /**
     * @dev Computes the merkle leaf for an allowed function.
     *      Combines function selector with constraints hash.
     * @param selector The function selector (first 4 bytes of calldata)
     * @param constraintsHash The keccak256 hash of the parameter constraints
     * @return The computed merkle leaf
     */
    function _computeFunctionLeaf(bytes4 selector, bytes32 constraintsHash) internal pure returns (bytes32) {
        return keccak256(bytes.concat(keccak256(abi.encode(selector, constraintsHash))));
    }
}
