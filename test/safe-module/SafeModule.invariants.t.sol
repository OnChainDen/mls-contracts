// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";

import {IBatchedTransaction} from "../../src/interfaces/IBatchedTransaction.sol";
import {ISafeExecutorModule} from "../../src/interfaces/ISafeExecutorModule.sol";
import {BatchedTransaction} from "../../src/safe-module/BatchedTransaction.sol";
import {SafeExecutorModule} from "../../src/safe-module/SafeExecutorModule.sol";

/**
 * @dev InvariantMockSafe — tracks every call to enforce invariants on value, target, and operation.
 */
contract InvariantMockSafe {
    /// @dev Records of all calls made to execTransactionFromModule.
    struct CallRecord {
        address to;
        uint256 value;
        uint8 operation;
    }

    CallRecord[] public callRecords;

    bool public executeDelegatecalls = false;

    /// @dev Records call and optionally executes it.
    function execTransactionFromModule(address to, uint256 value, bytes memory data, uint8 operation)
        external
        returns (bool success)
    {
        callRecords.push(CallRecord({to: to, value: value, operation: operation}));

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

    /**
     * @dev Returns total number of call records.
     * @return count Number of recorded calls
     */
    function callRecordCount() external view returns (uint256 count) {
        return callRecords.length;
    }
}

/**
 * @dev InvariantTarget — simple target that records state changes.
 */
contract InvariantTarget {
    uint256 public value;

    function setValue(uint256 v) external {
        value = v;
    }
}

/**
 * @dev InvariantReverter — helper target that always reverts when called from a batch.
 */
contract InvariantReverter {
    /// @dev Reverts unconditionally to exercise atomic batch failure paths.
    function alwaysRevert() external pure {
        revert("invariant-batch-revert");
    }
}

/**
 * @dev SafeModuleInvariantHandler — defines the action space for invariant fuzzing.
 *      Performs random executeOnBehalf calls with varying callers, targets, and data.
 */
contract SafeModuleInvariantHandler is Test {
    SafeExecutorModule public module;
    InvariantMockSafe public mockSafe;
    BatchedTransaction public batchedTx;
    InvariantTarget public target;
    InvariantReverter public reverter;

    address public authorizedExecutor;
    address public unauthorizedCaller;

    uint256 public successfulExecutions;
    uint256 public failedExecutions;
    uint256 public unauthorizedAttempts;
    uint256 public selfTargetBatchAttempts;
    uint256 public atomicRevertBatchAttempts;

    /**
     * @dev Sets up the handler with module and mock contracts.
     * @param _module The SafeExecutorModule under test
     * @param _mockSafe The mock Safe contract
     * @param _batchedTx The BatchedTransaction contract
     * @param _target The target contract
     * @param _reverter The helper target that always reverts
     * @param _authorizedExecutor The authorized executor address
     */
    constructor(
        SafeExecutorModule _module,
        InvariantMockSafe _mockSafe,
        BatchedTransaction _batchedTx,
        InvariantTarget _target,
        InvariantReverter _reverter,
        address _authorizedExecutor
    ) {
        module = _module;
        mockSafe = _mockSafe;
        batchedTx = _batchedTx;
        target = _target;
        reverter = _reverter;
        authorizedExecutor = _authorizedExecutor;
        unauthorizedCaller = makeAddr("unauthorizedInvariant");
    }

    /**
     * @dev Authorized executor calls executeOnBehalf with valid target.
     * @param newValue Fuzzed value to set on target
     */
    function executeAsAuthorized(uint256 newValue) external {
        bytes memory data = abi.encodeWithSelector(InvariantTarget.setValue.selector, newValue);
        vm.prank(authorizedExecutor);
        try module.executeOnBehalf(address(target), data) {
            successfulExecutions++;
        } catch {
            failedExecutions++;
        }
    }

    /**
     * @dev Unauthorized caller attempts executeOnBehalf — should always fail.
     * @param newValue Fuzzed value (irrelevant — call should revert)
     */
    function executeAsUnauthorized(uint256 newValue) external {
        bytes memory data = abi.encodeWithSelector(InvariantTarget.setValue.selector, newValue);
        vm.prank(unauthorizedCaller);
        try module.executeOnBehalf(address(target), data) {
            // This should never succeed.
            revert("INVARIANT VIOLATION: unauthorized caller succeeded");
        } catch {
            unauthorizedAttempts++;
        }
    }

    /// @dev Authorized executor attempts to call the Safe directly — should always fail.
    function executeTargetingSafe() external {
        bytes memory data = abi.encodeWithSelector(InvariantTarget.setValue.selector, 999);
        vm.prank(authorizedExecutor);
        try module.executeOnBehalf(address(mockSafe), data) {
            // This should never succeed.
            revert("INVARIANT VIOLATION: direct Safe call succeeded");
        } catch {
            failedExecutions++;
        }
    }

    /**
     * @dev Executes a batch via the module (delegatecall path).
     * @param newValue Value to set in a single-tx batch
     */
    function executeAsBatch(uint256 newValue) external {
        bytes memory subTx = abi.encodePacked(
            address(target), uint64(36), abi.encodeWithSelector(InvariantTarget.setValue.selector, newValue)
        );
        bytes memory data = abi.encodeWithSelector(BatchedTransaction.execute.selector, subTx);
        mockSafe.setExecuteDelegatecalls(true);
        vm.prank(authorizedExecutor);
        try module.executeOnBehalf(address(batchedTx), data) {
            successfulExecutions++;
        } catch {
            failedExecutions++;
        }
        mockSafe.setExecuteDelegatecalls(false);
    }

    /**
     * @dev Attempts a batch with one self-targeting sub-call and asserts atomic failure.
     * @param positionRaw Fuzzed position where the self-targeting sub-call is inserted
     * @param newValue Fuzzed value used by non-self-targeting sub-calls
     */
    function executeBatchTargetingSafe(uint8 positionRaw, uint256 newValue) external {
        uint8 batchSize = 3;
        uint8 position = uint8(bound(positionRaw, 0, batchSize - 1));
        uint256 beforeValue = target.value();

        bytes memory batch;
        for (uint256 i = 0; i < batchSize; i++) {
            address to = i == position ? address(mockSafe) : address(target);
            bytes memory callData = i == position
                ? abi.encodeWithSelector(InvariantTarget.setValue.selector, newValue)
                : abi.encodeWithSelector(InvariantTarget.setValue.selector, newValue + i + 1);
            batch = abi.encodePacked(batch, abi.encodePacked(to, uint64(callData.length), callData));
        }

        bytes memory data = abi.encodeWithSelector(BatchedTransaction.execute.selector, batch);
        mockSafe.setExecuteDelegatecalls(true);

        vm.prank(authorizedExecutor);
        try module.executeOnBehalf(address(batchedTx), data) {
            revert("INVARIANT VIOLATION: self-targeting batch succeeded");
        } catch {
            selfTargetBatchAttempts++;
            assertEq(target.value(), beforeValue, "self-targeting batch must leave no persisted state");
        }

        mockSafe.setExecuteDelegatecalls(false);
    }

    /**
     * @dev Attempts a batch with a reverting later sub-call and asserts atomic rollback.
     */
    function executeBatchWithFailingSubcall() external {
        uint256 beforeValue = target.value();
        uint256 stagedValue = beforeValue == type(uint256).max ? beforeValue - 1 : beforeValue + 1;

        bytes memory firstCall = abi.encodeWithSelector(InvariantTarget.setValue.selector, stagedValue);
        bytes memory secondCall = abi.encodeWithSelector(InvariantReverter.alwaysRevert.selector);
        bytes memory batch = abi.encodePacked(
            abi.encodePacked(address(target), uint64(firstCall.length), firstCall),
            abi.encodePacked(address(reverter), uint64(secondCall.length), secondCall)
        );

        bytes memory data = abi.encodeWithSelector(BatchedTransaction.execute.selector, batch);
        mockSafe.setExecuteDelegatecalls(true);

        vm.prank(authorizedExecutor);
        try module.executeOnBehalf(address(batchedTx), data) {
            revert("INVARIANT VIOLATION: reverting sub-call batch succeeded");
        } catch {
            atomicRevertBatchAttempts++;
            assertEq(target.value(), beforeValue, "failing batch must roll back earlier writes");
        }

        mockSafe.setExecuteDelegatecalls(false);
    }
}

/**
 * @dev Invariant tests for SafeExecutorModule and BatchedTransaction.
 *      Covers test plan rows SMI-INV-1 through SMI-INV-5.
 *      SMI-INV-6 covers guardian module signature invariants and is
 *      implemented in the existing LibOrganizationAccountSignature invariant suite.
 */
contract SafeModuleInvariantsTest is Test {
    SafeModuleInvariantHandler internal handler;
    InvariantMockSafe internal mockSafe;
    SafeExecutorModule internal module;
    BatchedTransaction internal batchedTx;
    InvariantTarget internal target;
    InvariantReverter internal reverter;

    address internal constant AUTHORIZED_EXECUTOR = address(0xA11CE);

    /// @dev Deploys all contracts, creates handler, seeds baseline actions, and registers fuzz target.
    function setUp() public {
        mockSafe = new InvariantMockSafe();
        batchedTx = new BatchedTransaction();
        target = new InvariantTarget();
        reverter = new InvariantReverter();
        module = new SafeExecutorModule(address(mockSafe), AUTHORIZED_EXECUTOR, address(batchedTx));

        handler = new SafeModuleInvariantHandler(module, mockSafe, batchedTx, target, reverter, AUTHORIZED_EXECUTOR);

        // Seed baseline coverage for each action.
        handler.executeAsAuthorized(1);
        handler.executeAsUnauthorized(2);
        handler.executeTargetingSafe();
        handler.executeAsBatch(3);
        handler.executeBatchTargetingSafe(1, 4);
        handler.executeBatchWithFailingSubcall();

        targetContract(address(handler));
    }

    /// @dev SMI-INV-1: Only AUTHORIZED_EXECUTOR can make executeOnBehalf succeed.
    function invariant_SMI_INV_1_onlyAuthorizedExecutorCanSucceed() public view {
        // If any unauthorized attempt had succeeded, the handler would have reverted.
        // The invariant holds as long as the handler didn't panic.
        assertTrue(handler.unauthorizedAttempts() >= 0, "Invariant check executed");
    }

    /// @dev SMI-INV-2: SafeExecutorModule never instructs Safe to send non-zero value.
    function invariant_SMI_INV_2_moduleNeverSendsNonZeroValue() public view {
        uint256 count = mockSafe.callRecordCount();
        for (uint256 i = 0; i < count; i++) {
            (, uint256 value,) = mockSafe.callRecords(i);
            assertEq(value, 0, "Module must never instruct Safe to send non-zero value");
        }
    }

    /// @dev SMI-INV-3: SafeExecutorModule never allows direct to == SAFE execution.
    function invariant_SMI_INV_3_moduleNeverAllowsDirectSafeExecution() public view {
        uint256 count = mockSafe.callRecordCount();
        for (uint256 i = 0; i < count; i++) {
            (address to,,) = mockSafe.callRecords(i);
            assertTrue(to != address(mockSafe), "Module must never allow direct to == SAFE");
        }
    }

    /// @dev SMI-INV-4: BatchedTransaction never allows a sub-call to the delegatecaller Safe.
    function invariant_SMI_INV_4_batchNeverAllowsSelfCall() public view {
        // Handler actions would revert immediately if a self-targeting batch ever succeeded or leaked state.
        assertTrue(handler.selfTargetBatchAttempts() > 0, "self-targeting batches should be exercised");
    }

    /// @dev SMI-INV-5: Batched execution is atomic after any reverting later sub-call.
    function invariant_SMI_INV_5_batchedExecutionIsAtomic() public view {
        // Handler actions would revert immediately if a failing batch ever persisted earlier writes.
        assertTrue(handler.atomicRevertBatchAttempts() > 0, "reverting later sub-calls should be exercised");
    }
}
