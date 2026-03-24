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
    /// @dev Verifies `_execute` preserves success semantics and forwards fuzzed value/data to the target.
    /// @param forwardedPayload The bytes payload decoded by the recorder target.
    /// @param marker The marker value decoded by the recorder target.
    /// @param rawValue The native-token value forwarded through `_execute`.
    function testFuzz_executeInternal_successPathForwardsRandomValueAndData(
        bytes calldata forwardedPayload,
        uint256 marker,
        uint256 rawValue
    ) public {
        vm.assume(forwardedPayload.length <= 1024);

        uint256 value = bound(rawValue, 0, 1 ether);
        uint256 txGas = 1_000_000;

        // Setup: fund the account and encode a recorder call carrying fuzzed payload/value inputs.
        AccountCallRecorderTarget target = new AccountCallRecorderTarget();
        bytes memory payload = abi.encodeWithSelector(target.record.selector, forwardedPayload, marker);
        vm.deal(address(account), value);

        // Call: invoke the internal helper wrapper against the recorder target.
        bool success = account.executeViaInternal(address(target), value, payload, txGas);

        // Verify: `_execute` returns success and preserves caller, value, calldata, and gas-cap semantics.
        assertTrue(success, "successful internal call should return true");
        assertEq(target.calls(), 1, "recorder target should be called exactly once");
        assertEq(target.lastCaller(), address(account), "callee should observe the account as msg.sender");
        assertEq(target.lastValue(), value, "callee should receive the forwarded native-token amount");
        assertEq(target.lastPayload(), forwardedPayload, "callee should decode the forwarded payload bytes");
        assertEq(target.returnMarker(), marker, "callee should decode the forwarded marker");
        assertTrue(target.observedGas() <= txGas, "callee gas should not exceed the provided gas cap");
    }

    /// @dev Verifies `_execute` fails closed and preserves balances when the downstream call reverts.
    /// @param rawValue The native-token value attempted on the reverting call.
    function testFuzz_executeInternal_failurePathReturnsFalseWithoutTransferringValue(uint256 rawValue) public {
        uint256 value = bound(rawValue, 0, 1 ether);
        uint256 txGas = 300_000;

        // Setup: fund the account and prepare a target that always reverts.
        AccountCallRecorderTarget target = new AccountCallRecorderTarget();
        bytes memory payload = abi.encodeWithSelector(target.fail.selector);
        vm.deal(address(account), value);

        // Call: execute the reverting downstream call through the internal helper wrapper.
        bool success = account.executeViaInternal(address(target), value, payload, txGas);

        // Verify: `_execute` reports failure and the reverting target receives no value.
        assertFalse(success, "reverting internal call should return false");
        assertEq(address(target).balance, 0, "reverting target should not retain forwarded value");
        assertEq(target.calls(), 0, "reverting path should not leave recorder state behind");
    }

    /**
     * @dev Verifies `_execute` returns true for a successful downstream call.
     */
    function test_executeInternal_successfulCall_returnsTrue() public {
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
    function test_executeInternal_targetReverts_returnsFalse() public {
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
    function test_executeInternal_callToEOA_returnsTrue() public {
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
    function test_executeInternal_forwardsEthValue() public {
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
    function test_executeInternal_forwardsCalldata() public {
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
    function test_executeInternal_respectsGasParameterUpperBound() public {
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
    function test_executeInternal_emptyDataWithValue_nativeTransferSucceeds() public {
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
    function test_executeInternal_targetReturnDataNotCaptured() public {
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
    function test_executeInternal_usesCallSemantics_notDelegatecallSemantics() public {
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
    function test_onlyOrganizationInternal_organizationCaller_succeeds() public {
        // Setup: bound organization is the beacon address.
        vm.prank(address(beacon));
        // Call: execute wrapper around `_onlyOrganization`.
        account.onlyOrganizationViaInternal();
        // Verify: no revert indicates authorization passed.
    }

    /**
     * @dev Verifies `_onlyOrganization` reverts when caller is not the bound organization.
     */
    function test_onlyOrganizationInternal_nonOrganizationCaller_revertsOnlyOrganization() public {
        // Verify: non-organization caller is rejected.
        vm.expectRevert(IAccount.OnlyOrganization.selector);
        vm.prank(NON_ORGANIZATION);
        // Call: execute wrapper around `_onlyOrganization`.
        account.onlyOrganizationViaInternal();
    }

    /**
     * @dev Verifies `_onlyOrganization` rejects `msg.sender == address(0)`.
     */
    function test_onlyOrganizationInternal_zeroAddressCaller_revertsOnlyOrganization() public {
        // Verify: zero-address caller is not authorized.
        vm.expectRevert(IAccount.OnlyOrganization.selector);
        vm.prank(address(0));
        // Call: execute wrapper around `_onlyOrganization`.
        account.onlyOrganizationViaInternal();
    }

    /**
     * @dev Verifies `_onlyOrganization` reverts for non-organization caller.
     */
    function test_onlyOrganizationInternal_nonOrganizationCaller_revertsOnlyOrganization_minimalPath() public {
        // Setup

        // Call
        vm.expectRevert(IAccount.OnlyOrganization.selector);
        vm.prank(NON_ORGANIZATION);
        account.onlyOrganizationViaInternal();

        // Verify
    }

    /**
     * @dev Verifies `_onlyOrganization` succeeds for configured organization caller.
     */
    function test_onlyOrganizationInternal_configuredOrganizationCaller_succeeds() public {
        // Setup

        // Call
        vm.prank(address(beacon));
        account.onlyOrganizationViaInternal();

        // Verify
    }

    /**
     * @dev Verifies `_execute` returns true for successful call and forwards exact tuple.
     */
    function test_executeInternal_success_returnsTrueAndForwardsExactTuple() public {
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
     * @dev Verifies `_execute` returns false when downstream call fails.
     */
    function test_executeInternal_failedInnerCall_returnsFalseWithoutReverting() public {
        // Setup
        AccountCallRecorderTarget target = new AccountCallRecorderTarget();
        bytes memory payload = abi.encodeWithSelector(target.fail.selector);

        // Call
        bool success = account.executeViaInternal(address(target), 0, payload, 200_000);

        // Verify
        assertFalse(success, "failed call should return false");
    }
}
