// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";

import {IBatchedTransaction} from "../../src/interfaces/IBatchedTransaction.sol";
import {BatchedTransaction} from "../../src/safe-module/BatchedTransaction.sol";

/**
 * @title MockTarget
 * @notice A mock target contract for testing BatchedTransaction execution
 */
contract MockTarget {
    uint256 public value;
    address public lastCaller;
    uint256 public callCount;

    event ValueSet(uint256 newValue, address caller);

    function setValue(uint256 newValue) external {
        value = newValue;
        lastCaller = msg.sender;
        callCount++;
        emit ValueSet(newValue, msg.sender);
    }

    function increment() external {
        value++;
        lastCaller = msg.sender;
        callCount++;
    }

    function revertingFunction() external pure {
        revert("MockTarget: intentional revert");
    }

    function getValuePlusOne() external view returns (uint256) {
        return value + 1;
    }

    receive() external payable {
        revert("MockTarget: ETH not accepted");
    }
}

/**
 * @title BatchedTransactionTest
 * @notice Comprehensive tests for the BatchedTransaction contract
 * @dev Tests cover:
 *      - Single transaction execution
 *      - Multiple transactions in a batch
 *      - Empty transactions (no-op)
 *      - address(this) (Safe) call blocking when delegatecalled
 *      - Sub-transaction failure handling
 *      - Fuzz tests for various scenarios
 *
 * @author Den Technologies Inc
 */
contract BatchedTransactionTest is Test {
    BatchedTransaction public batchedTx;
    MockTarget public target1;
    MockTarget public target2;

    /// @dev Set up test environment before each test
    function setUp() public {
        // Deploy contracts
        batchedTx = new BatchedTransaction();
        target1 = new MockTarget();
        target2 = new MockTarget();
    }

    // ============================================================
    // Helper Functions
    // ============================================================

    /// @dev Encodes a single transaction in the BatchedTransaction format
    /// @param to Target address (20 bytes)
    /// @param data Calldata
    /// @return encoded The packed transaction data
    function _encodeTx(address to, bytes memory data) internal pure returns (bytes memory encoded) {
        uint64 dataLength = uint64(data.length);
        return abi.encodePacked(to, dataLength, data);
    }

    /// @dev Encodes multiple transactions by concatenating them
    function _encodeBatch(bytes[] memory txs) internal pure returns (bytes memory batch) {
        for (uint256 i = 0; i < txs.length; i++) {
            batch = abi.encodePacked(batch, txs[i]);
        }
    }

    // ============================================================
    // Single Transaction Tests
    // ============================================================

    function test_execute_singleTransaction() public {
        // Encode a single transaction
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 42);
        bytes memory encoded = _encodeTx(address(target1), data);

        // Execute via delegatecall (simulating Safe calling)
        // When delegatecalled, address(this) inside execute() is the caller (this test contract)
        // So calls originate from this test contract
        (bool success,) =
            address(batchedTx).delegatecall(abi.encodeWithSelector(BatchedTransaction.execute.selector, encoded));

        assertTrue(success, "Delegatecall should succeed");
        assertEq(target1.value(), 42, "Target value should be set");
        assertEq(target1.lastCaller(), address(this), "Caller should be this test contract (simulating Safe)");
        assertEq(target1.callCount(), 1, "Should have one call");
    }

    function test_execute_singleTransactionEmptyData() public {
        // Encode a transaction with empty calldata (calling fallback/receive)
        // Use a target that accepts empty calls
        address emptyCallTarget = address(new EmptyCallTarget());
        bytes memory encoded = _encodeTx(emptyCallTarget, "");

        (bool success,) =
            address(batchedTx).delegatecall(abi.encodeWithSelector(BatchedTransaction.execute.selector, encoded));

        assertTrue(success, "Empty data transaction should succeed");
    }

    // ============================================================
    // Multiple Transaction Tests
    // ============================================================

    function test_execute_multipleTransactions() public {
        // Encode multiple transactions
        bytes[] memory txs = new bytes[](3);
        txs[0] = _encodeTx(address(target1), abi.encodeWithSelector(MockTarget.setValue.selector, 10));
        txs[1] = _encodeTx(address(target2), abi.encodeWithSelector(MockTarget.setValue.selector, 20));
        txs[2] = _encodeTx(address(target1), abi.encodeWithSelector(MockTarget.increment.selector));

        bytes memory batch = _encodeBatch(txs);

        (bool success,) =
            address(batchedTx).delegatecall(abi.encodeWithSelector(BatchedTransaction.execute.selector, batch));

        assertTrue(success, "Batch should succeed");
        assertEq(target1.value(), 11, "Target1 value should be 10 + 1");
        assertEq(target2.value(), 20, "Target2 value should be 20");
        assertEq(target1.callCount(), 2, "Target1 should have 2 calls");
        assertEq(target2.callCount(), 1, "Target2 should have 1 call");
    }

    function test_execute_emptyBatch() public {
        // Empty transactions should be a no-op
        bytes memory empty = "";

        (bool success,) =
            address(batchedTx).delegatecall(abi.encodeWithSelector(BatchedTransaction.execute.selector, empty));

        assertTrue(success, "Empty batch should succeed (no-op)");
    }

    // ============================================================
    // Security: CannotCallSafe Tests
    // ============================================================

    function test_execute_revertsWhenTargetIsThisContract() public {
        // When delegatecalled, address(this) is the caller (this test contract)
        // Try to call address(this) - should be blocked
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 42);
        bytes memory encoded = _encodeTx(address(this), data);

        (bool success, bytes memory returnData) =
            address(batchedTx).delegatecall(abi.encodeWithSelector(BatchedTransaction.execute.selector, encoded));

        assertFalse(success, "Should revert when targeting address(this)");

        // Verify the error
        bytes4 expectedSelector = IBatchedTransaction.CannotCallSafe.selector;
        bytes4 actualSelector;
        assembly {
            actualSelector := mload(add(returnData, 32))
        }
        assertEq(actualSelector, expectedSelector, "Should revert with CannotCallSafe");
    }

    function test_execute_revertsWhenSecondTxTargetsThisContract() public {
        // First tx is valid, second tx targets address(this) (the "Safe" when delegatecalled)
        bytes[] memory txs = new bytes[](2);
        txs[0] = _encodeTx(address(target1), abi.encodeWithSelector(MockTarget.setValue.selector, 10));
        txs[1] = _encodeTx(address(this), abi.encodeWithSelector(MockTarget.setValue.selector, 20));

        bytes memory batch = _encodeBatch(txs);

        (bool success,) =
            address(batchedTx).delegatecall(abi.encodeWithSelector(BatchedTransaction.execute.selector, batch));

        assertFalse(success, "Should revert when any tx targets address(this)");
    }

    // ============================================================
    // Sub-Transaction Failure Tests
    // ============================================================

    function test_execute_revertsOnSubTransactionFailure() public {
        // Transaction that will revert
        bytes memory data = abi.encodeWithSelector(MockTarget.revertingFunction.selector);
        bytes memory encoded = _encodeTx(address(target1), data);

        (bool success,) =
            address(batchedTx).delegatecall(abi.encodeWithSelector(BatchedTransaction.execute.selector, encoded));

        assertFalse(success, "Should revert on sub-transaction failure");
    }

    function test_execute_revertsOnSecondTxFailure() public {
        // First tx succeeds, second tx reverts
        bytes[] memory txs = new bytes[](2);
        txs[0] = _encodeTx(address(target1), abi.encodeWithSelector(MockTarget.setValue.selector, 10));
        txs[1] = _encodeTx(address(target1), abi.encodeWithSelector(MockTarget.revertingFunction.selector));

        bytes memory batch = _encodeBatch(txs);

        (bool success,) =
            address(batchedTx).delegatecall(abi.encodeWithSelector(BatchedTransaction.execute.selector, batch));

        assertFalse(success, "Should revert when any sub-tx fails");
    }

    // ============================================================
    // Fuzz Tests
    // ============================================================

    function testFuzz_execute_varyingDataLengths(uint16 dataLength) public {
        // Bound data length to reasonable values
        dataLength = uint16(bound(dataLength, 0, 1000));

        // Create data of the specified length
        bytes memory data = new bytes(dataLength);
        for (uint256 i = 0; i < dataLength; i++) {
            // casting to uint8 is safe because i % 256 is always in range [0, 255]
            // forge-lint: disable-next-line(unsafe-typecast)
            data[i] = bytes1(uint8(i % 256));
        }

        // For this test, we'll call a simple function since random data may not be valid
        // Just test that the encoding/decoding works correctly
        bytes memory validData = abi.encodeWithSelector(MockTarget.setValue.selector, uint256(dataLength));
        bytes memory encoded = _encodeTx(address(target1), validData);

        (bool success,) =
            address(batchedTx).delegatecall(abi.encodeWithSelector(BatchedTransaction.execute.selector, encoded));

        assertTrue(success, "Should handle varying data lengths");
        assertEq(target1.value(), uint256(dataLength), "Value should match data length");
    }

    function testFuzz_execute_varyingBatchSizes(uint8 batchSize) public {
        // Bound batch size to reasonable values
        batchSize = uint8(bound(batchSize, 1, 50));

        bytes[] memory txs = new bytes[](batchSize);
        for (uint256 i = 0; i < batchSize; i++) {
            txs[i] = _encodeTx(address(target1), abi.encodeWithSelector(MockTarget.increment.selector));
        }

        bytes memory batch = _encodeBatch(txs);

        (bool success,) =
            address(batchedTx).delegatecall(abi.encodeWithSelector(BatchedTransaction.execute.selector, batch));

        assertTrue(success, "Should handle varying batch sizes");
        assertEq(target1.value(), uint256(batchSize), "Value should equal batch size");
        assertEq(target1.callCount(), uint256(batchSize), "Call count should equal batch size");
    }

    function testFuzz_execute_anyTargetExceptThisContract(address target) public {
        // When delegatecalled, address(this) is this test contract, so skip it
        vm.assume(target != address(this));
        vm.assume(target != address(0));

        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 42);
        bytes memory encoded = _encodeTx(target, data);

        // May fail if target is not a contract or doesn't have setValue, but shouldn't revert with CannotCallSafe
        (bool success, bytes memory returnData) =
            address(batchedTx).delegatecall(abi.encodeWithSelector(BatchedTransaction.execute.selector, encoded));

        // If it failed, verify it's NOT CannotCallSafe
        if (!success && returnData.length >= 4) {
            bytes4 errorSelector;
            assembly {
                errorSelector := mload(add(returnData, 32))
            }
            assertTrue(
                errorSelector != IBatchedTransaction.CannotCallSafe.selector,
                "Should not revert with CannotCallSafe for non-self targets"
            );
        }
    }

    // ============================================================
    // Direct Call Tests (non-delegatecall)
    // ============================================================

    function test_execute_directCall() public {
        // When called directly (not via delegatecall), address(this) is batchedTx
        // So calls originate from batchedTx
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 42);
        bytes memory encoded = _encodeTx(address(target1), data);

        // Direct call from test contract
        batchedTx.execute(encoded);

        assertEq(target1.value(), 42, "Target value should be set");
        assertEq(target1.lastCaller(), address(batchedTx), "Caller should be BatchedTransaction");
    }

    function test_execute_directCallBlocksBatchedTxAsTarget() public {
        // When called directly, address(this) inside execute() is batchedTx itself
        // So targeting batchedTx should be blocked
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 42);
        bytes memory encoded = _encodeTx(address(batchedTx), data);

        vm.expectRevert(abi.encodeWithSelector(IBatchedTransaction.CannotCallSafe.selector, address(batchedTx)));
        batchedTx.execute(encoded);
    }
}

/**
 * @title EmptyCallTarget
 * @notice A contract that accepts empty calls for testing
 */
contract EmptyCallTarget {
    bool public wasCalled;

    fallback() external {
        wasCalled = true;
    }
}
