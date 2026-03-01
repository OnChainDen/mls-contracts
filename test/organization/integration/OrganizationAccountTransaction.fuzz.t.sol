// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationAccountFactory} from "interfaces/organization/IOrganizationAccountFactory.sol";
import {IOrganizationAccountTransaction} from "interfaces/organization/IOrganizationAccountTransaction.sol";
import {IOrganizationSignatures} from "interfaces/organization/IOrganizationSignatures.sol";
import {
    OrganizationAccountTransactionBaseHarness
} from "test/organization/base/OrganizationAccountTransactionBase/OrganizationAccountTransactionBaseHarness.sol";
import {
    MockAccountForOrganizationTransaction
} from "test/organization/base/OrganizationAccountTransactionBase/OrganizationAccountTransactionBaseMocks.sol";
import {
    LibOrganizationAccountTransactionTestBase
} from "test/organization/libraries/LibOrganizationAccountTransaction/LibOrganizationAccountTransactionTestBase.sol";
import {OperationType} from "types/CommonTypes.sol";
import {
    ApproverType,
    Policy,
    PolicyType,
    RateLimitScope,
    RateLimitType,
    TransactionType,
    ValidationProofs
} from "types/PolicyTypes.sol";

/**
 * @dev Fuzz tests for account-transaction approval/rejection behavior and hashing invariants.
 */
contract OrganizationAccountTransactionFuzzTest is LibOrganizationAccountTransactionTestBase {
    /// @dev Separate base harness used for undeployed-account fuzz checks.
    OrganizationAccountTransactionBaseHarness internal baseHarness;

    function setUp() public override {
        super.setUp();
        baseHarness = new OrganizationAccountTransactionBaseHarness();
        baseHarness.setGuardian(GUARDIAN);
        baseHarness.setMemberStatus(initiator1, true);
        baseHarness.setMemberStatus(reviewer1, true);
    }

    /// @dev Verifies random valid auto-approve transactions execute validation successfully.
    function testFuzz_AT_FZ_1_validateApproval_autoApproveRandomValidPayload_succeeds(
        address account,
        address to,
        uint128 value,
        bytes calldata data,
        uint256 salt
    ) public {
        // Setup: constrain fuzz inputs and build auto-approve proofs/signature.
        vm.assume(account != address(0));
        vm.assume(to != address(0));
        Policy memory policy = _buildApprovalPolicy(TransactionType.Any, PolicyType.AutoApprove);
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);
        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSig = _signInitiatorTx(
            address(harness), INITIATOR_PK_1, account, to, value, data, salt, expiration, DEFAULT_POLICY_ID, true
        );

        // Call: validate approval for fuzzed payload.
        harness.validateTransactionApprovalOrRevertViaLibrary(
            account, to, value, data, salt, expiration, DEFAULT_POLICY_ID, initiatorSig, bytes(""), proofs
        );
    }

    /// @dev Verifies random expiration timestamps: future passes, past fails.
    function testFuzz_AT_FZ_2_validateApproval_expirationFuturePassPastFail(uint64 offsetSeconds, bool shouldBeFuture)
        public
    {
        // Setup: build payload with fuzzed relative expiration.
        bytes memory data = abi.encodeWithSelector(bytes4(0x71717171), uint256(1));
        Policy memory policy = _buildApprovalPolicy(TransactionType.Any, PolicyType.AutoApprove);
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);
        uint256 offset = bound(uint256(offsetSeconds), 1, 10 days);
        uint256 expiration = shouldBeFuture
            ? block.timestamp + offset
            : (block.timestamp > offset ? block.timestamp - offset : uint256(0));
        bytes memory initiatorSig = _signInitiatorTx(
            address(harness), INITIATOR_PK_1, ACCOUNT, DESTINATION, 0, data, 1, expiration, DEFAULT_POLICY_ID, true
        );

        if (shouldBeFuture) {
            // Call: validate approval with future expiration.
            harness.validateTransactionApprovalOrRevertViaLibrary(
                ACCOUNT, DESTINATION, 0, data, 1, expiration, DEFAULT_POLICY_ID, initiatorSig, bytes(""), proofs
            );
        } else {
            // Verify: past expiration reverts.
            vm.expectRevert();
            // Call: validate approval with past expiration.
            harness.validateTransactionApprovalOrRevertViaLibrary(
                ACCOUNT, DESTINATION, 0, data, 1, expiration, DEFAULT_POLICY_ID, initiatorSig, bytes(""), proofs
            );
        }
    }

    /// @dev Verifies random salt values produce unique account-transaction nonces.
    function testFuzz_AT_FZ_3_nonce_randomSaltsProduceUniqueNonces(uint256 saltA, uint256 saltB) public view {
        // Setup: constrain salts to distinct values.
        vm.assume(saltA != saltB);
        bytes memory operationData = abi.encode(ACCOUNT, DESTINATION, 0, keccak256(bytes("nonce")), DEFAULT_POLICY_ID);

        // Call: compute nonce for both salts.
        uint256 nonceA = harness.computeNonce(OperationType.AccountTransaction, operationData, saltA);
        uint256 nonceB = harness.computeNonce(OperationType.AccountTransaction, operationData, saltB);

        // Verify: nonce space is salt-sensitive.
        assertTrue(nonceA != nonceB, "distinct salts should produce distinct nonces");
    }

    /// @dev Verifies random calldata produces deterministic initiator hash values.
    function testFuzz_AT_FZ_4__LOAT_CIHFP_12_computeInitiatorHash_randomDataDeterministic(
        bytes calldata data,
        uint256 salt
    ) public view {
        // Call: compute initiator hash twice with identical inputs.
        bytes32 hashA = harness.computeInitiatorHashFromParamsViaLibrary(
            ACCOUNT, DESTINATION, 0, salt, block.timestamp + 1 days, DEFAULT_POLICY_ID, data, true
        );
        bytes32 hashB = harness.computeInitiatorHashFromParamsViaLibrary(
            ACCOUNT, DESTINATION, 0, salt, block.timestamp + 1 days, DEFAULT_POLICY_ID, data, true
        );

        // Verify: identical inputs always produce identical hashes.
        assertEq(hashA, hashB, "initiator hash must be deterministic");
    }

    /// @dev Verifies review hash changes when initiator signature bytes change.
    function testFuzz_AT_FZ_5_computeReviewHash_differentInitiatorSignaturesProduceDifferentHashes(
        bytes calldata data,
        uint256 salt
    ) public view {
        // Setup: derive two distinct initiator signatures for the same payload.
        uint256 expiration = block.timestamp + 1 days;
        bytes memory sigA = _signInitiatorTx(
            address(harness), INITIATOR_PK_1, ACCOUNT, DESTINATION, 0, data, salt, expiration, DEFAULT_POLICY_ID, true
        );
        bytes memory sigB = _signInitiatorTx(
            address(harness), INITIATOR_PK_2, ACCOUNT, DESTINATION, 0, data, salt, expiration, DEFAULT_POLICY_ID, true
        );

        // Call: compute review hashes bound to each initiator signature.
        bytes32 hashA = harness.computeReviewHashFromParamsViaLibrary(
            ACCOUNT, DESTINATION, 0, salt, expiration, DEFAULT_POLICY_ID, data, true, sigA
        );
        bytes32 hashB = harness.computeReviewHashFromParamsViaLibrary(
            ACCOUNT, DESTINATION, 0, salt, expiration, DEFAULT_POLICY_ID, data, true, sigB
        );

        // Verify: initiator-signature binding changes review hash.
        assertTrue(hashA != hashB, "review hash should bind initiator signature");
    }

    /// @dev Verifies fuzzed transaction shapes compute destination/usage per policy rules.
    function testFuzz_AT_FZ_6_validateAndUpdateRateLimit_randomShapes_computeExpectedDestinationAndUsage(
        uint8 shape,
        uint96 amount
    ) public {
        // Setup: configure rate-limited policy with per-entity scopes.
        Policy memory policy;
        bytes memory data;
        address to;
        uint256 value;
        uint256 expectedUsage;
        address expectedDestination;

        uint256 boundedAmount = bound(uint256(amount), 1, 1000);
        uint8 mode = uint8(shape % 3);
        if (mode == 0) {
            policy = _buildApprovalPolicy(TransactionType.TokenTransfers, PolicyType.AutoApprove);
            to = DESTINATION;
            value = boundedAmount;
            data = bytes("");
            expectedUsage = boundedAmount;
            expectedDestination = DESTINATION;
        } else if (mode == 1) {
            policy = _buildApprovalPolicy(TransactionType.TokenTransfers, PolicyType.AutoApprove);
            to = TOKEN;
            value = 0;
            data = _encodeERC20Transfer(RECIPIENT, boundedAmount);
            expectedUsage = boundedAmount;
            expectedDestination = RECIPIENT;
        } else {
            policy = _buildApprovalPolicy(TransactionType.ContractInteractions, PolicyType.AutoApprove);
            to = DESTINATION;
            value = 0;
            data = abi.encodeWithSelector(bytes4(0x72727272), uint256(1));
            expectedUsage = 1;
            expectedDestination = DESTINATION;
        }
        policy.config.rateLimit.limitType = RateLimitType.TimeInterval;
        policy.config.rateLimit.timeIntervalHours = 1;
        policy.config.rateLimit.timeIntervalLimit = 5000;
        policy.config.rateLimit.destinationScope = RateLimitScope.PerEntity;
        policy.config.rateLimit.sourceScope = RateLimitScope.PerEntity;
        policy.config.rateLimit.initiatorScope = RateLimitScope.PerEntity;

        // Call: run direct rate-limit helper.
        harness.validateAndUpdateRateLimitOrRevertViaLibrary(
            ACCOUNT, to, value, 1, block.timestamp + 1 days, DEFAULT_POLICY_ID, data, initiator1, policy
        );

        bytes32 usageKey = _computeUsageKey(DEFAULT_POLICY_ID, policy, ACCOUNT, expectedDestination, initiator1);
        uint256 window = _computeTimeWindow(policy);
        // Verify: usage matches expected amount/count for fuzzed transaction shape.
        assertEq(policyStateHarness.getPolicyUsage(usageKey, window), expectedUsage, "usage should match shape model");
    }

    /// @dev Verifies random manual thresholds reject below-threshold valid signatures.
    function testFuzz_AT_FZ_7_validateManual_thresholdInsufficientAlwaysRejected(uint8 rawThreshold) public {
        // Setup: bound threshold to available reviewer universe [2..3].
        uint8 threshold = uint8(bound(uint256(rawThreshold), 2, 3));
        Policy memory policy = _buildApprovalPolicy(TransactionType.Any, PolicyType.RequireManualApproval);
        policy.config.approval.approverType = ApproverType.Group;
        policy.config.approval.approverGroupId = 910;
        policy.config.approval.approvalThreshold = threshold;
        policyStateHarness.setGroupStatus(910, true);
        policyStateHarness.setGroupMemberStatus(910, reviewer1, true);
        policyStateHarness.setGroupMemberStatus(910, reviewer2, true);
        policyStateHarness.setGroupMemberStatus(910, reviewer3, true);
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);

        bytes memory data = abi.encodeWithSelector(bytes4(0x73737373), uint256(3));
        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSig = _signInitiatorTx(
            address(harness), INITIATOR_PK_1, ACCOUNT, DESTINATION, 0, data, 2, expiration, DEFAULT_POLICY_ID, true
        );
        bytes memory oneReviewSig = _signReviewTx(
            address(harness),
            REVIEWER_PK_1,
            ACCOUNT,
            DESTINATION,
            0,
            data,
            2,
            expiration,
            DEFAULT_POLICY_ID,
            true,
            initiatorSig
        );

        // Verify: below-threshold signatures always revert.
        vm.expectRevert();
        // Call: validate approval with insufficient manual signatures.
        harness.validateTransactionApprovalOrRevertViaLibrary(
            ACCOUNT, DESTINATION, 0, data, 2, expiration, DEFAULT_POLICY_ID, initiatorSig, oneReviewSig, proofs
        );
    }

    /// @dev Verifies changing any single core field changes initiator hash.
    function testFuzz_AT_FZ_8__LOAT_CIHFP_2__LOAT_CIHFP_3__LOAT_CIHFP_4_computeInitiatorHash_singleFieldMutationsChangeHash(
        address account,
        address to,
        uint96 value,
        bytes calldata data,
        uint256 salt
    ) public view {
        // Setup: constrain addresses and compute baseline hash.
        vm.assume(account != address(0));
        vm.assume(to != address(0));
        uint256 expiration = block.timestamp + 1 days;
        bytes32 base = harness.computeInitiatorHashFromParamsViaLibrary(
            account, to, value, salt, expiration, DEFAULT_POLICY_ID, data, true
        );

        // Verify: mutate each field and assert hash changes.
        assertTrue(
            base
                != harness.computeInitiatorHashFromParamsViaLibrary(
                    _mutateAddress(account), to, value, salt, expiration, DEFAULT_POLICY_ID, data, true
                ),
            "account mutation should change hash"
        );
        assertTrue(
            base
                != harness.computeInitiatorHashFromParamsViaLibrary(
                    account, _mutateAddress(to), value, salt, expiration, DEFAULT_POLICY_ID, data, true
                ),
            "destination mutation should change hash"
        );
        assertTrue(
            base
                != harness.computeInitiatorHashFromParamsViaLibrary(
                    account, to, uint256(value) + 1, salt, expiration, DEFAULT_POLICY_ID, data, true
                ),
            "value mutation should change hash"
        );
    }

    /// @dev Verifies changing transaction fields changes review hash for fixed initiator signature.
    function testFuzz_AT_FZ_9_computeReviewHash_fieldMutationsChangeHash(
        address account,
        address to,
        bytes calldata data,
        uint256 salt
    ) public view {
        // Setup: constrain addresses and derive fixed initiator signature.
        vm.assume(account != address(0));
        vm.assume(to != address(0));
        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSig = _signInitiatorTx(
            address(harness), INITIATOR_PK_1, account, to, 0, data, salt, expiration, DEFAULT_POLICY_ID, true
        );
        bytes32 base = harness.computeReviewHashFromParamsViaLibrary(
            account, to, 0, salt, expiration, DEFAULT_POLICY_ID, data, true, initiatorSig
        );

        // Verify: mutating any core field changes review hash.
        assertTrue(
            base
                != harness.computeReviewHashFromParamsViaLibrary(
                    _mutateAddress(account), to, 0, salt, expiration, DEFAULT_POLICY_ID, data, true, initiatorSig
                ),
            "account mutation should change review hash"
        );
        assertTrue(
            base
                != harness.computeReviewHashFromParamsViaLibrary(
                    account, _mutateAddress(to), 0, salt, expiration, DEFAULT_POLICY_ID, data, true, initiatorSig
                ),
            "destination mutation should change review hash"
        );
        assertTrue(
            base
                != harness.computeReviewHashFromParamsViaLibrary(
                    account, to, 0, _mutateUint256(salt), expiration, DEFAULT_POLICY_ID, data, true, initiatorSig
                ),
            "salt mutation should change review hash"
        );
    }

    /// @dev Verifies random undeployed accounts are always rejected by base execution path.
    function testFuzz_AT_FZ_10_executeAccountTransaction_randomUndeployedAccount_revertsAccountNotDeployed(address account)
        public
    {
        // Setup: constrain random account to non-zero and leave it undeployed.
        vm.assume(account != address(0));
        bytes memory data = abi.encodeWithSelector(bytes4(0x74747474), uint256(4));
        Policy memory policy = _buildApprovalPolicy(TransactionType.Any, PolicyType.AutoApprove);
        ValidationProofs memory proofs = _emptyProofsForPolicy(policy);

        // Verify: undeployed account should always be rejected.
        vm.expectRevert(
            abi.encodeWithSelector(IOrganizationAccountFactory.AccountNotDeployedByOrganization.selector, account)
        );
        vm.prank(GUARDIAN);
        // Call: execute base path against undeployed account.
        baseHarness.executeAccountTransaction(
            account, DESTINATION, 0, data, 1, block.timestamp + 1 days, DEFAULT_POLICY_ID, hex"01", bytes(""), proofs
        );
    }

    /// @dev Verifies rejection handler routing by policy type (auto-approve succeeds, manual without review fails).
    function testFuzz_AT_FZ_11_validateRejection_routesByPolicyType(bool useManualPolicy) public {
        // Setup: shared tuple/signatures with policy type selected by fuzz boolean.
        bytes memory data = abi.encodeWithSelector(bytes4(0x75757575), uint256(5));
        uint256 expiration = block.timestamp + 1 days;
        Policy memory policy = _buildApprovalPolicy(
            TransactionType.Any, useManualPolicy ? PolicyType.RequireManualApproval : PolicyType.AutoApprove
        );
        ValidationProofs memory proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);

        bytes memory initiatorSig = _signInitiatorTx(
            address(harness), INITIATOR_PK_1, ACCOUNT, DESTINATION, 0, data, 1, expiration, DEFAULT_POLICY_ID, true
        );
        bytes memory autoRejectionSig = _signInitiatorTx(
            address(harness), INITIATOR_PK_1, ACCOUNT, DESTINATION, 0, data, 1, expiration, DEFAULT_POLICY_ID, false
        );

        if (useManualPolicy) {
            // Verify: manual path without review signatures fails.
            vm.expectRevert();
            // Call: validate rejection with manual policy and no review signatures.
            harness.validateTransactionRejectionOrRevertViaLibrary(
                ACCOUNT, DESTINATION, 0, data, 1, expiration, DEFAULT_POLICY_ID, initiatorSig, bytes(""), proofs
            );
        } else {
            // Call: validate rejection with auto policy and initiator rejection signature.
            harness.validateTransactionRejectionOrRevertViaLibrary(
                ACCOUNT, DESTINATION, 0, data, 1, expiration, DEFAULT_POLICY_ID, initiatorSig, autoRejectionSig, proofs
            );
        }
    }

    /// @dev Applies deterministic +1 mutation with wraparound safety for fuzzed addresses.
    function _mutateAddress(address value) internal pure returns (address mutated) {
        unchecked {
            mutated = address(uint160(value) + 1);
        }
    }

    /// @dev Applies deterministic +1 mutation with wraparound safety for fuzzed uint256 values.
    function _mutateUint256(uint256 value) internal pure returns (uint256 mutated) {
        unchecked {
            mutated = value + 1;
        }
    }
}
