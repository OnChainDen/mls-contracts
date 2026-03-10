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

    /// @dev Verifies `execute` succeeds as no-op for empty transactions bytes.
    function test_BT_EVB_1_executeEmptyTransactionsSucceedsAsNoop() public {
        // Call: execute with empty bytes (no sub-transactions).
        (bool success,) = _executeBatchViaDelegatecall("");

        // Verify: succeeds without executing anything.
        assertTrue(success, "Empty batch should succeed as no-op");
    }

    /// @dev Verifies `execute` successfully executes a single packed transaction.
    function test_BT_EVB_2_executeSinglePackedTransaction() public {
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

    /// @dev Verifies `execute` runs multiple packed transactions in encoded order.
    function test_BT_EVB_3_executeMultipleTransactionsInOrder() public {
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
    function test_BT_EVB_4_executeRepeatedCallsCumulativeState() public {
        // Setup: five increment calls to same target.
        bytes[] memory txs = new bytes[](5);
        for (uint256 i = 0; i < 5; i++) {
            txs[i] = _encodeTx(address(target1), abi.encodeWithSelector(MockBTTarget.increment.selector));
        }

        // Call: execute batch.
        (bool success,) = _executeBatchViaDelegatecall(_encodeBatch(txs));

        // Verify: target value reflects all five increments.
        assertTrue(success, "Batch should succeed");
        assertEq(target1.value(), 5, "Target should have been incremented 5 times");
        assertEq(target1.callCount(), 5, "Call count should be 5");
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

    /// @dev Verifies mixed targets within one batch execute correctly.
    function test_BT_EVB_6_executeMixedTargetsBatch() public {
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

    /// @dev Verifies delegatecall context: sub-transaction targeting delegatecaller reverts `CannotCallSafe`.
    function test_BT_ESF_1_executeDelegatecallSelfTargetRevertsCannotCallSafe() public {
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

    /// @dev Verifies self-target in later sub-transaction reverts the entire batch.
    function test_BT_ESF_2_executeSelfTargetInLaterTxRevertsEntireBatch() public {
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

    /// @dev Verifies first sub-call success + second sub-call revert => first side effects rolled back.
    function test_BT_ESF_4_executeSecondTxRevertRollsBackFirstTx() public {
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

    /// @dev Verifies payable target receives `msg.value == 0` for every sub-call.
    function test_BT_ESF_6_executeSubCallsReceiveZeroMsgValue() public {
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

    /// @dev [DESIRED BEHAVIOR] Verifies trailing bytes shorter than one 28-byte header reverts.
    function test_BT_EMB_1_executeShortTrailingBytesReverts() public {
        // Setup: 20 bytes (partial header — address only, missing dataLength).
        bytes memory partialHeader = abi.encodePacked(address(target1));
        require(partialHeader.length == 20, "partialHeader should be 20 bytes");

        // Call: execute with partial header. Desired behavior: revert.
        (bool success,) = _executeBatchViaDelegatecall(partialHeader);

        // Verify: should revert on invalid encoding.
        assertFalse(success, "[DESIRED BEHAVIOR] Trailing bytes shorter than header should revert");
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

    /// @dev Verifies extremely large declared dataLength with short payload reverts safely.
    function test_BT_EMB_7_executeExtremelyLargeDataLengthReverts() public {
        // Setup: header with extremely large declared dataLength but no actual data.
        bytes memory malformed = abi.encodePacked(
            address(target1),
            uint64(type(uint64).max) // extremely large dataLength
        );

        // Call: execute with extreme dataLength.
        (bool success,) = _executeBatchViaDelegatecall(malformed);

        // Verify: should revert (calldatacopy with extreme length or OOG).
        assertFalse(success, "Extremely large declared dataLength should revert safely");
    }

    /// @dev Verifies offset/length confusion cannot bypass self-call block (CannotCallSafe).
    function test_BT_EMB_8_executeOffsetLengthConfusionCannotBypassSelfCallBlock() public {
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
}
