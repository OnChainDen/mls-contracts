// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";

import {IBatchedTransaction} from "../../src/interfaces/IBatchedTransaction.sol";
import {BatchedTransaction} from "../../src/safe-module/BatchedTransaction.sol";

/**
 * @dev MockBTTarget — target contract tracking calls, values, and caller identity.
 */
contract MockBTTarget {
    uint256 public value;
    address public lastCaller;
    uint256 public callCount;
    uint256 public lastMsgValue;

    event ValueSet(uint256 newValue, address caller);

    function setValue(uint256 newValue) external payable {
        value = newValue;
        lastCaller = msg.sender;
        lastMsgValue = msg.value;
        callCount++;
        emit ValueSet(newValue, msg.sender);
    }

    function increment() external payable {
        value++;
        lastCaller = msg.sender;
        lastMsgValue = msg.value;
        callCount++;
    }

    function revertingFunction() external pure {
        revert("MockBTTarget: intentional revert");
    }

    function getValuePlusOne() external view returns (uint256) {
        return value + 1;
    }

    receive() external payable {
        revert("MockBTTarget: ETH not accepted");
    }
}

/**
 * @dev EmptyCallTarget — accepts empty calls (fallback) for testing zero-length calldata.
 */
contract EmptyCallTarget {
    bool public wasCalled;
    address public lastCaller;

    fallback() external {
        wasCalled = true;
        lastCaller = msg.sender;
    }
}

/**
 * @dev MsgValueTracker — records msg.value for every call, used to verify value=0 enforcement.
 */
contract MsgValueTracker {
    uint256 public lastMsgValue;
    uint256 public callCount;

    function track() external payable {
        lastMsgValue = msg.value;
        callCount++;
    }
}

/**
 * @dev CallOrderTracker — records the argument of each call to verify execution order.
 */
contract CallOrderTracker {
    uint256[] public callOrder;

    function recordCall(uint256 id) external {
        callOrder.push(id);
    }

    function getCallOrder() external view returns (uint256[] memory) {
        return callOrder;
    }
}


/**
 * @dev CalldataRecorderTarget — accepts arbitrary calldata and records the exact payload delivered to it.
 */
contract CalldataRecorderTarget {
    bytes public lastCalldata;
    address public lastCaller;
    uint256 public callCount;

    fallback() external payable {
        lastCalldata = msg.data;
        lastCaller = msg.sender;
        callCount++;
    }
}

/**
 * @dev CalldataValueRecorderTarget — fallback target that records both calldata and msg.value.
 */
contract CalldataValueRecorderTarget {
    bytes public lastCalldata;
    uint256 public lastMsgValue;
    uint256 public callCount;

    fallback() external payable {
        lastCalldata = msg.data;
        lastMsgValue = msg.value;
        callCount++;
    }
}

/**
 * @dev RequiresEthBTTarget — reverts unless msg.value > 0.
 */
contract RequiresEthBTTarget {
    function payableAction() external payable {
        require(msg.value > 0, "ETH required");
    }
}

/**
 * @dev Comprehensive tests for BatchedTransaction covering valid execution, security/failure,
 *      and malformed encoding scenarios. Covers test plan rows BT-EVB-*, BT-ESF-*, BT-EMB-*.
 */
contract BatchedTransactionTest is Test {
    BatchedTransaction internal batchedTx;
    MockBTTarget internal target1;
    MockBTTarget internal target2;

    /// @dev Deploy contracts before each test.
    function setUp() public {
        batchedTx = new BatchedTransaction();
        target1 = new MockBTTarget();
        target2 = new MockBTTarget();
    }

    /**
     * @dev Encodes a single transaction in the BatchedTransaction format: [to(20)][dataLength(8)][data(N)].
     * @param to Target address (20 bytes)
     * @param data Calldata
     * @return encoded The packed transaction data
     */
    function _encodeTx(address to, bytes memory data) internal pure returns (bytes memory encoded) {
        return abi.encodePacked(to, uint64(data.length), data);
    }

    /**
     * @dev Concatenates multiple encoded sub-transactions into a batch.
     * @param txs Array of individually encoded sub-transactions
     * @return batch Concatenated batch bytes
     */
    function _encodeBatch(bytes[] memory txs) internal pure returns (bytes memory batch) {
        for (uint256 i = 0; i < txs.length; i++) {
            batch = abi.encodePacked(batch, txs[i]);
        }
    }

    /**
     * @dev Executes a batch via delegatecall (simulating Safe calling BatchedTransaction).
     * @param encoded The packed batch bytes
     * @return success Whether the delegatecall succeeded
     * @return returnData Raw return data from the delegatecall
     */
    function _executeBatchViaDelegatecall(bytes memory encoded)
        internal
        returns (bool success, bytes memory returnData)
    {
        (success, returnData) = address(batchedTx)
            .delegatecall(abi.encodeWithSelector(BatchedTransaction.execute.selector, encoded));
    }

    /**
     * @dev Builds deterministic calldata bytes from fuzz seed material for batch field-decoding assertions.
     * @param seed Base fuzz entropy shared across the batch
     * @param index Sub-transaction index mixed into the payload
     * @param length Desired calldata length
     * @return payload Deterministic calldata bytes
     */
    function _buildFuzzedCalldata(bytes32 seed, uint256 index, uint256 length)
        internal
        pure
        returns (bytes memory payload)
    {
        bytes memory entropy = abi.encodePacked(keccak256(abi.encodePacked(seed, index)));
        payload = new bytes(length);

        for (uint256 i = 0; i < length; i++) {
            payload[i] = bytes1(uint8(entropy[i % entropy.length]) ^ uint8(index + i));
        }
    }

    /// @dev Verifies `execute` succeeds as no-op for empty transactions bytes.
    function test_BT_EVB_1_executeEmptyTransactionsSucceedsAsNoop() public {
        // Call: execute with empty bytes (no sub-transactions).
        (bool success,) = _executeBatchViaDelegatecall("");

        // Verify: succeeds without executing anything.
        assertTrue(success, "Empty batch should succeed as no-op");
    }

    /// @dev Verifies `execute` successfully executes a single packed transaction. [ASIG-INV-14]
    function test_ASIG_INV_14_A_BT_EVB_2_executeSinglePackedTransaction() public {
        // Setup: encode a single setValue(42) call.
        bytes memory data = abi.encodeWithSelector(MockBTTarget.setValue.selector, 42);
        bytes memory encoded = _encodeTx(address(target1), data);

        // Call: execute via delegatecall (simulating Safe).
        (bool success,) = _executeBatchViaDelegatecall(encoded);

        // Verify: sub-transaction executed correctly.
        assertTrue(success, "Single transaction should succeed");
        assertEq(target1.value(), 42, "Target value should be set to 42");
        assertEq(target1.callCount(), 1, "Target should have received exactly one call");
    }

    // ISEM-BTE-1
    /// @dev Verifies `execute` runs multiple packed transactions in encoded order. [ASIG-INV-15]
    function test_ASIG_INV_15_A_ISEM_BTE_1__BT_EVB_3_executeMultipleTransactionsInOrder() public {
        // Setup: encode three sub-transactions in specific order.
        bytes[] memory txs = new bytes[](3);
        txs[0] = _encodeTx(address(target1), abi.encodeWithSelector(MockBTTarget.setValue.selector, 10));
        txs[1] = _encodeTx(address(target2), abi.encodeWithSelector(MockBTTarget.setValue.selector, 20));
        txs[2] = _encodeTx(address(target1), abi.encodeWithSelector(MockBTTarget.increment.selector));

        // Call: execute batch.
        (bool success,) = _executeBatchViaDelegatecall(_encodeBatch(txs));

        // Verify: transactions executed in encoded order (target1: 10 → 11, target2: 20).
        assertTrue(success, "Batch should succeed");
        assertEq(target1.value(), 11, "Target1 value should be 10 + 1 = 11");
        assertEq(target2.value(), 20, "Target2 value should be 20");
    }

    /// @dev Verifies repeated calls to same target preserve order and cumulative state.
    function test_ASIG_INV_15_B_BT_EVB_4_executeRepeatedCallsCumulativeState() public {
        // Setup: five recordCall() invocations with ordered IDs to a CallOrderTracker.
        CallOrderTracker tracker = new CallOrderTracker();
        bytes[] memory txs = new bytes[](5);
        for (uint256 i = 0; i < 5; i++) {
            txs[i] = _encodeTx(address(tracker), abi.encodeWithSelector(CallOrderTracker.recordCall.selector, i));
        }

        // Call: execute batch.
        (bool success,) = _executeBatchViaDelegatecall(_encodeBatch(txs));

        // Verify: all five calls executed in the exact encoded order.
        assertTrue(success, "Batch should succeed");
        uint256[] memory order = tracker.getCallOrder();
        assertEq(order.length, 5, "Should have recorded 5 calls");
        for (uint256 i = 0; i < 5; i++) {
            assertEq(order[i], i, "Call at position should match encoded order");
        }
    }

    /// @dev Verifies zero-length calldata sub-transaction is valid (fallback/receive path).
    function test_BT_EVB_5_executeZeroLengthCalldataCallsFallback() public {
        // Setup: deploy target that accepts empty calls via fallback.
        EmptyCallTarget emptyTarget = new EmptyCallTarget();
        bytes memory encoded = _encodeTx(address(emptyTarget), "");

        // Call: execute with empty calldata sub-transaction.
        (bool success,) = _executeBatchViaDelegatecall(encoded);

        // Verify: fallback was triggered.
        assertTrue(success, "Zero-length calldata transaction should succeed");
        assertTrue(emptyTarget.wasCalled(), "Fallback should have been called");
    }

    /// @dev Verifies mixed targets within one batch execute correctly. [ASIG-INV-14]
    function test_ASIG_INV_14_B_BT_EVB_6_executeMixedTargetsBatch() public {
        // Setup: encode sub-transactions targeting different contracts.
        EmptyCallTarget emptyTarget = new EmptyCallTarget();
        bytes[] memory txs = new bytes[](3);
        txs[0] = _encodeTx(address(target1), abi.encodeWithSelector(MockBTTarget.setValue.selector, 100));
        txs[1] = _encodeTx(address(emptyTarget), "");
        txs[2] = _encodeTx(address(target2), abi.encodeWithSelector(MockBTTarget.setValue.selector, 200));

        // Call: execute mixed batch.
        (bool success,) = _executeBatchViaDelegatecall(_encodeBatch(txs));

        // Verify: all targets received their calls.
        assertTrue(success, "Mixed-target batch should succeed");
        assertEq(target1.value(), 100, "Target1 should be set to 100");
        assertEq(target2.value(), 200, "Target2 should be set to 200");
        assertTrue(emptyTarget.wasCalled(), "EmptyCallTarget should have been called");
    }

    /// @dev Verifies direct call mode (non-delegatecall) works and target sees `msg.sender == BatchedTransaction`.
    function test_BT_EVB_7_executeDirectCallTargetSeesBatchedTxAsSender() public {
        // Setup: encode a single transaction.
        bytes memory encoded = _encodeTx(address(target1), abi.encodeWithSelector(MockBTTarget.setValue.selector, 42));

        // Call: direct call (not delegatecall).
        batchedTx.execute(encoded);

        // Verify: target sees BatchedTransaction as caller (not this test contract).
        assertEq(target1.value(), 42, "Target value should be set");
        assertEq(target1.lastCaller(), address(batchedTx), "Direct-call mode: target should see BatchedTransaction");
    }

    /// @dev Verifies direct call mode still enforces self-target blocking.
    function test_BT_EVB_8_executeDirectCallBlocksSelfTarget() public {
        // Setup: encode a sub-transaction targeting BatchedTransaction itself.
        bytes memory encoded = _encodeTx(address(batchedTx), abi.encodeWithSelector(MockBTTarget.setValue.selector, 42));

        // Call: direct call with self-target. Expect CannotCallSafe.
        vm.expectRevert(abi.encodeWithSelector(IBatchedTransaction.CannotCallSafe.selector, address(batchedTx)));
        batchedTx.execute(encoded);
    }

    /// @dev Verifies delegatecall mode sub-calls see `msg.sender` == delegatecaller (this test contract as Safe).
    function test_BT_EVB_9_executeDelegatecallSubCallsSeeDelegatecallerAsSender() public {
        // Setup: encode a single transaction. When delegatecalled, address(this) is this test contract.
        bytes memory encoded = _encodeTx(address(target1), abi.encodeWithSelector(MockBTTarget.setValue.selector, 42));

        // Call: delegatecall (this test contract simulates the Safe).
        (bool success,) = _executeBatchViaDelegatecall(encoded);

        // Verify: target sees this test contract (the delegatecaller/Safe) as msg.sender.
        assertTrue(success, "Delegatecall should succeed");
        assertEq(
            target1.lastCaller(), address(this), "Delegatecall mode: target should see delegatecaller as msg.sender"
        );
    }

    // ISEM-BTE-3
    /// @dev Verifies delegatecall context: sub-transaction targeting delegatecaller reverts `CannotCallSafe`.
    ///      [ASIG-INV-9]
    function test_ASIG_INV_9_A_ISEM_BTE_3__BT_ESF_1_executeDelegatecallSelfTargetRevertsCannotCallSafe() public {
        // Setup: encode sub-transaction targeting address(this) (the "Safe" when delegatecalled).
        bytes memory data = abi.encodeWithSelector(MockBTTarget.setValue.selector, 42);
        bytes memory encoded = _encodeTx(address(this), data);

        // Call: delegatecall with self-target.
        (bool success, bytes memory returnData) = _executeBatchViaDelegatecall(encoded);

        // Verify: reverts with CannotCallSafe error.
        assertFalse(success, "Self-target should cause revert");
        bytes4 expectedSelector = IBatchedTransaction.CannotCallSafe.selector;
        bytes4 actualSelector;
        assembly {
            actualSelector := mload(add(returnData, 32))
        }
        assertEq(actualSelector, expectedSelector, "Should revert with CannotCallSafe");
    }

    /// @dev Verifies self-target in later sub-transaction reverts the entire batch. [ASIG-INV-9]
    function test_ASIG_INV_9_B_BT_ESF_2_executeSelfTargetInLaterTxRevertsEntireBatch() public {
        // Setup: first tx is valid, second tx targets address(this).
        bytes[] memory txs = new bytes[](2);
        txs[0] = _encodeTx(address(target1), abi.encodeWithSelector(MockBTTarget.setValue.selector, 10));
        txs[1] = _encodeTx(address(this), abi.encodeWithSelector(MockBTTarget.setValue.selector, 20));

        // Call: execute batch.
        (bool success,) = _executeBatchViaDelegatecall(_encodeBatch(txs));

        // Verify: entire batch reverts.
        assertFalse(success, "Self-target in later tx should revert entire batch");
    }

    /// @dev Verifies any sub-transaction revert causes entire batch revert.
    function test_BT_ESF_3_executeAnySubTxRevertCausesEntireBatchRevert() public {
        // Setup: single reverting sub-transaction.
        bytes memory data = abi.encodeWithSelector(MockBTTarget.revertingFunction.selector);
        bytes memory encoded = _encodeTx(address(target1), data);

        // Call: execute batch.
        (bool success,) = _executeBatchViaDelegatecall(encoded);

        // Verify: batch reverts.
        assertFalse(success, "Reverting sub-transaction should cause batch revert");
    }

    // ISEM-BTE-2
    /// @dev Verifies first sub-call success + second sub-call revert => first side effects rolled back.
    ///      [ASIG-INV-9]
    function test_ASIG_INV_9_C_ISEM_BTE_2__BT_ESF_4_executeSecondTxRevertRollsBackFirstTx() public {
        // Setup: first tx succeeds (setValue(10)), second tx reverts.
        bytes[] memory txs = new bytes[](2);
        txs[0] = _encodeTx(address(target1), abi.encodeWithSelector(MockBTTarget.setValue.selector, 10));
        txs[1] = _encodeTx(address(target1), abi.encodeWithSelector(MockBTTarget.revertingFunction.selector));

        // Call: execute batch.
        (bool success,) = _executeBatchViaDelegatecall(_encodeBatch(txs));

        // Verify: batch failed and first tx side effects are rolled back.
        assertFalse(success, "Second tx revert should fail entire batch");
        assertEq(target1.value(), 0, "First tx side effects should be rolled back (value should be 0)");
        assertEq(target1.callCount(), 0, "First tx call count should be rolled back");
    }

    /// @dev Verifies first sub-call success + second CannotCallSafe => first side effects rolled back.
    function test_BT_ESF_5_executeCannotCallSafeRollsBackPriorSuccesses() public {
        // Setup: first tx succeeds, second tx targets Safe (address(this) in delegatecall context).
        bytes[] memory txs = new bytes[](2);
        txs[0] = _encodeTx(address(target1), abi.encodeWithSelector(MockBTTarget.setValue.selector, 10));
        txs[1] = _encodeTx(address(this), abi.encodeWithSelector(MockBTTarget.setValue.selector, 20));

        // Call: execute batch.
        (bool success,) = _executeBatchViaDelegatecall(_encodeBatch(txs));

        // Verify: batch failed and first tx side effects are rolled back.
        assertFalse(success, "CannotCallSafe should fail entire batch");
        assertEq(target1.value(), 0, "First tx side effects should be rolled back on CannotCallSafe");
    }

    // ISEM-BTE-4
    /// @dev Verifies payable target receives `msg.value == 0` for every sub-call.
    function test_ISEM_BTE_4__BT_ESF_6_executeSubCallsReceiveZeroMsgValue() public {
        // Setup: deploy target that tracks msg.value.
        MsgValueTracker tracker = new MsgValueTracker();
        bytes[] memory txs = new bytes[](2);
        txs[0] = _encodeTx(address(tracker), abi.encodeWithSelector(MsgValueTracker.track.selector));
        txs[1] = _encodeTx(address(tracker), abi.encodeWithSelector(MsgValueTracker.track.selector));

        // Call: execute batch.
        (bool success,) = _executeBatchViaDelegatecall(_encodeBatch(txs));

        // Verify: msg.value was 0 for all calls.
        assertTrue(success, "Batch should succeed");
        assertEq(tracker.lastMsgValue(), 0, "msg.value should be 0 for sub-calls");
        assertEq(tracker.callCount(), 2, "Tracker should have received 2 calls");
    }

    /// @dev Verifies sub-call requiring positive msg.value fails and reverts whole batch.
    function test_BT_ESF_7_executeSubCallRequiringEthFailsBatch() public {
        // Setup: target that requires ETH.
        RequiresEthBTTarget ethTarget = new RequiresEthBTTarget();
        bytes memory encoded =
            _encodeTx(address(ethTarget), abi.encodeWithSelector(RequiresEthBTTarget.payableAction.selector));

        // Call: execute batch. Sub-call receives value=0 → target reverts → batch fails.
        (bool success,) = _executeBatchViaDelegatecall(encoded);

        // Verify: batch failed.
        assertFalse(success, "Sub-call requiring ETH should fail the batch (value=0 always)");
    }

    /// @dev Verifies batch cannot transfer ETH from delegatecaller balance.
    function test_BT_ESF_8_executeBatchCannotTransferEthFromDelegatecaller() public {
        // Setup: fund this test contract (simulating a Safe with ETH).
        vm.deal(address(this), 10 ether);
        MsgValueTracker tracker = new MsgValueTracker();
        bytes memory encoded = _encodeTx(address(tracker), abi.encodeWithSelector(MsgValueTracker.track.selector));

        // Call: execute batch via delegatecall (delegatecaller has ETH balance).
        (bool success,) = _executeBatchViaDelegatecall(encoded);

        // Verify: sub-call still received value=0 (hardcoded in assembly).
        assertTrue(success, "Batch should succeed");
        assertEq(tracker.lastMsgValue(), 0, "Sub-call should receive value=0 despite delegatecaller having ETH");
    }

    /// @dev Verifies all sub-transactions are executed as CALL (no per-subtx delegatecall path).
    function test_BT_ESF_9_executeSubTransactionsUseCallNotDelegatecall() public {
        // Setup: encode a single sub-transaction. In CALL mode, target sees its own address(this).
        bytes memory encoded = _encodeTx(address(target1), abi.encodeWithSelector(MockBTTarget.setValue.selector, 42));

        // Call: delegatecall into BatchedTransaction.
        (bool success,) = _executeBatchViaDelegatecall(encoded);

        // Verify: target received a CALL (msg.sender = this test contract acting as Safe).
        assertTrue(success, "Batch should succeed");
        assertEq(target1.lastCaller(), address(this), "Sub-tx should be CALL (msg.sender = delegatecaller)");
        // If it were delegatecall, target1.value would be in this contract's storage, not target1's.
        assertEq(target1.value(), 42, "State change should be in target's storage, confirming CALL not DELEGATECALL");
    }

    /// @dev Verifies no partial completion is observable after any failure (all-or-nothing).
    function test_BT_ESF_10_executeNoPartialCompletionOnFailure() public {
        // Setup: first two txs succeed, third reverts.
        bytes[] memory txs = new bytes[](3);
        txs[0] = _encodeTx(address(target1), abi.encodeWithSelector(MockBTTarget.setValue.selector, 100));
        txs[1] = _encodeTx(address(target2), abi.encodeWithSelector(MockBTTarget.setValue.selector, 200));
        txs[2] = _encodeTx(address(target1), abi.encodeWithSelector(MockBTTarget.revertingFunction.selector));

        // Call: execute batch.
        (bool success,) = _executeBatchViaDelegatecall(_encodeBatch(txs));

        // Verify: all side effects rolled back.
        assertFalse(success, "Batch should fail");
        assertEq(target1.value(), 0, "Target1 value should be rolled back to 0");
        assertEq(target2.value(), 0, "Target2 value should be rolled back to 0");
        assertEq(target1.callCount(), 0, "Target1 call count should be 0");
        assertEq(target2.callCount(), 0, "Target2 call count should be 0");
    }

    /// @dev Verifies failed execution never returns success=true (no silent partial failure).
    function test_BT_ESF_11_executeFailedExecutionNeverReturnsTrue() public {
        // Setup: reverting sub-transaction.
        bytes memory encoded =
            _encodeTx(address(target1), abi.encodeWithSelector(MockBTTarget.revertingFunction.selector));

        // Call: execute batch.
        (bool success,) = _executeBatchViaDelegatecall(encoded);

        // Verify: success is false (never silently returns true on failure).
        assertFalse(success, "Failed execution must never return success=true");
    }

    /// @dev Verifies malformed first transaction causes revert before any external call.
    function test_BT_EMB_3_executeMalformedFirstTxRevertsBeforeExternalCall() public {
        // Setup: encode a batch where first tx is a reverting function, ensuring no state change.
        bytes memory encoded =
            _encodeTx(address(target1), abi.encodeWithSelector(MockBTTarget.revertingFunction.selector));

        // Call: execute batch.
        (bool success,) = _executeBatchViaDelegatecall(encoded);

        // Verify: reverted and no state changes occurred.
        assertFalse(success, "Malformed/reverting first tx should revert");
        assertEq(target1.callCount(), 0, "No external calls should have succeeded");
    }

    /// @dev Verifies malformed later transaction reverts and rolls back earlier successful sub-calls.
    function test_BT_EMB_4_executeMalformedLaterTxRollsBackEarlier() public {
        // Setup: first tx succeeds, second tx reverts.
        bytes[] memory txs = new bytes[](2);
        txs[0] = _encodeTx(address(target1), abi.encodeWithSelector(MockBTTarget.setValue.selector, 42));
        txs[1] = _encodeTx(address(target1), abi.encodeWithSelector(MockBTTarget.revertingFunction.selector));

        // Call: execute batch.
        (bool success,) = _executeBatchViaDelegatecall(_encodeBatch(txs));

        // Verify: all side effects rolled back.
        assertFalse(success, "Later reverting tx should fail entire batch");
        assertEq(target1.value(), 0, "Earlier successful sub-call should be rolled back");
    }

    /// @dev Verifies exact boundary case: header-only entry with dataLength=0 is accepted.
    function test_BT_EMB_6_executeHeaderOnlyWithZeroDataLength() public {
        // Setup: encode a sub-transaction with dataLength=0 targeting a fallback-accepting contract.
        EmptyCallTarget emptyTarget = new EmptyCallTarget();
        bytes memory headerOnly = abi.encodePacked(address(emptyTarget), uint64(0));
        require(headerOnly.length == 28, "Header should be exactly 28 bytes");

        // Call: execute header-only entry.
        (bool success,) = _executeBatchViaDelegatecall(headerOnly);

        // Verify: call succeeds via target's fallback.
        assertTrue(success, "Header-only entry with dataLength=0 should succeed");
        assertTrue(emptyTarget.wasCalled(), "Target fallback should have been called");
    }

    /// @dev Verifies offset/length confusion cannot bypass self-call block (CannotCallSafe).
    function test_ASIG_INV_9_D_BT_EMB_8_executeOffsetLengthConfusionCannotBypassSelfCallBlock() public {
        EmptyCallTarget emptyTarget = new EmptyCallTarget();
        bytes4 expectedSelector = IBatchedTransaction.CannotCallSafe.selector;

        // Attempt 1: 4 bytes of truncated data before address(this).
        // dataLength=4 causes the parser to consume only 4 bytes, then read
        // address(this) directly as the next entry's `to`.
        //   [emptyTarget:20][len=4:8][0xdeadbeef:4][address(this):20][0:8]
        {
            bytes memory crafted = abi.encodePacked(
                address(emptyTarget), uint64(4), bytes4(0xdeadbeef), address(this), uint64(0)
            );
            (bool success, bytes memory returnData) = _executeBatchViaDelegatecall(crafted);
            assertFalse(success, "Attempt 1: should revert");
            bytes4 selector;
            assembly {
                selector := mload(add(returnData, 32))
            }
            assertEq(selector, expectedSelector, "Attempt 1: should be CannotCallSafe");
        }

        // Attempt 2: 32 bytes of misaligned data before address(this).
        // dataLength=32 absorbs a full ABI-argument-sized region, then the parser
        // reads address(this) at the boundary immediately after.
        //   [emptyTarget:20][len=32:8][32B data][address(this):20][0:8]
        {
            bytes memory crafted = abi.encodePacked(
                address(emptyTarget),
                uint64(32),
                bytes32(uint256(0xdeadbeefcafebabe)),
                address(this),
                uint64(0)
            );
            (bool success, bytes memory returnData) = _executeBatchViaDelegatecall(crafted);
            assertFalse(success, "Attempt 2: should revert");
            bytes4 selector;
            assembly {
                selector := mload(add(returnData, 32))
            }
            assertEq(selector, expectedSelector, "Attempt 2: should be CannotCallSafe");
        }

        // Attempt 3: phantom intermediate entry between truncated data and address(this).
        // After entry 1's truncated 4-byte data, the next 28 bytes form a phantom entry
        // (codeless address + len=0) whose call succeeds (EVM calls to codeless addresses
        // return success), then address(this) appears as entry 3's `to`.
        //   [emptyTarget:20][len=4:8][0xdeadbeef:4][phantom:20][0:8][address(this):20][0:8]
        {
            bytes memory crafted = abi.encodePacked(
                address(emptyTarget),
                uint64(4),
                bytes4(0xdeadbeef),
                address(uint160(0xdead)),
                uint64(0),
                address(this),
                uint64(0)
            );
            (bool success, bytes memory returnData) = _executeBatchViaDelegatecall(crafted);
            assertFalse(success, "Attempt 3: should revert");
            bytes4 selector;
            assembly {
                selector := mload(add(returnData, 32))
            }
            assertEq(selector, expectedSelector, "Attempt 3: should be CannotCallSafe");
        }
    }

    /// @dev Verifies malformed payload must not silently succeed using zero-padded calldata.
    function test_BT_EMB_9_executeMalformedPayloadDoesNotSilentlySucceed() public {
        // Setup: valid header with dataLength pointing to non-existent data (only zeros from padding).
        // This tests that zero-padded reads don't cause silent success with wrong calldata.
        bytes memory encoded = abi.encodePacked(
            address(target1),
            uint64(4) // declares 4 bytes of data
            // but NO actual data bytes follow — calldatacopy reads zeros/garbage
        );

        // Call: execute with missing data bytes after header.
        (bool success,) = _executeBatchViaDelegatecall(encoded);

        // Verify: zero-padded selector (0x00000000) matches no function on target and there is no
        // fallback, so the call reverts and the batch fails.
        assertFalse(success, "Malformed payload with zero-padded selector should not silently succeed");
    }

    /// @dev Verifies bounded packed batches with fuzzed calldata lengths terminate while preserving exact field
    ///      decoding under delegatecall execution. [ASIG-INV-14]
    function testFuzz_ASIG_INV_14_C__FBT_EXEC_159_executeBatchFieldDecodingForwardsExactToAndData(
        uint8 rawCount,
        bytes32 seed
    ) public {
        uint8 count = uint8(bound(rawCount, 1, 6));
        CalldataRecorderTarget[] memory targets = new CalldataRecorderTarget[](count);
        bytes[] memory txs = new bytes[](count);
        bytes[] memory expectedCalldata = new bytes[](count);

        // Setup: build N packed sub-transactions with deterministic fuzz-derived calldata for distinct targets.
        for (uint256 i = 0; i < count; i++) {
            targets[i] = new CalldataRecorderTarget();
            uint256 dataLength = uint256(uint8(uint256(keccak256(abi.encodePacked(seed, i))))) % 48;
            expectedCalldata[i] = _buildFuzzedCalldata(seed, i, dataLength);
            txs[i] = _encodeTx(address(targets[i]), expectedCalldata[i]);
        }

        // Call: execute the fuzz-derived packed batch through delegatecall mode.
        (bool success,) = _executeBatchViaDelegatecall(_encodeBatch(txs));

        // Verify: each target is called exactly once and receives the exact bytes encoded for its entry.
        assertTrue(success, "Well-formed fuzz batch should succeed");
        for (uint256 i = 0; i < count; i++) {
            assertEq(targets[i].callCount(), 1, "Each target should be called exactly once");
            assertEq(targets[i].lastCaller(), address(this), "Delegatecall mode should preserve the safe caller");
            assertEq(targets[i].lastCalldata(), expectedCalldata[i], "Target should receive the exact encoded data");
        }
    }

    /// @dev Verifies malformed packed payload tails revert atomically without preserving earlier successful effects.
    /// @param rawValidPrefixCount The number of valid prefix sub-transactions prepended before the malformed tail.
    function testFuzz_FBT_EXEC_158_malformedPackedPayloadsRevertAtomically(uint8 rawValidPrefixCount) public {
        uint8 validPrefixCount = uint8(bound(rawValidPrefixCount, 1, 4));
        MockBTTarget[] memory targets = new MockBTTarget[](validPrefixCount);
        bytes[] memory prefixTxs = new bytes[](validPrefixCount);

        // Setup: build a valid prefix of increment calls whose effects would be visible if atomic rollback failed.
        for (uint256 i = 0; i < validPrefixCount; ++i) {
            targets[i] = new MockBTTarget();
            prefixTxs[i] = _encodeTx(address(targets[i]), abi.encodeWithSelector(MockBTTarget.increment.selector));
        }

        // Append a malformed tail whose declared calldata length exceeds the provided bytes and resolves to an
        // invalid selector on a contract without fallback.
        MockBTTarget malformedTarget = new MockBTTarget();
        bytes memory malformedTail = abi.encodePacked(address(malformedTarget), uint64(4), hex"ff");
        bytes memory malformedBatch = bytes.concat(_encodeBatch(prefixTxs), malformedTail);

        // Call: execute the prefix plus malformed tail through delegatecall mode.
        (bool success,) = _executeBatchViaDelegatecall(malformedBatch);

        // Verify: the malformed tail fails the batch and rolls back every earlier prefix side effect.
        assertFalse(success, "malformed packed payload should fail the batch");
        for (uint256 i = 0; i < validPrefixCount; ++i) {
            assertEq(targets[i].value(), 0, "prefix effects must be rolled back atomically");
            assertEq(targets[i].callCount(), 0, "prefix calls must not persist after malformed-tail revert");
        }
    }

    /// @dev Verifies a well-formed packed batch executes every encoded sub-tx exactly once with no skips or
    ///      repeats. [ASIG-INV-15]
    function testFuzz_ASIG_INV_15_C_executeWellFormedBatchExecutesEachSubTxExactlyOnce(uint8 rawCount) public {
        uint8 count = uint8(bound(rawCount, 1, 8));
        MockBTTarget[] memory targets = new MockBTTarget[](count);
        bytes[] memory txs = new bytes[](count);

        // Setup: build N increment calls targeting fresh counters so each successful sub-tx is independently visible.
        for (uint256 i = 0; i < count; i++) {
            targets[i] = new MockBTTarget();
            txs[i] = _encodeTx(address(targets[i]), abi.encodeWithSelector(MockBTTarget.increment.selector));
        }

        // Call: execute the packed batch through delegatecall mode.
        (bool success,) = _executeBatchViaDelegatecall(_encodeBatch(txs));

        // Verify: every encoded target increments exactly once and records exactly one observed call.
        assertTrue(success, "Well-formed fuzz batch should succeed");
        for (uint256 i = 0; i < count; i++) {
            assertEq(targets[i].value(), 1, "Each counter should be incremented exactly once");
            assertEq(targets[i].callCount(), 1, "No target should be skipped or called more than once");
        }
    }

    /// @dev Verifies every fallback-shaped sub-call executes with `msg.value == 0` regardless of payload bytes.
    /// @param rawCount The bounded number of fallback targets in the fuzzed batch.
    /// @param seed Entropy used to derive distinct fallback calldata payloads.
    function testFuzz_FBT_EXEC_160_executeSubcallsAlwaysUseZeroValueRegardlessOfPayloadShape(
        uint8 rawCount,
        bytes32 seed
    ) public {
        uint8 count = uint8(bound(rawCount, 1, 6));
        CalldataValueRecorderTarget[] memory targets = new CalldataValueRecorderTarget[](count);
        bytes[] memory txs = new bytes[](count);
        bytes[] memory expectedCalldata = new bytes[](count);

        // Setup: fund the delegatecaller and build fallback calls with fuzz-derived payload lengths and bytes.
        vm.deal(address(this), 5 ether);
        for (uint256 i = 0; i < count; ++i) {
            targets[i] = new CalldataValueRecorderTarget();
            uint256 dataLength = uint256(uint8(uint256(keccak256(abi.encodePacked(seed, i))))) % 48;
            expectedCalldata[i] = _buildFuzzedCalldata(seed, i, dataLength);
            txs[i] = _encodeTx(address(targets[i]), expectedCalldata[i]);
        }

        // Call: execute the fuzz-shaped fallback batch through delegatecall mode.
        (bool success,) = _executeBatchViaDelegatecall(_encodeBatch(txs));

        // Verify: all fallback targets are reached with the exact calldata bytes and a hardcoded zero msg.value.
        assertTrue(success, "well-formed fallback batch should succeed");
        for (uint256 i = 0; i < count; ++i) {
            assertEq(targets[i].callCount(), 1, "each fallback target should be called exactly once");
            assertEq(targets[i].lastCalldata(), expectedCalldata[i], "fallback should receive the encoded calldata");
            assertEq(targets[i].lastMsgValue(), 0, "sub-calls must always execute with zero value");
        }
    }

}
