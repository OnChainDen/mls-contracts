// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";

import {IBatchedTransaction} from "../../src/interfaces/IBatchedTransaction.sol";
import {ISafeExecutorModule} from "../../src/interfaces/ISafeExecutorModule.sol";
import {SignatureUtils} from "../../src/libraries/SignatureUtils.sol";
import {BatchedTransaction} from "../../src/safe-module/BatchedTransaction.sol";
import {SafeExecutorModule} from "../../src/safe-module/SafeExecutorModule.sol";
import {MockERC1271RevertingSigner, MockERC1271ShortReturnSigner} from "test/helpers/MockERC1271Signers.sol";
import {SignatureTestHelpers} from "test/helpers/SignatureTestHelpers.sol";

/**
 * @dev MockSafe — tracks all calls made via `execTransactionFromModule` for assertion.
 *      Supports configurable success/failure responses and optional real delegatecall execution.
 */
contract MockSafe {
    address public lastCallTo;
    uint256 public lastCallValue;
    bytes public lastCallData;
    uint8 public lastCallOperation;
    uint256 public callCount;

    bool public shouldSucceed = true;
    /// @dev When true, delegatecalls are actually executed (for integration tests with real BatchedTransaction).
    bool public executeDelegatecalls = false;

    /**
     * @dev Simulates Safe's execTransactionFromModule.
     * @param to Target address
     * @param value ETH value
     * @param data Calldata
     * @param operation 0 = Call, 1 = DelegateCall
     * @return success Whether the execution succeeded
     */
    function execTransactionFromModule(address to, uint256 value, bytes memory data, uint8 operation)
        external
        returns (bool success)
    {
        lastCallTo = to;
        lastCallValue = value;
        lastCallData = data;
        lastCallOperation = operation;
        callCount++;

        if (!shouldSucceed) {
            return false;
        }

        if (operation == 0) {
            (success,) = to.call{value: value}(data);
        } else if (executeDelegatecalls) {
            // Execute real delegatecall — safe for BatchedTransaction (no sstore).
            (success,) = to.delegatecall(data);
        } else {
            success = true;
        }
        return success;
    }

    /// @dev Configure success/failure behavior.
    function setShouldSucceed(bool succeed) external {
        shouldSucceed = succeed;
    }

    /// @dev Enable real delegatecall execution for integration tests.
    function setExecuteDelegatecalls(bool enabled) external {
        executeDelegatecalls = enabled;
    }

    /// @dev Reset call tracking.
    function resetCalls() external {
        lastCallTo = address(0);
        lastCallValue = 0;
        lastCallData = "";
        lastCallOperation = 0;
        callCount = 0;
    }

    /// @dev Functions that should never be callable via the module.
    function addOwnerWithThreshold(address, uint256) external pure {}
    function enableModule(address) external pure {}
}

/**
 * @dev RevertingMockSafe — always reverts with custom data on execTransactionFromModule.
 *      Used to test revert propagation (SEM-EOB-13, SEM-EOB-20).
 */
contract RevertingMockSafe {
    error CustomSafeError(string reason);

    function execTransactionFromModule(address, uint256, bytes memory, uint8) external pure returns (bool) {
        revert CustomSafeError("unexpected safe revert");
    }
}

/**
 * @dev MockSafeWithModuleAuth — checks that caller is an enabled module before executing.
 *      Simulates Safe v1.4.1 module auth behavior (SEM-EOB-15).
 */
contract MockSafeWithModuleAuth {
    mapping(address module => bool enabled) public enabledModules;

    /// @dev Enable or disable a module for auth checks.
    function setModuleEnabled(address module, bool enabled) external {
        enabledModules[module] = enabled;
    }

    /// @dev Reverts with "GS104" when caller is not an enabled module.
    function execTransactionFromModule(address to, uint256, bytes memory data, uint8) external returns (bool) {
        require(enabledModules[msg.sender], "GS104");
        (bool success,) = to.call(data);
        return success;
    }
}

/**
 * @dev MockTarget — basic target contract for testing module execution.
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
}

/**
 * @dev RequiresEthTarget — reverts unless msg.value > 0 (SEM-EOB-14).
 */
contract RequiresEthTarget {
    function payableAction() external payable {
        require(msg.value > 0, "ETH required");
    }
}

/**
 * @dev MockBatchedTransaction — tracks if execute was called without executing.
 */
contract MockBatchedTransaction {
    bool public wasCalled;

    function execute(bytes memory) external {
        wasCalled = true;
    }
}

/**
 * @dev MockERC1271AlwaysValid — returns the ERC-1271 magic value for any signature.
 *      Used to test that a valid contract signature from a non-authorized signer is rejected.
 */
contract MockERC1271AlwaysValid {
    function isValidSignature(bytes32, bytes memory) external pure returns (bytes4) {
        return bytes4(0x1626ba7e);
    }
}

/**
 * @dev Comprehensive tests for SafeExecutorModule covering constructor, executeOnBehalf,
 *      and isValidSignature. Covers test plan rows SEM-CON-*, SEM-EOB-*, SEM-IVS-*.
 */
contract SafeExecutorModuleTest is Test, SignatureTestHelpers {
    MockSafe internal mockSafe;
    MockTarget internal mockTarget;
    MockBatchedTransaction internal mockBatchedTransaction;
    SafeExecutorModule internal module;

    uint256 internal constant AUTHORIZED_EXECUTOR_PK = 0xA11CE;
    uint256 internal constant OTHER_SIGNER_PK = 0xB0B;
    address internal authorizedExecutor;
    address internal otherSigner;
    address internal unauthorizedUser;

    bytes32 internal constant TEST_HASH = keccak256("test message");

    /// @dev Deploy mocks and module before each test.
    function setUp() public {
        authorizedExecutor = vm.addr(AUTHORIZED_EXECUTOR_PK);
        otherSigner = vm.addr(OTHER_SIGNER_PK);
        unauthorizedUser = makeAddr("unauthorizedUser");

        mockSafe = new MockSafe();
        mockTarget = new MockTarget();
        mockBatchedTransaction = new MockBatchedTransaction();

        module = new SafeExecutorModule(address(mockSafe), authorizedExecutor, address(mockBatchedTransaction));
    }

    /**
     * @dev Encodes a single sub-transaction for BatchedTransaction.
     * @param to Target address (20 bytes)
     * @param data Calldata
     * @return encoded Packed transaction bytes
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

    /// @dev Verifies `constructor` sets all three immutable addresses correctly.
    function test_SEM_CON_1_SEM_CON_2_SEM_CON_3_constructorSetsImmutables() public view {
        // Verify: SAFE, AUTHORIZED_EXECUTOR, and BATCHED_TRANSACTION are stored correctly.
        assertEq(module.SAFE(), address(mockSafe), "SAFE immutable mismatch");
        assertEq(module.AUTHORIZED_EXECUTOR(), authorizedExecutor, "AUTHORIZED_EXECUTOR immutable mismatch");
        assertEq(
            module.BATCHED_TRANSACTION(), address(mockBatchedTransaction), "BATCHED_TRANSACTION immutable mismatch"
        );
    }

    /// @dev Verifies `constructor` reverts with `SafeAddressCannotBeZero` when safe is address(0).
    function test_SEM_CON_4_constructorRevertsZeroSafe() public {
        // Call: deploy with zero safe address. Expect revert.
        vm.expectRevert(ISafeExecutorModule.SafeAddressCannotBeZero.selector);
        new SafeExecutorModule(address(0), authorizedExecutor, address(mockBatchedTransaction));
    }

    /// @dev Verifies `constructor` reverts with `ExecutorAddressCannotBeZero` when executor is address(0).
    function test_SEM_CON_5_constructorRevertsZeroExecutor() public {
        // Call: deploy with zero executor address. Expect revert.
        vm.expectRevert(ISafeExecutorModule.ExecutorAddressCannotBeZero.selector);
        new SafeExecutorModule(address(mockSafe), address(0), address(mockBatchedTransaction));
    }

    /// @dev Verifies `constructor` reverts with `BatchedTransactionAddressCannotBeZero` when batchedTransaction is
    /// address(0).
    function test_SEM_CON_6_constructorRevertsZeroBatchedTransaction() public {
        // Call: deploy with zero batchedTransaction address. Expect revert.
        vm.expectRevert(ISafeExecutorModule.BatchedTransactionAddressCannotBeZero.selector);
        new SafeExecutorModule(address(mockSafe), authorizedExecutor, address(0));
    }

    /// @dev Verifies `constructor` revert precedence: safe check is first when all params are zero.
    function test_SEM_CON_7_constructorRevertPrecedenceSafeFirst() public {
        // Call: deploy with all-zero params. Expect SafeAddressCannotBeZero (first check).
        vm.expectRevert(ISafeExecutorModule.SafeAddressCannotBeZero.selector);
        new SafeExecutorModule(address(0), address(0), address(0));
    }

    /// @dev Verifies `executeOnBehalf` reverts with `UnauthorizedCaller` for non-authorized callers.
    function test_SEM_EOB_1_executeOnBehalfRevertsUnauthorizedCaller() public {
        // Setup: prepare valid calldata targeting mockTarget.
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 42);

        // Call: non-authorized caller attempts execution. Expect UnauthorizedCaller.
        vm.prank(unauthorizedUser);
        vm.expectRevert(
            abi.encodeWithSelector(
                ISafeExecutorModule.UnauthorizedCaller.selector, unauthorizedUser, authorizedExecutor
            )
        );
        module.executeOnBehalf(address(mockTarget), data);
    }

    /// @dev Verifies `executeOnBehalf` checks authorization before target restrictions (auth check first).
    function test_SEM_EOB_2_executeOnBehalfAuthCheckBeforeTargetCheck() public {
        // Setup: calldata targeting the Safe itself (would trigger CannotCallSafe if auth passed).
        bytes memory data = abi.encodeWithSelector(MockSafe.addOwnerWithThreshold.selector, makeAddr("owner"), 2);

        // Call: non-authorized caller targets the Safe. Expect UnauthorizedCaller (not CannotCallSafe).
        vm.prank(unauthorizedUser);
        vm.expectRevert(
            abi.encodeWithSelector(
                ISafeExecutorModule.UnauthorizedCaller.selector, unauthorizedUser, authorizedExecutor
            )
        );
        module.executeOnBehalf(address(mockSafe), data);
    }

    /// @dev Verifies `executeOnBehalf` reverts with `CannotCallSafe` when targeting the Safe.
    function test_SEM_EOB_3_executeOnBehalfRevertsCannotCallSafe() public {
        // Setup: calldata targeting the Safe.
        bytes memory data = abi.encodeWithSelector(MockSafe.addOwnerWithThreshold.selector, makeAddr("owner"), 2);

        // Call: authorized caller targets the Safe. Expect CannotCallSafe.
        vm.prank(authorizedExecutor);
        vm.expectRevert(abi.encodeWithSelector(ISafeExecutorModule.CannotCallSafe.selector, address(mockSafe)));
        module.executeOnBehalf(address(mockSafe), data);
    }

    /// @dev Verifies `executeOnBehalf` invokes `Safe.execTransactionFromModule` exactly once and returns true.
    function test_SEM_EOB_4_SEM_EOB_10_executeOnBehalfCallsSafeOnceAndReturnsTrue() public {
        // Setup: valid calldata.
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 123);

        // Call: authorized executor invokes executeOnBehalf.
        vm.prank(authorizedExecutor);
        bool success = module.executeOnBehalf(address(mockTarget), data);

        // Verify: Safe called exactly once and module returns true.
        assertTrue(success, "executeOnBehalf should return true");
        assertEq(mockSafe.callCount(), 1, "Safe should be called exactly once");
    }

    /// @dev Verifies `executeOnBehalf` forwards the exact `to` argument to the Safe.
    function test_SEM_EOB_5_executeOnBehalfForwardsToArgument() public {
        // Setup: valid calldata targeting mockTarget.
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 42);

        // Call: execute targeting mockTarget.
        vm.prank(authorizedExecutor);
        module.executeOnBehalf(address(mockTarget), data);

        // Verify: Safe received the exact target address.
        assertEq(mockSafe.lastCallTo(), address(mockTarget), "Safe should receive exact to address");
    }

    /// @dev Verifies `executeOnBehalf` forwards the exact `data` bytes to the Safe.
    function test_SEM_EOB_6_executeOnBehalfForwardsDataBytes() public {
        // Setup: specific calldata to verify byte-for-byte forwarding.
        uint256 expectedValue = 999;
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, expectedValue);

        // Call: execute with specific data.
        vm.prank(authorizedExecutor);
        module.executeOnBehalf(address(mockTarget), data);

        // Verify: Safe received the exact data bytes.
        assertEq(mockSafe.lastCallData(), data, "Safe should receive exact data bytes");
    }

    /// @dev Verifies `executeOnBehalf` always forwards value=0 to the Safe.
    function test_SEM_EOB_7_executeOnBehalfAlwaysForwardsZeroValue() public {
        // Setup: valid calldata.
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 42);

        // Call: execute via module.
        vm.prank(authorizedExecutor);
        module.executeOnBehalf(address(mockTarget), data);

        // Verify: value is always zero.
        assertEq(mockSafe.lastCallValue(), 0, "Value forwarded to Safe must be zero");
    }

    /// @dev Verifies `executeOnBehalf` uses CALL (0) for non-BatchedTransaction targets.
    function test_SEM_EOB_8_executeOnBehalfUsesCallForRegularTargets() public {
        // Setup: target is not BatchedTransaction.
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 42);

        // Call: execute targeting mockTarget.
        vm.prank(authorizedExecutor);
        module.executeOnBehalf(address(mockTarget), data);

        // Verify: operation is CALL (0).
        assertEq(mockSafe.lastCallOperation(), 0, "Operation should be CALL (0) for regular targets");
    }

    /// @dev Verifies `executeOnBehalf` uses DELEGATECALL (1) when target is BatchedTransaction.
    function test_SEM_EOB_9_executeOnBehalfUsesDelegatecallForBatchedTransaction() public {
        // Setup: target is BatchedTransaction.
        bytes memory data = abi.encodeWithSelector(MockBatchedTransaction.execute.selector, "");

        // Call: execute targeting BatchedTransaction.
        vm.prank(authorizedExecutor);
        module.executeOnBehalf(address(mockBatchedTransaction), data);

        // Verify: operation is DELEGATECALL (1) and target is correct.
        assertEq(mockSafe.lastCallOperation(), 1, "Operation should be DELEGATECALL (1) for BatchedTransaction");
        assertEq(mockSafe.lastCallTo(), address(mockBatchedTransaction), "Target should be BatchedTransaction");
    }

    /// @dev Verifies `executeOnBehalf` reverts with `ExecutionFailed` when Safe returns false.
    function test_SEM_EOB_11_executeOnBehalfRevertsOnSafeReturnsFalse() public {
        // Setup: configure Safe to return false.
        mockSafe.setShouldSucceed(false);
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 42);

        // Call: execute via module. Expect ExecutionFailed.
        vm.prank(authorizedExecutor);
        vm.expectRevert(ISafeExecutorModule.ExecutionFailed.selector);
        module.executeOnBehalf(address(mockTarget), data);
    }

    /// @dev Verifies `executeOnBehalf` reverts with `ExecutionFailed` when downstream target reverts.
    function test_SEM_EOB_12_executeOnBehalfRevertsOnDownstreamTargetRevert() public {
        // Setup: call a function that always reverts on the target.
        bytes memory data = abi.encodeWithSelector(MockTarget.revertingFunction.selector);

        // Call: Safe forwards call, target reverts, Safe returns false → ExecutionFailed.
        vm.prank(authorizedExecutor);
        vm.expectRevert(ISafeExecutorModule.ExecutionFailed.selector);
        module.executeOnBehalf(address(mockTarget), data);
    }

    /// @dev Verifies `executeOnBehalf` reverts when Safe itself reverts unexpectedly (never returns success).
    function test_SEM_EOB_13_executeOnBehalfRevertsWhenSafeReverts() public {
        // Setup: deploy a Safe mock that always reverts with custom error.
        RevertingMockSafe revertingSafe = new RevertingMockSafe();
        SafeExecutorModule revertModule =
            new SafeExecutorModule(address(revertingSafe), authorizedExecutor, address(mockBatchedTransaction));
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 42);

        // Call: Safe reverts, revert should propagate (not converted to ExecutionFailed).
        vm.prank(authorizedExecutor);
        vm.expectRevert(abi.encodeWithSelector(RevertingMockSafe.CustomSafeError.selector, "unexpected safe revert"));
        revertModule.executeOnBehalf(address(mockTarget), data);
    }

    /// @dev Verifies `executeOnBehalf` enforces no-ETH-transfer policy (value always 0).
    function test_SEM_EOB_14_executeOnBehalfCannotSendEth() public {
        // Setup: deploy target that requires non-zero msg.value.
        RequiresEthTarget ethTarget = new RequiresEthTarget();
        bytes memory data = abi.encodeWithSelector(RequiresEthTarget.payableAction.selector);

        // Call: module always passes value=0 → target reverts → Safe returns false → ExecutionFailed.
        vm.prank(authorizedExecutor);
        vm.expectRevert(ISafeExecutorModule.ExecutionFailed.selector);
        module.executeOnBehalf(address(ethTarget), data);
    }

    /// @dev Verifies `executeOnBehalf` fails when module is not enabled on actual Safe.
    function test_SEM_EOB_15_executeOnBehalfFailsWhenModuleNotEnabled() public {
        // Setup: deploy Safe that checks module auth (module not enabled).
        MockSafeWithModuleAuth authSafe = new MockSafeWithModuleAuth();
        SafeExecutorModule authModule =
            new SafeExecutorModule(address(authSafe), authorizedExecutor, address(mockBatchedTransaction));
        // Note: module is NOT enabled on authSafe.
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 42);

        // Call: execution fails because module is not an enabled module on the Safe.
        vm.prank(authorizedExecutor);
        vm.expectRevert("GS104");
        authModule.executeOnBehalf(address(mockTarget), data);
    }

    /// @dev Verifies multiple sequential `executeOnBehalf` calls are independent and deterministic.
    function test_SEM_EOB_16_executeOnBehalfMultipleSequentialCallsIndependent() public {
        // Call: three sequential calls with different values.
        vm.prank(authorizedExecutor);
        module.executeOnBehalf(address(mockTarget), abi.encodeWithSelector(MockTarget.setValue.selector, 10));
        assertEq(mockTarget.value(), 10, "First call should set value to 10");

        vm.prank(authorizedExecutor);
        module.executeOnBehalf(address(mockTarget), abi.encodeWithSelector(MockTarget.setValue.selector, 20));
        assertEq(mockTarget.value(), 20, "Second call should set value to 20");

        vm.prank(authorizedExecutor);
        module.executeOnBehalf(address(mockTarget), abi.encodeWithSelector(MockTarget.setValue.selector, 30));
        assertEq(mockTarget.value(), 30, "Third call should set value to 30");

        // Verify: Safe received exactly three calls and each was independent.
        assertEq(mockSafe.callCount(), 3, "Safe should have received exactly 3 calls");
    }

    /// @dev Verifies non-batch target observes `msg.sender == SAFE` (not module or executor).
    function test_SEM_EOB_17_executeOnBehalfTargetSeesSafeAsMsgSender() public {
        // Setup: valid calldata targeting mockTarget.
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 42);

        // Call: execute via module.
        vm.prank(authorizedExecutor);
        module.executeOnBehalf(address(mockTarget), data);

        // Verify: target received msg.sender == Safe (not module or executor).
        assertEq(mockTarget.lastCaller(), address(mockSafe), "Target should see Safe as msg.sender");
    }

    /// @dev Verifies `executeOnBehalf` with BatchedTransaction target executes sub-transactions successfully.
    function test_SEM_EOB_18_executeOnBehalfBatchedTransactionExecutesSubTxs() public {
        // Setup: deploy real BatchedTransaction and configure MockSafe to execute delegatecalls.
        BatchedTransaction realBatchedTx = new BatchedTransaction();
        SafeExecutorModule integrationModule =
            new SafeExecutorModule(address(mockSafe), authorizedExecutor, address(realBatchedTx));
        mockSafe.setExecuteDelegatecalls(true);

        // Encode a batch: setValue(10) on target + increment on target.
        MockTarget integrationTarget = new MockTarget();
        bytes[] memory txs = new bytes[](2);
        txs[0] = _encodeTx(address(integrationTarget), abi.encodeWithSelector(MockTarget.setValue.selector, 10));
        txs[1] = _encodeTx(address(integrationTarget), abi.encodeWithSelector(MockTarget.increment.selector));
        bytes memory batchData = abi.encodeWithSelector(BatchedTransaction.execute.selector, _encodeBatch(txs));

        // Call: authorized executor runs batch through module → Safe → BatchedTransaction.
        vm.prank(authorizedExecutor);
        bool success = integrationModule.executeOnBehalf(address(realBatchedTx), batchData);

        // Verify: sub-transactions executed in order (10 + 1 = 11).
        assertTrue(success, "Batch execution should succeed");
        assertEq(integrationTarget.value(), 11, "Target value should be 10 + 1 = 11");
        assertEq(integrationTarget.callCount(), 2, "Target should have received 2 calls");
    }

    /// @dev Verifies `executeOnBehalf` with BatchedTransaction sub-tx targeting Safe fails atomically.
    function test_SEM_EOB_19_executeOnBehalfBatchWithSafeTargetRevertsAtomically() public {
        // Setup: real BatchedTransaction, MockSafe executing delegatecalls.
        BatchedTransaction realBatchedTx = new BatchedTransaction();
        SafeExecutorModule integrationModule =
            new SafeExecutorModule(address(mockSafe), authorizedExecutor, address(realBatchedTx));
        mockSafe.setExecuteDelegatecalls(true);

        MockTarget integrationTarget = new MockTarget();
        // Batch: first tx is valid, second tx targets the Safe (address(this) in delegatecall context).
        bytes[] memory txs = new bytes[](2);
        txs[0] = _encodeTx(address(integrationTarget), abi.encodeWithSelector(MockTarget.setValue.selector, 10));
        txs[1] = _encodeTx(address(mockSafe), abi.encodeWithSelector(MockTarget.setValue.selector, 20));
        bytes memory batchData = abi.encodeWithSelector(BatchedTransaction.execute.selector, _encodeBatch(txs));

        // Call: execution should fail atomically because second sub-tx targets the Safe.
        vm.prank(authorizedExecutor);
        vm.expectRevert(ISafeExecutorModule.ExecutionFailed.selector);
        integrationModule.executeOnBehalf(address(realBatchedTx), batchData);

        // Verify: first sub-tx side effects are rolled back (target value unchanged).
        assertEq(integrationTarget.value(), 0, "First sub-tx side effects should be rolled back");
    }

    /// @dev Verifies Safe revert reason/data is bubbled through (not remapped to ExecutionFailed).
    function test_SEM_EOB_20_executeOnBehalfBubblesSafeRevertData() public {
        // Setup: deploy a Safe that reverts with specific custom error.
        RevertingMockSafe revertingSafe = new RevertingMockSafe();
        SafeExecutorModule revertModule =
            new SafeExecutorModule(address(revertingSafe), authorizedExecutor, address(mockBatchedTransaction));
        bytes memory data = abi.encodeWithSelector(MockTarget.setValue.selector, 42);

        // Call: Safe reverts with CustomSafeError — verify it propagates as-is.
        vm.prank(authorizedExecutor);
        vm.expectRevert(abi.encodeWithSelector(RevertingMockSafe.CustomSafeError.selector, "unexpected safe revert"));
        revertModule.executeOnBehalf(address(mockTarget), data);
    }

    /// @dev Verifies delegatecall context: sub-transaction targets observe `msg.sender == SAFE`.
    function test_SEM_EOB_21_executeOnBehalfDelegatecallSubTxSeeSafeAsSender() public {
        // Setup: real BatchedTransaction with delegatecall execution enabled.
        BatchedTransaction realBatchedTx = new BatchedTransaction();
        SafeExecutorModule integrationModule =
            new SafeExecutorModule(address(mockSafe), authorizedExecutor, address(realBatchedTx));
        mockSafe.setExecuteDelegatecalls(true);

        MockTarget integrationTarget = new MockTarget();
        // Batch: single sub-tx targeting integrationTarget.
        bytes[] memory txs = new bytes[](1);
        txs[0] = _encodeTx(address(integrationTarget), abi.encodeWithSelector(MockTarget.setValue.selector, 42));
        bytes memory batchData = abi.encodeWithSelector(BatchedTransaction.execute.selector, _encodeBatch(txs));

        // Call: execute batch through delegatecall path.
        vm.prank(authorizedExecutor);
        integrationModule.executeOnBehalf(address(realBatchedTx), batchData);

        // Verify: sub-tx target sees msg.sender == Safe (delegatecall preserves caller context).
        assertEq(
            integrationTarget.lastCaller(),
            address(mockSafe),
            "Sub-tx target should see Safe as msg.sender via delegatecall"
        );
    }

    /// @dev Verifies `isValidSignature` returns ERC-1271 magic value for valid authorized executor EOA signature.
    function test_SEM_IVS_1_isValidSignatureAcceptsAuthorizedEOASignature() public view {
        // Setup: create valid EOA signature from authorized executor.
        bytes memory signature = _signHash(AUTHORIZED_EXECUTOR_PK, TEST_HASH);

        // Call: validate signature.
        bytes4 result = module.isValidSignature(TEST_HASH, signature);

        // Verify: returns ERC-1271 magic value.
        assertEq(result, SignatureUtils.ERC1271_MAGIC_VALUE, "Valid authorized signature should return magic value");
    }

    /// @dev Verifies `isValidSignature` returns invalid value for valid EOA signature from non-authorized signer.
    function test_SEM_IVS_2_isValidSignatureRejectsNonAuthorizedSigner() public view {
        // Setup: create valid EOA signature from a different signer.
        bytes memory signature = _signHash(OTHER_SIGNER_PK, TEST_HASH);

        // Call: validate signature.
        bytes4 result = module.isValidSignature(TEST_HASH, signature);

        // Verify: returns invalid value.
        assertEq(result, SignatureUtils.ERC1271_INVALID_VALUE, "Non-authorized signer should return invalid value");
    }

    /// @dev Verifies `isValidSignature` returns invalid value when signature was created for a different hash.
    function test_SEM_IVS_3_isValidSignatureRejectsWrongHash() public view {
        // Setup: sign a different hash with the authorized key.
        bytes32 differentHash = keccak256("different message");
        bytes memory signature = _signHash(AUTHORIZED_EXECUTOR_PK, differentHash);

        // Call: validate against the original TEST_HASH (wrong hash for this signature).
        bytes4 result = module.isValidSignature(TEST_HASH, signature);

        // Verify: returns invalid value (recovered signer won't match).
        assertEq(result, SignatureUtils.ERC1271_INVALID_VALUE, "Signature for different hash should return invalid");
    }

    /// @dev Verifies `isValidSignature` returns invalid value (no revert) for empty signature.
    function test_SEM_IVS_4_isValidSignatureHandlesEmptySignature() public view {
        // Setup: empty signature bytes.
        bytes memory emptySig = "";

        // Call: validate empty signature.
        bytes4 result = module.isValidSignature(TEST_HASH, emptySig);

        // Verify: returns invalid value without reverting.
        assertEq(result, SignatureUtils.ERC1271_INVALID_VALUE, "Empty signature should return invalid value");
    }

    /// @dev Verifies `isValidSignature` returns invalid value (no revert) for malformed EOA signature.
    function test_SEM_IVS_5_isValidSignatureHandlesMalformedSignature() public view {
        // Setup: signature with valid v byte (27) but wrong length (33 bytes instead of 65).
        bytes memory malformedSig = abi.encodePacked(uint8(27), bytes32(0));

        // Call: validate malformed signature.
        bytes4 result = module.isValidSignature(TEST_HASH, malformedSig);

        // Verify: returns invalid value without reverting.
        assertEq(result, SignatureUtils.ERC1271_INVALID_VALUE, "Malformed signature should return invalid value");
    }

    /// @dev Verifies `isValidSignature` returns invalid value for signature with invalid v byte (not 0/27/28).
    function test_SEM_IVS_6_isValidSignatureRejectsInvalidVByte() public view {
        // Setup: 65-byte signature with v=1 (invalid v byte).
        bytes memory invalidVSig = abi.encodePacked(uint8(1), bytes32(uint256(0x1234)), bytes32(uint256(0x5678)));

        // Call: validate signature with invalid v.
        bytes4 result = module.isValidSignature(TEST_HASH, invalidVSig);

        // Verify: returns invalid value (v=1 is neither EOA nor contract signature marker).
        assertEq(result, SignatureUtils.ERC1271_INVALID_VALUE, "Invalid v byte should return invalid value");
    }

    /// @dev Verifies `isValidSignature` returns invalid value for high-s malleable EOA signature.
    function test_SEM_IVS_7_isValidSignatureRejectsHighSMalleableSignature() public view {
        // Setup: create a malleable (high-s) signature from the authorized executor.
        bytes memory malleableSig = _makeHighSSignature(AUTHORIZED_EXECUTOR_PK, TEST_HASH);

        // Call: validate malleable signature.
        bytes4 result = module.isValidSignature(TEST_HASH, malleableSig);

        // Verify: returns invalid value (malleability check rejects high-s).
        assertEq(result, SignatureUtils.ERC1271_INVALID_VALUE, "Malleable high-s signature should return invalid");
    }

    /// @dev Verifies `isValidSignature` returns invalid for ERC-1271 signature where signer != authorized executor.
    function test_SEM_IVS_8_isValidSignatureRejectsNonAuthorizedContractSigner() public {
        // Setup: deploy a mock ERC-1271 signer that always returns valid magic, but is not the authorized executor.
        MockERC1271AlwaysValid mockSigner = new MockERC1271AlwaysValid();
        bytes memory contractSig = _buildContractSignature(address(mockSigner), hex"AABB");

        // Call: validate contract signature (recovered signer = mockSigner address, != authorizedExecutor).
        bytes4 result = module.isValidSignature(TEST_HASH, contractSig);

        // Verify: returns invalid value because recovered signer != AUTHORIZED_EXECUTOR.
        assertEq(result, SignatureUtils.ERC1271_INVALID_VALUE, "Non-authorized contract signer should return invalid");
    }

    /// @dev Verifies `isValidSignature` returns invalid value (no revert) for malformed nested ERC-1271 payload.
    function test_SEM_IVS_9_isValidSignatureHandlesMalformedNestedPayload() public view {
        // Setup: ERC-1271 header with only 2 bytes (v=0, missing signer and length fields).
        bytes memory malformedContractSig = hex"0000";

        // Call: validate malformed contract signature.
        bytes4 result = module.isValidSignature(TEST_HASH, malformedContractSig);

        // Verify: returns invalid value without reverting.
        assertEq(
            result, SignatureUtils.ERC1271_INVALID_VALUE, "Malformed nested ERC-1271 payload should return invalid"
        );
    }

    /// @dev Verifies `isValidSignature` returns deterministic output for identical inputs.
    function test_SEM_IVS_10_isValidSignatureIsDeterministic() public view {
        // Setup: valid authorized signature.
        bytes memory signature = _signHash(AUTHORIZED_EXECUTOR_PK, TEST_HASH);

        // Call: validate same (hash, signature) twice.
        bytes4 result1 = module.isValidSignature(TEST_HASH, signature);
        bytes4 result2 = module.isValidSignature(TEST_HASH, signature);

        // Verify: both calls return the same value.
        assertEq(result1, result2, "Deterministic: same inputs should always return same value");
        assertEq(result1, SignatureUtils.ERC1271_MAGIC_VALUE, "Should be magic value for valid signature");
    }

    /// @dev Verifies `isValidSignature` is view and does not mutate state.
    function test_SEM_IVS_11_isValidSignatureIsViewAndNoStateMutation() public {
        // Setup: build a valid signature.
        bytes memory signature = _signHash(AUTHORIZED_EXECUTOR_PK, TEST_HASH);

        // Call + Verify: staticcall reverts at the EVM level if any state mutation occurs.
        (bool success,) = address(module).staticcall(
            abi.encodeCall(module.isValidSignature, (TEST_HASH, signature))
        );
        assertTrue(success, "isValidSignature should succeed under staticcall (view)");
    }

    /// @dev Verifies `isValidSignature` accepts valid authorized signature for both v=27 and v=28 encodings.
    function test_SEM_IVS_12_isValidSignatureAcceptsBothVValues() public view {
        // Setup: find valid signatures with v=27 and v=28.
        (bytes memory sig27, bytes32 hash27) = _findValidSignatureForV(AUTHORIZED_EXECUTOR_PK, 27, TEST_HASH);
        (bytes memory sig28, bytes32 hash28) = _findValidSignatureForV(AUTHORIZED_EXECUTOR_PK, 28, TEST_HASH);

        // Call: validate both signatures.
        bytes4 result27 = module.isValidSignature(hash27, sig27);
        bytes4 result28 = module.isValidSignature(hash28, sig28);

        // Verify: both return magic value.
        assertEq(result27, SignatureUtils.ERC1271_MAGIC_VALUE, "v=27 signature should be accepted");
        assertEq(result28, SignatureUtils.ERC1271_MAGIC_VALUE, "v=28 signature should be accepted");
    }

    /// @dev Verifies `isValidSignature` returns invalid (no revert) when nested ERC-1271 signer reverts.
    function test_SEM_IVS_13_isValidSignatureHandlesRevertingNestedSigner() public {
        // Setup: deploy ERC-1271 signer that always reverts.
        MockERC1271RevertingSigner revertingSigner = new MockERC1271RevertingSigner();
        bytes memory contractSig = _buildContractSignature(address(revertingSigner), hex"AABB");

        // Call: validate signature with reverting nested signer.
        bytes4 result = module.isValidSignature(TEST_HASH, contractSig);

        // Verify: returns invalid value without reverting.
        assertEq(result, SignatureUtils.ERC1271_INVALID_VALUE, "Reverting nested ERC-1271 signer should return invalid");
    }

    /// @dev Verifies `isValidSignature` returns invalid (no revert) when nested ERC-1271 signer returns truncated data.
    function test_SEM_IVS_14_isValidSignatureHandlesTruncatedNestedReturn() public {
        // Setup: deploy ERC-1271 signer that returns < 32 bytes.
        MockERC1271ShortReturnSigner shortSigner = new MockERC1271ShortReturnSigner();
        bytes memory contractSig = _buildContractSignature(address(shortSigner), hex"AABB");

        // Call: validate signature with truncated-return nested signer.
        bytes4 result = module.isValidSignature(TEST_HASH, contractSig);

        // Verify: returns invalid value without reverting.
        assertEq(result, SignatureUtils.ERC1271_INVALID_VALUE, "Truncated-return nested signer should return invalid");
    }
}
