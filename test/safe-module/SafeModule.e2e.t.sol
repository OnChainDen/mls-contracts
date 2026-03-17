// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";

import {ISafeExecutorModule} from "../../src/interfaces/ISafeExecutorModule.sol";
import {SignatureUtils} from "../../src/libraries/SignatureUtils.sol";
import {BatchedTransaction} from "../../src/safe-module/BatchedTransaction.sol";
import {SafeExecutorModule} from "../../src/safe-module/SafeExecutorModule.sol";
import {MockGuardianSafe} from "test/helpers/MockGuardianSafe.sol";
import {SignatureTestHelpers} from "test/helpers/SignatureTestHelpers.sol";

/**
 * @dev E2EMockSafe — mock Safe that supports module enablement, execution, and real delegatecall.
 *      Combines tracking, module auth, and execution for end-to-end testing.
 */
contract E2EMockSafe {
    mapping(address module => bool enabled) public enabledModules;
    uint256 public callCount;
    bool public executeDelegatecalls = true;

    /// @dev Enable or disable a module.
    function setModuleEnabled(address module, bool enabled) external {
        enabledModules[module] = enabled;
    }

    /// @dev Checks module auth and executes the transaction.
    function execTransactionFromModule(address to, uint256 value, bytes memory data, uint8 operation)
        external
        returns (bool success)
    {
        require(enabledModules[msg.sender], "GS104");
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

    /// @dev Safe-compatible isModuleEnabled check.
    function isModuleEnabled(address module) external view returns (bool) {
        return enabledModules[module];
    }

    /// @dev Simulates Safe management functions (should be unreachable through module).
    function addOwnerWithThreshold(address, uint256) external pure {}
    function removeOwner(address, address, uint256) external pure {}
    function changeThreshold(uint256) external pure {}
    function enableModuleCall(address) external pure {}
    function disableModule(address, address) external pure {}
}

/**
 * @dev E2ETarget — tracks calls with msg.sender identity for E2E assertion.
 */
contract E2ETarget {
    uint256 public value;
    address public lastCaller;
    uint256 public callCount;

    function setValue(uint256 v) external {
        value = v;
        lastCaller = msg.sender;
        callCount++;
    }

    function increment() external {
        value++;
        lastCaller = msg.sender;
        callCount++;
    }
}

/**
 * @dev End-to-end integration tests for SafeExecutorModule ecosystem.
 *      Covers test plan rows SMI-ETE-*.
 *      Note: SMI-ETE-1, SMI-ETE-4, SMI-ETE-8 through SMI-ETE-10 require full Organization
 *      infrastructure (policies, accounts, guardians) and are out of scope for this mock-based file.
 */
contract SafeModuleE2ETest is Test, SignatureTestHelpers {
    E2EMockSafe internal safe;
    BatchedTransaction internal batchedTx;
    SafeExecutorModule internal module;
    E2ETarget internal target;

    uint256 internal constant AUTHORIZED_EXECUTOR_PK = 0xA11CE;
    address internal authorizedExecutor;
    address internal unauthorizedCaller;

    /// @dev Deploy complete E2E test environment.
    function setUp() public {
        authorizedExecutor = vm.addr(AUTHORIZED_EXECUTOR_PK);
        unauthorizedCaller = makeAddr("unauthorizedE2E");

        safe = new E2EMockSafe();
        batchedTx = new BatchedTransaction();
        target = new E2ETarget();

        module = new SafeExecutorModule(address(safe), authorizedExecutor, address(batchedTx));

        // Enable module on Safe.
        safe.setModuleEnabled(address(module), true);
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

    /// @dev Verifies disabled module on Guardian Safe still results in valid signature from module, even if not
    /// accepted by the account.
    function test_SMI_ETE_2_disabledModuleStillValidatesSignatureAtModuleLevel() public {
        // Setup: deploy a Guardian Safe mock, enable module as a module on it.
        MockGuardianSafe guardianSafe = new MockGuardianSafe();
        SafeExecutorModule guardianModule =
            new SafeExecutorModule(address(guardianSafe), authorizedExecutor, address(batchedTx));
        guardianSafe.setModuleEnabled(address(guardianModule), true);

        bytes32 testHash = keccak256("e2e test hash");
        bytes memory authorizedSig = _signHash(AUTHORIZED_EXECUTOR_PK, testHash);

        // Call: verify module validates signature when enabled.
        bytes4 resultEnabled = guardianModule.isValidSignature(testHash, authorizedSig);
        assertEq(resultEnabled, SignatureUtils.ERC1271_MAGIC_VALUE, "Signature should be valid when module enabled");

        // Call: disable module on the guardian Safe.
        guardianSafe.setModuleEnabled(address(guardianModule), false);

        // Verify: signature is still valid at the module level (module checks AUTHORIZED_EXECUTOR, not module
        // enablement). Note: The module's isValidSignature checks the AUTHORIZED_EXECUTOR signer, not module
        // enablement.
        // Module enablement affects whether the Guardian Safe recognizes the module as a valid signer.
        // This test verifies the module-level behavior. The guardian-level impact is tested in LOAS tests.
        bytes4 resultDisabled = guardianModule.isValidSignature(testHash, authorizedSig);
        assertEq(
            resultDisabled,
            SignatureUtils.ERC1271_MAGIC_VALUE,
            "Module-level signature check is independent of module enablement on Safe"
        );
    }

    /// @dev Verifies module rotation: disable old module + enable new module → old fails, new passes.
    function test_SMI_ETE_3_moduleRotationOldFailsNewPasses() public {
        // Setup: deploy old and new modules with different executor keys.
        uint256 oldExecutorPk = 0xDEAD;
        uint256 newExecutorPk = 0xBEEF;
        address oldExecutor = vm.addr(oldExecutorPk);
        address newExecutor = vm.addr(newExecutorPk);

        SafeExecutorModule oldModule = new SafeExecutorModule(address(safe), oldExecutor, address(batchedTx));
        SafeExecutorModule newModule = new SafeExecutorModule(address(safe), newExecutor, address(batchedTx));

        safe.setModuleEnabled(address(oldModule), true);
        safe.setModuleEnabled(address(newModule), false);

        // Verify: old module can execute, new module cannot.
        bytes memory data = abi.encodeWithSelector(E2ETarget.setValue.selector, 10);
        vm.prank(oldExecutor);
        bool oldSuccess = oldModule.executeOnBehalf(address(target), data);
        assertTrue(oldSuccess, "Old module should succeed before rotation");

        vm.prank(newExecutor);
        vm.expectRevert("GS104");
        newModule.executeOnBehalf(address(target), data);

        // Call: rotate modules (disable old, enable new).
        safe.setModuleEnabled(address(oldModule), false);
        safe.setModuleEnabled(address(newModule), true);

        // Verify: old module fails, new module succeeds immediately.
        vm.prank(oldExecutor);
        vm.expectRevert("GS104");
        oldModule.executeOnBehalf(address(target), abi.encodeWithSelector(E2ETarget.setValue.selector, 20));

        vm.prank(newExecutor);
        bool newSuccess =
            newModule.executeOnBehalf(address(target), abi.encodeWithSelector(E2ETarget.setValue.selector, 30));
        assertTrue(newSuccess, "New module should succeed after rotation");
        assertEq(target.value(), 30, "Target should reflect new module's call");
    }

    /// @dev Verifies authorized executor can execute functions through the module path.
    function test_SMI_ETE_5_authorizedExecutorCanExecuteViaModule() public {
        // Setup: valid calldata.
        bytes memory data = abi.encodeWithSelector(E2ETarget.setValue.selector, 42);

        // Call: authorized executor executes through full path (module → Safe → target).
        vm.prank(authorizedExecutor);
        bool success = module.executeOnBehalf(address(target), data);

        // Verify: execution succeeded and state changed.
        assertTrue(success, "Authorized executor should succeed via module");
        assertEq(target.value(), 42, "Target value should be updated");
        assertEq(target.lastCaller(), address(safe), "Target should see Safe as caller");
    }

    /// @dev Verifies unauthorized caller cannot execute functions through the module path.
    function test_SMI_ETE_6_unauthorizedCallerCannotExecuteViaModule() public {
        // Setup: valid calldata.
        bytes memory data = abi.encodeWithSelector(E2ETarget.setValue.selector, 42);

        // Call: unauthorized caller attempts execution. Expect UnauthorizedCaller.
        vm.prank(unauthorizedCaller);
        vm.expectRevert(
            abi.encodeWithSelector(
                ISafeExecutorModule.UnauthorizedCaller.selector, unauthorizedCaller, authorizedExecutor
            )
        );
        module.executeOnBehalf(address(target), data);

        // Verify: target state unchanged.
        assertEq(target.value(), 0, "Target state should be unchanged after unauthorized attempt");
    }

    /// @dev Verifies batched transactions cannot execute Safe management calls (owner/module/threshold).
    function test_SMI_ETE_7_batchCannotExecuteSafeManagementCalls() public {
        // Setup: batch with sub-transaction targeting the Safe itself.
        bytes[] memory txs = new bytes[](2);
        txs[0] = _encodeTx(address(target), abi.encodeWithSelector(E2ETarget.setValue.selector, 10));
        // Sub-tx targeting Safe for addOwnerWithThreshold — should trigger CannotCallSafe.
        txs[1] = _encodeTx(
            address(safe), abi.encodeWithSelector(E2EMockSafe.addOwnerWithThreshold.selector, makeAddr("newOwner"), 2)
        );
        bytes memory batchData = abi.encodeWithSelector(BatchedTransaction.execute.selector, _encodeBatch(txs));

        // Call: authorized executor executes batch through module.
        vm.prank(authorizedExecutor);
        vm.expectRevert(ISafeExecutorModule.ExecutionFailed.selector);
        module.executeOnBehalf(address(batchedTx), batchData);

        // Verify: target state unchanged (atomically rolled back).
        assertEq(target.value(), 0, "Batch targeting Safe should roll back all state changes");
    }

    /// @dev Verifies disabling module on Safe prevents execution and leaves state unchanged.
    function test_SMI_ETE_11_executionGatingDisabledModuleOrWrongExecutor() public {
        // Setup: prepare valid batch data.
        bytes[] memory txs = new bytes[](1);
        txs[0] = _encodeTx(address(target), abi.encodeWithSelector(E2ETarget.setValue.selector, 42));
        bytes memory batchData = abi.encodeWithSelector(BatchedTransaction.execute.selector, _encodeBatch(txs));

        // Part A: Disable module on Safe → execution fails.
        safe.setModuleEnabled(address(module), false);

        vm.prank(authorizedExecutor);
        vm.expectRevert("GS104");
        module.executeOnBehalf(address(batchedTx), batchData);
        assertEq(target.value(), 0, "State unchanged when module disabled");

        // Part B: Re-enable module, but use wrong executor → execution fails.
        safe.setModuleEnabled(address(module), true);

        vm.prank(unauthorizedCaller);
        vm.expectRevert(
            abi.encodeWithSelector(
                ISafeExecutorModule.UnauthorizedCaller.selector, unauthorizedCaller, authorizedExecutor
            )
        );
        module.executeOnBehalf(address(batchedTx), batchData);
        assertEq(target.value(), 0, "State unchanged with wrong executor");

        // Part C: Correct executor + enabled module → execution succeeds.
        vm.prank(authorizedExecutor);
        bool success = module.executeOnBehalf(address(batchedTx), batchData);
        assertTrue(success, "Should succeed with correct executor and enabled module");
        assertEq(target.value(), 42, "State should be updated after successful execution");
    }
}
