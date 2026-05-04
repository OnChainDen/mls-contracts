// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {PolicyLibrariesSuiteBase} from "test/organization/libraries/policy/PolicyLibrariesSuiteBase.sol";
import {
    ApproverType,
    ConstraintType,
    DestinationType,
    ParamType,
    ParameterConstraint,
    Policy,
    RateLimitScope,
    RateLimitType
} from "types/PolicyTypes.sol";

/**
 * @dev Shared helper builders for policy-library fuzz suites.
 */
abstract contract PolicyLibrariesFuzzTestBase is PolicyLibrariesSuiteBase {
    /**
     * @dev Builds a policy that restricts destinations to `customDestinationsRoot`.
     * @param customDestinationsRoot The merkle root of allowed destinations.
     * @return policy The configured policy fixture.
     */
    function _customDestinationPolicy(bytes32 customDestinationsRoot) internal view returns (Policy memory policy) {
        policy = _buildBasePolicy();
        policy.config.destinationType = DestinationType.CustomList;
        policy.roots.customDestinationsRoot = customDestinationsRoot;
    }

    /**
     * @dev Builds a single-leaf destination root and proof.
     * @param destination The only allowed destination in the tree.
     * @return root The resulting merkle root.
     * @return proof The proof for `destination`.
     */
    function _buildSingleDestinationRootAndProof(address destination)
        internal
        returns (bytes32 root, bytes32[] memory proof)
    {
        address[] memory values = buildArray(destination);
        return _buildAddressRootAndProof(values, 0);
    }

    /**
     * @dev Builds a policy with one allowed function leaf and one allowed destination leaf.
     * @param destination The allowed destination address.
     * @param selector The allowed function selector.
     * @param constraints The ABI-encoded parameter constraints used in the function leaf.
     * @return policy The configured policy fixture.
     * @return functionProof The proof for `(selector, constraints)`.
     * @return destinationProof The proof for `destination`.
     */
    function _buildPolicyWithSingleAllowedFunctionAndDestination(
        address destination,
        bytes4 selector,
        bytes memory constraints
    ) internal returns (Policy memory policy, bytes32[] memory functionProof, bytes32[] memory destinationProof) {
        policy = _buildBasePolicy();
        policy.config.destinationType = DestinationType.CustomList;
        policy.config.anyFunction = false;

        address[] memory destinations = buildArray(destination);
        (policy.roots.customDestinationsRoot, destinationProof) = _buildAddressRootAndProof(destinations, 0);

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = selector;
        bytes[] memory constraintsList = new bytes[](1);
        constraintsList[0] = constraints;
        (policy.roots.allowedFunctionsRoot, functionProof) = _buildFunctionRootAndProof(selectors, constraintsList, 0);
    }

    /**
     * @dev Encodes a single exact-uint constraint array for contract-interaction fixtures.
     * @param expectedValue The expected uint256 argument value.
     * @return constraints The ABI-encoded one-element constraints array.
     */
    function _encodeUintExactConstraint(uint256 expectedValue) internal pure returns (bytes memory constraints) {
        ParameterConstraint memory constraint = ParameterConstraint({
            paramType: ParamType.Uint,
            constraintType: ConstraintType.Exact,
            paramCalldataHeadSlotCount: 1,
            comparisonData: abi.encode(expectedValue)
        });

        ParameterConstraint[] memory array = new ParameterConstraint[](1);
        array[0] = constraint;
        constraints = abi.encode(array);
    }

    /**
     * @dev Builds a member-approver policy fixture.
     * @param approverMember The only member authorized to approve.
     * @return policy The configured policy fixture.
     */
    function _memberApproverPolicy(address approverMember) internal view returns (Policy memory policy) {
        policy = _buildBasePolicy();
        policy.config.approval.approverType = ApproverType.Member;
        policy.config.approval.approverMember = approverMember;
        policy.config.approval.approvalThreshold = 1;
    }

    /**
     * @dev Builds a group-approver policy fixture.
     * @param approverGroupId The group whose members may approve.
     * @param threshold The approval threshold for the group.
     * @return policy The configured policy fixture.
     */
    function _groupApproverPolicy(uint256 approverGroupId, uint8 threshold)
        internal
        view
        returns (Policy memory policy)
    {
        policy = _buildBasePolicy();
        policy.config.approval.approverType = ApproverType.Group;
        policy.config.approval.approverGroupId = approverGroupId;
        policy.config.approval.approvalThreshold = threshold;
    }

    /**
     * @dev Builds a time-interval rate-limit policy fixture.
     * @param intervalHours The size of each time window in hours.
     * @param intervalLimit The maximum usage allowed per window.
     * @return policy The configured policy fixture.
     */
    function _timeIntervalPolicy(uint16 intervalHours, uint256 intervalLimit)
        internal
        view
        returns (Policy memory policy)
    {
        policy = _buildBasePolicy();
        policy.config.rateLimit.limitType = RateLimitType.TimeInterval;
        policy.config.rateLimit.timeIntervalHours = intervalHours;
        policy.config.rateLimit.timeIntervalLimit = intervalLimit;
        policy.config.rateLimit.initiatorScope = RateLimitScope.AcrossAll;
        policy.config.rateLimit.sourceScope = RateLimitScope.AcrossAll;
        policy.config.rateLimit.destinationScope = RateLimitScope.AcrossAll;
    }
}
