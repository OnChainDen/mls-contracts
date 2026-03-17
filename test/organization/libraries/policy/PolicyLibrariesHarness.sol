// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {LibPolicyApproval} from "organization/libraries/policy/LibPolicyApproval.sol";
import {LibPolicyInitiator} from "organization/libraries/policy/LibPolicyInitiator.sol";
import {LibPolicyRateLimits} from "organization/libraries/policy/LibPolicyRateLimits.sol";
import {
    LibOrganizationPolicyHarness
} from "test/organization/libraries/LibOrganizationPolicy/LibOrganizationPolicyHarness.sol";
import {Policy} from "types/PolicyTypes.sol";

/**
 * @dev Local policy-library harness for tests in `test/organization/libraries/policy`.
 *      Adds raw-enum wrappers used to test malformed enum calldata behavior.
 */
contract PolicyLibrariesHarness is LibOrganizationPolicyHarness {
    uint256 private constant _SLOT_APPROVER_TYPE = 5;
    uint256 private constant _SLOT_INITIATOR_TYPE = 10;
    uint256 private constant _SLOT_RATE_LIMIT_TYPE = 17;
    uint256 private constant _SLOT_RATE_INITIATOR_SCOPE = 20;
    uint256 private constant _SLOT_RATE_SOURCE_SCOPE = 21;
    uint256 private constant _SLOT_RATE_DESTINATION_SCOPE = 22;

    /**
     * @dev Raw-enum wrapper for `LibPolicyInitiator.isInitiatorAuthorized`.
     */
    function isInitiatorAuthorizedViaPolicyLibraryRawInitiatorType(
        Policy memory policy,
        uint256 rawInitiatorType,
        address initiatorAddress
    ) external view returns (bool) {
        _unsafeSetPolicySlot(policy, _SLOT_INITIATOR_TYPE, rawInitiatorType);
        return LibPolicyInitiator.isInitiatorAuthorized(policy, initiatorAddress);
    }

    /**
     * @dev Raw-enum wrapper for `LibPolicyApproval.areApprovalsValid`.
     */
    function areApprovalsValidViaPolicyLibraryRawApproverType(
        Policy memory policy,
        uint256 rawApproverType,
        bytes memory signatures,
        bytes32 messageHash
    ) external view returns (bool) {
        _unsafeSetPolicySlot(policy, _SLOT_APPROVER_TYPE, rawApproverType);
        return LibPolicyApproval.areApprovalsValid(policy, signatures, messageHash);
    }

    /**
     * @dev Raw-enum wrapper for `LibPolicyApproval.getRequiredApprovals`.
     */
    function getRequiredApprovalsViaPolicyLibraryRawApproverType(Policy memory policy, uint256 rawApproverType)
        external
        pure
        returns (uint256)
    {
        _unsafeSetPolicySlot(policy, _SLOT_APPROVER_TYPE, rawApproverType);
        return LibPolicyApproval.getRequiredApprovals(policy);
    }

    /**
     * @dev Raw-enum wrapper for `LibPolicyApproval._isSignerAuthorizedForPolicy`.
     */
    function isSignerAuthorizedForPolicyViaPolicyLibraryRawApproverType(
        Policy memory policy,
        uint256 rawApproverType,
        address signerAddress
    ) external view returns (bool) {
        _unsafeSetPolicySlot(policy, _SLOT_APPROVER_TYPE, rawApproverType);
        return LibPolicyApproval._isSignerAuthorizedForPolicy(policy, signerAddress);
    }

    /**
     * @dev Raw-enum wrapper for `LibPolicyRateLimits.checkAndUpdateRateLimit`.
     */
    function checkAndUpdateRateLimitViaPolicyLibraryRawLimitType(
        uint256 policyId,
        Policy memory policy,
        uint256 rawLimitType,
        address account,
        address destination,
        address initiator,
        uint256 usageAmount
    ) external returns (bool) {
        _unsafeSetPolicySlot(policy, _SLOT_RATE_LIMIT_TYPE, rawLimitType);
        return
            LibPolicyRateLimits.checkAndUpdateRateLimit(policyId, policy, account, destination, initiator, usageAmount);
    }

    /**
     * @dev Raw-enum wrapper for `LibPolicyRateLimits.computeUsageKey`.
     */
    function computeUsageKeyViaPolicyLibraryRawScopes(
        uint256 policyId,
        Policy memory policy,
        uint256 rawInitiatorScope,
        uint256 rawSourceScope,
        uint256 rawDestinationScope,
        address account,
        address destination,
        address initiator
    ) external pure returns (bytes32) {
        _unsafeSetPolicySlot(policy, _SLOT_RATE_INITIATOR_SCOPE, rawInitiatorScope);
        _unsafeSetPolicySlot(policy, _SLOT_RATE_SOURCE_SCOPE, rawSourceScope);
        _unsafeSetPolicySlot(policy, _SLOT_RATE_DESTINATION_SCOPE, rawDestinationScope);
        return LibPolicyRateLimits.computeUsageKey(policyId, policy, account, destination, initiator);
    }

    /**
     * @dev Mutates a memory-slot in `Policy` for malformed-enum testing.
     */
    function _unsafeSetPolicySlot(Policy memory policy, uint256 slotIndex, uint256 rawValue) private pure {
        assembly {
            mstore(add(policy, mul(slotIndex, 0x20)), rawValue)
        }
    }
}
