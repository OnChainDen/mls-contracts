// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {OrganizationPolicyTestBase} from "test/organization/shared/OrganizationPolicyTestBase.sol";
import {
    ApproverType,
    Policy,
    PolicyType,
    RateLimitScope,
    TransactionType,
    ValidationProofs
} from "types/PolicyTypes.sol";

/**
 * @dev Hash helper surface shared by account-transaction harness contracts.
 */
interface AccountTransactionHashHarness {
    function computeInitiatorHashFromParamsViaLibrary(
        address account,
        address to,
        uint256 value,
        uint256 salt,
        uint256 expirationTimestamp,
        uint256 policyId,
        bytes calldata data,
        bool isApproval
    ) external view returns (bytes32);

    function computeReviewHashFromParamsViaLibrary(
        address account,
        address to,
        uint256 value,
        uint256 salt,
        uint256 expirationTimestamp,
        uint256 policyId,
        bytes calldata data,
        bool isApproval,
        bytes calldata initiatorSignature
    ) external view returns (bytes32);
}

/**
 * @dev Shared setup/helpers for account-transaction library/base/integration suites.
 */
abstract contract OrganizationAccountTransactionTestBase is OrganizationPolicyTestBase {
    /// @dev Default deterministic fixtures reused across account-transaction tests.
    uint256 internal constant DEFAULT_POLICY_ID = 77;
    address internal constant ACCOUNT = address(0xA1101);
    address internal constant DESTINATION = address(0xB2202);
    address internal constant TOKEN = address(0xC3303);
    address internal constant RECIPIENT = address(0xD4404);

    /**
     * @dev Seeds shared member fixture state used by initiator/reviewer policy paths.
     */
    function setUp() public virtual override {
        super.setUp();
        policyStateHarness.setMemberStatus(initiator1, true);
        policyStateHarness.setMemberStatus(initiator2, true);
        policyStateHarness.setMemberStatus(reviewer1, true);
        policyStateHarness.setMemberStatus(reviewer2, true);
        policyStateHarness.setMemberStatus(reviewer3, true);
    }

    /**
     * @dev Builds a policy configured for account-transaction approval/rejection tests.
     */
    function _buildApprovalPolicy(TransactionType txType, PolicyType approvalType)
        internal
        view
        returns (Policy memory policy)
    {
        policy = _buildBasePolicy();
        policy.config.transactionType = txType;
        policy.config.approval.policyType = approvalType;

        policy.config.initiator.anyInitiator = false;
        policy.config.initiator.initiatorType = ApproverType.Member;
        policy.config.initiator.initiatorMember = initiator1;

        policy.config.approval.approverType = ApproverType.Member;
        policy.config.approval.approverMember = reviewer1;
        policy.config.approval.approvalThreshold = 1;
    }

    /**
     * @dev Builds empty proofs payload for a policy.
     */
    function _emptyProofsForPolicy(Policy memory policy) internal pure returns (ValidationProofs memory proofs) {
        bytes32[] memory empty = new bytes32[](0);
        proofs = ValidationProofs({
            policy: policy,
            policyProof: empty,
            sourceAccountProof: empty,
            destinationProof: empty,
            functionProof: empty,
            constraints: bytes(""),
            constraintOneOfProofs: bytes("")
        });
    }

    /**
     * @dev Sets single-policy root and returns matching proofs payload.
     */
    function _setSinglePolicyRootAndBuildProofs(uint256 policyId, Policy memory policy)
        internal
        returns (ValidationProofs memory proofs)
    {
        policyStateHarness.setPoliciesRoot(_computePolicyLeaf(policyId, policy));
        proofs = _emptyProofsForPolicy(policy);
    }

    /**
     * @dev Signs an initiator hash for account-transaction approval/rejection paths.
     */
    function _signInitiatorTx(
        address txHarness,
        uint256 privateKey,
        address account,
        address to,
        uint256 value,
        bytes memory data,
        uint256 salt,
        uint256 expirationTimestamp,
        uint256 policyId,
        bool isApproval
    ) internal view returns (bytes memory) {
        bytes32 hash = AccountTransactionHashHarness(txHarness)
            .computeInitiatorHashFromParamsViaLibrary({
                account: account,
                to: to,
                value: value,
                salt: salt,
                expirationTimestamp: expirationTimestamp,
                policyId: policyId,
                data: data,
                isApproval: isApproval
            });
        return _signHash(privateKey, hash);
    }

    /**
     * @dev Signs a review hash for account-transaction approval/rejection paths.
     */
    function _signReviewTx(
        address txHarness,
        uint256 privateKey,
        address account,
        address to,
        uint256 value,
        bytes memory data,
        uint256 salt,
        uint256 expirationTimestamp,
        uint256 policyId,
        bool isApproval,
        bytes memory initiatorSignature
    ) internal view returns (bytes memory) {
        bytes32 hash = AccountTransactionHashHarness(txHarness)
            .computeReviewHashFromParamsViaLibrary({
                account: account,
                to: to,
                value: value,
                salt: salt,
                expirationTimestamp: expirationTimestamp,
                policyId: policyId,
                data: data,
                isApproval: isApproval,
                initiatorSignature: initiatorSignature
            });
        return _signHash(privateKey, hash);
    }

    /**
     * @dev Computes policy usage window for time-interval rate-limit assertions.
     */
    function _computeTimeWindow(Policy memory policy) internal view returns (uint256) {
        if (policy.config.rateLimit.timeIntervalHours == 0) return 0;
        uint256 anchor = policy.config.rateLimit.anchorTimestamp;
        if (block.timestamp < anchor) return 0;
        return (block.timestamp - anchor) / (uint256(policy.config.rateLimit.timeIntervalHours) * 3600);
    }

    /**
     * @dev Computes usage key using policy scope rules.
     */
    function _computeUsageKey(
        uint256 policyId,
        Policy memory policy,
        address account,
        address destination,
        address initiator
    ) internal pure returns (bytes32) {
        address scopedAccount = policy.config.rateLimit.sourceScope == RateLimitScope.PerEntity ? account : address(0);
        address scopedDestination =
            policy.config.rateLimit.destinationScope == RateLimitScope.PerEntity ? destination : address(0);
        address scopedInitiator =
            policy.config.rateLimit.initiatorScope == RateLimitScope.PerEntity ? initiator : address(0);

        return keccak256(
            abi.encode(
                policyId,
                policy.config.rateLimit.anchorTimestamp,
                policy.config.rateLimit.timeIntervalHours,
                policy.config.rateLimit.sourceScope,
                scopedAccount,
                policy.config.rateLimit.destinationScope,
                scopedDestination,
                policy.config.rateLimit.initiatorScope,
                scopedInitiator
            )
        );
    }
}
