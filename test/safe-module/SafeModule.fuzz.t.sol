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
 *      Covers test plan rows SMI-FUZ-1 through SMI-FUZ-4 and SMI-FUZ-6.
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

    /// @dev Verifies `executeOnBehalf` chooses the Safe operation solely from the target kind.
    /// @param useBatchedTarget Whether to route through `BATCHED_TRANSACTION` instead of a direct call target.
    /// @param newValue Fuzzed value written through the selected execution path.
    function testFuzz_SMI_FUZ_1_executeOnBehalf_operationMatchesTargetKind(bool useBatchedTarget, uint256 newValue)
        public
    {
        // Setup: build a successful direct-call or batch-call payload against known contract targets.
        address target = useBatchedTarget ? address(batchedTx) : address(fuzzTarget);
        bytes memory data;

        if (useBatchedTarget) {
            bytes[] memory txs = new bytes[](1);
            txs[0] = _encodeTx(address(fuzzTarget), abi.encodeWithSelector(FuzzTarget.setValue.selector, newValue));
            data = abi.encodeWithSelector(BatchedTransaction.execute.selector, _encodeBatch(txs));
            mockSafe.setExecuteDelegatecalls(true);
        } else {
            data = abi.encodeWithSelector(FuzzTarget.setValue.selector, newValue);
        }

        // Call: execute the fuzzed target-kind path as the authorized executor.
        vm.prank(authorizedExecutor);
        bool success = module.executeOnBehalf(target, data);

        if (useBatchedTarget) {
            mockSafe.setExecuteDelegatecalls(false);
        }

        // Verify: successful executions use DELEGATECALL only for the batched target and preserve effects.
        assertTrue(success, "prepared target-kind path should succeed");
        assertEq(mockSafe.lastCallTo(), target, "Safe should receive the selected target");
        assertEq(
            mockSafe.lastCallOperation(),
            useBatchedTarget ? uint8(1) : uint8(0),
            "operation should depend only on whether the target is batched"
        );
        assertEq(fuzzTarget.value(), newValue, "selected execution path should apply the fuzzed value");
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

    /// @dev Verifies malformed signature inputs never revert and only return canonical ERC-1271 values.
    /// @param hash Message hash supplied to `isValidSignature`.
    /// @param signature Arbitrary malformed or random signature bytes.
    function testFuzz_SMI_FUZ_3_A_isValidSignature_randomInputsNeverRevertOrReturnUnexpectedValues(
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

    /// @dev Verifies only an exact authorized-executor signature over the validated hash can produce magic.
    /// @param useAuthorizedSigner Whether to sign with the module's configured authorized executor.
    /// @param signCorrectHash Whether the signer signs the exact validated hash.
    /// @param hash Message hash supplied to `isValidSignature`.
    /// @param otherSignerPkRaw Fuzzed seed for an alternate non-authorized signer key.
    function testFuzz_SMI_FUZ_3_B_isValidSignature_onlyAuthorizedExactHashProducesMagic(
        bool useAuthorizedSigner,
        bool signCorrectHash,
        bytes32 hash,
        uint256 otherSignerPkRaw
    ) public {
        // Setup: pick either the authorized signer or a bounded alternate signer and optionally mutate the signed hash.
        uint256 signerPk =
            useAuthorizedSigner ? AUTHORIZED_EXECUTOR_PK : bound(otherSignerPkRaw, 1, SECP256K1_CURVE_ORDER - 1);
        vm.assume(useAuthorizedSigner || signerPk != AUTHORIZED_EXECUTOR_PK);

        bytes32 signedHash = signCorrectHash ? hash : keccak256(abi.encode(hash, otherSignerPkRaw));
        bytes memory signature = _signHash(signerPk, signedHash);

        // Call: validate the constructed signature against the requested hash.
        bytes4 actual = module.isValidSignature(hash, signature);

        // Verify: magic is only reachable when the authorized executor signed the exact hash under validation.
        bytes4 expected = useAuthorizedSigner && signCorrectHash
            ? SignatureUtils.ERC1271_MAGIC_VALUE
            : SignatureUtils.ERC1271_INVALID_VALUE;
        assertEq(actual, expected, "only the authorized executor on the exact hash should validate");
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
