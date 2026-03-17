// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";

import {IAccount} from "interfaces/IAccount.sol";
import {SignatureUtils} from "libraries/SignatureUtils.sol";
import {
    AccountCallRecorderTarget,
    AccountNativeReceiver,
    AccountReceiveReentrancyAttacker
} from "test/account/AccountImplementationMocks.sol";
import {AccountImplementationSuiteBase} from "test/account/AccountImplementationSuiteBase.sol";

/**
 * @dev Tests for externally exposed `AccountImplementation` behavior.
 */
contract AccountImplementationExternalTest is AccountImplementationSuiteBase {
    /**
     * @dev Verifies receive accepts ETH from arbitrary senders.
     */
    function test_AI_RCV_1__OAT_AI_4_receive_acceptsEthFromAnyone() public {
        // Setup: fund a random sender and define transfer value.
        address sender = address(0xA101);
        uint256 value = 0.7 ether;
        vm.deal(sender, value);

        vm.prank(sender);
        // Call: send ETH to account receive function.
        (bool success,) = address(account).call{value: value}("");

        // Verify: receive call succeeds and account balance increases.
        assertTrue(success, "receive should accept ETH from arbitrary sender");
        assertEq(address(account).balance, value, "account balance should increase by sent value");
    }

    /**
     * @dev Verifies receive emits `MLSWalletAccountNativeTokenReceived` with sender/value.
     */
    /// AI-AENT-6
    function test_AI_AENT_6__AI_RCV_2__OAT_AI_4_receive_emitsNativeTokenReceivedEvent() public {
        // Setup: fund sender and configure event expectation.
        address sender = address(0xA102);
        uint256 value = 0.3 ether;
        vm.deal(sender, value);

        vm.expectEmit(true, true, true, true, address(account));
        emit IAccount.MLSWalletAccountNativeTokenReceived(sender, value);

        vm.prank(sender);
        // Call: send ETH to account receive function.
        (bool success,) = address(account).call{value: value}("");
        assertTrue(success, "receive should succeed");
    }

    /**
     * @dev Verifies zero-value receive still emits `MLSWalletAccountNativeTokenReceived`.
     */
    function test_AI_RCV_3_receive_zeroValueTransfer_emitsEvent() public {
        // Setup: choose sender for zero-value call.
        address sender = address(0xA103);

        vm.expectEmit(true, true, true, true, address(account));
        emit IAccount.MLSWalletAccountNativeTokenReceived(sender, 0);

        vm.prank(sender);
        // Call: send zero-value empty calldata call.
        (bool success,) = address(account).call{value: 0}("");

        // Verify: call succeeds and event is emitted with value zero.
        assertTrue(success, "zero-value receive should succeed");
    }

    /**
     * @dev Verifies non-organization caller reverts with `OnlyOrganization`.
     */
    /// AI-AENT-1
    function testFuzz_AI_AENT_1__AI_INV_1__AI_ET_1__OAT_AI_1__FAI_ORG_145_executeTransaction_nonOrganizationCaller_revertsOnlyOrganization(address caller)
        public
    {
        vm.assume(caller != address(beacon));

        // Setup: deploy target call receiver and choose a non-organization caller.
        AccountCallRecorderTarget target = new AccountCallRecorderTarget();

        vm.expectRevert(IAccount.OnlyOrganization.selector);
        vm.prank(caller);
        // Call: invoke executeTransaction from the fuzzed non-organization address.
        account.executeTransaction(
            address(target), 0, abi.encodeWithSelector(target.record.selector, bytes("x"), 1), 1, 1
        );

        // Verify: every caller other than the bound organization is rejected.
    }

    /**
     * @dev Verifies successful executeTransaction emits `TransactionExecuted`.
     */
    function test_AI_ET_3_executeTransaction_success_emitsTransactionExecuted() public {
        // Setup: deploy target and build calldata tuple.
        AccountCallRecorderTarget target = new AccountCallRecorderTarget();
        bytes memory payload = abi.encodeWithSelector(target.record.selector, bytes("payload"), 33);
        uint256 nonce = 91;
        uint256 policyId = 501;

        vm.expectEmit(true, true, true, true, address(account));
        emit IAccount.TransactionExecuted(address(target), 0, payload, nonce, policyId);

        vm.prank(address(beacon));
        // Call: execute transaction through organization caller.
        account.executeTransaction(address(target), 0, payload, nonce, policyId);
    }

    /**
     * @dev Verifies failed downstream call reverts with `TransactionExecutionFailed`.
     */
    /// AI-AENT-3
    /// AI-AENT-4
    function test_AI_AENT_3__AI_AENT_4__AI_INV_4__AI_ET_4__OAT_AI_2_executeTransaction_failedCall_revertsTransactionExecutionFailed()
        public
    {
        // Setup: deploy target and build reverting calldata.
        AccountCallRecorderTarget target = new AccountCallRecorderTarget();
        bytes memory payload = abi.encodeWithSelector(target.fail.selector);

        vm.expectRevert(IAccount.TransactionExecutionFailed.selector);
        vm.prank(address(beacon));
        // Call: execute transaction expected to fail in downstream call.
        account.executeTransaction(address(target), 0, payload, 11, 22);
    }

    /**
     * @dev Verifies value is forwarded to destination in executeTransaction.
     */
    function test_AI_ET_5_executeTransaction_forwardsEthValue() public {
        // Setup: deploy receiver and fund account balance.
        AccountNativeReceiver receiver = new AccountNativeReceiver();
        uint256 value = 0.21 ether;
        vm.deal(address(account), value);

        vm.prank(address(beacon));
        // Call: execute value transfer from account to receiver.
        account.executeTransaction(address(receiver), value, bytes(""), 12, 23);

        // Verify: receiver gets value and sender is account proxy.
        assertEq(receiver.totalReceived(), value, "receiver should receive forwarded ETH");
        assertEq(receiver.lastSender(), address(account), "forwarded call should originate from account");
    }

    /**
     * @dev Verifies calldata is forwarded unchanged to destination.
     */
    function test_AI_ET_6_executeTransaction_forwardsCalldata() public {
        // Setup: deploy target and encode deterministic payload.
        AccountCallRecorderTarget target = new AccountCallRecorderTarget();
        bytes memory innerPayload = hex"112233445566";
        uint256 marker = 77;
        bytes memory payload = abi.encodeWithSelector(target.record.selector, innerPayload, marker);

        vm.prank(address(beacon));
        // Call: execute calldata-carrying transaction.
        account.executeTransaction(address(target), 0, payload, 13, 24);

        // Verify: target records forwarded values and marker.
        assertEq(target.calls(), 1, "target should be called once");
        assertEq(target.lastCaller(), address(account), "caller should be account proxy");
        assertEq(target.lastPayload(), innerPayload, "inner payload should be forwarded unchanged");
        assertEq(target.returnMarker(), marker, "marker should be decoded and recorded");
    }

    /**
     * @dev Verifies emitted `TransactionExecuted` carries exact `(to,value,data,nonce,policyId)`.
     */
    /// AI-AENT-2
    function test_AI_AENT_2__AI_ET_7_executeTransaction_emitsTransactionExecutedWithExpectedTuple() public {
        // Setup: deploy target and deterministic tuple.
        AccountCallRecorderTarget target = new AccountCallRecorderTarget();
        bytes memory payload = abi.encodeWithSelector(target.record.selector, bytes("tuple"), 90);
        uint256 value = 0;
        uint256 nonce = 14;
        uint256 policyId = 25;

        vm.expectEmit(true, true, true, true, address(account));
        emit IAccount.TransactionExecuted(address(target), value, payload, nonce, policyId);

        vm.prank(address(beacon));
        // Call: execute transaction for event tuple assertion.
        account.executeTransaction(address(target), value, payload, nonce, policyId);
    }

    /**
     * @dev Verifies getOrganizationAddress returns beacon (organization) address.
     */
    function test_AI_GOA_1_getOrganizationAddress_returnsBoundOrganizationAddress() public view {
        // Call: read organization address through account proxy.
        address organization = account.getOrganizationAddress();

        // Verify: beacon address is returned.
        assertEq(organization, address(beacon), "organization should resolve to beacon address");
    }

    /**
     * @dev Verifies getOrganizationAddress is callable by arbitrary callers.
     */
    function test_AI_GOA_2_getOrganizationAddress_callableByAnyone() public {
        // Setup: choose arbitrary caller.
        address caller = address(0xA104);

        vm.prank(caller);
        // Call: read organization address from non-privileged caller.
        address organization = account.getOrganizationAddress();

        // Verify: call succeeds and returns expected beacon address.
        assertEq(organization, address(beacon), "getter must be publicly callable");
    }

    /**
     * @dev Verifies isValidSignature delegates `(account,hash,signature)` to organization contract.
     */
    function test_AI_INV_3__AI_IVS_1__OAT_AI_5_isValidSignature_delegatesToOrganizationWithExpectedArguments() public {
        // Setup: configure beacon mock to enforce exact delegated call arguments.
        bytes32 hash = keccak256("account-signature-delegate");
        bytes memory signature = hex"0102030405";
        beacon.setExpectedSignatureValidation(address(account), hash, signature);
        beacon.setSignatureResult(IERC1271.isValidSignature.selector);

        // Call: validate signature through account proxy.
        bytes4 result = account.isValidSignature(hash, signature);

        // Verify: call did not revert and returned configured result.
        assertEq(result, IERC1271.isValidSignature.selector, "delegated validation result should bubble through");
    }

    /**
     * @dev Verifies isValidSignature returns ERC-1271 magic value when organization approves.
     */
    /// AI-AENT-9
    function test_AI_AENT_9_A__AI_IVS_2__OAT_AI_5_isValidSignature_organizationApproves_returnsMagicValue() public {
        // Setup: configure organization to approve.
        beacon.clearExpectedSignatureValidation();
        beacon.setSignatureResult(IERC1271.isValidSignature.selector);

        // Call: validate arbitrary signature.
        bytes4 result = account.isValidSignature(keccak256("approve"), hex"AA");

        // Verify: account returns magic value from organization.
        assertEq(result, IERC1271.isValidSignature.selector, "approved signature should return magic value");
    }

    /**
     * @dev Verifies isValidSignature returns non-magic value when organization rejects.
     */
    /// AI-AENT-9
    function test_AI_AENT_9_B__AI_IVS_3__OAT_AI_5_isValidSignature_organizationRejects_returnsNonMagicValue() public {
        // Setup: configure organization to reject.
        beacon.clearExpectedSignatureValidation();
        beacon.setSignatureResult(0xffffffff);

        // Call: validate arbitrary signature.
        bytes4 result = account.isValidSignature(keccak256("reject"), hex"BB");

        // Verify: account returns rejection code from organization.
        assertEq(result, bytes4(0xffffffff), "rejected signature should return non-magic value");
    }

    /**
     * @dev Verifies bouncing ETH into `receive()` does not let an arbitrary contract bypass `onlyOrganization`.
     */
    /// AI-AENT-7
    function test_AI_AENT_7_receiveBounce_cannotBypassOnlyOrganizationForPrivilegedExecution() public {
        // Setup: deploy a target that sends ETH into the account receive path and then attempts privileged reentry.
        AccountReceiveReentrancyAttacker attacker = new AccountReceiveReentrancyAttacker();
        AccountCallRecorderTarget downstream = new AccountCallRecorderTarget();
        bytes memory nestedPayload = abi.encodeWithSelector(downstream.record.selector, bytes("nested"), uint256(77));
        bytes memory payload = abi.encodeCall(
            attacker.bounceAndReenter, (payable(address(account)), address(downstream), 0, nestedPayload)
        );

        vm.deal(address(account), 0.25 ether);
        uint256 balanceBefore = address(account).balance;

        vm.prank(address(beacon));
        // Call: execute the attacker flow through the bound organization caller.
        account.executeTransaction(address(attacker), 0.05 ether, payload, 16, 27);

        // Verify: the receive hop succeeds, but the follow-up privileged reentry is rejected.
        assertTrue(attacker.receiveCallSucceeded(), "attacker should successfully hit the account receive path");
        assertEq(
            attacker.privilegedRevertData(),
            abi.encodeWithSelector(IAccount.OnlyOrganization.selector),
            "privileged reentry should still fail with only-organization guard"
        );
        assertEq(address(account).balance, balanceBefore, "receive bounce should return value back to the account");
        assertEq(downstream.calls(), 0, "unauthorized reentry must not execute downstream target");
    }

    /**
     * @dev Verifies direct calls on the implementation contract fail `onlyOrganization` because its own storage is
     * unset.
     */
    function test_OAT_AI_6_executeTransaction_calledOnImplementationContract_revertsOnlyOrganization() public {
        // Setup: deploy a deterministic target for the direct implementation call.
        AccountCallRecorderTarget target = new AccountCallRecorderTarget();
        bytes memory payload = abi.encodeWithSelector(target.record.selector, bytes("direct-impl"), 88);

        vm.expectRevert(IAccount.OnlyOrganization.selector);
        vm.prank(address(beacon));
        // Call: invoke `executeTransaction` on the implementation contract instead of the proxy account.
        implementation.executeTransaction(address(target), 0, payload, 17, 29);

        // Verify: direct implementation calls fail closed because the implementation has no bound organization.
    }

    /**
     * @dev Verifies direct `isValidSignature` calls on the implementation contract fail closed and return invalid.
     */
    function test_OAT_AI_7_isValidSignature_calledOnImplementationContract_returnsInvalidValue() public view {
        // Call: validate an arbitrary signature directly against the implementation contract.
        bytes4 result = implementation.isValidSignature(keccak256("direct-implementation-signature"), hex"CAFE");

        // Verify: unset organization storage causes the direct implementation path to return the ERC-1271 invalid
        // value.
        assertEq(result, SignatureUtils.ERC1271_INVALID_VALUE, "direct implementation path should fail closed");
    }

    /**
     * @dev Verifies isValidSignature is callable by arbitrary callers (fuzz).
     */
    function testFuzz_AI_IVS_4_isValidSignature_callableByAnyone(address caller, bytes32 hash, bytes memory signature)
        public
    {
        // Setup: configure deterministic organization response.
        beacon.clearExpectedSignatureValidation();
        beacon.setSignatureResult(IERC1271.isValidSignature.selector);

        vm.prank(caller);
        // Call: execute isValidSignature from arbitrary caller.
        bytes4 result = account.isValidSignature(hash, signature);

        // Verify: caller is unrestricted and response is returned.
        assertEq(result, IERC1271.isValidSignature.selector, "isValidSignature should be publicly callable");
    }
}
