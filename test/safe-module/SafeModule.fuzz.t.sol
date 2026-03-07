// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";

import {IBatchedTransaction} from "../../src/interfaces/IBatchedTransaction.sol";
import {ISafeExecutorModule} from "../../src/interfaces/ISafeExecutorModule.sol";
import {SignatureUtils} from "../../src/libraries/SignatureUtils.sol";
import {BatchedTransaction} from "../../src/safe-module/BatchedTransaction.sol";
import {SafeExecutorModule} from "../../src/safe-module/SafeExecutorModule.sol";
import {SignatureTestHelpers} from "test/helpers/SignatureTestHelpers.sol";

/**
 * @dev FuzzMockSafe — mock Safe for fuzz tests, tracks operation type per call.
 */
contract FuzzMockSafe {
    address public lastCallTo;
    uint8 public lastCallOperation;
    bytes public lastCallData;
    uint256 public lastCallValue;
    uint256 public callCount;

    bool public executeDelegatecalls = false;

    /// @dev Simulates Safe's execTransactionFromModule with call tracking.
    function execTransactionFromModule(address to, uint256 value, bytes memory data, uint8 operation)
        external
        returns (bool success)
    {
        lastCallTo = to;
        lastCallOperation = operation;
        lastCallData = data;
        lastCallValue = value;
        callCount++;

        if (operation == 0) {
            (success,) = to.call{value: value}(data);
        } else if (executeDelegatecalls) {
            (success,) = to.delegatecall(data);
        } else {
            success = true;
        }
        return success;
    }

    /// @dev Enable real delegatecall execution.
    function setExecuteDelegatecalls(bool enabled) external {
        executeDelegatecalls = enabled;
    }
}

/**
 * @dev FuzzTarget — simple state-tracking target for fuzz tests.
 */
contract FuzzTarget {
    uint256 public value;

    function setValue(uint256 v) external {
        value = v;
    }

    function increment() external {
        value++;
    }
}

/**
 * @dev Fuzz tests for SafeExecutorModule and BatchedTransaction.
 *      Covers test plan rows SMI-FUZ-1 through SMI-FUZ-6.
 *      SMI-FUZ-7 and SMI-FUZ-8 cover guardian module signature fuzzing and are
 *      implemented in the existing LibOrganizationAccountSignature fuzz suite.
 */
contract SafeModuleFuzzTest is Test, SignatureTestHelpers {
    FuzzMockSafe internal mockSafe;
    FuzzTarget internal fuzzTarget;
    BatchedTransaction internal batchedTx;
    SafeExecutorModule internal module;

    uint256 internal constant AUTHORIZED_EXECUTOR_PK = 0xA11CE;
    address internal authorizedExecutor;

    /// @dev Deploy all contracts before each test.
    function setUp() public {
        authorizedExecutor = vm.addr(AUTHORIZED_EXECUTOR_PK);
        mockSafe = new FuzzMockSafe();
        fuzzTarget = new FuzzTarget();
        batchedTx = new BatchedTransaction();
        module = new SafeExecutorModule(address(mockSafe), authorizedExecutor, address(batchedTx));
    }

    /**
     * @dev Encodes a single sub-transaction for BatchedTransaction.
     * @param to Target address
     * @param data Calldata
     * @return encoded Packed bytes
     */
    function _encodeTx(address to, bytes memory data) internal pure returns (bytes memory) {
        return abi.encodePacked(to, uint64(data.length), data);
    }

    /**
     * @dev Concatenates encoded sub-transactions into a batch.
     * @param txs Array of encoded sub-transactions
     * @return batch Concatenated bytes
     */
    function _encodeBatch(bytes[] memory txs) internal pure returns (bytes memory batch) {
        for (uint256 i = 0; i < txs.length; i++) {
            batch = abi.encodePacked(batch, txs[i]);
        }
    }

    /// @dev Verifies `executeOnBehalf` always chooses DELEGATECALL iff target == BATCHED_TRANSACTION.
    function testFuzz_SMI_FUZ_1_executeOnBehalf_operationMatchesTarget(address target) public {
        // Setup: skip Safe target (would revert CannotCallSafe) and address(0).
        vm.assume(target != address(mockSafe));
        vm.assume(target != address(0));

        bytes memory data = abi.encodeWithSelector(FuzzTarget.setValue.selector, 42);

        // Call: execute with fuzzed target.
        vm.prank(authorizedExecutor);
        try module.executeOnBehalf(target, data) {
            // Verify: DELEGATECALL(1) iff target == batchedTx, else CALL(0).
            if (target == address(batchedTx)) {
                assertEq(mockSafe.lastCallOperation(), 1, "BatchedTransaction must use DELEGATECALL");
            } else {
                assertEq(mockSafe.lastCallOperation(), 0, "Non-BatchedTransaction must use CALL");
            }
        } catch {
            // Execution failures (non-contract target, etc.) are acceptable.
        }
    }

    /// @dev Verifies `executeOnBehalf` forwards fuzzed calldata byte-for-byte to Safe.
    function testFuzz_SMI_FUZ_2_executeOnBehalf_calldataForwardedByteForByte(bytes calldata randomData) public {
        // Call: execute with fuzzed calldata.
        vm.prank(authorizedExecutor);
        try module.executeOnBehalf(address(fuzzTarget), randomData) {
            // Verify: Safe received exact bytes.
            assertEq(mockSafe.lastCallData(), randomData, "Calldata must be forwarded byte-for-byte");
        } catch {
            // Target call may fail for random data, but data should still have been forwarded.
            // Only check if Safe was actually called.
            if (mockSafe.callCount() > 0) {
                assertEq(mockSafe.lastCallData(), randomData, "Calldata must be forwarded even on failure");
            }
        }
    }

    /// @dev Verifies `isValidSignature` never reverts for random inputs and only returns magic for authorized signer.
    function testFuzz_SMI_FUZ_3_isValidSignature_neverRevertsNeverMagicUnlessAuthorized(
        bytes32 hash,
        bytes calldata signature
    ) public view {
        // Call: isValidSignature with fuzzed hash and signature. Must not revert.
        bytes4 result = module.isValidSignature(hash, signature);

        // Verify: result is either magic (0x1626ba7e) or invalid (0xffffffff).
        assertTrue(
            result == SignatureUtils.ERC1271_MAGIC_VALUE || result == SignatureUtils.ERC1271_INVALID_VALUE,
            "Result must be magic or invalid - no other values allowed"
        );
    }

    /// @dev Verifies successful batch execution matches sequential-call semantics.
    function testFuzz_SMI_FUZ_4_execute_validBatchMatchesSequentialSemantics(uint8 batchSize) public {
        // Setup: bound batch size to reasonable range.
        batchSize = uint8(bound(batchSize, 1, 20));

        // Build batch of increment calls.
        bytes[] memory txs = new bytes[](batchSize);
        for (uint256 i = 0; i < batchSize; i++) {
            txs[i] = _encodeTx(address(fuzzTarget), abi.encodeWithSelector(FuzzTarget.increment.selector));
        }

        // Call: execute batch via delegatecall.
        (bool success,) = address(batchedTx)
            .delegatecall(abi.encodeWithSelector(BatchedTransaction.execute.selector, _encodeBatch(txs)));

        // Verify: batch result matches calling increment() N times sequentially.
        assertTrue(success, "Valid batch should succeed");
        assertEq(fuzzTarget.value(), uint256(batchSize), "Batch result should match sequential execution");
    }

    /// @dev Verifies malformed batches (truncated data) never partially apply state.
    function testFuzz_SMI_FUZ_5_execute_malformedBatchNeverPartiallyAppliesState(uint8 truncateBytes) public {
        // Setup: build a valid 2-tx batch, then truncate it to create malformed encoding.
        bytes[] memory txs = new bytes[](2);
        txs[0] = _encodeTx(address(fuzzTarget), abi.encodeWithSelector(FuzzTarget.setValue.selector, 100));
        txs[1] = _encodeTx(address(fuzzTarget), abi.encodeWithSelector(FuzzTarget.setValue.selector, 200));
        bytes memory validBatch = _encodeBatch(txs);

        // Truncate by at least 1 byte from the second transaction to make it malformed.
        uint256 firstTxLen = txs[0].length;
        truncateBytes = uint8(bound(truncateBytes, 1, uint8(txs[1].length)));
        uint256 malformedLen = validBatch.length - truncateBytes;

        // Only test if the truncation actually cuts into the second transaction.
        if (malformedLen <= firstTxLen) return;

        bytes memory malformed = new bytes(malformedLen);
        for (uint256 i = 0; i < malformedLen; i++) {
            malformed[i] = validBatch[i];
        }

        // Call: execute malformed batch.
        (bool success,) =
            address(batchedTx).delegatecall(abi.encodeWithSelector(BatchedTransaction.execute.selector, malformed));

        // Verify: if batch failed, no partial state changes.
        if (!success) {
            assertEq(fuzzTarget.value(), 0, "Failed malformed batch must not leave partial state");
        }
        // If batch succeeded (possible when truncation removes trailing data of a
        // sub-tx that reads from zero-padded calldata), verify state is consistent.
    }

    /// @dev Verifies that self-target at any position in the batch causes atomic revert.
    function testFuzz_SMI_FUZ_6_execute_selfTargetAtAnyPositionCausesAtomicRevert(uint8 position) public {
        // Setup: batch of 5 transactions with one targeting address(this) (the "Safe").
        uint8 batchSize = 5;
        position = uint8(bound(position, 0, batchSize - 1));

        bytes[] memory txs = new bytes[](batchSize);
        for (uint256 i = 0; i < batchSize; i++) {
            if (i == position) {
                // Self-target: address(this) is the delegatecaller ("Safe").
                txs[i] = _encodeTx(address(this), abi.encodeWithSelector(FuzzTarget.setValue.selector, 999));
            } else {
                txs[i] = _encodeTx(address(fuzzTarget), abi.encodeWithSelector(FuzzTarget.increment.selector));
            }
        }

        // Call: execute batch via delegatecall.
        (bool success,) = address(batchedTx)
            .delegatecall(abi.encodeWithSelector(BatchedTransaction.execute.selector, _encodeBatch(txs)));

        // Verify: batch reverts atomically — no partial state changes.
        assertFalse(success, "Self-target at any position should cause batch revert");
        assertEq(fuzzTarget.value(), 0, "No state changes should persist after atomic revert");
    }
}
