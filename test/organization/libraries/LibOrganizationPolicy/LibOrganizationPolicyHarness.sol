// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {LibOrganizationPolicy} from "organization/libraries/LibOrganizationPolicy.sol";
import {LibPolicyApproval} from "organization/libraries/policy/LibPolicyApproval.sol";
import {LibPolicyContractInteraction} from "organization/libraries/policy/LibPolicyContractInteraction.sol";
import {LibPolicyDestination} from "organization/libraries/policy/LibPolicyDestination.sol";
import {LibPolicyInitiator} from "organization/libraries/policy/LibPolicyInitiator.sol";
import {LibPolicyParameterConstraints} from "organization/libraries/policy/LibPolicyParameterConstraints.sol";
import {LibPolicyRateLimits} from "organization/libraries/policy/LibPolicyRateLimits.sol";
import {LibPolicyTokenTransfer} from "organization/libraries/policy/LibPolicyTokenTransfer.sol";
import {OrganizationPolicyStateHarness} from "test/organization/shared/OrganizationPolicyStateHarness.sol";
import {ConstraintType, ParameterConstraint, Policy, ValidationProofs} from "types/PolicyTypes.sol";

/**
 * @dev Library-focused test harness for policy libraries.
 *      Exposes wrappers around public and internal helper functions.
 */
contract LibOrganizationPolicyHarness is OrganizationPolicyStateHarness {
    /**
     * @dev Wrapper around `LibOrganizationPolicy.setPolicies`.
     */
    function setPoliciesViaLibrary(bytes32 newPoliciesRoot, string calldata ipfsCid) external {
        LibOrganizationPolicy.setPolicies(newPoliciesRoot, ipfsCid);
    }

    /**
     * @dev Wrapper around `LibOrganizationPolicy.checkAndUpdateRateLimit`.
     */
    function checkAndUpdateRateLimitViaLibrary(
        uint256 policyId,
        Policy memory policy,
        address account,
        address destination,
        address initiator,
        uint256 usageAmount
    ) external returns (bool) {
        return LibOrganizationPolicy.checkAndUpdateRateLimit(
            policyId, policy, account, destination, initiator, usageAmount
        );
    }

    /**
     * @dev Wrapper around `LibOrganizationPolicy.isPolicyInOrg`.
     */
    function isPolicyInOrgViaLibrary(uint256 policyId, Policy memory policy, bytes32[] memory proof)
        external
        view
        returns (bool)
    {
        return LibOrganizationPolicy.isPolicyInOrg(policyId, policy, proof);
    }

    /**
     * @dev Wrapper around `LibOrganizationPolicy.isTransactionAllowedByPolicy`.
     */
    function isTransactionAllowedByPolicyViaLibrary(
        uint256 policyId,
        address sourceAccount,
        address to,
        uint256 value,
        bytes calldata data,
        address initiator,
        ValidationProofs calldata proofs
    ) external view returns (bool) {
        return LibOrganizationPolicy.isTransactionAllowedByPolicy(
            policyId, sourceAccount, to, value, data, initiator, proofs
        );
    }

    /**
     * @dev Wrapper around `LibOrganizationPolicy.areApprovalsValid`.
     */
    function areApprovalsValidViaLibrary(Policy memory policy, bytes memory signatures, bytes32 messageHash)
        external
        view
        returns (bool)
    {
        return LibOrganizationPolicy.areApprovalsValid(policy, signatures, messageHash);
    }

    /**
     * @dev Wrapper around `LibOrganizationPolicy.computeTimeWindow`.
     */
    function computeTimeWindowViaLibrary(Policy memory policy) external view returns (uint256) {
        return LibOrganizationPolicy.computeTimeWindow(policy);
    }

    /**
     * @dev Wrapper around `LibOrganizationPolicy.getCurrentUsage`.
     */
    function getCurrentUsageViaLibrary(
        uint256 policyId,
        Policy memory policy,
        address account,
        address destination,
        address initiator
    ) external view returns (uint256) {
        return LibOrganizationPolicy.getCurrentUsage(policyId, policy, account, destination, initiator);
    }

    /**
     * @dev Wrapper around `LibOrganizationPolicy.isInitiatorAuthorized`.
     */
    function isInitiatorAuthorizedViaLibrary(Policy memory policy, address initiatorAddress)
        external
        view
        returns (bool)
    {
        return LibOrganizationPolicy.isInitiatorAuthorized(policy, initiatorAddress);
    }

    /**
     * @dev Wrapper around `LibOrganizationPolicy.isSourceAccountAllowedByPolicy`.
     */
    function isSourceAccountAllowedByPolicyViaLibrary(
        Policy memory policy,
        address sourceAccount,
        bytes32[] memory sourceAccountProof
    ) external pure returns (bool) {
        return LibOrganizationPolicy.isSourceAccountAllowedByPolicy(policy, sourceAccount, sourceAccountProof);
    }

    /**
     * @dev Wrapper around `LibOrganizationPolicy.getRequiredApprovals`.
     */
    function getRequiredApprovalsViaLibrary(Policy memory policy) external pure returns (uint256) {
        return LibOrganizationPolicy.getRequiredApprovals(policy);
    }

    /**
     * @dev Wrapper around `LibOrganizationPolicy.getActualDestination`.
     */
    function getActualDestinationViaLibrary(address to, bytes calldata data, uint256 value)
        external
        pure
        returns (address)
    {
        return LibOrganizationPolicy.getActualDestination(to, data, value);
    }

    /**
     * @dev Wrapper around `LibOrganizationPolicy.computeUsageKey`.
     */
    function computeUsageKeyViaLibrary(
        uint256 policyId,
        Policy memory policy,
        address account,
        address destination,
        address initiator
    ) external pure returns (bytes32) {
        return LibOrganizationPolicy.computeUsageKey(policyId, policy, account, destination, initiator);
    }

    /**
     * @dev Wrapper around `LibOrganizationPolicy._computePolicyLeaf`.
     */
    function computePolicyLeafViaLibrary(uint256 policyId, Policy memory policy) external pure returns (bytes32) {
        return LibOrganizationPolicy._computePolicyLeaf(policyId, policy);
    }

    /**
     * @dev Wrapper around `LibPolicyInitiator.isInitiatorAuthorized`.
     */
    function isInitiatorAuthorizedViaPolicyLibrary(Policy memory policy, address initiatorAddress)
        external
        view
        returns (bool)
    {
        return LibPolicyInitiator.isInitiatorAuthorized(policy, initiatorAddress);
    }

    /**
     * @dev Wrapper around `LibPolicyApproval.areApprovalsValid`.
     */
    function areApprovalsValidViaPolicyLibrary(Policy memory policy, bytes memory signatures, bytes32 messageHash)
        external
        view
        returns (bool)
    {
        return LibPolicyApproval.areApprovalsValid(policy, signatures, messageHash);
    }

    /**
     * @dev Wrapper around `LibPolicyApproval.getRequiredApprovals`.
     */
    function getRequiredApprovalsViaPolicyLibrary(Policy memory policy) external pure returns (uint256) {
        return LibPolicyApproval.getRequiredApprovals(policy);
    }

    /**
     * @dev Wrapper around `LibPolicyApproval._isSignerAuthorizedForPolicy`.
     */
    function isSignerAuthorizedForPolicyViaPolicyLibrary(Policy memory policy, address signerAddress)
        external
        view
        returns (bool)
    {
        return LibPolicyApproval._isSignerAuthorizedForPolicy(policy, signerAddress);
    }

    /**
     * @dev Wrapper around `LibPolicyDestination.getActualDestination`.
     */
    function getActualDestinationViaPolicyLibrary(address to, bytes calldata data, uint256 value)
        external
        pure
        returns (address)
    {
        return LibPolicyDestination.getActualDestination(to, data, value);
    }

    /**
     * @dev Wrapper around `LibPolicyDestination.isDestinationAllowedByPolicy`.
     */
    function isDestinationAllowedByPolicyViaPolicyLibrary(
        Policy calldata policy,
        address to,
        uint256 value,
        bytes calldata data,
        bytes32[] calldata destinationProof
    ) external pure returns (bool) {
        return LibPolicyDestination.isDestinationAllowedByPolicy(policy, to, value, data, destinationProof);
    }

    /**
     * @dev Wrapper around `LibPolicyTokenTransfer.isTokenTransferAllowedByPolicy`.
     */
    function isTokenTransferAllowedByPolicyViaPolicyLibrary(
        Policy calldata policy,
        address to,
        uint256 value,
        bytes calldata data,
        bytes32[] calldata destinationProof
    ) external pure returns (bool) {
        return LibPolicyTokenTransfer.isTokenTransferAllowedByPolicy(policy, to, value, data, destinationProof);
    }

    /**
     * @dev Wrapper around `LibPolicyTokenTransfer._isTokenAllowedByPolicy`.
     */
    function isTokenAllowedByPolicyViaPolicyLibrary(Policy calldata policy, address to, bytes calldata data)
        external
        pure
        returns (bool)
    {
        return LibPolicyTokenTransfer._isTokenAllowedByPolicy(policy, to, data);
    }

    /**
     * @dev Wrapper around `LibPolicyTokenTransfer._isTokenAmountAllowedByPolicy`.
     */
    function isTokenAmountAllowedByPolicyViaPolicyLibrary(Policy calldata policy, bytes calldata data, uint256 value)
        external
        pure
        returns (bool)
    {
        return LibPolicyTokenTransfer._isTokenAmountAllowedByPolicy(policy, data, value);
    }

    /**
     * @dev Wrapper around `LibPolicyContractInteraction.isContractInteractionAllowedByPolicy`.
     */
    function isContractInteractionAllowedByPolicyViaPolicyLibrary(
        Policy calldata policy,
        address to,
        uint256 value,
        bytes calldata data,
        bytes32[] calldata functionProof,
        bytes calldata constraints,
        bytes32[] calldata destinationProof
    ) external pure returns (bool) {
        return LibPolicyContractInteraction.isContractInteractionAllowedByPolicy(
            policy, to, value, data, functionProof, constraints, destinationProof
        );
    }

    /**
     * @dev Wrapper around `LibPolicyContractInteraction._isFunctionAllowedByPolicy`.
     */
    function isFunctionAllowedByPolicyViaPolicyLibrary(
        Policy calldata policy,
        bytes calldata data,
        bytes32[] calldata functionProof,
        bytes calldata constraints
    ) external pure returns (bool) {
        return LibPolicyContractInteraction._isFunctionAllowedByPolicy(policy, data, functionProof, constraints);
    }

    /**
     * @dev Wrapper around `LibPolicyContractInteraction._computeFunctionLeaf`.
     */
    function computeFunctionLeafViaPolicyLibrary(bytes4 selector, bytes32 constraintsHash)
        external
        pure
        returns (bytes32)
    {
        return LibPolicyContractInteraction._computeFunctionLeaf(selector, constraintsHash);
    }

    /**
     * @dev Wrapper around `LibPolicyParameterConstraints.areParametersAllowedByConstraints`.
     */
    function areParametersAllowedByConstraintsViaPolicyLibrary(bytes calldata parameterConstraints, bytes calldata data)
        external
        pure
        returns (bool)
    {
        return LibPolicyParameterConstraints.areParametersAllowedByConstraints(parameterConstraints, data);
    }

    /**
     * @dev Wrapper around `LibPolicyParameterConstraints._processConstraints`.
     */
    function processConstraintsViaPolicyLibrary(ParameterConstraint[] calldata constraints, bytes calldata data)
        external
        pure
        returns (bool)
    {
        ParameterConstraint[] memory constraintsMemory = constraints;
        return LibPolicyParameterConstraints._processConstraints(constraintsMemory, data);
    }

    /**
     * @dev Wrapper around `LibPolicyParameterConstraints._isParameterAllowedByConstraint`.
     */
    function isParameterAllowedByConstraintViaPolicyLibrary(
        ParameterConstraint calldata constraint,
        bytes32 paramHeadValue,
        bytes calldata data
    ) external pure returns (bool) {
        ParameterConstraint memory constraintMemory = constraint;
        return LibPolicyParameterConstraints._isParameterAllowedByConstraint(constraintMemory, paramHeadValue, data);
    }

    /**
     * @dev Wrapper around `LibPolicyParameterConstraints._isBoolParameterAllowedByConstraint`.
     */
    function isBoolParameterAllowedByConstraintViaPolicyLibrary(
        ConstraintType constraintType,
        bytes calldata comparisonData,
        bytes32 paramHeadValue
    ) external pure returns (bool) {
        return LibPolicyParameterConstraints._isBoolParameterAllowedByConstraint(
            constraintType, comparisonData, paramHeadValue
        );
    }

    /**
     * @dev Wrapper around `LibPolicyParameterConstraints._isUintParameterAllowedByConstraint`.
     */
    function isUintParameterAllowedByConstraintViaPolicyLibrary(
        ConstraintType constraintType,
        bytes calldata comparisonData,
        bytes32 paramHeadValue
    ) external pure returns (bool) {
        return LibPolicyParameterConstraints._isUintParameterAllowedByConstraint(
            constraintType, comparisonData, paramHeadValue
        );
    }

    /**
     * @dev Wrapper around `LibPolicyParameterConstraints._isIntParameterAllowedByConstraint`.
     */
    function isIntParameterAllowedByConstraintViaPolicyLibrary(
        ConstraintType constraintType,
        bytes calldata comparisonData,
        bytes32 paramHeadValue
    ) external pure returns (bool) {
        return LibPolicyParameterConstraints._isIntParameterAllowedByConstraint(
            constraintType, comparisonData, paramHeadValue
        );
    }

    /**
     * @dev Wrapper around `LibPolicyParameterConstraints._isAddressParameterAllowedByConstraint`.
     */
    function isAddressParameterAllowedByConstraintViaPolicyLibrary(
        ConstraintType constraintType,
        bytes calldata comparisonData,
        bytes32 paramHeadValue,
        bytes32[] calldata addressListProof
    ) external pure returns (bool) {
        bytes32[] memory addressListProofMemory = addressListProof;
        return LibPolicyParameterConstraints._isAddressParameterAllowedByConstraint(
            constraintType, comparisonData, paramHeadValue, addressListProofMemory
        );
    }

    /**
     * @dev Wrapper around `LibPolicyParameterConstraints._isFixedBytesParameterAllowedByConstraint`.
     */
    function isFixedBytesParameterAllowedByConstraintViaPolicyLibrary(
        ConstraintType constraintType,
        bytes calldata comparisonData,
        bytes32 paramHeadValue
    ) external pure returns (bool) {
        return LibPolicyParameterConstraints._isFixedBytesParameterAllowedByConstraint(
            constraintType, comparisonData, paramHeadValue
        );
    }

    /**
     * @dev Wrapper around `LibPolicyParameterConstraints._isBytesOrStringParameterAllowedByConstraint`.
     */
    function isBytesOrStringParameterAllowedByConstraintViaPolicyLibrary(
        ConstraintType constraintType,
        bytes calldata comparisonData,
        bytes32 paramHeadValue,
        bytes calldata data
    ) external pure returns (bool) {
        return LibPolicyParameterConstraints._isBytesOrStringParameterAllowedByConstraint(
            constraintType, comparisonData, paramHeadValue, data
        );
    }

    /**
     * @dev Wrapper around `LibPolicyRateLimits.checkAndUpdateRateLimit`.
     */
    function checkAndUpdateRateLimitViaPolicyLibrary(
        uint256 policyId,
        Policy memory policy,
        address account,
        address destination,
        address initiator,
        uint256 usageAmount
    ) external returns (bool) {
        return LibPolicyRateLimits.checkAndUpdateRateLimit(
            policyId, policy, account, destination, initiator, usageAmount
        );
    }

    /**
     * @dev Wrapper around `LibPolicyRateLimits.computeTimeWindow`.
     */
    function computeTimeWindowViaPolicyLibrary(Policy memory policy) external view returns (uint256) {
        return LibPolicyRateLimits.computeTimeWindow(policy);
    }

    /**
     * @dev Wrapper around `LibPolicyRateLimits.getCurrentUsage`.
     */
    function getCurrentUsageViaPolicyLibrary(
        uint256 policyId,
        Policy memory policy,
        address account,
        address destination,
        address initiator
    ) external view returns (uint256) {
        return LibPolicyRateLimits.getCurrentUsage(policyId, policy, account, destination, initiator);
    }

    /**
     * @dev Wrapper around `LibPolicyRateLimits.computeUsageKey`.
     */
    function computeUsageKeyViaPolicyLibrary(
        uint256 policyId,
        Policy memory policy,
        address account,
        address destination,
        address initiator
    ) external pure returns (bytes32) {
        return LibPolicyRateLimits.computeUsageKey(policyId, policy, account, destination, initiator);
    }
}
