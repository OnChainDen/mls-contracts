// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

import {AccountImplementation} from "account/AccountImplementation.sol";
import {IAccount} from "interfaces/IAccount.sol";
import {IOrganizationAccountFactory} from "interfaces/organization/IOrganizationAccountFactory.sol";
import {IOrganizationAdmin} from "interfaces/organization/IOrganizationAdmin.sol";
import {IOrganizationAdminOperationTimelock} from "interfaces/organization/IOrganizationAdminOperationTimelock.sol";
import {IOrganizationSignatures} from "interfaces/organization/IOrganizationSignatures.sol";
import {IOrganizationTxRecovery} from "interfaces/organization/IOrganizationTxRecovery.sol";
import {TimelockUtils} from "libraries/TimelockUtils.sol";
import {
    MockAccountForOrganizationTransaction,
    MockInteractionTarget,
    MockNativeReceiver
} from "test/organization/base/OrganizationAccountTransactionBase/OrganizationAccountTransactionBaseMocks.sol";
import {
    OrganizationTxRecoveryBaseSuiteBase
} from "test/organization/base/OrganizationTxRecoveryBase/OrganizationTxRecoveryBaseSuiteBase.sol";
import {
    OrganizationTxRecoveryBaseHarness
} from "test/organization/base/OrganizationTxRecoveryBase/OrganizationTxRecoveryBaseHarness.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";
import {OperationType} from "types/CommonTypes.sol";
import {PendingRecoveryInitTimelock, TxRecoveryState} from "types/RecoveryTypes.sol";

/**
 * @dev Unit/integration tests for `OrganizationTxRecoveryBase` entry points.
 */
contract OrganizationTxRecoveryBaseTxRecoveryEntryPointsTest is OrganizationTxRecoveryBaseSuiteBase {
    address internal constant ALT_TX_RECOVERY = address(0x710AA);

    /// @dev Verifies OTRB-IETR-1 and OTRB-IETR-2: non-recovery callers (including guardian) revert via
    /// `onlyTxRecoveryAddress`.
    function test_OTRB_IETR_1__OTRB_IETR_2_nonRecoveryCallerAndGuardian_revertUnauthorizedTxRecoveryAddress() public {
        // Setup

        // Call
        _expectOnlyTxRecoveryRevert(NON_GUARDIAN);
        vm.prank(NON_GUARDIAN);
        harness.initiateEnableTransactionAndERC1271Recovery();

        _expectOnlyTxRecoveryRevert(GUARDIAN);
        vm.prank(GUARDIAN);
        harness.initiateEnableTransactionAndERC1271Recovery();

        // Verify
        assertEq(harness.getTxRecoveryState().pendingEnableTimestamp, 0, "pending enable must stay unset");
    }

    /// @dev Verifies OTRB-IETR-3: authorized tx-recovery caller reaches library initiate-enable flow.
    function test_OTRB_IETR_3_authorizedRecoveryCaller_initiatesEnableFlow() public {
        // Setup
        uint256 expectedPending = block.timestamp + TX_RECOVERY_TIMELOCK;

        // Call
        vm.prank(TX_RECOVERY);
        harness.initiateEnableTransactionAndERC1271Recovery();

        // Verify
        assertEq(
            harness.getTxRecoveryState().pendingEnableTimestamp, expectedPending, "pending enable timestamp mismatch"
        );
    }

    /// @dev Verifies OTRB-IETR-4: with zero timelock configuration, initiate bubbles invalid timelock validation.
    function test_OTRB_IETR_4_initiateEnable_zeroTimelock_bubblesInvalidTimelockDuration() public {
        // Setup
        _setTxRecoveryState(TX_RECOVERY, false, 0, 0, address(0), 0, 0);

        // Call
        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockUtils.InvalidTimelockDuration.selector,
                0,
                TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS,
                TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
            )
        );
        vm.prank(TX_RECOVERY);
        harness.initiateEnableTransactionAndERC1271Recovery();

        // Verify
        assertEq(harness.getTxRecoveryState().pendingEnableTimestamp, 0, "pending enable should remain zero");
    }

    /// @dev Verifies `OrganizationTxRecoveryBase.initiateEnableTransactionAndERC1271Recovery` bubbles
    /// `TxRecoveryNotConfigured` when storage has a zero recovery address with an in-range timelock.
    function test_OTRB_IETR_4_A__OREC_TRF_2_initiateEnable_zeroRecoveryAddress_bubblesTxRecoveryNotConfigured()
        public
    {
        // Setup: seed unconfigured recovery state with a valid timelock and use zero-address caller to satisfy
        // `onlyTxRecoveryAddress` so execution reaches library-level configuration checks.
        _setTxRecoveryState(address(0), false, TX_RECOVERY_TIMELOCK, 0, address(0), 0, 0);

        // Call: initiate enable as `address(0)` and expect the not-configured custom error from library validation.
        vm.expectRevert(IOrganizationTxRecovery.TxRecoveryNotConfigured.selector);
        vm.prank(address(0));
        harness.initiateEnableTransactionAndERC1271Recovery();

        // Verify: pending-enable state remains unchanged after the failed call.
        assertEq(harness.getTxRecoveryState().pendingEnableTimestamp, 0, "pending enable should remain zero");
    }

    /// @dev Verifies OTRB-IETR-5 and OTRB-IETR-6: initiate bubbles `already-enabled` and `already-pending` guards.
    function test_OTRB_IETR_5__OTRB_IETR_6_initiateEnable_alreadyEnabledOrPending_reverts() public {
        // Setup
        _setTxRecoveryState(TX_RECOVERY, true, TX_RECOVERY_TIMELOCK, 0, address(0), 0, 0);

        // Call
        vm.expectRevert(IOrganizationTxRecovery.TxRecoveryAlreadyEnabled.selector);
        vm.prank(TX_RECOVERY);
        harness.initiateEnableTransactionAndERC1271Recovery();

        _setTxRecoveryState(TX_RECOVERY, false, TX_RECOVERY_TIMELOCK, block.timestamp + 1, address(0), 0, 0);
        vm.expectRevert(IOrganizationTxRecovery.TxRecoveryEnableAlreadyPending.selector);
        vm.prank(TX_RECOVERY);
        harness.initiateEnableTransactionAndERC1271Recovery();

        // Verify
        assertEq(
            harness.getTxRecoveryState().pendingEnableTimestamp,
            block.timestamp + 1,
            "pending enable should remain unchanged"
        );
    }

    /// @dev Verifies OTRB-FETR-1, OTRB-FETR-2, and OTRB-FETR-3: finalize access and timelock guards.
    function test_OTRB_FETR_1__OTRB_FETR_2__OTRB_FETR_3__OREC_TRF_1_finalizeEnable_accessAndTimelockGuards_revert()
        public
    {
        // Setup
        _expectOnlyTxRecoveryRevert(NON_GUARDIAN);
        vm.prank(NON_GUARDIAN);
        harness.finalizeEnableTransactionAndERC1271Recovery();

        // Call
        vm.expectRevert(IOrganizationTxRecovery.NoTxRecoveryEnablePending.selector);
        vm.prank(TX_RECOVERY);
        harness.finalizeEnableTransactionAndERC1271Recovery();

        vm.prank(TX_RECOVERY);
        harness.initiateEnableTransactionAndERC1271Recovery();

        uint256 pending = harness.getTxRecoveryState().pendingEnableTimestamp;
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationAdminOperationTimelock.TimelockNotExpired.selector, pending, block.timestamp
            )
        );
        vm.prank(TX_RECOVERY);
        harness.finalizeEnableTransactionAndERC1271Recovery();

        // Verify
        assertFalse(harness.getTxRecoveryState().isEnabled, "recovery should remain disabled");
    }

    /// @dev Verifies OTRB-FETR-4, OTRB-FETR-5, and OTRB-FETR-6: finalize succeeds at boundary, clears pending, and
    /// cannot be replayed.
    function test_OTRB_FETR_4__OTRB_FETR_5__OTRB_FETR_6_finalizeEnable_boundarySuccessAndReplayGuard() public {
        // Setup
        vm.prank(TX_RECOVERY);
        harness.initiateEnableTransactionAndERC1271Recovery();

        uint256 pending = harness.getTxRecoveryState().pendingEnableTimestamp;
        vm.warp(pending);

        // Call
        vm.prank(TX_RECOVERY);
        harness.finalizeEnableTransactionAndERC1271Recovery();

        // Verify
        TxRecoveryState memory state = harness.getTxRecoveryState();
        assertTrue(state.isEnabled, "recovery should be enabled");
        assertEq(state.pendingEnableTimestamp, 0, "pending enable must be cleared");

        vm.expectRevert(IOrganizationTxRecovery.NoTxRecoveryEnablePending.selector);
        vm.prank(TX_RECOVERY);
        harness.finalizeEnableTransactionAndERC1271Recovery();
    }

    /// @dev Verifies OTRB-CETR-1 and OTRB-CETR-2: cancel-enable access/no-pending guards.
    function test_OTRB_CETR_1__OTRB_CETR_2_cancelEnable_accessAndNoPendingGuards_revert() public {
        // Setup

        // Call
        _expectOnlyTxRecoveryRevert(NON_GUARDIAN);
        vm.prank(NON_GUARDIAN);
        harness.cancelEnableTransactionAndERC1271Recovery();

        vm.expectRevert(IOrganizationTxRecovery.NoTxRecoveryEnablePending.selector);
        vm.prank(TX_RECOVERY);
        harness.cancelEnableTransactionAndERC1271Recovery();

        // Verify
        assertEq(harness.getTxRecoveryState().pendingEnableTimestamp, 0, "pending must remain zero");
    }

    /// @dev Verifies OTRB-CETR-3, OTRB-CETR-4, and OTRB-CETR-5: cancel clears pending, works after expiry, and never
    /// enables recovery.
    function test_OTRB_CETR_3__OTRB_CETR_4__OTRB_CETR_5_cancelEnable_clearsPendingAndDoesNotEnable() public {
        // Setup
        vm.prank(TX_RECOVERY);
        harness.initiateEnableTransactionAndERC1271Recovery();

        uint256 pending = harness.getTxRecoveryState().pendingEnableTimestamp;
        vm.warp(pending + 1);

        // Call
        vm.prank(TX_RECOVERY);
        harness.cancelEnableTransactionAndERC1271Recovery();

        // Verify
        TxRecoveryState memory state = harness.getTxRecoveryState();
        assertEq(state.pendingEnableTimestamp, 0, "pending enable should be cleared");
        assertFalse(state.isEnabled, "cancel should never enable recovery");
    }

    /// @dev Verifies OTRB-DTER-1: disable is protected by `onlyTxRecoveryAddress`.
    function test_OTRB_DTER_1_disable_nonRecoveryCaller_revertsUnauthorizedTxRecoveryAddress() public {
        // Setup

        // Call
        _expectOnlyTxRecoveryRevert(NON_GUARDIAN);
        vm.prank(NON_GUARDIAN);
        harness.disableTransactionAndERC1271Recovery();

        // Verify
        assertFalse(harness.getTxRecoveryState().isEnabled, "state should remain unchanged");
    }

    /// @dev Verifies OTRB-DTER-2, OTRB-DTER-3, OTRB-DTER-4, and OTRB-DTER-5: disable clears enabled/pending state, is
    /// idempotent, and blocks recovery execution.
    function test_OTRB_DTER_2__OTRB_DTER_3__OTRB_DTER_4__OTRB_DTER_5_disable_clearsStateAndBlocksExecution() public {
        // Setup
        _enableTxRecovery();
        _setTxRecoveryState(TX_RECOVERY, false, TX_RECOVERY_TIMELOCK, block.timestamp + 1, address(0), 0, 0);

        // Call
        vm.prank(TX_RECOVERY);
        harness.disableTransactionAndERC1271Recovery();

        // Verify
        TxRecoveryState memory state = harness.getTxRecoveryState();
        assertFalse(state.isEnabled, "disable must set isEnabled=false");
        assertEq(state.pendingEnableTimestamp, 0, "disable must clear pending enable");

        vm.prank(TX_RECOVERY);
        harness.disableTransactionAndERC1271Recovery();
        assertFalse(harness.getTxRecoveryState().isEnabled, "second disable should still be safe");

        MockAccountForOrganizationTransaction account = new MockAccountForOrganizationTransaction(address(harness));
        harness.setDeployedAccount(address(account), true);

        vm.expectRevert(IOrganizationTxRecovery.TxRecoveryNotEnabled.selector);
        vm.prank(TX_RECOVERY);
        harness.executeRecoveryAccountTransaction(address(account), DESTINATION, 0, bytes(""));
    }

    /// @dev Verifies OTRB-ERAT-1, OTRB-ERAT-2, and OTRB-ERAT-3: execute-recovery access/config/enabled guards.
    function test_OTRB_ERAT_1__OTRB_ERAT_2__OTRB_ERAT_3_executeRecovery_accessAndEnableGuards_revert() public {
        // Setup
        MockAccountForOrganizationTransaction account = new MockAccountForOrganizationTransaction(address(harness));
        harness.setDeployedAccount(address(account), true);

        // Call
        _expectOnlyTxRecoveryRevert(NON_GUARDIAN);
        vm.prank(NON_GUARDIAN);
        harness.executeRecoveryAccountTransaction(address(account), DESTINATION, 0, bytes(""));

        _setTxRecoveryState(TX_RECOVERY, false, 0, 0, address(0), 0, 0);
        vm.expectRevert(IOrganizationTxRecovery.TxRecoveryNotConfigured.selector);
        vm.prank(TX_RECOVERY);
        harness.executeRecoveryAccountTransaction(address(account), DESTINATION, 0, bytes(""));

        _setTxRecoveryState(TX_RECOVERY, false, TX_RECOVERY_TIMELOCK, 0, address(0), 0, 0);
        vm.expectRevert(IOrganizationTxRecovery.TxRecoveryNotEnabled.selector);
        vm.prank(TX_RECOVERY);
        harness.executeRecoveryAccountTransaction(address(account), DESTINATION, 0, bytes(""));

        // Verify
        assertEq(account.executionCount(), 0, "account execution should never be reached");
    }

    /// @dev Verifies OTRB-ERAT-4 and OTRB-ERAT-5: pending enable (pre/post-expiry) is not sufficient before finalize.
    function test_OTRB_ERAT_4__OTRB_ERAT_5_executeRecovery_pendingEnableNotFinalized_revertsTxRecoveryNotEnabled()
        public
    {
        // Setup
        MockAccountForOrganizationTransaction account = new MockAccountForOrganizationTransaction(address(harness));
        harness.setDeployedAccount(address(account), true);

        vm.prank(TX_RECOVERY);
        harness.initiateEnableTransactionAndERC1271Recovery();

        // Call
        vm.expectRevert(IOrganizationTxRecovery.TxRecoveryNotEnabled.selector);
        vm.prank(TX_RECOVERY);
        harness.executeRecoveryAccountTransaction(address(account), DESTINATION, 0, bytes(""));

        vm.warp(harness.getTxRecoveryState().pendingEnableTimestamp + 1);
        vm.expectRevert(IOrganizationTxRecovery.TxRecoveryNotEnabled.selector);
        vm.prank(TX_RECOVERY);
        harness.executeRecoveryAccountTransaction(address(account), DESTINATION, 0, bytes(""));

        // Verify
        assertEq(account.executionCount(), 0, "account execution should remain blocked");
    }

    /// @dev Verifies OTRB-ERAT-6 and OTRB-ERAT-13: deployed-account check occurs after recovery-enabled validation.
    function test_OTRB_ERAT_6__OTRB_ERAT_13_executeRecovery_validationOrder_preserved() public {
        // Setup
        _setTxRecoveryState(TX_RECOVERY, false, TX_RECOVERY_TIMELOCK, 0, address(0), 0, 0);

        // Call
        vm.expectRevert(IOrganizationTxRecovery.TxRecoveryNotEnabled.selector);
        vm.prank(TX_RECOVERY);
        harness.executeRecoveryAccountTransaction(address(0xFEED01), DESTINATION, 0, bytes(""));

        _enableTxRecovery();
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationAccountFactory.AccountNotDeployedByOrganization.selector, address(0xFEED01)
            )
        );
        vm.prank(TX_RECOVERY);
        harness.executeRecoveryAccountTransaction(address(0xFEED01), DESTINATION, 0, bytes(""));

        // Verify
    }

    /// @dev Verifies OTRB-ERAT-7, OTRB-ERAT-8, and OTRB-ERAT-9: successful execution emits event and forwards exact
    /// tuple with nonce/policy fixed to zero.
    function test_OTRB_ERAT_7__OTRB_ERAT_8__OTRB_ERAT_9_executeRecovery_success_emitsAndForwardsExpectedTuple() public {
        // Setup
        _enableTxRecovery();
        MockAccountForOrganizationTransaction account = new MockAccountForOrganizationTransaction(address(harness));
        harness.setDeployedAccount(address(account), true);

        bytes memory payload = abi.encodeWithSelector(bytes4(0xCAFEBABE), uint256(11));

        vm.expectEmit(true, true, true, true);
        emit IOrganizationTxRecovery.RecoveryAccountTransactionExecuted(address(account), DESTINATION, 0, payload);

        // Call
        vm.prank(TX_RECOVERY);
        harness.executeRecoveryAccountTransaction(address(account), DESTINATION, 0, payload);

        // Verify
        assertEq(account.lastTo(), DESTINATION, "destination should be forwarded");
        assertEq(account.lastValue(), 0, "value should be forwarded");
        assertEq(account.lastData(), payload, "payload should be forwarded");
        assertEq(account.lastNonce(), 0, "recovery path must force nonce=0");
        assertEq(account.lastPolicyId(), 0, "recovery path must force policyId=0");
    }

    /// @dev Verifies the real `AccountImplementation` emits `IAccount.TransactionExecuted` with nonce=0 and policyId=0
    /// when invoked through the recovery execution path.
    function test_OTRB_ERAT_7__OTRB_ERAT_8__OTRB_ERAT_9__OREC_TRF_5_executeRecovery_realAccount_emitsAccountTransactionExecuted()
        public
    {
        // Setup: deploy real AccountImplementation behind a BeaconProxy pointing to the harness as beacon.
        _enableTxRecovery();
        harness.setAccountImplementation(address(new AccountImplementation()));
        address realAccount = address(new BeaconProxy(address(harness), bytes("")));
        harness.setDeployedAccount(realAccount, true);

        MockInteractionTarget target = new MockInteractionTarget();
        bytes memory payload = abi.encodeWithSelector(target.ping.selector, uint256(11));

        // Call: expect both the organization-level recovery event and the account-level execution event.
        vm.expectEmit(true, true, true, true);
        emit IOrganizationTxRecovery.RecoveryAccountTransactionExecuted(realAccount, address(target), 0, payload);

        vm.expectEmit(true, true, true, true);
        emit IAccount.TransactionExecuted(address(target), 0, payload, 0, 0);

        vm.prank(TX_RECOVERY);
        harness.executeRecoveryAccountTransaction(realAccount, address(target), 0, payload);

        // Verify: downstream target confirms the call arrived from the real account.
        assertEq(target.calls(), 1, "target should be called once");
        assertEq(target.lastCaller(), realAccount, "call should originate from real account");
        assertEq(target.total(), 11, "calldata should be processed by target");
    }

    /// @dev Verifies OTRB-ERAT-10 and OTRB-ERAT-11: native transfer and contract-call recovery execution succeed
    /// end-to-end.
    function test_OTRB_ERAT_10__OTRB_ERAT_11_executeRecovery_nativeTransferAndContractCall_succeed() public {
        // Setup
        _enableTxRecovery();
        MockAccountForOrganizationTransaction account = new MockAccountForOrganizationTransaction(address(harness));
        harness.setDeployedAccount(address(account), true);

        MockNativeReceiver receiver = new MockNativeReceiver();
        MockInteractionTarget target = new MockInteractionTarget();
        uint256 value = 0.2 ether;
        vm.deal(address(account), value);

        // Call
        vm.prank(TX_RECOVERY);
        harness.executeRecoveryAccountTransaction(address(account), address(receiver), value, bytes(""));

        bytes memory payload = abi.encodeWithSelector(target.ping.selector, uint256(21));
        vm.prank(TX_RECOVERY);
        harness.executeRecoveryAccountTransaction(address(account), address(target), 0, payload);

        // Verify
        assertEq(receiver.totalReceived(), value, "native transfer should reach receiver");
        assertEq(target.calls(), 1, "contract interaction should execute once");
        assertEq(target.lastCaller(), address(account), "account should call downstream target");
        assertEq(target.total(), 21, "calldata should be processed by target");
    }

    /// @dev Verifies OTRB-ERAT-12 and OTRB-ERAT-20: downstream account revert bubbles and no recovery event persists.
    function test_OTRB_ERAT_12__OTRB_ERAT_20__OREC_TRF_6_executeRecovery_downstreamRevert_bubblesAndNoRecoveryEventPersists()
        public
    {
        // Setup
        _enableTxRecovery();
        MockAccountForOrganizationTransaction account = new MockAccountForOrganizationTransaction(address(harness));
        account.setShouldRevertExecution(true);
        harness.setDeployedAccount(address(account), true);

        // Call
        vm.expectRevert(IAccount.TransactionExecutionFailed.selector);
        vm.prank(TX_RECOVERY);
        harness.executeRecoveryAccountTransaction(address(account), DESTINATION, 0, bytes(""));

        // Verify
        assertEq(account.executionCount(), 0, "full revert should rollback account execution count");
    }

    /// @dev Verifies OTRB-ERAT-14: executing recovery tx does not mutate tx-recovery configuration fields.
    function test_OTRB_ERAT_14_executeRecovery_doesNotMutateTxRecoveryConfigFields() public {
        // Setup
        _setTxRecoveryState(TX_RECOVERY, true, TX_RECOVERY_TIMELOCK, 0, address(0), 0, 0);
        TxRecoveryState memory beforeState = harness.getTxRecoveryState();

        MockAccountForOrganizationTransaction account = new MockAccountForOrganizationTransaction(address(harness));
        harness.setDeployedAccount(address(account), true);

        // Call
        vm.prank(TX_RECOVERY);
        harness.executeRecoveryAccountTransaction(address(account), DESTINATION, 0, bytes(""));

        // Verify
        TxRecoveryState memory afterState = harness.getTxRecoveryState();
        assertEq(afterState.recoveryAddress, beforeState.recoveryAddress, "recovery address must not change");
        assertEq(afterState.timelockDurationSeconds, beforeState.timelockDurationSeconds, "timelock must not change");
        assertEq(afterState.isEnabled, beforeState.isEnabled, "enabled flag must not change");
        assertEq(
            afterState.pendingEnableTimestamp, beforeState.pendingEnableTimestamp, "pending enable must not change"
        );
        assertEq(
            afterState.pendingInit.pendingRecoveryAddress,
            beforeState.pendingInit.pendingRecoveryAddress,
            "pending init address must not change"
        );
        assertEq(
            afterState.pendingInit.pendingTimelockDurationSeconds,
            beforeState.pendingInit.pendingTimelockDurationSeconds,
            "pending init timelock must not change"
        );
        assertEq(
            afterState.pendingInit.pendingTimestamp,
            beforeState.pendingInit.pendingTimestamp,
            "pending init timestamp must not change"
        );
    }

    /// @dev Verifies OTRB-ERAT-15: recovery execution targeting organization state-changing selectors fails closed.
    ///      Sweeps every non-view Organization function selector to ensure none can be invoked via recovery execution.
    function test_OTRB_ERAT_15_executeRecovery_targetingOrganization_revertsTransactionExecutionFailed() public {
        // Setup
        _enableTxRecovery();
        MockAccountForOrganizationTransaction account = new MockAccountForOrganizationTransaction(address(harness));
        harness.setDeployedAccount(address(account), true);

        AdminAuthParams memory auth = AdminAuthParams({salt: 0, expirationTimestamp: 0, signatures: hex""});
        address[] memory empty = new address[](0);

        bytes[] memory payloads = _buildOrganizationStateChangingPayloads(auth, empty);

        // Call
        for (uint256 i = 0; i < payloads.length; i++) {
            vm.expectRevert(IAccount.TransactionExecutionFailed.selector);
            vm.prank(TX_RECOVERY);
            harness.executeRecoveryAccountTransaction(address(account), address(harness), 0, payloads[i]);
        }

        // Verify
        assertEq(account.executionCount(), 0, "organization target failure should fully revert account execution");
    }

    /// @dev Verifies OTRB-ERAT-16: recovery execution targeting account state-changing selectors fails closed.
    ///      `IAccount.executeTransaction` is the only state-changing Account function; sweep varies nested call
    /// arguments (to external, to organization, to self) and also attempts every Organization state-changing selector
    /// on the
    ///      account address to confirm the account rejects unknown selectors.
    function test_OTRB_ERAT_16_executeRecovery_targetingAccount_revertsTransactionExecutionFailedForSelectorSweep()
        public
    {
        // Setup
        _enableTxRecovery();
        MockAccountForOrganizationTransaction account = new MockAccountForOrganizationTransaction(address(harness));
        harness.setDeployedAccount(address(account), true);

        AdminAuthParams memory auth = AdminAuthParams({salt: 0, expirationTimestamp: 0, signatures: hex""});
        address[] memory empty = new address[](0);

        bytes[] memory accountPayloads = new bytes[](5);
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
        accountPayloads[3] = abi.encodeWithSelector(
            IAccount.executeTransaction.selector, address(0), uint256(0), bytes(""), uint256(0), uint256(0)
        );
        accountPayloads[4] = abi.encodeWithSelector(
            IAccount.executeTransaction.selector,
            DESTINATION,
            uint256(1 ether),
            bytes("value-tx"),
            uint256(99),
            uint256(42)
        );

        // Call: sweep executeTransaction (only state-changing Account selector) with varied nested params.
        for (uint256 i = 0; i < accountPayloads.length; i++) {
            vm.expectRevert(IAccount.TransactionExecutionFailed.selector);
            vm.prank(TX_RECOVERY);
            harness.executeRecoveryAccountTransaction(address(account), address(account), 0, accountPayloads[i]);
        }

        // Call: sweep every Organization state-changing selector on the account address to confirm the account rejects
        // unrecognized function selectors.
        bytes[] memory orgPayloads = _buildOrganizationStateChangingPayloads(auth, empty);
        for (uint256 i = 0; i < orgPayloads.length; i++) {
            vm.expectRevert(IAccount.TransactionExecutionFailed.selector);
            vm.prank(TX_RECOVERY);
            harness.executeRecoveryAccountTransaction(address(account), address(account), 0, orgPayloads[i]);
        }

        // Verify
        assertEq(account.executionCount(), 0, "account self-target failure should fully revert account execution");
    }

    /// @dev Verifies OTRB-IITR-1 and OTRB-IITR-2: initiate-initialize is guardian-gated and enforces sufficient admin
    /// authorization.
    function test_OTRB_IITR_1__OTRB_IITR_2_initiateInitialize_nonGuardianOrInsufficientAuth_reverts() public {
        // Setup
        _setTxRecoveryState(address(0), false, 0, 0, address(0), 0, 0);

        (AdminAuthParams memory auth,) = _buildTxRecoveryAuth({
            operationType: OperationType.InitiateInitializeTransactionRecovery,
            recoveryAddress: ALT_TX_RECOVERY,
            timelockDurationSeconds: TX_RECOVERY_TIMELOCK,
            salt: 101,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        _setMembersAndAdmins({members: buildArray(admin1, admin2), admins: buildArray(admin1, admin2), threshold: 2});

        // Call
        _expectOnlyGuardian(NON_GUARDIAN);
        vm.prank(NON_GUARDIAN);
        harness.initiateInitializeTransactionAndERC1271Recovery(ALT_TX_RECOVERY, TX_RECOVERY_TIMELOCK, auth);

        vm.expectRevert(IOrganizationAdmin.InsufficientAdminAuthorization.selector);
        vm.prank(GUARDIAN);
        harness.initiateInitializeTransactionAndERC1271Recovery(ALT_TX_RECOVERY, TX_RECOVERY_TIMELOCK, auth);

        // Verify
        assertEq(
            harness.getTxRecoveryState().pendingInit.pendingTimestamp,
            0,
            "pending init should remain unset on failed auth"
        );
    }

    /// @dev Verifies OTRB-IITR-3, OTRB-IITR-4, OTRB-IITR-5, OTRB-IITR-6, OTRB-IITR-7, OTRB-IITR-8, and OTRB-IITR-9
    /// across auth binding/replay and successful initiation.
    function test_OTRB_IITR_3__OTRB_IITR_4__OTRB_IITR_5__OTRB_IITR_6__OTRB_IITR_7__OTRB_IITR_8__OTRB_IITR_9__NMTRB_ITR_1__NMTRB_ITR_7_initiateInitialize_authBindingReplayAndSuccess()
        public
    {
        // Setup
        _setTxRecoveryState(address(0), false, 0, 0, address(0), 0, 0);

        (AdminAuthParams memory validAuth, bytes memory validOperationData) = _buildTxRecoveryAuth({
            operationType: OperationType.InitiateInitializeTransactionRecovery,
            recoveryAddress: ALT_TX_RECOVERY,
            timelockDurationSeconds: TX_RECOVERY_TIMELOCK,
            salt: 102,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        AdminAuthParams memory rejectionAuth = _buildAdminAuthParamsForEOA({
            operationType: OperationType.InitiateInitializeTransactionRecovery,
            operationData: validOperationData,
            isApproval: false,
            salt: 103,
            expirationTimestamp: block.timestamp + 1 days,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        AdminAuthParams memory wrongTypeAuth = _buildAdminAuthParamsForEOA({
            operationType: OperationType.FinalizeInitializeTransactionRecovery,
            operationData: validOperationData,
            isApproval: true,
            salt: 104,
            expirationTimestamp: block.timestamp + 1 days,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call
        vm.expectPartialRevert(IOrganizationAdmin.SignerIsNotAdmin.selector);
        vm.prank(GUARDIAN);
        harness.initiateInitializeTransactionAndERC1271Recovery(ALT_TX_RECOVERY, TX_RECOVERY_TIMELOCK, rejectionAuth);

        vm.expectPartialRevert(IOrganizationAdmin.SignerIsNotAdmin.selector);
        vm.prank(GUARDIAN);
        harness.initiateInitializeTransactionAndERC1271Recovery(ALT_TX_RECOVERY, TX_RECOVERY_TIMELOCK, wrongTypeAuth);

        vm.expectPartialRevert(IOrganizationAdmin.SignerIsNotAdmin.selector);
        vm.prank(GUARDIAN);
        harness.initiateInitializeTransactionAndERC1271Recovery(address(0xBAADF00D), TX_RECOVERY_TIMELOCK, validAuth);

        vm.prank(GUARDIAN);
        harness.initiateInitializeTransactionAndERC1271Recovery(ALT_TX_RECOVERY, TX_RECOVERY_TIMELOCK, validAuth);

        // Verify
        TxRecoveryState memory state = harness.getTxRecoveryState();
        assertEq(state.pendingInit.pendingRecoveryAddress, ALT_TX_RECOVERY, "pending recovery address mismatch");
        assertEq(
            state.pendingInit.pendingTimelockDurationSeconds,
            TX_RECOVERY_TIMELOCK,
            "pending timelock should match signed payload"
        );
        assertEq(
            state.pendingInit.pendingTimestamp,
            block.timestamp + ADMIN_OPERATION_TIMELOCK,
            "pending init timestamp should respect admin-op timelock"
        );

        uint256 nonce =
            harness.computeNonce(OperationType.InitiateInitializeTransactionRecovery, validOperationData, 102);
        assertTrue(harness.getUsedNonce(nonce), "valid initiate should consume nonce");

        vm.expectRevert(abi.encodeWithSelector(IOrganizationSignatures.NonceAlreadyUsed.selector, nonce));
        vm.prank(GUARDIAN);
        harness.initiateInitializeTransactionAndERC1271Recovery(ALT_TX_RECOVERY, TX_RECOVERY_TIMELOCK, validAuth);
    }

    /// @dev Verifies OTRB-IITR-10, OTRB-IITR-11, and OTRB-IITR-12: initiate-initialize bubbles downstream
    /// already-configured/pending/invalid-param errors.
    function test_OTRB_IITR_10__OTRB_IITR_11__OTRB_IITR_12__NMTRB_ITR_9__OREC_DRI_5_initiateInitialize_downstreamErrorsBubble()
        public
    {
        // Setup
        (AdminAuthParams memory configuredAuth, bytes memory configuredOperationData) = _buildTxRecoveryAuth({
            operationType: OperationType.InitiateInitializeTransactionRecovery,
            recoveryAddress: ALT_TX_RECOVERY,
            timelockDurationSeconds: TX_RECOVERY_TIMELOCK,
            salt: 105,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        uint256 configuredNonce =
            harness.computeNonce(OperationType.InitiateInitializeTransactionRecovery, configuredOperationData, 105);

        // Call
        vm.expectRevert(IOrganizationTxRecovery.TransactionRecoveryAlreadyConfigured.selector);
        vm.prank(GUARDIAN);
        harness.initiateInitializeTransactionAndERC1271Recovery(ALT_TX_RECOVERY, TX_RECOVERY_TIMELOCK, configuredAuth);
        assertFalse(harness.getUsedNonce(configuredNonce), "already-configured revert should not burn nonce");

        _setTxRecoveryState(address(0), false, 0, 0, address(0xABC), TX_RECOVERY_TIMELOCK, block.timestamp + 1);
        (AdminAuthParams memory pendingAuth, bytes memory pendingOperationData) = _buildTxRecoveryAuth({
            operationType: OperationType.InitiateInitializeTransactionRecovery,
            recoveryAddress: ALT_TX_RECOVERY,
            timelockDurationSeconds: TX_RECOVERY_TIMELOCK,
            salt: 106,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        uint256 pendingNonce =
            harness.computeNonce(OperationType.InitiateInitializeTransactionRecovery, pendingOperationData, 106);

        vm.expectRevert(IOrganizationTxRecovery.TxRecoveryInitializationAlreadyPending.selector);
        vm.prank(GUARDIAN);
        harness.initiateInitializeTransactionAndERC1271Recovery(ALT_TX_RECOVERY, TX_RECOVERY_TIMELOCK, pendingAuth);
        assertFalse(harness.getUsedNonce(pendingNonce), "already-pending revert should not burn nonce");

        _setTxRecoveryState(address(0), false, 0, 0, address(0), 0, 0);
        (AdminAuthParams memory invalidAddressAuth, bytes memory invalidAddressOperationData) = _buildTxRecoveryAuth({
            operationType: OperationType.InitiateInitializeTransactionRecovery,
            recoveryAddress: address(0),
            timelockDurationSeconds: TX_RECOVERY_TIMELOCK,
            salt: 107,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        uint256 invalidAddressNonce =
            harness.computeNonce(OperationType.InitiateInitializeTransactionRecovery, invalidAddressOperationData, 107);
        vm.expectRevert(IOrganizationTxRecovery.InvalidTxRecoveryAddress.selector);
        vm.prank(GUARDIAN);
        harness.initiateInitializeTransactionAndERC1271Recovery(address(0), TX_RECOVERY_TIMELOCK, invalidAddressAuth);
        assertFalse(harness.getUsedNonce(invalidAddressNonce), "invalid-address revert should not burn nonce");

        (AdminAuthParams memory invalidTimelockAuth, bytes memory invalidTimelockOperationData) = _buildTxRecoveryAuth({
            operationType: OperationType.InitiateInitializeTransactionRecovery,
            recoveryAddress: ALT_TX_RECOVERY,
            timelockDurationSeconds: TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS - 1,
            salt: 108,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        uint256 invalidTimelockNonce = harness.computeNonce(
            OperationType.InitiateInitializeTransactionRecovery,
            invalidTimelockOperationData,
            108
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockUtils.InvalidTimelockDuration.selector,
                TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS - 1,
                TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS,
                TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
            )
        );
        vm.prank(GUARDIAN);
        harness.initiateInitializeTransactionAndERC1271Recovery(
            ALT_TX_RECOVERY, TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS - 1, invalidTimelockAuth
        );
        assertFalse(harness.getUsedNonce(invalidTimelockNonce), "invalid-timelock revert should not burn nonce");

        // Verify
    }

    /// @dev Verifies `OrganizationTxRecoveryBase.initiateInitializeTransactionAndERC1271Recovery` can re-initiate the
    /// same params with a different salt after cancellation.
    function test_NMTRB_ITR_2__OREC_DRI_2_initiateInitialize_sameParamsDifferentSalts_canSucceedAcrossCancel()
        public
    {
        // Setup: start from zeroed tx-recovery config and build two initiate auth payloads around an intermediate
        // cancel for the same deferred-init tuple.
        _setTxRecoveryState(address(0), false, 0, 0, address(0), 0, 0);
        (AdminAuthParams memory firstInitiateAuth, bytes memory operationData) = _buildTxRecoveryAuth({
            operationType: OperationType.InitiateInitializeTransactionRecovery,
            recoveryAddress: ALT_TX_RECOVERY,
            timelockDurationSeconds: TX_RECOVERY_TIMELOCK,
            salt: 109,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        (AdminAuthParams memory cancelAuth,) = _buildTxRecoveryAuth({
            operationType: OperationType.CancelInitializeTransactionRecovery,
            recoveryAddress: ALT_TX_RECOVERY,
            timelockDurationSeconds: TX_RECOVERY_TIMELOCK,
            salt: 110,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        (AdminAuthParams memory secondInitiateAuth,) = _buildTxRecoveryAuth({
            operationType: OperationType.InitiateInitializeTransactionRecovery,
            recoveryAddress: ALT_TX_RECOVERY,
            timelockDurationSeconds: TX_RECOVERY_TIMELOCK,
            salt: 111,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        uint256 firstNonce =
            harness.computeNonce(OperationType.InitiateInitializeTransactionRecovery, operationData, 109);
        uint256 secondNonce =
            harness.computeNonce(OperationType.InitiateInitializeTransactionRecovery, operationData, 111);

        // Call: initiate once, cancel the staged tuple, then re-initiate the identical params with a new auth salt.
        vm.prank(GUARDIAN);
        harness.initiateInitializeTransactionAndERC1271Recovery(
            ALT_TX_RECOVERY,
            TX_RECOVERY_TIMELOCK,
            firstInitiateAuth
        );

        vm.prank(GUARDIAN);
        harness.cancelInitializeTransactionAndERC1271Recovery(cancelAuth);

        vm.prank(GUARDIAN);
        harness.initiateInitializeTransactionAndERC1271Recovery(
            ALT_TX_RECOVERY,
            TX_RECOVERY_TIMELOCK,
            secondInitiateAuth
        );

        // Verify: both initiate nonces are isolated by salt, and the second call recreates the same pending tuple.
        assertTrue(firstNonce != secondNonce, "different salts should isolate initiate nonces");
        assertTrue(harness.getUsedNonce(firstNonce), "first initiate nonce should remain consumed");
        assertTrue(harness.getUsedNonce(secondNonce), "second initiate nonce should be consumed");
        assertEq(
            harness.getTxRecoveryState().pendingInit.pendingRecoveryAddress,
            ALT_TX_RECOVERY,
            "re-initiated pending recovery should match the original tuple"
        );
        assertEq(
            harness.getTxRecoveryState().pendingInit.pendingTimelockDurationSeconds,
            TX_RECOVERY_TIMELOCK,
            "re-initiated pending timelock should match the original tuple"
        );
    }

    /// @dev Verifies `OrganizationTxRecoveryBase.initiateInitializeTransactionAndERC1271Recovery` rolls back nonce
    /// usage when downstream init validation fails.
    function test_NMTRB_ITR_9_initiateInitialize_downstreamFailures_rollBackNonce() public {
        // Setup: prepare four initiate auth payloads that will each reach a distinct downstream failure branch:
        // already-configured, already-pending, invalid zero recovery address, and invalid timelock duration.
        (AdminAuthParams memory configuredAuth, bytes memory configuredOperationData) = _buildTxRecoveryAuth({
            operationType: OperationType.InitiateInitializeTransactionRecovery,
            recoveryAddress: ALT_TX_RECOVERY,
            timelockDurationSeconds: TX_RECOVERY_TIMELOCK,
            salt: 112,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        uint256 configuredNonce =
            harness.computeNonce(OperationType.InitiateInitializeTransactionRecovery, configuredOperationData, 112);

        (AdminAuthParams memory pendingAuth, bytes memory pendingOperationData) = _buildTxRecoveryAuth({
            operationType: OperationType.InitiateInitializeTransactionRecovery,
            recoveryAddress: ALT_TX_RECOVERY,
            timelockDurationSeconds: TX_RECOVERY_TIMELOCK,
            salt: 113,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        uint256 pendingNonce =
            harness.computeNonce(OperationType.InitiateInitializeTransactionRecovery, pendingOperationData, 113);

        (AdminAuthParams memory invalidAddressAuth, bytes memory invalidAddressOperationData) = _buildTxRecoveryAuth({
            operationType: OperationType.InitiateInitializeTransactionRecovery,
            recoveryAddress: address(0),
            timelockDurationSeconds: TX_RECOVERY_TIMELOCK,
            salt: 114,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        uint256 invalidAddressNonce = harness.computeNonce(
            OperationType.InitiateInitializeTransactionRecovery,
            invalidAddressOperationData,
            114
        );

        (AdminAuthParams memory invalidTimelockAuth, bytes memory invalidTimelockOperationData) = _buildTxRecoveryAuth({
            operationType: OperationType.InitiateInitializeTransactionRecovery,
            recoveryAddress: ALT_TX_RECOVERY,
            timelockDurationSeconds: TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS - 1,
            salt: 115,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        uint256 invalidTimelockNonce = harness.computeNonce(
            OperationType.InitiateInitializeTransactionRecovery,
            invalidTimelockOperationData,
            115
        );

        // Call: exercise each failure branch as guardian using valid signatures that should only fail after auth and
        // nonce validation.
        vm.expectRevert(IOrganizationTxRecovery.TransactionRecoveryAlreadyConfigured.selector);
        vm.prank(GUARDIAN);
        harness.initiateInitializeTransactionAndERC1271Recovery(ALT_TX_RECOVERY, TX_RECOVERY_TIMELOCK, configuredAuth);

        _setTxRecoveryState(address(0), false, 0, 0, address(0xABC), TX_RECOVERY_TIMELOCK, block.timestamp + 1);
        vm.expectRevert(IOrganizationTxRecovery.TxRecoveryInitializationAlreadyPending.selector);
        vm.prank(GUARDIAN);
        harness.initiateInitializeTransactionAndERC1271Recovery(ALT_TX_RECOVERY, TX_RECOVERY_TIMELOCK, pendingAuth);

        _setTxRecoveryState(address(0), false, 0, 0, address(0), 0, 0);
        vm.expectRevert(IOrganizationTxRecovery.InvalidTxRecoveryAddress.selector);
        vm.prank(GUARDIAN);
        harness.initiateInitializeTransactionAndERC1271Recovery(address(0), TX_RECOVERY_TIMELOCK, invalidAddressAuth);

        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockUtils.InvalidTimelockDuration.selector,
                TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS - 1,
                TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS,
                TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
            )
        );
        vm.prank(GUARDIAN);
        harness.initiateInitializeTransactionAndERC1271Recovery(
            ALT_TX_RECOVERY, TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS - 1, invalidTimelockAuth
        );

        // Verify: every downstream revert path leaves its derived nonce unused so a corrected retry remains possible.
        assertFalse(harness.getUsedNonce(configuredNonce), "already-configured revert should not burn nonce");
        assertFalse(harness.getUsedNonce(pendingNonce), "already-pending revert should not burn nonce");
        assertFalse(harness.getUsedNonce(invalidAddressNonce), "invalid-address revert should not burn nonce");
        assertFalse(harness.getUsedNonce(invalidTimelockNonce), "invalid-timelock revert should not burn nonce");
    }

    /// @dev Verifies `OrganizationTxRecoveryBase.finalizeInitializeTransactionAndERC1271Recovery` reverts when admin
    /// signatures do not satisfy the current admin threshold.
    function test_OTRB_FITR_2_finalizeInitialize_insufficientAdminAuthorization_reverts() public {
        // Setup: require two admin signatures and seed a pending deferred-init tuple for finalize.
        _setMembersAndAdmins({members: buildArray(admin1, admin2), admins: buildArray(admin1, admin2), threshold: 2});
        _setTxRecoveryState(
            address(0), false, 0, 0, ALT_TX_RECOVERY, TX_RECOVERY_TIMELOCK, block.timestamp + ADMIN_OPERATION_TIMELOCK
        );
        (AdminAuthParams memory insufficientAuth,) = _buildTxRecoveryAuth({
            operationType: OperationType.FinalizeInitializeTransactionRecovery,
            recoveryAddress: ALT_TX_RECOVERY,
            timelockDurationSeconds: TX_RECOVERY_TIMELOCK,
            salt: 206,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call: finalize deferred-init as guardian with a single admin signature while threshold requires two.
        vm.expectRevert(IOrganizationAdmin.InsufficientAdminAuthorization.selector);
        vm.prank(GUARDIAN);
        harness.finalizeInitializeTransactionAndERC1271Recovery(insufficientAuth);

        // Verify: pending deferred-init values remain intact after rejected authorization.
        TxRecoveryState memory state = harness.getTxRecoveryState();
        assertEq(state.pendingInit.pendingRecoveryAddress, ALT_TX_RECOVERY, "pending recovery address should remain");
        assertEq(
            state.pendingInit.pendingTimelockDurationSeconds, TX_RECOVERY_TIMELOCK, "pending timelock should remain"
        );
    }

    /// @dev Verifies `OrganizationTxRecoveryBase.finalizeInitializeTransactionAndERC1271Recovery` rejects stale admin
    /// signatures when current pending values differ from signed operation data.
    function test_OTRB_FITR_6__NMTRB_ITR_8_finalizeInitialize_stalePendingValues_revert() public {
        // Setup: build finalize auth for an initial pending tuple, then mutate the stored pending recovery address.
        _setTxRecoveryState(
            address(0), false, 0, 0, ALT_TX_RECOVERY, TX_RECOVERY_TIMELOCK, block.timestamp + ADMIN_OPERATION_TIMELOCK
        );
        (AdminAuthParams memory staleAuth,) = _buildTxRecoveryAuth({
            operationType: OperationType.FinalizeInitializeTransactionRecovery,
            recoveryAddress: ALT_TX_RECOVERY,
            timelockDurationSeconds: TX_RECOVERY_TIMELOCK,
            salt: 207,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        address mutatedPendingRecovery = address(0xFEEDC0DE);
        _setTxRecoveryState(
            address(0),
            false,
            0,
            0,
            mutatedPendingRecovery,
            TX_RECOVERY_TIMELOCK,
            block.timestamp + ADMIN_OPERATION_TIMELOCK
        );

        // Call: attempt finalize with signatures bound to stale pending values.
        vm.expectPartialRevert(IOrganizationAdmin.SignerIsNotAdmin.selector);
        vm.prank(GUARDIAN);
        harness.finalizeInitializeTransactionAndERC1271Recovery(staleAuth);

        // Verify: stale-signature rejection leaves the mutated pending tuple untouched.
        TxRecoveryState memory state = harness.getTxRecoveryState();
        assertEq(
            state.pendingInit.pendingRecoveryAddress, mutatedPendingRecovery, "pending recovery should remain mutated"
        );
        assertEq(
            state.pendingInit.pendingTimelockDurationSeconds, TX_RECOVERY_TIMELOCK, "pending timelock should remain"
        );
    }

    /// @dev Verifies OTRB-FITR-1 through OTRB-FITR-12: the full auth, timelock, and state lifecycle of
    /// `finalizeInitializeTransactionAndERC1271Recovery`. Walks through every guard in sequence:
    ///   - FITR-1:  Non-guardian caller reverts via `onlyGuardian`.
    ///   - FITR-7:  Guardian with valid auth but no pending init reverts `NoTxRecoveryInitializationPending`.
    ///   - FITR-3:  `isApproval=false` rejection signatures are rejected.
    ///   - FITR-4:  Wrong `OperationType` (Cancel instead of Finalize) signatures are rejected.
    ///   - FITR-5:  Correct `FinalizeInitializeTransactionRecovery` + `isApproval=true` passes auth.
    ///   - FITR-6:  Auth `operationData` is derived from current pending storage values (stale-value
    ///              variant tested in dedicated `test_OTRB_FITR_6_*`).
    ///   - FITR-8:  Valid auth before admin-op timelock expiry reverts `TimelockNotExpired`.
    ///   - FITR-9:  At exact admin-op timelock expiry, finalize succeeds.
    ///   - FITR-10: Success writes `recoveryAddress` + `timelockDurationSeconds` and clears all pending fields.
    ///   - FITR-11: `isEnabled` remains false after finalize (enable flow still required).
    ///   - FITR-12: Second finalize reverts `NoTxRecoveryInitializationPending` (pending already cleared).
    ///   - FITR-2:  Insufficient admin threshold variant tested in dedicated `test_OTRB_FITR_2_*`.
    function test_OTRB_FITR_1__OTRB_FITR_2__OTRB_FITR_3__OTRB_FITR_4__OTRB_FITR_5__OTRB_FITR_6__OTRB_FITR_7__OTRB_FITR_8__OTRB_FITR_9__OTRB_FITR_10__OTRB_FITR_11__OTRB_FITR_12__NMTRB_ITR_7__OREC_DRI_3__OREC_PH_1_finalizeInitialize_authAndStateSemantics()
        public
    {
        // Setup: start from a fully zeroed recovery state (no config, no pending init).
        _setTxRecoveryState(address(0), false, 0, 0, address(0), 0, 0);

        (AdminAuthParams memory noPendingAuth,) = _buildTxRecoveryAuth({
            operationType: OperationType.FinalizeInitializeTransactionRecovery,
            recoveryAddress: address(0),
            timelockDurationSeconds: 0,
            salt: 201,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // FITR-1: non-guardian caller is rejected before any auth or state checks.
        _expectOnlyGuardian(NON_GUARDIAN);
        vm.prank(NON_GUARDIAN);
        harness.finalizeInitializeTransactionAndERC1271Recovery(noPendingAuth);

        // FITR-7: guardian with valid auth reverts because no pending init exists yet.
        vm.expectRevert(IOrganizationTxRecovery.NoTxRecoveryInitializationPending.selector);
        vm.prank(GUARDIAN);
        harness.finalizeInitializeTransactionAndERC1271Recovery(noPendingAuth);

        // Seed a pending deferred-init tuple so the remaining checks can exercise auth validation.
        _setTxRecoveryState(
            address(0), false, 0, 0, ALT_TX_RECOVERY, TX_RECOVERY_TIMELOCK, block.timestamp + ADMIN_OPERATION_TIMELOCK
        );

        // FITR-3: `isApproval=false` (rejection) signatures do not satisfy finalize auth.
        (AdminAuthParams memory rejectionAuth,) = _buildTxRecoveryAuth({
            operationType: OperationType.FinalizeInitializeTransactionRecovery,
            recoveryAddress: ALT_TX_RECOVERY,
            timelockDurationSeconds: TX_RECOVERY_TIMELOCK,
            salt: 202,
            isApproval: false,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        vm.expectPartialRevert(IOrganizationAdmin.SignerIsNotAdmin.selector);
        vm.prank(GUARDIAN);
        harness.finalizeInitializeTransactionAndERC1271Recovery(rejectionAuth);

        // FITR-4: signatures for wrong OperationType (Cancel instead of Finalize) are rejected.
        (AdminAuthParams memory wrongTypeAuth,) = _buildTxRecoveryAuth({
            operationType: OperationType.CancelInitializeTransactionRecovery,
            recoveryAddress: ALT_TX_RECOVERY,
            timelockDurationSeconds: TX_RECOVERY_TIMELOCK,
            salt: 203,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        vm.expectPartialRevert(IOrganizationAdmin.SignerIsNotAdmin.selector);
        vm.prank(GUARDIAN);
        harness.finalizeInitializeTransactionAndERC1271Recovery(wrongTypeAuth);

        // FITR-5 + FITR-6: build valid auth with correct OperationType, isApproval=true, and operationData
        // derived from the current pending storage values (ALT_TX_RECOVERY, TX_RECOVERY_TIMELOCK).
        (AdminAuthParams memory finalizeAuth, bytes memory finalizeOperationData) = _buildTxRecoveryAuth({
            operationType: OperationType.FinalizeInitializeTransactionRecovery,
            recoveryAddress: ALT_TX_RECOVERY,
            timelockDurationSeconds: TX_RECOVERY_TIMELOCK,
            salt: 204,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // FITR-8: valid auth before admin-op timelock expiry reverts with the pending and current timestamps.
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationAdminOperationTimelock.TimelockNotExpired.selector,
                block.timestamp + ADMIN_OPERATION_TIMELOCK,
                block.timestamp
            )
        );
        vm.prank(GUARDIAN);
        harness.finalizeInitializeTransactionAndERC1271Recovery(finalizeAuth);

        // FITR-9: warp to exact admin-op timelock boundary — finalize now succeeds.
        vm.warp(block.timestamp + ADMIN_OPERATION_TIMELOCK);
        vm.prank(GUARDIAN);
        harness.finalizeInitializeTransactionAndERC1271Recovery(finalizeAuth);

        // FITR-10: config written from pending values; all pending fields cleared.
        TxRecoveryState memory state = harness.getTxRecoveryState();
        assertEq(state.recoveryAddress, ALT_TX_RECOVERY, "finalize should write recovery address");
        assertEq(state.timelockDurationSeconds, TX_RECOVERY_TIMELOCK, "finalize should write timelock");
        assertEq(state.pendingInit.pendingRecoveryAddress, address(0), "pending address should clear");
        assertEq(state.pendingInit.pendingTimelockDurationSeconds, 0, "pending timelock should clear");
        assertEq(state.pendingInit.pendingTimestamp, 0, "pending timestamp should clear");

        // FITR-11: finalize only writes config — recovery is NOT auto-enabled.
        assertFalse(state.isEnabled, "finalize should not auto-enable recovery");

        // FITR-5 (continued): the finalize nonce is consumed, preventing replay.
        uint256 nonce =
            harness.computeNonce(OperationType.FinalizeInitializeTransactionRecovery, finalizeOperationData, 204);
        assertTrue(harness.getUsedNonce(nonce), "finalize nonce should be consumed");

        // FITR-12: second finalize reverts because pending init was already cleared by the first.
        (AdminAuthParams memory afterFinalizeNoPendingAuth,) = _buildTxRecoveryAuth({
            operationType: OperationType.FinalizeInitializeTransactionRecovery,
            recoveryAddress: address(0),
            timelockDurationSeconds: 0,
            salt: 205,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        vm.expectRevert(IOrganizationTxRecovery.NoTxRecoveryInitializationPending.selector);
        vm.prank(GUARDIAN);
        harness.finalizeInitializeTransactionAndERC1271Recovery(afterFinalizeNoPendingAuth);
    }

    /// @dev Verifies `OrganizationTxRecoveryBase.finalizeInitializeTransactionAndERC1271Recovery` reusing the same
    /// signed params and salt reverts once the nonce has been consumed.
    function test_NMTRB_ITR_3_finalizeInitialize_replaySameNonce_revertsNonceAlreadyUsed() public {
        // Setup: stage one pending deferred-init tuple and build a single finalize auth payload for it.
        _setTxRecoveryState(address(0), false, 0, 0, ALT_TX_RECOVERY, TX_RECOVERY_TIMELOCK, block.timestamp);
        (AdminAuthParams memory auth, bytes memory operationData) = _buildTxRecoveryAuth({
            operationType: OperationType.FinalizeInitializeTransactionRecovery,
            recoveryAddress: ALT_TX_RECOVERY,
            timelockDurationSeconds: TX_RECOVERY_TIMELOCK,
            salt: 209,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        uint256 nonce = harness.computeNonce(OperationType.FinalizeInitializeTransactionRecovery, operationData, 209);

        // Call: finalize once successfully, then recreate the identical pending tuple and replay the same auth.
        vm.prank(GUARDIAN);
        harness.finalizeInitializeTransactionAndERC1271Recovery(auth);

        _setTxRecoveryState(address(0), false, 0, 0, ALT_TX_RECOVERY, TX_RECOVERY_TIMELOCK, block.timestamp);
        vm.expectRevert(abi.encodeWithSelector(IOrganizationSignatures.NonceAlreadyUsed.selector, nonce));
        vm.prank(GUARDIAN);
        harness.finalizeInitializeTransactionAndERC1271Recovery(auth);

        // Verify: the original finalize consumed the nonce, which blocks replay even after the pending tuple is
        // recreated.
        assertTrue(harness.getUsedNonce(nonce), "finalize nonce should remain consumed after replay attempt");
    }

    /// @dev Verifies `OrganizationTxRecoveryBase.finalizeInitializeTransactionAndERC1271Recovery` can finalize the
    /// same pending tuple on fresh organization instances with different salts.
    function test_NMTRB_ITR_4_finalizeInitialize_samePendingTupleDifferentSalts_succeedsPerFreshOrg() public {
        // Setup: deploy two fresh harnesses with the same pending deferred-init tuple and distinct finalize salts.
        OrganizationTxRecoveryBaseHarness secondHarness = new OrganizationTxRecoveryBaseHarness();
        secondHarness.setGuardian(GUARDIAN);
        secondHarness.setAdminOperationTimelockDurationSeconds(ADMIN_OPERATION_TIMELOCK);
        secondHarness.setMemberStatus(admin1, true);
        secondHarness.setAdminStatus(admin1, true);
        secondHarness.setAdminCount(1);
        secondHarness.setVotingThreshold(1);
        secondHarness.setTxRecoveryState(
            TxRecoveryState({
                recoveryAddress: address(0),
                isEnabled: false,
                timelockDurationSeconds: 0,
                pendingEnableTimestamp: 0,
                pendingInit: PendingRecoveryInitTimelock({
                    pendingRecoveryAddress: ALT_TX_RECOVERY,
                    pendingTimelockDurationSeconds: TX_RECOVERY_TIMELOCK,
                    pendingTimestamp: block.timestamp
                })
            })
        );

        _setTxRecoveryState(address(0), false, 0, 0, ALT_TX_RECOVERY, TX_RECOVERY_TIMELOCK, block.timestamp);
        (AdminAuthParams memory firstAuth, bytes memory operationData) = _buildTxRecoveryAuth({
            operationType: OperationType.FinalizeInitializeTransactionRecovery,
            recoveryAddress: ALT_TX_RECOVERY,
            timelockDurationSeconds: TX_RECOVERY_TIMELOCK,
            salt: 210,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        bytes32 secondOperationHash = secondHarness.getAdminOperationHash({
            operationType: OperationType.FinalizeInitializeTransactionRecovery,
            operationData: operationData,
            salt: 211,
            expirationTimestamp: block.timestamp + 30 days,
            isApproval: true
        });
        AdminAuthParams memory secondAuth = AdminAuthParams({
            salt: 211,
            expirationTimestamp: block.timestamp + 30 days,
            signatures: _buildSortedEOASignatures(secondOperationHash, buildUint256Array(ADMIN_PK_1))
        });
        uint256 firstNonce = harness.computeNonce(OperationType.FinalizeInitializeTransactionRecovery, operationData, 210);
        uint256 secondNonce =
            secondHarness.computeNonce(OperationType.FinalizeInitializeTransactionRecovery, operationData, 211);

        // Call: finalize the identical pending tuple once per fresh organization instance using different auth salts.
        vm.prank(GUARDIAN);
        harness.finalizeInitializeTransactionAndERC1271Recovery(firstAuth);

        vm.prank(GUARDIAN);
        secondHarness.finalizeInitializeTransactionAndERC1271Recovery(secondAuth);

        // Verify: each organization consumes only its own finalize nonce while writing the same configured tuple.
        assertTrue(firstNonce != secondNonce, "different salts should isolate finalize nonces across organizations");
        assertTrue(harness.getUsedNonce(firstNonce), "first finalize nonce should be consumed");
        assertTrue(secondHarness.getUsedNonce(secondNonce), "second finalize nonce should be consumed");
        assertEq(harness.getTxRecoveryState().recoveryAddress, ALT_TX_RECOVERY, "first org should finalize recovery");
        assertEq(
            secondHarness.getTxRecoveryState().recoveryAddress,
            ALT_TX_RECOVERY,
            "second org should finalize recovery"
        );
        assertEq(
            harness.getTxRecoveryState().timelockDurationSeconds,
            TX_RECOVERY_TIMELOCK,
            "first org should finalize timelock"
        );
        assertEq(
            secondHarness.getTxRecoveryState().timelockDurationSeconds,
            TX_RECOVERY_TIMELOCK,
            "second org should finalize timelock"
        );
    }

    /// @dev Verifies finalize and cancel downstream check failures roll back nonce usage.
    function test_NMTRB_ITR_10_finalizeAndCancelFailures_rollBackNonce() public {
        // Setup: stage one pending tuple that is still timelocked for finalize, then prepare a zero-pending cancel
        // auth for the no-pending branch.
        _setTxRecoveryState(
            address(0),
            false,
            0,
            0,
            ALT_TX_RECOVERY,
            TX_RECOVERY_TIMELOCK,
            block.timestamp + ADMIN_OPERATION_TIMELOCK
        );
        (AdminAuthParams memory finalizeAuth, bytes memory finalizeOperationData) = _buildTxRecoveryAuth({
            operationType: OperationType.FinalizeInitializeTransactionRecovery,
            recoveryAddress: ALT_TX_RECOVERY,
            timelockDurationSeconds: TX_RECOVERY_TIMELOCK,
            salt: 212,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        uint256 finalizeNonce =
            harness.computeNonce(OperationType.FinalizeInitializeTransactionRecovery, finalizeOperationData, 212);

        (AdminAuthParams memory cancelAuth, bytes memory cancelOperationData) = _buildTxRecoveryAuth({
            operationType: OperationType.CancelInitializeTransactionRecovery,
            recoveryAddress: address(0),
            timelockDurationSeconds: 0,
            salt: 213,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        uint256 cancelNonce =
            harness.computeNonce(OperationType.CancelInitializeTransactionRecovery, cancelOperationData, 213);

        // Call: fail finalize before the pending timestamp, then clear pending state and fail cancel with no tuple.
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationAdminOperationTimelock.TimelockNotExpired.selector,
                block.timestamp + ADMIN_OPERATION_TIMELOCK,
                block.timestamp
            )
        );
        vm.prank(GUARDIAN);
        harness.finalizeInitializeTransactionAndERC1271Recovery(finalizeAuth);

        _setTxRecoveryState(address(0), false, 0, 0, address(0), 0, 0);
        vm.expectRevert(IOrganizationTxRecovery.NoTxRecoveryInitializationPending.selector);
        vm.prank(GUARDIAN);
        harness.cancelInitializeTransactionAndERC1271Recovery(cancelAuth);

        // Verify: neither downstream failure path leaves its nonce consumed.
        assertFalse(harness.getUsedNonce(finalizeNonce), "timelock failure should not burn finalize nonce");
        assertFalse(harness.getUsedNonce(cancelNonce), "no-pending failure should not burn cancel nonce");
    }

    /// @dev Verifies `OrganizationTxRecoveryBase.cancelInitializeTransactionAndERC1271Recovery` replaying the same
    /// signed pending tuple and salt reverts once the cancel nonce has been consumed.
    function test_NMTRB_ITR_5_cancelInitialize_replaySameNonce_revertsNonceAlreadyUsed() public {
        // Setup: stage one pending deferred-init tuple and build a single cancel auth payload for it.
        _setTxRecoveryState(
            address(0),
            false,
            0,
            0,
            ALT_TX_RECOVERY,
            TX_RECOVERY_TIMELOCK,
            block.timestamp + ADMIN_OPERATION_TIMELOCK
        );
        (AdminAuthParams memory auth, bytes memory operationData) = _buildTxRecoveryAuth({
            operationType: OperationType.CancelInitializeTransactionRecovery,
            recoveryAddress: ALT_TX_RECOVERY,
            timelockDurationSeconds: TX_RECOVERY_TIMELOCK,
            salt: 337,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        uint256 nonce = harness.computeNonce(OperationType.CancelInitializeTransactionRecovery, operationData, 337);

        // Call: cancel once successfully, recreate the identical pending tuple, then replay the same auth payload.
        vm.prank(GUARDIAN);
        harness.cancelInitializeTransactionAndERC1271Recovery(auth);

        _setTxRecoveryState(
            address(0),
            false,
            0,
            0,
            ALT_TX_RECOVERY,
            TX_RECOVERY_TIMELOCK,
            block.timestamp + ADMIN_OPERATION_TIMELOCK
        );
        vm.expectRevert(abi.encodeWithSelector(IOrganizationSignatures.NonceAlreadyUsed.selector, nonce));
        vm.prank(GUARDIAN);
        harness.cancelInitializeTransactionAndERC1271Recovery(auth);

        // Verify: the consumed cancel nonce blocks replay even after the same pending tuple is recreated.
        assertTrue(harness.getUsedNonce(nonce), "cancel nonce should remain consumed after replay attempt");
        TxRecoveryState memory state = harness.getTxRecoveryState();
        assertEq(state.pendingInit.pendingRecoveryAddress, ALT_TX_RECOVERY, "replayed tuple should remain pending");
        assertEq(
            state.pendingInit.pendingTimelockDurationSeconds,
            TX_RECOVERY_TIMELOCK,
            "replayed tuple timelock should remain pending"
        );
    }

    /// @dev Verifies `OrganizationTxRecoveryBase.cancelInitializeTransactionAndERC1271Recovery` reverts for
    /// insufficient admin authorization, `isApproval=false` signatures, and wrong operation type signatures.
    function test_OTRB_CITR_2__OTRB_CITR_3__OTRB_CITR_4__NMTRB_ITR_7_cancelInitialize_authValidation_reverts()
        public
    {
        // Setup: seed pending deferred-init state, then require two admin signatures for the insufficient-auth branch.
        _setTxRecoveryState(
            address(0), false, 0, 0, ALT_TX_RECOVERY, TX_RECOVERY_TIMELOCK, block.timestamp + ADMIN_OPERATION_TIMELOCK
        );
        _setMembersAndAdmins({members: buildArray(admin1, admin2), admins: buildArray(admin1, admin2), threshold: 2});
        (AdminAuthParams memory insufficientAuth,) = _buildTxRecoveryAuth({
            operationType: OperationType.CancelInitializeTransactionRecovery,
            recoveryAddress: ALT_TX_RECOVERY,
            timelockDurationSeconds: TX_RECOVERY_TIMELOCK,
            salt: 331,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call: attempt cancel with one signature under threshold=2, then with non-approval and wrong-op signatures.
        vm.expectRevert(IOrganizationAdmin.InsufficientAdminAuthorization.selector);
        vm.prank(GUARDIAN);
        harness.cancelInitializeTransactionAndERC1271Recovery(insufficientAuth);

        _setMembersAndAdmins({members: buildArray(admin1, admin2), admins: buildArray(admin1, admin2), threshold: 1});
        (AdminAuthParams memory rejectionAuth,) = _buildTxRecoveryAuth({
            operationType: OperationType.CancelInitializeTransactionRecovery,
            recoveryAddress: ALT_TX_RECOVERY,
            timelockDurationSeconds: TX_RECOVERY_TIMELOCK,
            salt: 332,
            isApproval: false,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        vm.expectPartialRevert(IOrganizationAdmin.SignerIsNotAdmin.selector);
        vm.prank(GUARDIAN);
        harness.cancelInitializeTransactionAndERC1271Recovery(rejectionAuth);

        (AdminAuthParams memory wrongTypeAuth,) = _buildTxRecoveryAuth({
            operationType: OperationType.FinalizeInitializeTransactionRecovery,
            recoveryAddress: ALT_TX_RECOVERY,
            timelockDurationSeconds: TX_RECOVERY_TIMELOCK,
            salt: 333,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        vm.expectPartialRevert(IOrganizationAdmin.SignerIsNotAdmin.selector);
        vm.prank(GUARDIAN);
        harness.cancelInitializeTransactionAndERC1271Recovery(wrongTypeAuth);

        // Verify: rejected auth paths do not clear or alter pending deferred-init values.
        TxRecoveryState memory state = harness.getTxRecoveryState();
        assertEq(state.pendingInit.pendingRecoveryAddress, ALT_TX_RECOVERY, "pending recovery should remain");
        assertEq(
            state.pendingInit.pendingTimelockDurationSeconds, TX_RECOVERY_TIMELOCK, "pending timelock should remain"
        );
    }

    /// @dev Verifies `OrganizationTxRecoveryBase.cancelInitializeTransactionAndERC1271Recovery` rejects stale admin
    /// signatures when pending values change after signature creation.
    function test_OTRB_CITR_6__NMTRB_ITR_8_cancelInitialize_stalePendingValues_revert() public {
        // Setup: sign cancel auth for initial pending values, then mutate pending recovery address in storage.
        _setTxRecoveryState(
            address(0), false, 0, 0, ALT_TX_RECOVERY, TX_RECOVERY_TIMELOCK, block.timestamp + ADMIN_OPERATION_TIMELOCK
        );
        (AdminAuthParams memory staleAuth,) = _buildTxRecoveryAuth({
            operationType: OperationType.CancelInitializeTransactionRecovery,
            recoveryAddress: ALT_TX_RECOVERY,
            timelockDurationSeconds: TX_RECOVERY_TIMELOCK,
            salt: 334,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        address mutatedPendingRecovery = address(0xF0F0);
        _setTxRecoveryState(
            address(0),
            false,
            0,
            0,
            mutatedPendingRecovery,
            TX_RECOVERY_TIMELOCK,
            block.timestamp + ADMIN_OPERATION_TIMELOCK
        );

        // Call: attempt cancel using stale signatures bound to old pending values.
        vm.expectPartialRevert(IOrganizationAdmin.SignerIsNotAdmin.selector);
        vm.prank(GUARDIAN);
        harness.cancelInitializeTransactionAndERC1271Recovery(staleAuth);

        // Verify: stale-signature rejection keeps current pending tuple unchanged.
        TxRecoveryState memory state = harness.getTxRecoveryState();
        assertEq(
            state.pendingInit.pendingRecoveryAddress, mutatedPendingRecovery, "pending recovery should remain mutated"
        );
        assertEq(state.pendingInit.pendingTimestamp, block.timestamp + ADMIN_OPERATION_TIMELOCK, "pending time remains");
    }

    /// @dev Verifies `OrganizationTxRecoveryBase.cancelInitializeTransactionAndERC1271Recovery` reverts with
    /// `NoTxRecoveryInitializationPending` when no deferred-init tuple is staged.
    function test_OTRB_CITR_7_cancelInitialize_noPendingInit_revertsNoTxRecoveryInitializationPending() public {
        // Setup: clear pending-init storage and build valid cancel auth bound to zero pending values.
        _setTxRecoveryState(address(0), false, 0, 0, address(0), 0, 0);
        (AdminAuthParams memory noPendingAuth,) = _buildTxRecoveryAuth({
            operationType: OperationType.CancelInitializeTransactionRecovery,
            recoveryAddress: address(0),
            timelockDurationSeconds: 0,
            salt: 335,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call: execute cancel as guardian with valid auth while no pending deferred-init exists.
        vm.expectRevert(IOrganizationTxRecovery.NoTxRecoveryInitializationPending.selector);
        vm.prank(GUARDIAN);
        harness.cancelInitializeTransactionAndERC1271Recovery(noPendingAuth);

        // Verify: deferred-init tuple remains zeroed after the revert.
        TxRecoveryState memory state = harness.getTxRecoveryState();
        assertEq(state.pendingInit.pendingRecoveryAddress, address(0), "pending recovery should stay zero");
        assertEq(state.pendingInit.pendingTimelockDurationSeconds, 0, "pending timelock should stay zero");
        assertEq(state.pendingInit.pendingTimestamp, 0, "pending timestamp should stay zero");
    }

    /// @dev Verifies `OrganizationTxRecoveryBase.cancelInitializeTransactionAndERC1271Recovery` succeeds before pending
    /// timestamp expiry and does not require waiting for admin-op timelock.
    function test_OTRB_CITR_9_cancelInitialize_beforePendingTimestamp_succeeds() public {
        // Setup: stage pending deferred-init values with a future pending timestamp.
        uint256 pendingTimestamp = block.timestamp + ADMIN_OPERATION_TIMELOCK;
        _setTxRecoveryState(address(0), false, 0, 0, ALT_TX_RECOVERY, TX_RECOVERY_TIMELOCK, pendingTimestamp);
        (AdminAuthParams memory cancelAuth,) = _buildTxRecoveryAuth({
            operationType: OperationType.CancelInitializeTransactionRecovery,
            recoveryAddress: ALT_TX_RECOVERY,
            timelockDurationSeconds: TX_RECOVERY_TIMELOCK,
            salt: 336,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call: cancel pending deferred-init immediately as guardian before the pending timestamp is reached.
        vm.prank(GUARDIAN);
        harness.cancelInitializeTransactionAndERC1271Recovery(cancelAuth);

        // Verify: cancel clears all pending deferred-init fields without requiring timelock expiry.
        TxRecoveryState memory state = harness.getTxRecoveryState();
        assertEq(state.pendingInit.pendingRecoveryAddress, address(0), "pending recovery should clear");
        assertEq(state.pendingInit.pendingTimelockDurationSeconds, 0, "pending timelock should clear");
        assertEq(state.pendingInit.pendingTimestamp, 0, "pending timestamp should clear");
    }

    /// @dev Verifies `OrganizationTxRecoveryBase.cancelInitializeTransactionAndERC1271Recovery` can cancel the same
    /// pending deferred-init tuple twice when fresh auth salts are used and the tuple is re-initiated in between.
    function test_NMTRB_ITR_6_cancelInitialize_samePendingTupleDifferentSalts_canCancelTwiceAcrossReinitiation()
        public
    {
        // Setup: build two initiate auth payloads and two cancel auth payloads around the same deferred-init tuple.
        _setTxRecoveryState(address(0), false, 0, 0, address(0), 0, 0);
        (AdminAuthParams memory firstInitiateAuth,) = _buildTxRecoveryAuth({
            operationType: OperationType.InitiateInitializeTransactionRecovery,
            recoveryAddress: ALT_TX_RECOVERY,
            timelockDurationSeconds: TX_RECOVERY_TIMELOCK,
            salt: 338,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        (AdminAuthParams memory firstCancelAuth, bytes memory operationData) = _buildTxRecoveryAuth({
            operationType: OperationType.CancelInitializeTransactionRecovery,
            recoveryAddress: ALT_TX_RECOVERY,
            timelockDurationSeconds: TX_RECOVERY_TIMELOCK,
            salt: 339,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        (AdminAuthParams memory secondInitiateAuth,) = _buildTxRecoveryAuth({
            operationType: OperationType.InitiateInitializeTransactionRecovery,
            recoveryAddress: ALT_TX_RECOVERY,
            timelockDurationSeconds: TX_RECOVERY_TIMELOCK,
            salt: 340,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        (AdminAuthParams memory secondCancelAuth,) = _buildTxRecoveryAuth({
            operationType: OperationType.CancelInitializeTransactionRecovery,
            recoveryAddress: ALT_TX_RECOVERY,
            timelockDurationSeconds: TX_RECOVERY_TIMELOCK,
            salt: 341,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        uint256 firstNonce = harness.computeNonce(OperationType.CancelInitializeTransactionRecovery, operationData, 339);
        uint256 secondNonce =
            harness.computeNonce(OperationType.CancelInitializeTransactionRecovery, operationData, 341);

        // Call: initiate and cancel the tuple once, re-initiate the identical tuple, then cancel it again with a new
        // auth salt.
        vm.prank(GUARDIAN);
        harness.initiateInitializeTransactionAndERC1271Recovery(
            ALT_TX_RECOVERY,
            TX_RECOVERY_TIMELOCK,
            firstInitiateAuth
        );

        vm.prank(GUARDIAN);
        harness.cancelInitializeTransactionAndERC1271Recovery(firstCancelAuth);

        vm.prank(GUARDIAN);
        harness.initiateInitializeTransactionAndERC1271Recovery(
            ALT_TX_RECOVERY,
            TX_RECOVERY_TIMELOCK,
            secondInitiateAuth
        );

        vm.prank(GUARDIAN);
        harness.cancelInitializeTransactionAndERC1271Recovery(secondCancelAuth);

        // Verify: both cancel salts consume independent nonces while the second cancel clears the recreated tuple.
        assertTrue(firstNonce != secondNonce, "different salts should isolate cancel nonces");
        assertTrue(harness.getUsedNonce(firstNonce), "first cancel nonce should be consumed");
        assertTrue(harness.getUsedNonce(secondNonce), "second cancel nonce should be consumed");
        TxRecoveryState memory state = harness.getTxRecoveryState();
        assertEq(state.pendingInit.pendingRecoveryAddress, address(0), "second cancel should clear pending address");
        assertEq(state.pendingInit.pendingTimelockDurationSeconds, 0, "second cancel should clear pending timelock");
        assertEq(state.pendingInit.pendingTimestamp, 0, "second cancel should clear pending timestamp");
    }

    /// @dev Verifies OTRB-CITR-1, OTRB-CITR-2, OTRB-CITR-3, OTRB-CITR-4, OTRB-CITR-5, OTRB-CITR-6, OTRB-CITR-7,
    /// OTRB-CITR-8, OTRB-CITR-9, OTRB-CITR-10, and OTRB-CITR-11 across cancel auth/state semantics.
    function test_OTRB_CITR_1__OTRB_CITR_2__OTRB_CITR_3__OTRB_CITR_4__OTRB_CITR_5__OTRB_CITR_6__OTRB_CITR_7__OTRB_CITR_8__OTRB_CITR_9__OTRB_CITR_10__OTRB_CITR_11_cancelInitialize_authAndStateSemantics()
        public
    {
        // Setup
        _setTxRecoveryState(
            address(0), false, 0, 0, ALT_TX_RECOVERY, TX_RECOVERY_TIMELOCK, block.timestamp + ADMIN_OPERATION_TIMELOCK
        );

        (AdminAuthParams memory cancelAuth, bytes memory operationData) = _buildTxRecoveryAuth({
            operationType: OperationType.CancelInitializeTransactionRecovery,
            recoveryAddress: ALT_TX_RECOVERY,
            timelockDurationSeconds: TX_RECOVERY_TIMELOCK,
            salt: 301,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call
        _expectOnlyGuardian(NON_GUARDIAN);
        vm.prank(NON_GUARDIAN);
        harness.cancelInitializeTransactionAndERC1271Recovery(cancelAuth);

        vm.warp(block.timestamp + ADMIN_OPERATION_TIMELOCK + 1);
        vm.prank(GUARDIAN);
        harness.cancelInitializeTransactionAndERC1271Recovery(cancelAuth);

        // Verify
        TxRecoveryState memory state = harness.getTxRecoveryState();
        assertEq(state.pendingInit.pendingRecoveryAddress, address(0), "pending recovery address should clear");
        assertEq(state.pendingInit.pendingTimelockDurationSeconds, 0, "pending timelock should clear");
        assertEq(state.pendingInit.pendingTimestamp, 0, "pending timestamp should clear");
        assertEq(state.recoveryAddress, address(0), "active config should remain unconfigured");

        uint256 nonce = harness.computeNonce(OperationType.CancelInitializeTransactionRecovery, operationData, 301);
        assertTrue(harness.getUsedNonce(nonce), "cancel nonce should be consumed");

        (AdminAuthParams memory reinitAuth,) = _buildTxRecoveryAuth({
            operationType: OperationType.InitiateInitializeTransactionRecovery,
            recoveryAddress: TX_RECOVERY,
            timelockDurationSeconds: TX_RECOVERY_TIMELOCK,
            salt: 302,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        vm.prank(GUARDIAN);
        harness.initiateInitializeTransactionAndERC1271Recovery(TX_RECOVERY, TX_RECOVERY_TIMELOCK, reinitAuth);
        assertEq(
            harness.getTxRecoveryState().pendingInit.pendingRecoveryAddress,
            TX_RECOVERY,
            "re-initiation should be possible after cancel"
        );
    }

    /// @dev Verifies OTRB-GTRS-1, OTRB-GTRS-2, OTRB-GTRS-3, OTRB-GTRS-4, OTRB-GTRS-5, and OTRB-GTRS-6:
    /// `getTxRecoveryState` returns full snapshots across lifecycle transitions and is callable by anyone.
    function test_OTRB_GTRS_1__OTRB_GTRS_2__OTRB_GTRS_3__OTRB_GTRS_4__OTRB_GTRS_5__OTRB_GTRS_6_getTxRecoveryState_reflectsLifecycleAndIsPermissionless()
        public
    {
        // Setup
        _setTxRecoveryState(address(0), false, 0, 0, address(0), 0, 0);

        // Call
        vm.prank(NON_GUARDIAN);
        TxRecoveryState memory zeroState = harness.getTxRecoveryState();

        _setTxRecoveryState(TX_RECOVERY, false, TX_RECOVERY_TIMELOCK, block.timestamp + 77, address(0), 0, 0);
        TxRecoveryState memory pendingEnableState = harness.getTxRecoveryState();

        _setTxRecoveryState(
            address(0), false, 0, 0, ALT_TX_RECOVERY, TX_RECOVERY_TIMELOCK, block.timestamp + ADMIN_OPERATION_TIMELOCK
        );
        TxRecoveryState memory pendingInitState = harness.getTxRecoveryState();

        _setTxRecoveryState(TX_RECOVERY, true, TX_RECOVERY_TIMELOCK, 0, address(0), 0, 0);
        TxRecoveryState memory enabledState = harness.getTxRecoveryState();
        _setTxRecoveryState(TX_RECOVERY, false, TX_RECOVERY_TIMELOCK, 0, address(0), 0, 0);
        TxRecoveryState memory disabledState = harness.getTxRecoveryState();

        // Verify: zero state – all fields default
        assertEq(zeroState.recoveryAddress, address(0), "zero snapshot: recovery address");
        assertFalse(zeroState.isEnabled, "zero snapshot: isEnabled");
        assertEq(zeroState.timelockDurationSeconds, 0, "zero snapshot: timelock");
        assertEq(zeroState.pendingEnableTimestamp, 0, "zero snapshot: pendingEnableTimestamp");
        assertEq(zeroState.pendingInit.pendingRecoveryAddress, address(0), "zero snapshot: pendingInit address");
        assertEq(zeroState.pendingInit.pendingTimelockDurationSeconds, 0, "zero snapshot: pendingInit timelock");
        assertEq(zeroState.pendingInit.pendingTimestamp, 0, "zero snapshot: pendingInit timestamp");

        // Verify: pending-enable state
        assertEq(pendingEnableState.recoveryAddress, TX_RECOVERY, "pending-enable snapshot: recovery address");
        assertFalse(pendingEnableState.isEnabled, "pending-enable snapshot: isEnabled");
        assertEq(pendingEnableState.timelockDurationSeconds, TX_RECOVERY_TIMELOCK, "pending-enable snapshot: timelock");
        assertEq(
            pendingEnableState.pendingEnableTimestamp,
            block.timestamp + 77,
            "pending-enable snapshot: pendingEnableTimestamp"
        );
        assertEq(
            pendingEnableState.pendingInit.pendingRecoveryAddress,
            address(0),
            "pending-enable snapshot: pendingInit address"
        );
        assertEq(
            pendingEnableState.pendingInit.pendingTimelockDurationSeconds,
            0,
            "pending-enable snapshot: pendingInit timelock"
        );
        assertEq(pendingEnableState.pendingInit.pendingTimestamp, 0, "pending-enable snapshot: pendingInit timestamp");

        // Verify: pending-init state
        assertEq(pendingInitState.recoveryAddress, address(0), "pending-init snapshot: recovery address");
        assertFalse(pendingInitState.isEnabled, "pending-init snapshot: isEnabled");
        assertEq(pendingInitState.timelockDurationSeconds, 0, "pending-init snapshot: timelock");
        assertEq(pendingInitState.pendingEnableTimestamp, 0, "pending-init snapshot: pendingEnableTimestamp");
        assertEq(
            pendingInitState.pendingInit.pendingRecoveryAddress,
            ALT_TX_RECOVERY,
            "pending-init snapshot: pendingInit address"
        );
        assertEq(
            pendingInitState.pendingInit.pendingTimelockDurationSeconds,
            TX_RECOVERY_TIMELOCK,
            "pending-init snapshot: pendingInit timelock"
        );
        assertEq(
            pendingInitState.pendingInit.pendingTimestamp,
            block.timestamp + ADMIN_OPERATION_TIMELOCK,
            "pending-init snapshot: pendingInit timestamp"
        );

        // Verify: enabled state
        assertEq(enabledState.recoveryAddress, TX_RECOVERY, "enabled snapshot: recovery address");
        assertTrue(enabledState.isEnabled, "enabled snapshot: isEnabled");
        assertEq(enabledState.timelockDurationSeconds, TX_RECOVERY_TIMELOCK, "enabled snapshot: timelock");
        assertEq(enabledState.pendingEnableTimestamp, 0, "enabled snapshot: pendingEnableTimestamp");
        assertEq(enabledState.pendingInit.pendingRecoveryAddress, address(0), "enabled snapshot: pendingInit address");
        assertEq(enabledState.pendingInit.pendingTimelockDurationSeconds, 0, "enabled snapshot: pendingInit timelock");
        assertEq(enabledState.pendingInit.pendingTimestamp, 0, "enabled snapshot: pendingInit timestamp");

        // Verify: disabled state
        assertEq(disabledState.recoveryAddress, TX_RECOVERY, "disabled snapshot: recovery address");
        assertFalse(disabledState.isEnabled, "disabled snapshot: isEnabled");
        assertEq(disabledState.timelockDurationSeconds, TX_RECOVERY_TIMELOCK, "disabled snapshot: timelock");
        assertEq(disabledState.pendingEnableTimestamp, 0, "disabled snapshot: pendingEnableTimestamp");
        assertEq(disabledState.pendingInit.pendingRecoveryAddress, address(0), "disabled snapshot: pendingInit address");
        assertEq(disabledState.pendingInit.pendingTimelockDurationSeconds, 0, "disabled snapshot: pendingInit timelock");
        assertEq(disabledState.pendingInit.pendingTimestamp, 0, "disabled snapshot: pendingInit timestamp");
    }
}
