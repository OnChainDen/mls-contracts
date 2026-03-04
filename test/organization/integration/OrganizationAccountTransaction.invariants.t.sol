// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {Vm} from "forge-std/Vm.sol";

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
    Policy internal policy;
    ValidationProofs internal proofs;
    bytes internal data;
    uint256 internal expiration;
    bytes internal initiatorSig;
    uint256 internal usedSalt;
    uint256 internal executedNonce;
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

        // Setup: force a post-validation execution failure to assert atomic usage rollback.
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
        vm.expectRevert();
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
    }

    /// @dev Verifies invariant: consumed nonce cannot be reused for execution or rejection.
    function invariant_AT_INV_1_nonceConsumption_preventsExecuteAndRejectReplay() public {
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
    function invariant_AT_INV_2_rateLimitAtomicity_noPartialUsageMutations() public view {
        assertEq(
            harness.getPolicyUsage(usageKey, usageWindow), usageAfterSuccess, "usage must remain exact after revert"
        );
    }

    /// @dev Verifies invariant: nonce is already consumed before account external call entry (CEI ordering).
    function invariant_AT_INV_3_ceiNonceConsumption_accountEntryObservedConsumedNonce() public view {
        assertEq(account.executionCount(), 1, "account call should have observed consumed nonce and succeeded once");
    }

    /// @dev Verifies invariant: execute/reject share the same nonce space for identical tuples.
    function invariant_AT_INV_4_sharedNonceSpace_executeAndRejectUseSameNonce() public {
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
    function invariant_AT_INV_5_approvalRejectionHashSeparation() public view {
        bytes32 approvalHash = harness.computeInitiatorHashFromParamsViaLibrary(
            address(account), DESTINATION, 0, usedSalt, expiration, DEFAULT_POLICY_ID, data, true
        );
        bytes32 rejectionHash = harness.computeInitiatorHashFromParamsViaLibrary(
            address(account), DESTINATION, 0, usedSalt, expiration, DEFAULT_POLICY_ID, data, false
        );
        assertTrue(approvalHash != rejectionHash, "approval/rejection hashes must be distinct");
    }

    /// @dev Verifies invariant: organization address is bound in initiator hash.
    function invariant_AT_INV_6_organizationBinding_preventsCrossOrganizationReplay() public {
        OrganizationAccountTransactionBaseHarness orgB = new OrganizationAccountTransactionBaseHarness();
        bytes32 hashA = harness.computeInitiatorHashFromParamsViaLibrary(
            address(account), DESTINATION, 0, usedSalt, expiration, DEFAULT_POLICY_ID, data, true
        );
        bytes32 hashB = orgB.computeInitiatorHashFromParamsViaLibrary(
            address(account), DESTINATION, 0, usedSalt, expiration, DEFAULT_POLICY_ID, data, true
        );
        assertTrue(hashA != hashB, "hash should bind organization address");
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
