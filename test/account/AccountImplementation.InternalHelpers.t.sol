// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IAccount} from "interfaces/IAccount.sol";
import {AccountCallRecorderTarget, AccountNativeReceiver} from "test/account/AccountImplementationMocks.sol";
import {AccountImplementationSuiteBase} from "test/account/AccountImplementationSuiteBase.sol";

/**
 * @dev Tests for exposed internal helpers `_execute` and `_onlyOrganization`.
 */
contract AccountImplementationInternalHelpersTest is AccountImplementationSuiteBase {
    /**
     * @dev Verifies `_execute` returns true for a successful downstream call.
     */
    function test_AI_EXE_1_executeInternal_successfulCall_returnsTrue() public {
        // Setup: deploy target and encode successful calldata.
        AccountCallRecorderTarget target = new AccountCallRecorderTarget();
        bytes memory payload = abi.encodeWithSelector(target.record.selector, bytes("ok"), uint256(1));

        // Call: execute wrapper around `_execute`.
        bool success = account.executeViaInternal(address(target), 0, payload, 200_000);

        // Verify: wrapper reports success and target call happened.
        assertTrue(success, "successful call should return true");
        assertEq(target.calls(), 1, "target should be called once");
    }

    /**
     * @dev Verifies `_execute` returns false when downstream target reverts.
     */
    function test_AI_EXE_2_executeInternal_targetReverts_returnsFalse() public {
        // Setup: deploy target and encode reverting calldata.
        AccountCallRecorderTarget target = new AccountCallRecorderTarget();
        bytes memory payload = abi.encodeWithSelector(target.fail.selector);

        // Call: execute wrapper around `_execute`.
        bool success = account.executeViaInternal(address(target), 0, payload, 200_000);

        // Verify: wrapper reports failure without reverting.
        assertFalse(success, "reverting call should return false");
    }

    /**
     * @dev Verifies `_execute` call to an EOA with no code returns true.
     */
    function test_AI_EXE_3_executeInternal_callToEOA_returnsTrue() public {
        // Setup: choose deterministic EOA destination.
        address eoa = address(0xE0A1);

        // Call: execute wrapper around `_execute` against EOA.
        bool success = account.executeViaInternal(eoa, 0, bytes(""), 50_000);

        // Verify: CALL to EOA succeeds.
        assertTrue(success, "CALL to EOA should return true");
    }

    /**
     * @dev Verifies `_execute` forwards ETH value to target.
     */
    function test_AI_EXE_4_executeInternal_forwardsEthValue() public {
        // Setup: deploy receiver and fund account balance.
        AccountNativeReceiver receiver = new AccountNativeReceiver();
        uint256 value = 0.15 ether;
        vm.deal(address(account), value);

        // Call: execute wrapper with value transfer.
        bool success = account.executeViaInternal(address(receiver), value, bytes(""), 90_000);

        // Verify: call succeeds and receiver gets value.
        assertTrue(success, "value transfer should succeed");
        assertEq(receiver.totalReceived(), value, "receiver should get forwarded value");
        assertEq(receiver.lastSender(), address(account), "call sender should be account");
    }

    /**
     * @dev Verifies `_execute` forwards calldata to target contract unchanged.
     */
    function test_AI_EXE_5_executeInternal_forwardsCalldata() public {
        // Setup: deploy recorder target and encode deterministic payload.
        AccountCallRecorderTarget target = new AccountCallRecorderTarget();
        bytes memory payloadBytes = hex"11223344AABB";
        uint256 marker = 44;
        bytes memory payload = abi.encodeWithSelector(target.record.selector, payloadBytes, marker);

        // Call: execute wrapper around `_execute`.
        bool success = account.executeViaInternal(address(target), 0, payload, 200_000);

        // Verify: target observes original payload bytes.
        assertTrue(success, "calldata-forwarding call should succeed");
        assertEq(target.lastPayload(), payloadBytes, "payload bytes should match");
        assertEq(target.returnMarker(), marker, "marker should decode correctly");
    }

    /**
     * @dev Verifies `_execute` does not forward more gas than specified.
     */
    function test_AI_EXE_6_executeInternal_respectsGasParameterUpperBound() public {
        // Setup: deploy target and encode payload.
        AccountCallRecorderTarget target = new AccountCallRecorderTarget();
        bytes memory payload = abi.encodeWithSelector(target.record.selector, bytes("gas"), uint256(2));
        uint256 txGas = 300_000;

        // Call: execute wrapper around `_execute` with explicit gas cap.
        bool success = account.executeViaInternal(address(target), 0, payload, txGas);

        // Verify: call succeeds and observed gas is capped by requested gas.
        assertTrue(success, "gas-capped call should succeed");
        assertTrue(target.observedGas() <= txGas, "callee gas should not exceed requested gas");
    }

    /**
     * @dev Verifies `_execute` supports empty calldata with value-only native transfer.
     */
    function test_AI_EXE_7_executeInternal_emptyDataWithValue_nativeTransferSucceeds() public {
        // Setup: deploy receiver and fund account.
        AccountNativeReceiver receiver = new AccountNativeReceiver();
        uint256 value = 0.09 ether;
        vm.deal(address(account), value);

        // Call: execute value-only transfer with empty data.
        bool success = account.executeViaInternal(address(receiver), value, bytes(""), 90_000);

        // Verify: transfer succeeds and receiver gets ETH.
        assertTrue(success, "empty-data value transfer should succeed");
        assertEq(receiver.totalReceived(), value, "receiver should receive transfer value");
    }

    /**
     * @dev Verifies target return data is not propagated by `_execute` (bool-only wrapper output).
     */
    function test_AI_EXE_8_executeInternal_targetReturnDataNotCaptured() public {
        // Setup: deploy target that returns bytes32 from `record`.
        AccountCallRecorderTarget target = new AccountCallRecorderTarget();
        bytes memory payload = abi.encodeWithSelector(target.record.selector, bytes("ret"), uint256(99));

        // Call: invoke wrapper via low-level call to inspect ABI return size.
        (bool ok, bytes memory returnData) =
            address(account).call(abi.encodeCall(account.executeViaInternal, (address(target), 0, payload, 200_000)));

        // Verify: wrapper returns only ABI-encoded bool (32 bytes), not downstream return payload.
        assertTrue(ok, "wrapper call should succeed");
        assertEq(returnData.length, 32, "wrapper should return only bool encoding");
        assertTrue(abi.decode(returnData, (bool)), "wrapper bool result should be true");
    }

    /**
     * @dev Verifies execution uses CALL semantics (callee sees account as `msg.sender`, not external caller).
     */
    function test_AI_EXE_9_executeInternal_usesCallSemantics_notDelegatecallSemantics() public {
        // Setup: deploy target and encode payload.
        AccountCallRecorderTarget target = new AccountCallRecorderTarget();
        bytes memory payload = abi.encodeWithSelector(target.record.selector, bytes("caller"), uint256(123));

        // Call: invoke wrapper from this test contract.
        bool success = account.executeViaInternal(address(target), 0, payload, 200_000);

        // Verify: callee observes account proxy as caller, proving CALL (not delegatecall) semantics.
        assertTrue(success, "call should succeed");
        assertEq(target.lastCaller(), address(account), "callee must see account as msg.sender");
    }

    /**
     * @dev Verifies `_onlyOrganization` passes when caller equals bound organization.
     */
    function test_AI_OO_1_onlyOrganizationInternal_organizationCaller_succeeds() public {
        // Setup: bound organization is the beacon address.
        vm.prank(address(beacon));
        // Call: execute wrapper around `_onlyOrganization`.
        account.onlyOrganizationViaInternal();
        // Verify: no revert indicates authorization passed.
    }

    /**
     * @dev Verifies `_onlyOrganization` reverts when caller is not the bound organization.
     */
    function test_AI_OO_2_onlyOrganizationInternal_nonOrganizationCaller_revertsOnlyOrganization() public {
        // Verify: non-organization caller is rejected.
        vm.expectRevert(IAccount.OnlyOrganization.selector);
        vm.prank(NON_ORGANIZATION);
        // Call: execute wrapper around `_onlyOrganization`.
        account.onlyOrganizationViaInternal();
    }

    /**
     * @dev Verifies `_onlyOrganization` rejects `msg.sender == address(0)`.
     */
    function test_AI_OO_4_onlyOrganizationInternal_zeroAddressCaller_revertsOnlyOrganization() public {
        // Verify: zero-address caller is not authorized.
        vm.expectRevert(IAccount.OnlyOrganization.selector);
        vm.prank(address(0));
        // Call: execute wrapper around `_onlyOrganization`.
        account.onlyOrganizationViaInternal();
    }

    /**
     * @dev Verifies AI-PH-1: `_onlyOrganization` reverts for non-organization caller.
     */
    function test_AI_PH_1_onlyOrganizationInternal_nonOrganizationCaller_revertsOnlyOrganization() public {
        // Setup

        // Call
        vm.expectRevert(IAccount.OnlyOrganization.selector);
        vm.prank(NON_ORGANIZATION);
        account.onlyOrganizationViaInternal();

        // Verify
    }

    /**
     * @dev Verifies AI-PH-2: `_onlyOrganization` succeeds for configured organization caller.
     */
    function test_AI_PH_2_onlyOrganizationInternal_configuredOrganizationCaller_succeeds() public {
        // Setup

        // Call
        vm.prank(address(beacon));
        account.onlyOrganizationViaInternal();

        // Verify
    }

    /**
     * @dev Verifies AI-PH-3: `_execute` returns true for successful call and forwards exact tuple.
     */
    function test_AI_PH_3_executeInternal_success_returnsTrueAndForwardsExactTuple() public {
        // Setup
        AccountCallRecorderTarget target = new AccountCallRecorderTarget();
        bytes memory payload = abi.encodeWithSelector(target.record.selector, bytes("ai-ph"), uint256(303));

        // Call
        bool success = account.executeViaInternal(address(target), 0, payload, 200_000);

        // Verify
        assertTrue(success, "successful call should return true");
        assertEq(target.calls(), 1, "target should be called once");
        assertEq(target.lastCaller(), address(account), "callee should see account caller");
        assertEq(target.lastPayload(), bytes("ai-ph"), "payload should be forwarded");
        assertEq(target.returnMarker(), 303, "marker should decode correctly");
    }

    /**
     * @dev Verifies AI-PH-4: `_execute` returns false when downstream call fails.
     */
    function test_AI_PH_4_executeInternal_failedInnerCall_returnsFalseWithoutReverting() public {
        // Setup
        AccountCallRecorderTarget target = new AccountCallRecorderTarget();
        bytes memory payload = abi.encodeWithSelector(target.fail.selector);

        // Call
        bool success = account.executeViaInternal(address(target), 0, payload, 200_000);

        // Verify
        assertFalse(success, "failed call should return false");
    }
}
