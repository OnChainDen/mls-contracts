// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {
    OrganizationPolicyInvariantHandler
} from "test/organization/integration/policy/OrganizationPolicyInvariantHandler.sol";
import {
    LibOrganizationAccountSignatureHarness
} from "test/organization/libraries/LibOrganizationAccountSignature/LibOrganizationAccountSignatureHarness.sol";
import {
    LibOrganizationAccountTransactionHarness
} from "test/organization/libraries/LibOrganizationAccountTransaction/LibOrganizationAccountTransactionHarness.sol";
import {
    LibOrganizationPolicyHarness
} from "test/organization/libraries/LibOrganizationPolicy/LibOrganizationPolicyHarness.sol";
import {
    LibOrganizationPolicySuiteBase
} from "test/organization/libraries/LibOrganizationPolicy/LibOrganizationPolicySuiteBase.sol";
import {
    ApproverType,
    ConstraintType,
    DestinationType,
    ParamType,
    ParameterConstraint,
    Policy,
    PolicyType,
    RateLimitType,
    TransactionType,
    ValidationProofs
} from "types/PolicyTypes.sol";

/**
 * @dev Cross-file invariant tests for organization policy behavior.
 */
contract OrganizationPolicyCrossFileInvariants is LibOrganizationPolicySuiteBase {
    uint256 internal constant DEFAULT_POLICY_ID = 6101;

    OrganizationPolicyInvariantHandler internal handler;
    LibOrganizationPolicyHarness internal checkHarness;
    LibOrganizationAccountTransactionHarness internal txHarness;
    LibOrganizationAccountSignatureHarness internal signatureHarness;

    function setUp() public override {
        super.setUp();

        // Main handler mutates `harness` only.
        handler = new OrganizationPolicyInvariantHandler(harness);
        targetContract(address(handler));

        // Independent harnesses used by invariant assertions that need custom roots/state.
        checkHarness = new LibOrganizationPolicyHarness();
        txHarness = new LibOrganizationAccountTransactionHarness();
        signatureHarness = new LibOrganizationAccountSignatureHarness();

        _seedMembers(address(harness));
        _seedMembers(address(checkHarness));
        _seedMembers(address(txHarness));
        _seedMembers(address(signatureHarness));

        checkHarness.setGroupStatus(700, true);
        checkHarness.setGroupMemberStatus(700, reviewer1, true);
        checkHarness.setGroupMemberStatus(700, reviewer2, true);
    }

    /// @dev Verifies that policy root changes only through set policies.
    function invariant_POL_INV_1_policyRootChangesOnlyThroughSetPolicies() public view {
        // Setup: configure a valid fixture for policy root changes only through set policies.
        // Call: execute `getPoliciesRoot` with the happy-path payload.
        assertEq(harness.getPoliciesRoot(), handler.modelPoliciesRoot(), "policy root must match handler model");
    }

    /// @dev Verifies that policy and function leaves use double hash construction.
    function invariant_policyAndFunctionLeavesUseDoubleHashConstruction() public view {
        // Setup: configure a valid fixture for policy and function leaves use double hash construction.
        Policy memory policy = _buildBasePolicy();
        uint256 policyId = 6202;

        bytes32 expectedPolicyLeaf = keccak256(bytes.concat(keccak256(abi.encode(policyId, policy))));
        // Call: execute `computePolicyLeafViaLibrary` with the happy-path payload.
        bytes32 actualPolicyLeaf = harness.computePolicyLeafViaLibrary(policyId, policy);
        // Verify: assert the expected success result and state updates.
        assertEq(actualPolicyLeaf, expectedPolicyLeaf, "policy leaf must use double hash");

        bytes4 selector = bytes4(0x12345678);
        bytes32 constraintsHash = keccak256("invariant-constraints");
        bytes32 expectedFunctionLeaf = keccak256(bytes.concat(keccak256(abi.encode(selector, constraintsHash))));
        bytes32 actualFunctionLeaf = harness.computeFunctionLeafViaPolicyLibrary(selector, constraintsHash);
        assertEq(actualFunctionLeaf, expectedFunctionLeaf, "function leaf must use double hash");
    }

    /// @dev Verifies invalid policy proofs never authorize transaction or signature flows. [POL-INV-2]
    function invariant_POL_INV_2_invalidPolicyProofCannotAuthorizeTransactionOrSignature() public {
        // Setup: build fixture inputs where invalid policy proof cannot authorize transaction or signature should be
        // denied.
        Policy memory policy = _buildBasePolicy();
        policy.config.transactionType = TransactionType.Any;
        policy.config.initiator.anyInitiator = false;
        policy.config.initiator.initiatorType = ApproverType.Member;
        policy.config.initiator.initiatorMember = initiator1;

        bytes32 root = _computePolicyLeaf(DEFAULT_POLICY_ID, policy);
        // Call: execute `setPoliciesRoot` and capture the authorization decision.
        checkHarness.setPoliciesRoot(root);
        signatureHarness.setPoliciesRoot(root);

        bytes32[] memory badProof = new bytes32[](1);
        badProof[0] = keccak256("invalid-proof");
        bytes32[] memory empty = new bytes32[](0);

        ValidationProofs memory proofs = ValidationProofs({
            policy: policy,
            policyProof: badProof,
            sourceAccountProof: empty,
            destinationProof: empty,
            functionProof: empty,
            constraints: bytes("")
        });

        bool txAllowed = checkHarness.isTransactionAllowedByPolicyViaLibrary({
            policyId: DEFAULT_POLICY_ID,
            sourceAccount: address(0xA001),
            to: address(0xB001),
            value: 0,
            data: abi.encodeWithSelector(bytes4(0xCAFEBABE), uint256(1)),
            initiator: initiator1,
            proofs: proofs
        });
        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(txAllowed, "invalid policy proof must not authorize transactions");

        bool sigAllowed = signatureHarness.isERC1271SignatureAllowedByPolicyViaLibrary({
            account: address(0xA001), initiator: initiator1, policyId: DEFAULT_POLICY_ID, proofs: proofs
        });
        assertFalse(sigAllowed, "invalid policy proof must not authorize signatures");
    }

    /// @dev Verifies that usage monotonic on successful updates.
    function invariant_TXRL_INV_1_usageMonotonicOnSuccessfulUpdates() public view {
        // Setup: build fixture inputs where usage monotonic on successful updates should be denied.
        assertFalse(handler.usageMonotonicViolation(), "usage should not decrease after successful updates");
    }

    /// @dev Verifies exceeded rate-limit checks leave usage unchanged. [TXRL-INV-7]
    function invariant_TXRL_INV_7_exceededRateLimitNeverMutatesUsage() public view {
        // Setup: build fixture inputs where exceeded rate limit never mutates usage should be denied.
        assertFalse(handler.exceededLimitMutationViolation(), "exceeded-limit updates must not mutate usage");
    }

    /// @dev Verifies manual approvals require the configured threshold and do not pass short. [POL-INV-6]
    function invariant_POL_INV_6_manualPoliciesCannotPassWithFewerApprovalsThanRequired() public view {
        // Setup: build fixture inputs where manual policies cannot pass with fewer approvals than required should be
        // denied.
        Policy memory policy = _buildBasePolicy();
        policy.config.approval.policyType = PolicyType.RequireManualApproval;
        policy.config.approval.approverType = ApproverType.Group;
        policy.config.approval.approverGroupId = 700;
        policy.config.approval.approvalThreshold = 2;

        bytes32 reviewHash = keccak256("manual-review-hash");
        bytes memory oneSignature = _signHash(REVIEWER_PK_1, reviewHash);

        // Call: execute `areApprovalsValidViaPolicyLibrary` and capture the authorization decision.
        bool approvalsValid = checkHarness.areApprovalsValidViaPolicyLibrary(policy, oneSignature, reviewHash);
        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(approvalsValid, "fewer than required manual approvals must never pass");
    }

    /// @dev Verifies that unknown enums revert across validation paths.
    function invariant_unknownEnumsFailClosedAcrossValidationPaths() public {
        // Setup: build fixture inputs and mutate calldata words with unknown enum values.
        // ApproverType
        Policy memory invalidApproverPolicy = _buildBasePolicy();
        bytes memory approverCall = abi.encodeCall(
            checkHarness.isSignerAuthorizedForPolicyViaPolicyLibrary, (invalidApproverPolicy, reviewer1)
        );
        _setWord(approverCall, 4 + 5 * 32, 2);

        // Call: execute low-level call with malformed approver enum calldata.
        (bool approverSuccess,) = address(checkHarness).call(approverCall);
        // Verify: assert malformed enum values fail with a revert/panic.
        assertFalse(approverSuccess, "invalid approver enum should revert");

        // DestinationType
        Policy memory invalidDestinationPolicy = _buildBasePolicy();
        bytes32[] memory emptyProof = new bytes32[](0);
        bytes memory destinationCall = abi.encodeCall(
            checkHarness.isDestinationAllowedByPolicyViaPolicyLibrary,
            (invalidDestinationPolicy, address(0xD001), 1, bytes(""), emptyProof)
        );
        _setWord(destinationCall, 4 + 3 * 32, 2);

        (bool destinationSuccess,) = address(checkHarness).call(destinationCall);
        assertFalse(destinationSuccess, "invalid destination enum should revert");

        // ConstraintType + ParamType
        bytes32[] memory noProof = new bytes32[](0);
        ParameterConstraint memory constraint = ParameterConstraint({
            paramType: ParamType.Bool,
            constraintType: ConstraintType.Exact,
            paramCalldataHeadSlotCount: 1,
            comparisonData: abi.encode(true),
            paramValueInListProof: noProof
        });

        bytes memory invalidConstraintCall = abi.encodeCall(
            checkHarness.isParameterAllowedByConstraintViaPolicyLibrary,
            (constraint, bytes32(uint256(1)), abi.encodeWithSelector(bytes4(0x11111111), uint256(1)))
        );
        uint256 constraintOffset = _readWord(invalidConstraintCall, 4);
        _setWord(invalidConstraintCall, 4 + constraintOffset + 32, 9);

        (bool invalidConstraintSuccess,) = address(checkHarness).call(invalidConstraintCall);
        assertFalse(invalidConstraintSuccess, "invalid constraint enum should revert");

        bytes memory invalidParamCall = abi.encodeCall(
            checkHarness.isParameterAllowedByConstraintViaPolicyLibrary,
            (constraint, bytes32(uint256(1)), abi.encodeWithSelector(bytes4(0x11111111), uint256(1)))
        );
        constraintOffset = _readWord(invalidParamCall, 4);
        _setWord(invalidParamCall, 4 + constraintOffset, 11);

        (bool invalidParamSuccess,) = address(checkHarness).call(invalidParamCall);
        assertFalse(invalidParamSuccess, "invalid param enum should revert");

        // RateLimitType
        Policy memory invalidRateLimitTypePolicy = _buildBasePolicy();
        invalidRateLimitTypePolicy.config.rateLimit.timeIntervalHours = 1;
        invalidRateLimitTypePolicy.config.rateLimit.timeIntervalLimit = 1;
        bytes memory invalidRateTypeCall = abi.encodeCall(
            checkHarness.checkAndUpdateRateLimitViaPolicyLibrary,
            (7001, invalidRateLimitTypePolicy, address(0xA7), address(0xB7), address(0xC7), 1)
        );
        _setWord(invalidRateTypeCall, 4 + 32 + 17 * 32, 2);

        (bool invalidRateTypeSuccess,) = address(checkHarness).call(invalidRateTypeCall);
        assertFalse(invalidRateTypeSuccess, "invalid rate-limit type should revert");

        // RateLimitScope
        Policy memory invalidRateScopePolicy = _buildBasePolicy();
        invalidRateScopePolicy.config.rateLimit.limitType = RateLimitType.TimeInterval;
        invalidRateScopePolicy.config.rateLimit.timeIntervalHours = 1;
        invalidRateScopePolicy.config.rateLimit.timeIntervalLimit = 1;
        bytes memory invalidRateScopesCall = abi.encodeCall(
            checkHarness.checkAndUpdateRateLimitViaPolicyLibrary,
            (7002, invalidRateScopePolicy, address(0xA8), address(0xB8), address(0xC8), 1)
        );
        _setWord(invalidRateScopesCall, 4 + 32 + 20 * 32, 2);
        _setWord(invalidRateScopesCall, 4 + 32 + 21 * 32, 2);
        _setWord(invalidRateScopesCall, 4 + 32 + 22 * 32, 2);

        (bool invalidRateScopesSuccess,) = address(checkHarness).call(invalidRateScopesCall);
        assertFalse(invalidRateScopesSuccess, "invalid rate-limit scopes should revert");
    }

    /// @dev Verifies that desired any initiator must not authorize non members.
    function invariant_POL_INV_7_desiredAnyInitiatorMustNotAuthorizeNonMembers() public view {
        // Setup: build fixture inputs where desired any initiator must not authorize non members should be denied.
        Policy memory policy = _buildBasePolicy();
        policy.config.initiator.anyInitiator = true;

        address nonMember = address(0xF0F0);
        // Call: execute `isInitiatorAuthorizedViaPolicyLibrary` and capture the authorization decision.
        bool authorized = checkHarness.isInitiatorAuthorizedViaPolicyLibrary(policy, nonMember);
        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(authorized, "anyInitiator should still require organization membership");
    }

    /// @dev Verifies that token threshold uses exclusive max semantics.
    function invariant_POL_INV_9_tokenThresholdUsesExclusiveMax() public view {
        // Setup: build fixture inputs where token threshold uses exclusive max semantics should be denied.
        Policy memory policy = _buildBasePolicy();
        policy.config.token.hasAmountThreshold = true;
        policy.config.token.amountThreshold = 100;

        bytes memory data = _encodeERC20Transfer(address(0xF901), 100);
        // Call: execute `isTokenAmountAllowedByPolicyViaPolicyLibrary` and capture the authorization decision.
        bool allowed = checkHarness.isTokenAmountAllowedByPolicyViaPolicyLibrary(policy, data, 0);
        // Verify: assert that the request is denied and state remains unchanged.
        assertFalse(allowed, "token threshold should reject amount == threshold");
    }

    /// @dev Verifies that malformed constraints revert in policy-check paths and never authorize.
    function invariant_POL_INV_8_malformedConstraintsRevertInPolicyCheckPaths() public {
        // Setup: configure a contract-interaction policy and inject malformed constraints that trigger decode failure.
        Policy memory policy = _buildBasePolicy();
        policy.config.transactionType = TransactionType.ContractInteractions;
        policy.config.anyFunction = false;
        policy.config.initiator.anyInitiator = false;
        policy.config.initiator.initiatorType = ApproverType.Member;
        policy.config.initiator.initiatorMember = initiator1;

        bytes memory malformedConstraints = abi.encode(uint256(32), uint256(2));
        bytes4 selector = bytes4(0xF00DBAAD);
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = selector;

        bytes[] memory constraintsList = new bytes[](1);
        constraintsList[0] = malformedConstraints;

        (bytes32 functionsRoot, bytes32[] memory functionProof) =
            _buildFunctionRootAndProof(selectors, constraintsList, 0);
        policy.roots.allowedFunctionsRoot = functionsRoot;

        bytes32 policyRoot = _computePolicyLeaf(DEFAULT_POLICY_ID, policy);
        // Call: run `setPoliciesRoot` across the prepared variants.
        checkHarness.setPoliciesRoot(policyRoot);

        bytes32[] memory empty = new bytes32[](0);
        ValidationProofs memory proofs = ValidationProofs({
            policy: policy,
            policyProof: empty,
            sourceAccountProof: empty,
            destinationProof: empty,
            functionProof: functionProof,
            constraints: malformedConstraints
        });

        // Verify: malformed constraints should revert and must not authorize.
        vm.expectRevert();
        // Call: execute `isTransactionAllowedByPolicyViaLibrary` with malformed constraints.
        checkHarness.isTransactionAllowedByPolicyViaLibrary(
            DEFAULT_POLICY_ID,
            address(0xA010),
            address(0xB010),
            0,
            abi.encodeWithSelector(selector, uint256(1)),
            initiator1,
            proofs
        );
    }

    // Helpers

    function _unsafeSetApproverTypeRaw(Policy memory policy, uint256 rawValue) internal pure {
        // `Policy.config.approval.approverType` offset: 0xA0.
        assembly {
            mstore(add(policy, 0xA0), rawValue)
        }
    }

    function _unsafeSetDestinationTypeRaw(Policy memory policy, uint256 rawValue) internal pure {
        // `Policy.config.destinationType` offset: 0x60.
        assembly {
            mstore(add(policy, 0x60), rawValue)
        }
    }

    function _unsafeSetRateLimitTypeRaw(Policy memory policy, uint256 rawValue) internal pure {
        // `Policy.config.rateLimit.limitType` offset: 0x220.
        assembly {
            mstore(add(policy, 0x220), rawValue)
        }
    }

    function _unsafeSetRateLimitScopesRaw(
        Policy memory policy,
        uint256 initiatorScopeRaw,
        uint256 sourceScopeRaw,
        uint256 destinationScopeRaw
    ) internal pure {
        // `Policy.config.rateLimit.{initiatorScope,sourceScope,destinationScope}` offsets: 0x280/0x2A0/0x2C0.
        assembly {
            mstore(add(policy, 0x280), initiatorScopeRaw)
            mstore(add(policy, 0x2A0), sourceScopeRaw)
            mstore(add(policy, 0x2C0), destinationScopeRaw)
        }
    }

    function _unsafeSetConstraintTypeRaw(ParameterConstraint memory constraint, uint256 rawValue) internal pure {
        assembly {
            mstore(add(constraint, 0x20), rawValue)
        }
    }

    function _unsafeSetParamTypeRaw(ParameterConstraint memory constraint, uint256 rawValue) internal pure {
        assembly {
            mstore(constraint, rawValue)
        }
    }

    function _seedMembers(address target) internal {
        LibOrganizationPolicyHarness targetHarness = LibOrganizationPolicyHarness(target);
        targetHarness.setMemberStatus(initiator1, true);
        targetHarness.setMemberStatus(initiator2, true);
        targetHarness.setMemberStatus(reviewer1, true);
        targetHarness.setMemberStatus(reviewer2, true);
    }
}
