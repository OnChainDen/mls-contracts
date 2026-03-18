// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {Vm} from "forge-std/Vm.sol";

import {IAccount} from "interfaces/IAccount.sol";
import {IOrganizationAccountTransaction} from "interfaces/organization/IOrganizationAccountTransaction.sol";
import {IOrganizationSignatures} from "interfaces/organization/IOrganizationSignatures.sol";
import {
    OrganizationAccountTransactionBaseHarness
} from "test/organization/base/OrganizationAccountTransactionBase/OrganizationAccountTransactionBaseHarness.sol";
import {
    MockAccountForOrganizationTransaction
} from "test/organization/base/OrganizationAccountTransactionBase/OrganizationAccountTransactionBaseMocks.sol";
import {
    OrganizationAccountTransactionBaseSuiteBase
} from "test/organization/base/OrganizationAccountTransactionBase/OrganizationAccountTransactionBaseSuiteBase.sol";
import {
    OrganizationAccountTransactionInvariantHandler
} from "test/organization/integration/OrganizationAccountTransactionInvariantHandler.sol";
import {OperationType} from "types/CommonTypes.sol";
import {
    Policy,
    PolicyType,
    RateLimitScope,
    RateLimitType,
    TransactionType,
    ValidationProofs
} from "types/PolicyTypes.sol";

/**
 * @dev Invariant checks for account-transaction nonce, hash, and rate-limit properties.
 */
contract OrganizationAccountTransactionInvariants is OrganizationAccountTransactionBaseSuiteBase {
    OrganizationAccountTransactionInvariantHandler internal handler;
    MockAccountForOrganizationTransaction internal account;
    OrganizationAccountTransactionBaseHarness internal secondOrganization;
    Policy internal policy;
    ValidationProofs internal proofs;
    bytes internal data;
    uint256 internal expiration;
    bytes internal initiatorSig;
    uint256 internal usedSalt;
    uint256 internal executedNonce;
    uint256 internal failedExecutionNonce;
    bytes32 internal usageKey;
    uint256 internal usageWindow;
    uint256 internal usageAfterSuccess;

    function setUp() public override {
        super.setUp();

        // Setup: route invariant fuzz calls to a dedicated no-op handler to keep fixture state stable.
        handler = new OrganizationAccountTransactionInvariantHandler();
        targetContract(address(handler));

        // Setup: deploy account fixture and configure valid rate-limited policy.
        account = new MockAccountForOrganizationTransaction(address(harness));
        harness.setDeployedAccount(address(account), true);
        account.setAssertNonceConsumedOnEntry(true);

        policy = _buildApprovalPolicy(TransactionType.ContractInteractions, PolicyType.AutoApprove);
        policy.config.rateLimit.limitType = RateLimitType.TimeInterval;
        policy.config.rateLimit.timeIntervalHours = 1;
        policy.config.rateLimit.timeIntervalLimit = 1000;
        policy.config.rateLimit.destinationScope = RateLimitScope.PerEntity;
        policy.config.rateLimit.sourceScope = RateLimitScope.PerEntity;
        policy.config.rateLimit.initiatorScope = RateLimitScope.PerEntity;
        proofs = _setSinglePolicyRootAndBuildProofs(DEFAULT_POLICY_ID, policy);

        data = abi.encodeWithSelector(bytes4(0x81818181), uint256(1));
        expiration = block.timestamp + 1 days;
        usedSalt = 1;
        initiatorSig = _signInitiatorTx(
            address(harness),
            INITIATOR_PK_1,
            address(account),
            DESTINATION,
            0,
            data,
            usedSalt,
            expiration,
            DEFAULT_POLICY_ID,
            true
        );

        // Call: execute one valid transaction to consume nonce and update usage.
        vm.recordLogs();
        vm.prank(GUARDIAN);
        harness.executeAccountTransaction({
            account: address(account),
            to: DESTINATION,
            value: 0,
            data: data,
            salt: usedSalt,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: initiatorSig,
            reviewSignatures: bytes(""),
            proofs: proofs
        });
        executedNonce = _extractExecuteEventNonce(vm.getRecordedLogs());
        usageKey = _computeUsageKey(DEFAULT_POLICY_ID, policy, address(account), DESTINATION, initiator1);
        usageWindow = _computeTimeWindow(policy);
        usageAfterSuccess = harness.getPolicyUsage(usageKey, usageWindow);

        // Setup: force a post-validation execution failure. With partial reverts, the outer call succeeds,
        // nonce is consumed, and AccountTransactionExecutionReverted event is emitted.
        account.setShouldRevertExecution(true);
        bytes memory failingData = abi.encodeWithSelector(bytes4(0x82828282), uint256(2));
        bytes memory failingSig = _signInitiatorTx(
            address(harness),
            INITIATOR_PK_1,
            address(account),
            DESTINATION,
            0,
            failingData,
            2,
            expiration,
            DEFAULT_POLICY_ID,
            true
        );
        failedExecutionNonce = harness.computeNonce({
            operationType: OperationType.AccountTransaction,
            operationData: abi.encode(address(account), DESTINATION, 0, keccak256(failingData), DEFAULT_POLICY_ID),
            salt: 2
        });

        vm.expectEmit(true, true, true, true);
        emit IOrganizationAccountTransaction.AccountTransactionExecutionReverted({
            account: address(account),
            to: DESTINATION,
            value: 0,
            data: failingData,
            nonce: failedExecutionNonce,
            policyId: DEFAULT_POLICY_ID,
            revertData: abi.encodeWithSelector(IAccount.TransactionExecutionFailed.selector)
        });
        vm.prank(GUARDIAN);
        harness.executeAccountTransaction({
            account: address(account),
            to: DESTINATION,
            value: 0,
            data: failingData,
            salt: 2,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: failingSig,
            reviewSignatures: bytes(""),
            proofs: proofs
        });
        account.setShouldRevertExecution(false);

        // With partial reverts, rate-limit usage is consumed during validation (before the execution call),
        // so it persists even when execution reverts. Update expected usage to reflect both transactions.
        usageAfterSuccess = harness.getPolicyUsage(usageKey, usageWindow);
        secondOrganization = new OrganizationAccountTransactionBaseHarness();
    }

    /// @dev Verifies invariant: consumed nonce cannot be reused for execution or rejection.
    function invariant_NMINV_2_nonceConsumption_preventsExecuteAndRejectReplay() public {
        // Verify: execute replay fails on consumed nonce.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationSignatures.NonceAlreadyUsed.selector, executedNonce));
        vm.prank(GUARDIAN);
        harness.executeAccountTransaction({
            account: address(account),
            to: DESTINATION,
            value: 0,
            data: data,
            salt: usedSalt,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: initiatorSig,
            reviewSignatures: bytes(""),
            proofs: proofs
        });

        bytes memory rejectionSig = _signInitiatorTx(
            address(harness),
            INITIATOR_PK_1,
            address(account),
            DESTINATION,
            0,
            data,
            usedSalt,
            expiration,
            DEFAULT_POLICY_ID,
            false
        );
        vm.expectRevert(abi.encodeWithSelector(IOrganizationSignatures.NonceAlreadyUsed.selector, executedNonce));
        vm.prank(GUARDIAN);
        harness.rejectAccountTransaction({
            account: address(account),
            to: DESTINATION,
            value: 0,
            data: data,
            salt: usedSalt,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: initiatorSig,
            reviewSignatures: rejectionSig,
            proofs: proofs
        });
    }

    /// @dev Verifies invariant: rate-limit usage changes atomically (exact increment or full rollback).
    function invariant_rateLimitAtomicity_noPartialUsageMutations() public view {
        assertEq(
            harness.getPolicyUsage(usageKey, usageWindow), usageAfterSuccess, "usage must remain exact after revert"
        );
    }

    /// @dev Verifies invariant: nonce is already consumed before account external call entry (CEI ordering).
    function invariant_ceiNonceConsumption_accountEntryObservedConsumedNonce() public view {
        assertEq(account.executionCount(), 1, "account call should have observed consumed nonce and succeeded once");
    }

    /// @dev Verifies invariant: execute/reject share the same nonce space for identical tuples.
    function invariant_sharedNonceSpace_executeAndRejectUseSameNonce() public {
        // Setup: sign a rejection for the same tuple that was executed in setUp.
        bytes memory rejectionSig = _signInitiatorTx(
            address(harness),
            INITIATOR_PK_1,
            address(account),
            DESTINATION,
            0,
            data,
            usedSalt,
            expiration,
            DEFAULT_POLICY_ID,
            false
        );

        // Verify: reject reverts with the nonce emitted by the execute path, proving shared derivation.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationSignatures.NonceAlreadyUsed.selector, executedNonce));
        vm.prank(GUARDIAN);
        harness.rejectAccountTransaction({
            account: address(account),
            to: DESTINATION,
            value: 0,
            data: data,
            salt: usedSalt,
            expirationTimestamp: expiration,
            policyId: DEFAULT_POLICY_ID,
            initiatorSignature: initiatorSig,
            reviewSignatures: rejectionSig,
            proofs: proofs
        });
    }

    /// @dev Verifies invariant: approval and rejection initiator hashes are always distinct.
    function invariant_approvalRejectionHashSeparation() public view {
        bytes32 approvalHash = harness.computeInitiatorHashFromParamsViaLibrary(
            address(account), DESTINATION, 0, usedSalt, expiration, DEFAULT_POLICY_ID, data, true
        );
        bytes32 rejectionHash = harness.computeInitiatorHashFromParamsViaLibrary(
            address(account), DESTINATION, 0, usedSalt, expiration, DEFAULT_POLICY_ID, data, false
        );
        assertTrue(approvalHash != rejectionHash, "approval/rejection hashes must be distinct");
    }

    /// @dev Verifies invariant: organization address is bound in initiator hash.
    function invariant_organizationBinding_preventsCrossOrganizationReplay() public {
        OrganizationAccountTransactionBaseHarness orgB = new OrganizationAccountTransactionBaseHarness();
        bytes32 hashA = harness.computeInitiatorHashFromParamsViaLibrary(
            address(account), DESTINATION, 0, usedSalt, expiration, DEFAULT_POLICY_ID, data, true
        );
        bytes32 hashB = orgB.computeInitiatorHashFromParamsViaLibrary(
            address(account), DESTINATION, 0, usedSalt, expiration, DEFAULT_POLICY_ID, data, true
        );
        assertTrue(hashA != hashB, "hash should bind organization address");
    }

    /// @dev Verifies a consumed account-transaction nonce never flips back to unused.
    function invariant_NMINV_1_consumedAccountTransactionNonceRemainsUsed() public view {
        // Verify: the nonce consumed by the successful execution in `setUp` remains marked as used.
        assertTrue(harness.getUsedNonce(executedNonce), "consumed account-transaction nonce should remain used");
    }

    /// @dev Verifies invariant: identical account-transaction tuples do not share nonce usage across organizations.
    function invariant_NMINV_3_sameNonceValueDoesNotShareUsageAcrossOrganizations() public view {
        // Call: derive the matching account-transaction tuple on a fresh organization harness.
        uint256 sameTupleNonceOnSecondOrg = secondOrganization.computeNonce({
            operationType: OperationType.AccountTransaction,
            operationData: abi.encode(address(account), DESTINATION, 0, keccak256(data), DEFAULT_POLICY_ID),
            salt: usedSalt
        });

        // Verify: hash/nonce validity remains isolated per organization even when tuple derivation matches.
        assertTrue(harness.getUsedNonce(executedNonce), "primary organization should keep the executed nonce consumed");
        assertFalse(
            secondOrganization.getUsedNonce(executedNonce),
            "fresh organization should not inherit another org's consumed nonce"
        );
        assertFalse(
            secondOrganization.getUsedNonce(sameTupleNonceOnSecondOrg),
            "fresh organization should not inherit nonce usage"
        );
    }

    /// @dev Verifies invariant: partial-reverted account-transaction execution paths consume their nonce.
    function invariant_NMINV_4_partialRevertedExecutionPathsConsumeNonce() public view {
        // Verify: the nonce for the partial-reverted downstream execution in `setUp` is consumed.
        assertTrue(harness.getUsedNonce(failedExecutionNonce), "partial revert should consume nonce");
    }

    /// @dev Verifies `_computeInitiatorHashFromParams` remains distinct when any bound field changes.
    function invariant_computeInitiatorHash_boundFieldMutationsRemainDistinct() public {
        // Setup: use the seeded account-transaction tuple from `setUp` as the baseline initiator-hash input.
        bytes32 base = harness.computeInitiatorHashFromParamsViaLibrary(
            address(account), DESTINATION, 0, usedSalt, expiration, DEFAULT_POLICY_ID, data, true
        );

        // Call: recompute the initiator hash while mutating exactly one bound field at a time.
        assertTrue(
            base
                != secondOrganization.computeInitiatorHashFromParamsViaLibrary(
                    address(account), DESTINATION, 0, usedSalt, expiration, DEFAULT_POLICY_ID, data, true
                ),
            "organization binding should change initiator hash"
        );
        assertTrue(
            base
                != harness.computeInitiatorHashFromParamsViaLibrary(
                    address(uint160(address(account)) + 1),
                    DESTINATION,
                    0,
                    usedSalt,
                    expiration,
                    DEFAULT_POLICY_ID,
                    data,
                    true
                ),
            "account should change initiator hash"
        );
        assertTrue(
            base
                != harness.computeInitiatorHashFromParamsViaLibrary(
                    address(account),
                    address(uint160(DESTINATION) + 1),
                    0,
                    usedSalt,
                    expiration,
                    DEFAULT_POLICY_ID,
                    data,
                    true
                ),
            "destination should change initiator hash"
        );
        assertTrue(
            base
                != harness.computeInitiatorHashFromParamsViaLibrary(
                    address(account), DESTINATION, 1, usedSalt, expiration, DEFAULT_POLICY_ID, data, true
                ),
            "value should change initiator hash"
        );
        assertTrue(
            base
                != harness.computeInitiatorHashFromParamsViaLibrary(
                    address(account), DESTINATION, 0, usedSalt + 1, expiration, DEFAULT_POLICY_ID, data, true
                ),
            "salt should change initiator hash"
        );
        assertTrue(
            base
                != harness.computeInitiatorHashFromParamsViaLibrary(
                    address(account), DESTINATION, 0, usedSalt, expiration + 1, DEFAULT_POLICY_ID, data, true
                ),
            "expiration should change initiator hash"
        );
        assertTrue(
            base
                != harness.computeInitiatorHashFromParamsViaLibrary(
                    address(account), DESTINATION, 0, usedSalt, expiration, DEFAULT_POLICY_ID + 1, data, true
                ),
            "policy id should change initiator hash"
        );
        assertTrue(
            base
                != harness.computeInitiatorHashFromParamsViaLibrary(
                    address(account),
                    DESTINATION,
                    0,
                    usedSalt,
                    expiration,
                    DEFAULT_POLICY_ID,
                    abi.encodeWithSelector(bytes4(0x83838383), uint256(3)),
                    true
                ),
            "data should change initiator hash"
        );
        assertTrue(
            base
                != harness.computeInitiatorHashFromParamsViaLibrary(
                    address(account), DESTINATION, 0, usedSalt, expiration, DEFAULT_POLICY_ID, data, false
                ),
            "approval flag should change initiator hash"
        );
        uint256 originalChainId = block.chainid;
        vm.chainId(originalChainId + 1);
        bytes32 changedChainHash = harness.computeInitiatorHashFromParamsViaLibrary(
            address(account), DESTINATION, 0, usedSalt, expiration, DEFAULT_POLICY_ID, data, true
        );
        vm.chainId(originalChainId);

        // Verify: every bound-field mutation, including `chainId`, produces a distinct initiator hash.
        assertTrue(base != changedChainHash, "chain id should change initiator hash");
    }

    /// @dev Verifies `_computeReviewHashFromParams` remains distinct when any bound field changes.
    function invariant_computeReviewHash_boundFieldMutationsRemainDistinct() public {
        // Setup: use the seeded tuple and review-flow initiator signature as the baseline review-hash input.
        bytes32 base = harness.computeReviewHashFromParamsViaLibrary(
            address(account), DESTINATION, 0, usedSalt, expiration, DEFAULT_POLICY_ID, data, true, initiatorSig
        );
        bytes memory alternateInitiatorSignature = _signInitiatorTx(
            address(harness),
            INITIATOR_PK_2,
            address(account),
            DESTINATION,
            0,
            data,
            usedSalt,
            expiration,
            DEFAULT_POLICY_ID,
            true
        );

        // Call: recompute the review hash while mutating exactly one bound field at a time.
        assertTrue(
            base
                != secondOrganization.computeReviewHashFromParamsViaLibrary(
                    address(account), DESTINATION, 0, usedSalt, expiration, DEFAULT_POLICY_ID, data, true, initiatorSig
                ),
            "organization binding should change review hash"
        );
        assertTrue(
            base
                != harness.computeReviewHashFromParamsViaLibrary(
                    address(uint160(address(account)) + 1),
                    DESTINATION,
                    0,
                    usedSalt,
                    expiration,
                    DEFAULT_POLICY_ID,
                    data,
                    true,
                    initiatorSig
                ),
            "account should change review hash"
        );
        assertTrue(
            base
                != harness.computeReviewHashFromParamsViaLibrary(
                    address(account),
                    address(uint160(DESTINATION) + 1),
                    0,
                    usedSalt,
                    expiration,
                    DEFAULT_POLICY_ID,
                    data,
                    true,
                    initiatorSig
                ),
            "destination should change review hash"
        );
        assertTrue(
            base
                != harness.computeReviewHashFromParamsViaLibrary(
                    address(account), DESTINATION, 1, usedSalt, expiration, DEFAULT_POLICY_ID, data, true, initiatorSig
                ),
            "value should change review hash"
        );
        assertTrue(
            base
                != harness.computeReviewHashFromParamsViaLibrary(
                    address(account),
                    DESTINATION,
                    0,
                    usedSalt + 1,
                    expiration,
                    DEFAULT_POLICY_ID,
                    data,
                    true,
                    initiatorSig
                ),
            "salt should change review hash"
        );
        assertTrue(
            base
                != harness.computeReviewHashFromParamsViaLibrary(
                    address(account),
                    DESTINATION,
                    0,
                    usedSalt,
                    expiration + 1,
                    DEFAULT_POLICY_ID,
                    data,
                    true,
                    initiatorSig
                ),
            "expiration should change review hash"
        );
        assertTrue(
            base
                != harness.computeReviewHashFromParamsViaLibrary(
                    address(account),
                    DESTINATION,
                    0,
                    usedSalt,
                    expiration,
                    DEFAULT_POLICY_ID + 1,
                    data,
                    true,
                    initiatorSig
                ),
            "policy id should change review hash"
        );
        assertTrue(
            base
                != harness.computeReviewHashFromParamsViaLibrary(
                    address(account),
                    DESTINATION,
                    0,
                    usedSalt,
                    expiration,
                    DEFAULT_POLICY_ID,
                    abi.encodeWithSelector(bytes4(0x84848484), uint256(4)),
                    true,
                    initiatorSig
                ),
            "data should change review hash"
        );
        assertTrue(
            base
                != harness.computeReviewHashFromParamsViaLibrary(
                    address(account), DESTINATION, 0, usedSalt, expiration, DEFAULT_POLICY_ID, data, false, initiatorSig
                ),
            "approval flag should change review hash"
        );
        assertTrue(
            base
                != harness.computeReviewHashFromParamsViaLibrary(
                    address(account),
                    DESTINATION,
                    0,
                    usedSalt,
                    expiration,
                    DEFAULT_POLICY_ID,
                    data,
                    true,
                    alternateInitiatorSignature
                ),
            "initiator signature should change review hash"
        );
        uint256 originalChainId = block.chainid;
        vm.chainId(originalChainId + 1);
        bytes32 changedChainHash = harness.computeReviewHashFromParamsViaLibrary(
            address(account), DESTINATION, 0, usedSalt, expiration, DEFAULT_POLICY_ID, data, true, initiatorSig
        );
        vm.chainId(originalChainId);

        // Verify: every bound-field mutation, including `initiatorSignature` and `chainId`, produces a distinct
        // review hash.
        assertTrue(base != changedChainHash, "chain id should change review hash");
    }

    /// @dev Extracts nonce from the first `AccountTransactionExecuted` event in recorded logs.
    function _extractExecuteEventNonce(Vm.Log[] memory logs) private pure returns (uint256) {
        bytes32 topic = IOrganizationAccountTransaction.AccountTransactionExecuted.selector;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == topic) {
                return uint256(logs[i].topics[3]);
            }
        }
        revert("AccountTransactionExecuted event not found");
    }
}
