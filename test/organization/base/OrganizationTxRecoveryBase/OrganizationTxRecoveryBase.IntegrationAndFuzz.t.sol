// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IAccount} from "interfaces/IAccount.sol";
import {IOrganizationAccountFactory} from "interfaces/organization/IOrganizationAccountFactory.sol";
import {IOrganizationAdmin} from "interfaces/organization/IOrganizationAdmin.sol";
import {IOrganizationTxRecovery} from "interfaces/organization/IOrganizationTxRecovery.sol";
import {
    MockAccountForOrganizationTransaction
} from "test/organization/base/OrganizationAccountTransactionBase/OrganizationAccountTransactionBaseMocks.sol";
import {
    OrganizationTxRecoveryBaseSuiteBase
} from "test/organization/base/OrganizationTxRecoveryBase/OrganizationTxRecoveryBaseSuiteBase.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";
import {OperationType} from "types/CommonTypes.sol";
import {GuardianRecoveryState, PendingRecoveryInitTimelock, TxRecoveryState} from "types/RecoveryTypes.sol";

contract RecoveryFuzzTarget {
    address public lastCaller;
    uint256 public lastValue;
    bytes public lastData;
    uint256 public calls;

    fallback() external payable {
        calls++;
        lastCaller = msg.sender;
        lastValue = msg.value;
        lastData = msg.data;
    }

    receive() external payable {
        calls++;
        lastCaller = msg.sender;
        lastValue = msg.value;
        lastData = bytes("");
    }
}

/**
 * @dev Integration and fuzz coverage for tx-recovery lifecycle/security scenarios.
 */
contract OrganizationTxRecoveryBaseIntegrationAndFuzzTest is OrganizationTxRecoveryBaseSuiteBase {
    function _dummyAuthParams(uint256 salt) internal view returns (AdminAuthParams memory auth) {
        auth = AdminAuthParams({salt: salt, expirationTimestamp: block.timestamp + 30 days, signatures: hex"01"});
    }

    function _callAsTxRecovery(bytes memory payload) internal returns (bool success) {
        vm.prank(TX_RECOVERY);
        (success,) = address(harness).call(payload);
    }

    /// @dev Verifies deferred tx/ERC1271 recovery initialization can be finalized after the admin timelock and then
    /// execute a recovery transaction once the recovery mechanism is enabled.
    function test_deferredSetupLifecycle_fullFlow_succeeds() public {
        // Setup
        _setTxRecoveryState(address(0), false, 0, 0, address(0), 0, 0);

        (AdminAuthParams memory initiateAuth,) = _buildTxRecoveryAuth({
            operationType: OperationType.InitiateInitializeTransactionRecovery,
            recoveryAddress: TX_RECOVERY,
            timelockDurationSeconds: TX_RECOVERY_TIMELOCK,
            salt: 401,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call
        vm.prank(GUARDIAN);
        harness.initiateInitializeTransactionAndERC1271Recovery(TX_RECOVERY, TX_RECOVERY_TIMELOCK, initiateAuth);

        vm.warp(block.timestamp + ADMIN_OPERATION_TIMELOCK);

        (AdminAuthParams memory finalizeAuth,) = _buildTxRecoveryAuth({
            operationType: OperationType.FinalizeInitializeTransactionRecovery,
            recoveryAddress: TX_RECOVERY,
            timelockDurationSeconds: TX_RECOVERY_TIMELOCK,
            salt: 402,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        vm.prank(GUARDIAN);
        harness.finalizeInitializeTransactionAndERC1271Recovery(finalizeAuth);

        vm.prank(TX_RECOVERY);
        harness.initiateEnableTransactionAndERC1271Recovery();
        vm.warp(harness.getTxRecoveryState().pendingEnableTimestamp);
        vm.prank(TX_RECOVERY);
        harness.finalizeEnableTransactionAndERC1271Recovery();

        MockAccountForOrganizationTransaction account = new MockAccountForOrganizationTransaction(address(harness));
        harness.setDeployedAccount(address(account), true);

        vm.prank(TX_RECOVERY);
        harness.executeRecoveryAccountTransaction(address(account), DESTINATION, 0, bytes("txr-int-1"));

        // Verify
        assertEq(account.executionCount(), 1, "deferred lifecycle should allow one recovery execution");
        assertTrue(harness.getTxRecoveryState().isEnabled, "recovery should be enabled at end of lifecycle");
    }

    /// @dev Verifies init-time configured lifecycle supports enable/execute/disable/re-enable/execute.
    function test_initTimeSetupLifecycle_enableDisableReenable_executesAgain() public {
        // Setup
        MockAccountForOrganizationTransaction account = new MockAccountForOrganizationTransaction(address(harness));
        harness.setDeployedAccount(address(account), true);

        // Call
        _enableTxRecovery();
        vm.prank(TX_RECOVERY);
        harness.executeRecoveryAccountTransaction(address(account), DESTINATION, 0, bytes("first"));

        vm.prank(TX_RECOVERY);
        harness.disableTransactionAndERC1271Recovery();

        vm.prank(TX_RECOVERY);
        harness.initiateEnableTransactionAndERC1271Recovery();
        vm.warp(harness.getTxRecoveryState().pendingEnableTimestamp);
        vm.prank(TX_RECOVERY);
        harness.finalizeEnableTransactionAndERC1271Recovery();

        vm.prank(TX_RECOVERY);
        harness.executeRecoveryAccountTransaction(address(account), DESTINATION, 0, bytes("second"));

        // Verify
        assertEq(account.executionCount(), 2, "re-enabled lifecycle should allow another execution");
        assertTrue(harness.getTxRecoveryState().isEnabled, "recovery should end enabled");
    }

    /// @dev Verifies tx/ERC1271 recovery disable is immediate, clears any pending enable state, and prevents the
    /// stale enable-finalize from succeeding later.
    function test_emergencyDisableLifecycle_pendingEnableThenDisable_finalizeFails()
        public
    {
        // Setup
        vm.prank(TX_RECOVERY);
        harness.initiateEnableTransactionAndERC1271Recovery();

        // Call
        vm.prank(TX_RECOVERY);
        harness.disableTransactionAndERC1271Recovery();

        vm.expectRevert(IOrganizationTxRecovery.NoTxRecoveryEnablePending.selector);
        vm.prank(TX_RECOVERY);
        harness.finalizeEnableTransactionAndERC1271Recovery();

        // Verify
        TxRecoveryState memory state = harness.getTxRecoveryState();
        assertFalse(state.isEnabled, "disable should keep recovery disabled");
        assertEq(state.pendingEnableTimestamp, 0, "disable should clear pending enable");
    }

    /// @dev Verifies tx recovery operations do not mutate guardian-recovery state.
    function test_txRecoveryAndGuardianRecovery_independentState_noCrossCorruption() public {
        // Setup
        GuardianRecoveryState memory beforeState = GuardianRecoveryState({
            recoveryAddress: address(0xABC1),
            isUpdateReadyForAcceptance: true,
            pendingGuardian: address(0xABC2),
            timelockDurationSeconds: 5 days,
            pendingGuardianTimestamp: block.timestamp + 1234,
            pendingInit: PendingRecoveryInitTimelock({
                pendingRecoveryAddress: address(0xABC3),
                pendingTimelockDurationSeconds: 4 days,
                pendingTimestamp: block.timestamp + 4321
            })
        });
        harness.setGuardianRecoveryState(beforeState);

        // Call
        _enableTxRecovery();
        vm.prank(TX_RECOVERY);
        harness.disableTransactionAndERC1271Recovery();

        // Verify
        GuardianRecoveryState memory afterState = harness.getGuardianRecoveryState();
        assertEq(afterState.recoveryAddress, beforeState.recoveryAddress, "guardian recovery address must not change");
        assertEq(
            afterState.isUpdateReadyForAcceptance,
            beforeState.isUpdateReadyForAcceptance,
            "guardian ready flag must not change"
        );
        assertEq(afterState.pendingGuardian, beforeState.pendingGuardian, "pending guardian must not change");
        assertEq(
            afterState.timelockDurationSeconds,
            beforeState.timelockDurationSeconds,
            "guardian recovery timelock must not change"
        );
        assertEq(
            afterState.pendingGuardianTimestamp,
            beforeState.pendingGuardianTimestamp,
            "guardian pending timestamp must not change"
        );
        assertEq(
            afterState.pendingInit.pendingRecoveryAddress,
            beforeState.pendingInit.pendingRecoveryAddress,
            "guardian pending-init address must not change"
        );
        assertEq(
            afterState.pendingInit.pendingTimelockDurationSeconds,
            beforeState.pendingInit.pendingTimelockDurationSeconds,
            "guardian pending-init timelock must not change"
        );
        assertEq(
            afterState.pendingInit.pendingTimestamp,
            beforeState.pendingInit.pendingTimestamp,
            "guardian pending-init timestamp must not change"
        );
    }

    /// @dev Verifies guardian cannot call tx-recovery-only entrypoints and tx-recovery cannot call
    /// guardian-only entrypoints.
    function test_roleIsolation_guardianAndTxRecovery_cannotCrossCall() public {
        // Setup
        (AdminAuthParams memory auth,) = _buildTxRecoveryAuth({
            operationType: OperationType.InitiateInitializeTransactionRecovery,
            recoveryAddress: TX_RECOVERY,
            timelockDurationSeconds: TX_RECOVERY_TIMELOCK,
            salt: 410,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call
        _expectOnlyTxRecoveryRevert(GUARDIAN);
        vm.prank(GUARDIAN);
        harness.initiateEnableTransactionAndERC1271Recovery();

        _expectOnlyGuardian(TX_RECOVERY);
        vm.prank(TX_RECOVERY);
        harness.initiateInitializeTransactionAndERC1271Recovery(TX_RECOVERY, TX_RECOVERY_TIMELOCK, auth);

        // Verify
    }

    /// @dev Verifies stale deferred-init admin signatures fail once the pending tx/ERC1271 recovery tuple changes.
    function test_staleAdminSignatures_pendingValuesChanged_revert() public {
        // Setup
        address initialPendingRecovery = address(0xF100);
        address mutatedPendingRecovery = address(0xF200);

        _setTxRecoveryState(address(0), false, 0, 0, address(0), 0, 0);
        (AdminAuthParams memory initiateAuth,) = _buildTxRecoveryAuth({
            operationType: OperationType.InitiateInitializeTransactionRecovery,
            recoveryAddress: initialPendingRecovery,
            timelockDurationSeconds: TX_RECOVERY_TIMELOCK,
            salt: 420,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        vm.prank(GUARDIAN);
        harness.initiateInitializeTransactionAndERC1271Recovery(
            initialPendingRecovery, TX_RECOVERY_TIMELOCK, initiateAuth
        );

        (AdminAuthParams memory staleFinalizeAuth,) = _buildTxRecoveryAuth({
            operationType: OperationType.FinalizeInitializeTransactionRecovery,
            recoveryAddress: initialPendingRecovery,
            timelockDurationSeconds: TX_RECOVERY_TIMELOCK,
            salt: 421,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        (AdminAuthParams memory staleCancelAuth,) = _buildTxRecoveryAuth({
            operationType: OperationType.CancelInitializeTransactionRecovery,
            recoveryAddress: initialPendingRecovery,
            timelockDurationSeconds: TX_RECOVERY_TIMELOCK,
            salt: 422,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        _setTxRecoveryState(address(0), false, 0, 0, mutatedPendingRecovery, TX_RECOVERY_TIMELOCK, block.timestamp);

        // Call + verify
        vm.expectPartialRevert(IOrganizationAdmin.SignerIsNotAdmin.selector);
        vm.prank(GUARDIAN);
        harness.finalizeInitializeTransactionAndERC1271Recovery(staleFinalizeAuth);

        vm.expectPartialRevert(IOrganizationAdmin.SignerIsNotAdmin.selector);
        vm.prank(GUARDIAN);
        harness.cancelInitializeTransactionAndERC1271Recovery(staleCancelAuth);
    }

    /// @dev Verifies recovery execution bypasses guardian and policy checks but still requires the target account to
    /// be deployed by this organization.
    function test_recoveryExecution_bypassesGuardianPolicyButEnforcesAccountDeployment()
        public
    {
        // Setup
        _enableTxRecovery();
        MockAccountForOrganizationTransaction deployedAccount =
            new MockAccountForOrganizationTransaction(address(harness));
        harness.setDeployedAccount(address(deployedAccount), true);

        // Call
        vm.prank(TX_RECOVERY);
        harness.executeRecoveryAccountTransaction(address(deployedAccount), DESTINATION, 0, bytes("txr-int-8"));

        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationAccountFactory.AccountNotDeployedByOrganization.selector, address(0xF8F8F8)
            )
        );
        vm.prank(TX_RECOVERY);
        harness.executeRecoveryAccountTransaction(address(0xF8F8F8), DESTINATION, 0, bytes(""));

        // Verify
        assertEq(deployedAccount.executionCount(), 1, "deployed-account execution should succeed exactly once");
    }

    /// @dev Verifies recovery account call-chains to
    /// organization operations fail closed and leave state unchanged.
    function test_recoveryCallChainsToOrganizationOps_revertAndLeaveStateUnchanged()
        public
    {
        // Setup
        _enableTxRecovery();

        MockAccountForOrganizationTransaction account = new MockAccountForOrganizationTransaction(address(harness));
        harness.setDeployedAccount(address(account), true);

        harness.setPoliciesRoot(bytes32(uint256(0xABCDEF)));
        uint256 thresholdBefore = harness.getVotingThreshold();
        bytes32 policyRootBefore = harness.getPoliciesRoot();
        TxRecoveryState memory txRecoveryBefore = harness.getTxRecoveryState();

        AdminAuthParams memory auth = _dummyAuthParams(430);
        address[] memory empty = new address[](0);
        bytes[] memory organizationPayloads = _buildOrganizationStateChangingPayloads(auth, empty);

        // Call
        for (uint256 i = 0; i < organizationPayloads.length; i++) {
            vm.expectRevert(IAccount.TransactionExecutionFailed.selector);
            vm.prank(TX_RECOVERY);
            harness.executeRecoveryAccountTransaction(address(account), address(harness), 0, organizationPayloads[i]);
        }

        // Verify
        assertEq(account.executionCount(), 0, "blocked organization targets must never reach account execution");
        assertTrue(harness.getAdminStatus(admin1), "admin set should remain unchanged");
        assertTrue(harness.getMemberStatus(admin1), "membership should remain unchanged");
        assertEq(harness.getVotingThreshold(), thresholdBefore, "voting threshold should remain unchanged");
        assertEq(harness.getPoliciesRoot(), policyRootBefore, "policy root should remain unchanged");

        TxRecoveryState memory txRecoveryAfter = harness.getTxRecoveryState();
        assertEq(
            txRecoveryAfter.recoveryAddress, txRecoveryBefore.recoveryAddress, "tx recovery address should not change"
        );
        assertEq(txRecoveryAfter.isEnabled, txRecoveryBefore.isEnabled, "tx recovery enabled flag should not change");
        assertEq(
            txRecoveryAfter.timelockDurationSeconds,
            txRecoveryBefore.timelockDurationSeconds,
            "tx recovery timelock should not change"
        );
        assertEq(
            txRecoveryAfter.pendingEnableTimestamp,
            txRecoveryBefore.pendingEnableTimestamp,
            "tx recovery pending enable should not change"
        );
    }

    /// @dev Verifies organization non-view selector-matrix targets via recovery always revert and preserve
    /// state.
    function test_selectorMatrixToOrganization_alwaysRevertsAndPreservesState() public {
        // Setup
        _enableTxRecovery();
        MockAccountForOrganizationTransaction account = new MockAccountForOrganizationTransaction(address(harness));
        harness.setDeployedAccount(address(account), true);
        TxRecoveryState memory beforeState = harness.getTxRecoveryState();

        AdminAuthParams memory auth = _dummyAuthParams(440);
        address[] memory empty = new address[](0);
        bytes[] memory payloads = _buildOrganizationStateChangingPayloads(auth, empty);

        // Call
        for (uint256 i = 0; i < payloads.length; i++) {
            vm.expectRevert(IAccount.TransactionExecutionFailed.selector);
            vm.prank(TX_RECOVERY);
            harness.executeRecoveryAccountTransaction(address(account), address(harness), 0, payloads[i]);
        }

        // Verify
        assertEq(account.executionCount(), 0, "selector sweep must never execute account call");
        TxRecoveryState memory afterState = harness.getTxRecoveryState();
        assertEq(afterState.recoveryAddress, beforeState.recoveryAddress, "recovery address should remain unchanged");
        assertEq(afterState.isEnabled, beforeState.isEnabled, "enabled state should remain unchanged");
        assertEq(
            afterState.timelockDurationSeconds, beforeState.timelockDurationSeconds, "timelock should remain unchanged"
        );
        assertEq(
            afterState.pendingEnableTimestamp,
            beforeState.pendingEnableTimestamp,
            "pending enable should remain unchanged"
        );
    }

    /// @dev Verifies account non-view selector-matrix targets via recovery always revert and preserve
    /// state.
    function test_selectorMatrixToAccount_alwaysRevertsAndPreservesState() public {
        // Setup
        _enableTxRecovery();
        MockAccountForOrganizationTransaction account = new MockAccountForOrganizationTransaction(address(harness));
        harness.setDeployedAccount(address(account), true);

        bytes[] memory accountPayloads = new bytes[](3);
        accountPayloads[0] = abi.encodeWithSelector(
            IAccount.executeTransaction.selector, DESTINATION, uint256(0), bytes("nested"), uint256(1), uint256(1)
        );
        accountPayloads[1] = abi.encodeWithSelector(
            IAccount.executeTransaction.selector,
            address(harness),
            uint256(1),
            bytes("nested-2"),
            uint256(2),
            uint256(3)
        );
        accountPayloads[2] = abi.encodeWithSelector(
            IAccount.executeTransaction.selector,
            address(account),
            uint256(0),
            bytes("nested-3"),
            uint256(4),
            uint256(5)
        );

        // Call
        for (uint256 i = 0; i < accountPayloads.length; i++) {
            vm.expectRevert(IAccount.TransactionExecutionFailed.selector);
            vm.prank(TX_RECOVERY);
            harness.executeRecoveryAccountTransaction(address(account), address(account), 0, accountPayloads[i]);
        }

        // Verify
        assertEq(account.executionCount(), 0, "account selector sweep should never execute");
    }

    /// @dev Verifies fuzz non-recovery callers are unauthorized across tx-recovery-protected entrypoints.
    function testFuzz_nonRecoveryCallers_entrypointsAlwaysRevertUnauthorized(address caller)
        public
    {
        // Setup
        vm.assume(caller != TX_RECOVERY);
        MockAccountForOrganizationTransaction account = new MockAccountForOrganizationTransaction(address(harness));
        harness.setDeployedAccount(address(account), true);

        // Call
        _expectOnlyTxRecoveryRevert(caller);
        vm.prank(caller);
        harness.initiateEnableTransactionAndERC1271Recovery();

        _expectOnlyTxRecoveryRevert(caller);
        vm.prank(caller);
        harness.finalizeEnableTransactionAndERC1271Recovery();

        _expectOnlyTxRecoveryRevert(caller);
        vm.prank(caller);
        harness.cancelEnableTransactionAndERC1271Recovery();

        _expectOnlyTxRecoveryRevert(caller);
        vm.prank(caller);
        harness.disableTransactionAndERC1271Recovery();

        _expectOnlyTxRecoveryRevert(caller);
        vm.prank(caller);
        harness.executeRecoveryAccountTransaction(address(account), DESTINATION, 0, bytes(""));

        // Verify
    }

    /// @dev Verifies fuzzed recovery-execution tuples forward exact `to/value/data` on successful targets.
    function testFuzz_recoveryExecution_successfulTargets_forwardExactTuple(
        bytes calldata data,
        uint128 rawValue
    ) public {
        // Setup
        _enableTxRecovery();
        MockAccountForOrganizationTransaction account = new MockAccountForOrganizationTransaction(address(harness));
        RecoveryFuzzTarget target = new RecoveryFuzzTarget();
        harness.setDeployedAccount(address(account), true);

        uint256 value = bound(uint256(rawValue), 0, 1 ether);
        vm.deal(address(account), value);

        // Call
        vm.prank(TX_RECOVERY);
        harness.executeRecoveryAccountTransaction(address(account), address(target), value, data);

        // Verify
        assertEq(account.executionCount(), 1, "recovery execution should run exactly once");
        assertEq(account.lastTo(), address(target), "account target should match");
        assertEq(account.lastValue(), value, "account value should match");
        assertEq(account.lastData(), data, "account data should match");

        assertEq(target.calls(), 1, "target should receive exactly one call");
        assertEq(target.lastCaller(), address(account), "target caller should be account");
        assertEq(target.lastValue(), value, "target value should match");
        assertEq(target.lastData(), data, "target calldata should match");
    }

    /// @dev Verifies fuzzed non-view selector sweep to organization target always reverts.
    function testFuzz_selectorSweepToOrganizationStateChanging_alwaysReverts(uint8 rawIndex) public {
        // Setup
        _enableTxRecovery();
        MockAccountForOrganizationTransaction account = new MockAccountForOrganizationTransaction(address(harness));
        harness.setDeployedAccount(address(account), true);
        AdminAuthParams memory auth = _dummyAuthParams(450 + uint256(rawIndex));
        address[] memory empty = new address[](0);
        bytes[] memory payloads = _buildOrganizationStateChangingPayloads(auth, empty);

        bytes memory payload = payloads[bound(rawIndex, 0, payloads.length - 1)];

        // Call
        vm.expectRevert(IAccount.TransactionExecutionFailed.selector);
        vm.prank(TX_RECOVERY);
        harness.executeRecoveryAccountTransaction(address(account), address(harness), 0, payload);

        // Verify
        assertEq(account.executionCount(), 0, "organization selector sweep should fully revert account execution");
    }

    /// @dev Verifies fuzzed non-view selector sweep to account target always reverts.
    function testFuzz_selectorSweepToAccountStateChanging_alwaysReverts(
        address nestedTo,
        uint128 rawNestedValue,
        bytes calldata nestedData,
        uint256 nonce,
        uint256 policyId
    ) public {
        // Setup
        _enableTxRecovery();
        MockAccountForOrganizationTransaction account = new MockAccountForOrganizationTransaction(address(harness));
        harness.setDeployedAccount(address(account), true);
        bytes memory payload = abi.encodeWithSelector(
            IAccount.executeTransaction.selector, nestedTo, uint256(rawNestedValue), nestedData, nonce, policyId
        );

        // Call
        vm.expectRevert(IAccount.TransactionExecutionFailed.selector);
        vm.prank(TX_RECOVERY);
        harness.executeRecoveryAccountTransaction(address(account), address(account), 0, payload);

        // Verify
        assertEq(account.executionCount(), 0, "account selector sweep should fully revert account execution");
    }

    /// @dev Verifies repeated enable/disable cycles preserve immutable config and legal transitions.
    function testFuzz_repeatedEnableDisable_cyclesPreserveConfig(uint8 rawCycles) public {
        // Setup
        uint8 cycles = uint8(bound(rawCycles, 1, 16));
        TxRecoveryState memory baseline = harness.getTxRecoveryState();

        // Call
        for (uint8 i = 0; i < cycles; i++) {
            vm.prank(TX_RECOVERY);
            harness.initiateEnableTransactionAndERC1271Recovery();
            vm.warp(harness.getTxRecoveryState().pendingEnableTimestamp);
            vm.prank(TX_RECOVERY);
            harness.finalizeEnableTransactionAndERC1271Recovery();

            TxRecoveryState memory enabledState = harness.getTxRecoveryState();
            assertTrue(enabledState.isEnabled, "cycle finalize should enable recovery");
            assertEq(enabledState.pendingEnableTimestamp, 0, "enabled state should clear pending enable");
            assertEq(enabledState.recoveryAddress, baseline.recoveryAddress, "recovery address must remain immutable");
            assertEq(
                enabledState.timelockDurationSeconds, baseline.timelockDurationSeconds, "timelock must remain immutable"
            );

            vm.prank(TX_RECOVERY);
            harness.disableTransactionAndERC1271Recovery();

            TxRecoveryState memory disabledState = harness.getTxRecoveryState();
            assertFalse(disabledState.isEnabled, "cycle disable should disable recovery");
            assertEq(disabledState.pendingEnableTimestamp, 0, "disable should keep pending enable cleared");
            assertEq(disabledState.recoveryAddress, baseline.recoveryAddress, "recovery address must remain immutable");
            assertEq(
                disabledState.timelockDurationSeconds,
                baseline.timelockDurationSeconds,
                "timelock must remain immutable"
            );
        }

        // Verify
    }

    /// @dev Verifies mixed enable/finalize/disable sequences maintain enabled-state invariants.
    function testFuzz_mixedEnableFinalizeDisable_sequencesMaintainEnabledInvariants(
        bytes32 seed,
        uint8 rawSteps
    ) public {
        // Setup
        uint8 steps = uint8(bound(rawSteps, 1, 64));

        // Call
        for (uint8 i = 0; i < steps; i++) {
            uint256 randomness = uint256(keccak256(abi.encode(seed, i)));
            uint256 operation = randomness % 3;

            if (operation == 0) {
                _callAsTxRecovery(abi.encodeWithSelector(harness.initiateEnableTransactionAndERC1271Recovery.selector));
            } else if (operation == 1) {
                vm.warp(block.timestamp + (randomness % (TX_RECOVERY_TIMELOCK + 2)));
                _callAsTxRecovery(abi.encodeWithSelector(harness.finalizeEnableTransactionAndERC1271Recovery.selector));
            } else {
                _callAsTxRecovery(abi.encodeWithSelector(harness.disableTransactionAndERC1271Recovery.selector));
            }

            TxRecoveryState memory state = harness.getTxRecoveryState();
            if (state.isEnabled) {
                assertTrue(state.recoveryAddress != address(0), "enabled state must have configured recovery address");
                assertTrue(state.timelockDurationSeconds != 0, "enabled state must have configured timelock duration");
                assertEq(state.pendingEnableTimestamp, 0, "enabled state must not have pending-enable timestamp");
            }
        }

        // Verify
    }
}
