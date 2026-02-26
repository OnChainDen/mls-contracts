// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {
    LibOrganizationPolicySuiteBase
} from "test/organization/libraries/LibOrganizationPolicy/LibOrganizationPolicySuiteBase.sol";
import {
    ConstraintType,
    ParamType,
    ParameterConstraint,
    Policy,
    TransactionType,
    ValidationProofs
} from "types/PolicyTypes.sol";

/**
 * @dev Shared helpers for `LibOrganizationPolicy` test suites.
 */
abstract contract LibOrganizationPolicyTestHelpers is LibOrganizationPolicySuiteBase {
    /// @dev Deterministic addresses reused across policy-library suites.
    address internal constant SOURCE_ACCOUNT = address(0xAA01);
    address internal constant ALT_SOURCE_ACCOUNT = address(0xAA02);
    address internal constant DESTINATION = address(0xBB01);
    address internal constant ALT_DESTINATION = address(0xBB02);
    address internal constant TOKEN = address(0xCC01);
    address internal constant ALT_TOKEN = address(0xCC02);

    /// @dev Builds and stores a one-policy merkle root, returning the policy proof.
    function _setSinglePolicyRoot(uint256 policyId, Policy memory policy) internal returns (bytes32[] memory proof) {
        Policy[] memory policies = new Policy[](1);
        policies[0] = policy;

        (bytes32 root, bytes32[] memory builtProof) = _buildPolicyRootAndProof(buildUint256Array(policyId), policies, 0);
        policyStateHarness.setPoliciesRoot(root);
        return builtProof;
    }

    /// @dev Builds a one-address merkle tree and returns `(root, proof)`.
    function _buildSingleAddressRootAndProof(address value) internal returns (bytes32 root, bytes32[] memory proof) {
        return _buildAddressRootAndProof(buildArray(value), 0);
    }

    /// @dev Builds a one-function merkle tree and returns `(root, proof)`.
    function _buildSingleFunctionRootAndProof(bytes4 selector, bytes memory constraints)
        internal
        returns (bytes32 root, bytes32[] memory proof)
    {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = selector;

        bytes[] memory constraintsList = new bytes[](1);
        constraintsList[0] = constraints;

        return _buildFunctionRootAndProof(selectors, constraintsList, 0);
    }

    /// @dev Builds a standard `ValidationProofs` object for convenience.
    function _buildProofs(
        Policy memory policy,
        bytes32[] memory policyProof,
        bytes32[] memory sourceProof,
        bytes32[] memory destinationProof,
        bytes32[] memory functionProof,
        bytes memory constraints
    ) internal pure returns (ValidationProofs memory proofs) {
        return _buildValidationProofs(policy, policyProof, sourceProof, destinationProof, functionProof, constraints);
    }

    /// @dev Builds a one-constraint payload enforcing exact `uint256` equality for the first parameter.
    function _buildExactUintConstraintPayload(uint256 exactValue) internal pure returns (bytes memory) {
        ParameterConstraint memory constraint = _buildConstraint({
            paramType: ParamType.Uint,
            constraintType: ConstraintType.Exact,
            headSlots: 1,
            comparisonData: abi.encode(exactValue),
            paramValueInListProof: new bytes32[](0)
        });

        return _encodeSingleConstraint(constraint);
    }

    /// @dev Builds a policy configured for TokenTransfers with permissive source/initiator/destination defaults.
    function _buildTokenTransferPolicy() internal view returns (Policy memory policy) {
        policy = _buildBasePolicy();
        policy.config.transactionType = TransactionType.TokenTransfers;
    }

    /// @dev Builds a policy configured for ContractInteractions with permissive defaults.
    function _buildContractInteractionPolicy() internal view returns (Policy memory policy) {
        policy = _buildBasePolicy();
        policy.config.transactionType = TransactionType.ContractInteractions;
    }
}
