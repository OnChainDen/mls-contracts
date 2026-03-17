// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {IOrganizationAdminOperationTimelock} from "interfaces/organization/IOrganizationAdminOperationTimelock.sol";
import {IOrganizationTxRecovery} from "interfaces/organization/IOrganizationTxRecovery.sol";
import {TimelockUtils} from "libraries/TimelockUtils.sol";
import {LibOrganizationTxRecovery} from "organization/libraries/LibOrganizationTxRecovery.sol";
import {
    LibOrganizationAdminOperationTimelockStorage
} from "organization/libraries/storage/LibOrganizationAdminOperationTimelockStorage.sol";
import {LibOrganizationRecoveryStorage} from "organization/libraries/storage/LibOrganizationRecoveryStorage.sol";
import {
    MockERC1271RevertingSigner,
    MockERC1271ShortReturnSigner,
    MockERC1271ValidSigner,
    MockERC1271WrongMagicSigner
} from "test/helpers/MockERC1271Signers.sol";
import {SignatureTestHelpers} from "test/helpers/SignatureTestHelpers.sol";
import {PendingRecoveryInitTimelock, TxRecoveryState} from "types/RecoveryTypes.sol";

contract LibOrganizationTxRecoveryPlanHarness {
    function initializeTxRecovery(address recoveryAddress, uint256 timelockDurationSeconds) external {
        LibOrganizationTxRecovery.initializeTxRecovery(recoveryAddress, timelockDurationSeconds);
    }

    function initiateEnableTxRecovery() external {
        LibOrganizationTxRecovery.initiateEnableTxRecovery();
    }

    function finalizeEnableTxRecovery() external {
        LibOrganizationTxRecovery.finalizeEnableTxRecovery();
    }

    function cancelEnableTxRecovery() external {
        LibOrganizationTxRecovery.cancelEnableTxRecovery();
    }

    function disableTxRecovery() external {
        LibOrganizationTxRecovery.disableTxRecovery();
    }

    function initiateInitializeTxRecovery(address recoveryAddress, uint256 timelockDurationSeconds) external {
        LibOrganizationTxRecovery.initiateInitializeTxRecovery(recoveryAddress, timelockDurationSeconds);
    }

    function finalizeInitializeTxRecovery() external {
        LibOrganizationTxRecovery.finalizeInitializeTxRecovery();
    }

    function cancelInitializeTxRecovery() external {
        LibOrganizationTxRecovery.cancelInitializeTxRecovery();
    }

    function validateRecoveryAccountTransactionAllowedOrRevert() external view {
        LibOrganizationTxRecovery.validateRecoveryAccountTransactionAllowedOrRevert();
    }

    function isValidRecoverySignature(bytes32 hash, bytes calldata signature) external view returns (bool) {
        return LibOrganizationTxRecovery.isValidRecoverySignature(hash, signature);
    }

    function enforceOnlyTxRecoveryAddress() external view {
        LibOrganizationTxRecovery.enforceOnlyTxRecoveryAddress();
    }

    function isRecoveryEnabledForTxAndERC1271() external view returns (bool) {
        return LibOrganizationTxRecovery.isRecoveryEnabledForTxAndERC1271();
    }

    function setAdminOperationTimelockDurationSeconds(uint256 duration) external {
        LibOrganizationAdminOperationTimelockStorage.layout().adminOperationTimelockDurationSeconds = duration;
    }

    function setTxRecoveryState(TxRecoveryState calldata state) external {
        LibOrganizationRecoveryStorage.layout().txRecovery = state;
    }

    function getTxRecoveryState() external view returns (TxRecoveryState memory) {
        return LibOrganizationRecoveryStorage.layout().txRecovery;
    }

    function clearPendingTxRecoveryInitTimelockViaHarness() external {
        TxRecoveryState storage txRecovery = LibOrganizationRecoveryStorage.layout().txRecovery;
        LibOrganizationTxRecovery._clearPendingTxRecoveryInitTimelock(txRecovery);
    }

    function validateTxRecoveryNotConfiguredOrRevertViaHarness() external view {
        TxRecoveryState storage txRecovery = LibOrganizationRecoveryStorage.layout().txRecovery;
        LibOrganizationTxRecovery._validateTxRecoveryNotConfiguredOrRevert(txRecovery);
    }

    function validateTxRecoveryParamsOrRevertViaHarness(address recoveryAddress, uint256 timelockDurationSeconds)
        external
        pure
    {
        LibOrganizationTxRecovery._validateTxRecoveryParamsOrRevert(recoveryAddress, timelockDurationSeconds);
    }

    function resetTxRecoveryState() external {
        LibOrganizationRecoveryStorage.layout().txRecovery = TxRecoveryState({
            recoveryAddress: address(0),
            isEnabled: false,
            timelockDurationSeconds: 0,
            pendingEnableTimestamp: 0,
            pendingInit: PendingRecoveryInitTimelock({
                pendingRecoveryAddress: address(0), pendingTimelockDurationSeconds: 0, pendingTimestamp: 0
            })
        });
    }
}

/**
 * @dev Comprehensive plan-ID coverage for `LibOrganizationTxRecovery`.
 */
contract LibOrganizationTxRecoveryComprehensiveTest is Test, SignatureTestHelpers {
    LibOrganizationTxRecoveryPlanHarness internal harness;

    uint256 internal constant ADMIN_OPERATION_TIMELOCK = 3 days;
    uint256 internal constant TX_TIMELOCK = 2 days;

    uint256 internal constant RECOVERY_PK = 0xA11CE;
    uint256 internal constant OTHER_PK = 0xB0B;

    bytes32 internal constant MESSAGE_HASH = keccak256("tx-recovery-library-test");

    address internal recoveryAddress;
    address internal otherSigner;

    function setUp() public {
        harness = new LibOrganizationTxRecoveryPlanHarness();
        recoveryAddress = vm.addr(RECOVERY_PK);
        otherSigner = vm.addr(OTHER_PK);

        harness.setAdminOperationTimelockDurationSeconds(ADMIN_OPERATION_TIMELOCK);
        harness.initializeTxRecovery(recoveryAddress, TX_TIMELOCK);
    }

    /// @dev Verifies LOTR-ITR-1, LOTR-ITR-2, LOTR-ITR-3, and LOTR-ITR-4: initialization writes config and leaves
    /// pending fields cleared.
    function test_LOTR_ITR_1__LOTR_ITR_2__LOTR_ITR_3__LOTR_ITR_4_initialize_setsConfigAndClearsPending() public {
        // Setup

        // Call
        TxRecoveryState memory state = harness.getTxRecoveryState();

        // Verify
        assertEq(state.recoveryAddress, recoveryAddress, "recovery address mismatch");
        assertEq(state.timelockDurationSeconds, TX_TIMELOCK, "timelock mismatch");
        assertFalse(state.isEnabled, "initialize should keep disabled state");
        assertEq(state.pendingEnableTimestamp, 0, "pending enable should be zero");
        assertEq(state.pendingInit.pendingRecoveryAddress, address(0), "pending init address should be zero");
        assertEq(state.pendingInit.pendingTimelockDurationSeconds, 0, "pending init timelock duration should be zero");
        assertEq(state.pendingInit.pendingTimestamp, 0, "pending init timestamp should be zero");
    }

    /// @dev Verifies LOTR-ITR-5, LOTR-ITR-6, and LOTR-ITR-7: initialize rejects zero recovery or out-of-range
    /// timelocks.
    function test_LOTR_ITR_5__LOTR_ITR_6__LOTR_ITR_7_initialize_rejectsInvalidRecoveryParams() public {
        // Setup
        harness.resetTxRecoveryState();

        // Call
        vm.expectRevert(IOrganizationTxRecovery.InvalidTxRecoveryAddress.selector);
        harness.initializeTxRecovery(address(0), TX_TIMELOCK);

        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockUtils.InvalidTimelockDuration.selector,
                TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS - 1,
                TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS,
                TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
            )
        );
        harness.initializeTxRecovery(recoveryAddress, TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS - 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockUtils.InvalidTimelockDuration.selector,
                TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS + 1,
                TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS,
                TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
            )
        );
        harness.initializeTxRecovery(recoveryAddress, TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS + 1);

        // Verify
        assertEq(
            harness.getTxRecoveryState().recoveryAddress, address(0), "failed initialize should leave config unset"
        );
    }

    /// @dev Verifies LOTR-ITR-8 and LOTR-ITR-9: initialize accepts min/max timelock boundaries.
    function test_LOTR_ITR_8__LOTR_ITR_9_initialize_acceptsMinAndMaxTimelockBoundaries() public {
        // Setup
        harness.resetTxRecoveryState();

        // Call
        harness.initializeTxRecovery(recoveryAddress, TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS);

        // Verify
        assertEq(
            harness.getTxRecoveryState().timelockDurationSeconds,
            TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS,
            "min timelock should be accepted"
        );

        harness.resetTxRecoveryState();
        harness.initializeTxRecovery(recoveryAddress, TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS);
        assertEq(
            harness.getTxRecoveryState().timelockDurationSeconds,
            TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS,
            "max timelock should be accepted"
        );
    }

    /// @dev Verifies LOTR-ITR-10: initialize reverts when any pre-existing config field is already set.
    function test_LOTR_ITR_10_initialize_preconfiguredState_revertsTransactionRecoveryAlreadyConfigured() public {
        // Setup

        // Call
        vm.expectRevert(IOrganizationTxRecovery.TransactionRecoveryAlreadyConfigured.selector);
        harness.initializeTxRecovery(address(0x1234), TX_TIMELOCK);

        harness.resetTxRecoveryState();
        harness.setTxRecoveryState(
            TxRecoveryState({
                recoveryAddress: address(0),
                isEnabled: false,
                timelockDurationSeconds: TX_TIMELOCK,
                pendingEnableTimestamp: 0,
                pendingInit: PendingRecoveryInitTimelock({
                    pendingRecoveryAddress: address(0), pendingTimelockDurationSeconds: 0, pendingTimestamp: 0
                })
            })
        );

        vm.expectRevert(IOrganizationTxRecovery.TransactionRecoveryAlreadyConfigured.selector);
        harness.initializeTxRecovery(address(0x4321), TX_TIMELOCK);

        // Verify
    }

    /// @dev Verifies LOTR-IETR-1, LOTR-IETR-2, and LOTR-IETR-7: initiate-enable sets pending timestamp, emits event,
    /// and keeps recovery disabled.
    function test_LOTR_IETR_1__LOTR_IETR_2__LOTR_IETR_7_initiateEnable_setsPendingAndEmitsWhileRemainingDisabled()
        public
    {
        // Setup
        uint256 expectedTimestamp = block.timestamp + TX_TIMELOCK;

        vm.expectEmit(true, true, true, true);
        emit IOrganizationTxRecovery.TxRecoveryEnableInitiated(expectedTimestamp);

        // Call
        harness.initiateEnableTxRecovery();

        // Verify
        TxRecoveryState memory state = harness.getTxRecoveryState();
        assertEq(state.pendingEnableTimestamp, expectedTimestamp, "pending enable timestamp mismatch");
        assertFalse(state.isEnabled, "initiate should not enable recovery");
    }

    /// @dev Verifies LOTR-IETR-3 and LOTR-IETR-8: not-configured check reverts and takes precedence.
    function test_LOTR_IETR_3__LOTR_IETR_8_initiateEnable_notConfiguredCheck_precedesOtherChecks() public {
        // Setup
        harness.setTxRecoveryState(
            TxRecoveryState({
                recoveryAddress: address(0),
                isEnabled: true,
                timelockDurationSeconds: TX_TIMELOCK,
                pendingEnableTimestamp: block.timestamp + 1,
                pendingInit: PendingRecoveryInitTimelock({
                    pendingRecoveryAddress: address(0), pendingTimelockDurationSeconds: 0, pendingTimestamp: 0
                })
            })
        );

        // Call
        vm.expectRevert(IOrganizationTxRecovery.TxRecoveryNotConfigured.selector);
        harness.initiateEnableTxRecovery();

        // Verify
    }

    /// @dev Verifies LOTR-IETR-4: initiate-enable validates timelock range first and reverts for out-of-range values
    /// regardless of other configuration fields.
    function test_LOTR_IETR_4_initiateEnable_outOfRangeTimelock_revertsInvalidTimelockDuration() public {
        // Setup
        harness.setTxRecoveryState(
            TxRecoveryState({
                recoveryAddress: address(0),
                isEnabled: true,
                timelockDurationSeconds: TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS - 1,
                pendingEnableTimestamp: block.timestamp + 1,
                pendingInit: PendingRecoveryInitTimelock({
                    pendingRecoveryAddress: address(0), pendingTimelockDurationSeconds: 0, pendingTimestamp: 0
                })
            })
        );

        // Call
        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockUtils.InvalidTimelockDuration.selector,
                TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS - 1,
                TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS,
                TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
            )
        );
        harness.initiateEnableTxRecovery();

        harness.setTxRecoveryState(
            TxRecoveryState({
                recoveryAddress: recoveryAddress,
                isEnabled: false,
                timelockDurationSeconds: TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS + 1,
                pendingEnableTimestamp: 0,
                pendingInit: PendingRecoveryInitTimelock({
                    pendingRecoveryAddress: address(0), pendingTimelockDurationSeconds: 0, pendingTimestamp: 0
                })
            })
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockUtils.InvalidTimelockDuration.selector,
                TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS + 1,
                TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS,
                TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
            )
        );
        harness.initiateEnableTxRecovery();

        // Verify
    }

    /// @dev Verifies LOTR-IETR-5 and LOTR-IETR-6: initiate-enable rejects already-enabled and already-pending states.
    function test_LOTR_IETR_5__LOTR_IETR_6_initiateEnable_alreadyEnabledOrPending_reverts() public {
        // Setup
        harness.setTxRecoveryState(
            TxRecoveryState({
                recoveryAddress: recoveryAddress,
                isEnabled: true,
                timelockDurationSeconds: TX_TIMELOCK,
                pendingEnableTimestamp: 0,
                pendingInit: PendingRecoveryInitTimelock({
                    pendingRecoveryAddress: address(0), pendingTimelockDurationSeconds: 0, pendingTimestamp: 0
                })
            })
        );

        // Call
        vm.expectRevert(IOrganizationTxRecovery.TxRecoveryAlreadyEnabled.selector);
        harness.initiateEnableTxRecovery();

        harness.setTxRecoveryState(
            TxRecoveryState({
                recoveryAddress: recoveryAddress,
                isEnabled: false,
                timelockDurationSeconds: TX_TIMELOCK,
                pendingEnableTimestamp: block.timestamp + 1,
                pendingInit: PendingRecoveryInitTimelock({
                    pendingRecoveryAddress: address(0), pendingTimelockDurationSeconds: 0, pendingTimestamp: 0
                })
            })
        );
        vm.expectRevert(IOrganizationTxRecovery.TxRecoveryEnableAlreadyPending.selector);
        harness.initiateEnableTxRecovery();

        // Verify
    }

    /// @dev Verifies LOTR-FETR-1 and LOTR-FETR-2: finalize-enable reverts on no-pending and pre-expiry calls.
    function test_LOTR_FETR_1__LOTR_FETR_2_finalizeEnable_noPendingOrPreExpiry_reverts() public {
        // Setup

        // Call
        vm.expectRevert(IOrganizationTxRecovery.NoTxRecoveryEnablePending.selector);
        harness.finalizeEnableTxRecovery();

        harness.initiateEnableTxRecovery();
        uint256 pending = harness.getTxRecoveryState().pendingEnableTimestamp;

        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationAdminOperationTimelock.TimelockNotExpired.selector, pending, block.timestamp
            )
        );
        harness.finalizeEnableTxRecovery();

        // Verify
        assertFalse(harness.getTxRecoveryState().isEnabled, "state should remain disabled");
    }

    /// @dev Verifies LOTR-FETR-3, LOTR-FETR-5, LOTR-FETR-6, LOTR-FETR-7, and LOTR-FETR-8: finalize-enable succeeds at
    /// exact pending timestamp, enables recovery, clears pending, emits event, and preserves config.
    function test_LOTR_FETR_3__LOTR_FETR_5__LOTR_FETR_6__LOTR_FETR_7__LOTR_FETR_8_finalizeEnable_atExactTimestamp()
        public
    {
        // Setup
        harness.initiateEnableTxRecovery();
        TxRecoveryState memory beforeState = harness.getTxRecoveryState();

        vm.warp(beforeState.pendingEnableTimestamp);
        vm.expectEmit(true, true, true, true);
        emit IOrganizationTxRecovery.TxRecoveryEnableFinalized();

        // Call
        harness.finalizeEnableTxRecovery();

        // Verify
        TxRecoveryState memory afterState = harness.getTxRecoveryState();
        assertTrue(afterState.isEnabled, "finalize should enable recovery");
        assertEq(afterState.pendingEnableTimestamp, 0, "pending timestamp must clear");
        assertEq(afterState.recoveryAddress, beforeState.recoveryAddress, "recovery address must remain unchanged");
        assertEq(
            afterState.timelockDurationSeconds,
            beforeState.timelockDurationSeconds,
            "timelock duration must remain unchanged"
        );
    }

    /// @dev Verifies LOTR-FETR-4: finalize-enable succeeds after the pending timestamp has passed.
    function test_LOTR_FETR_4_finalizeEnable_afterExpiry() public {
        // Setup
        harness.initiateEnableTxRecovery();
        TxRecoveryState memory beforeState = harness.getTxRecoveryState();

        vm.warp(beforeState.pendingEnableTimestamp + 1);
        vm.expectEmit(true, true, true, true);
        emit IOrganizationTxRecovery.TxRecoveryEnableFinalized();

        // Call
        harness.finalizeEnableTxRecovery();

        // Verify
        TxRecoveryState memory afterState = harness.getTxRecoveryState();
        assertTrue(afterState.isEnabled, "finalize should enable recovery after expiry");
        assertEq(afterState.pendingEnableTimestamp, 0, "pending timestamp must clear");
    }

    /// @dev Verifies LOTR-CETR-1: cancel-enable reverts when no pending enable exists.
    function test_LOTR_CETR_1_cancelEnable_withoutPending_revertsNoTxRecoveryEnablePending() public {
        // Setup

        // Call
        vm.expectRevert(IOrganizationTxRecovery.NoTxRecoveryEnablePending.selector);
        harness.cancelEnableTxRecovery();

        // Verify
    }

    /// @dev Verifies LOTR-CETR-2, LOTR-CETR-3, LOTR-CETR-4, LOTR-CETR-5, and LOTR-CETR-6: cancel-enable clears pending,
    /// emits, does not enable, works after expiry, and keeps config stable.
    function test_LOTR_CETR_2__LOTR_CETR_3__LOTR_CETR_4__LOTR_CETR_5__LOTR_CETR_6_cancelEnable_successSemantics()
        public
    {
        // Setup
        harness.initiateEnableTxRecovery();
        TxRecoveryState memory beforeState = harness.getTxRecoveryState();
        vm.warp(beforeState.pendingEnableTimestamp + 1);

        vm.expectEmit(true, true, true, true);
        emit IOrganizationTxRecovery.TxRecoveryEnableCancelled();

        // Call
        harness.cancelEnableTxRecovery();

        // Verify
        TxRecoveryState memory afterState = harness.getTxRecoveryState();
        assertEq(afterState.pendingEnableTimestamp, 0, "pending enable should clear");
        assertFalse(afterState.isEnabled, "cancel should not enable recovery");
        assertEq(afterState.recoveryAddress, beforeState.recoveryAddress, "recovery address should remain unchanged");
        assertEq(
            afterState.timelockDurationSeconds,
            beforeState.timelockDurationSeconds,
            "timelock duration should remain unchanged"
        );
    }

    /// @dev Verifies LOTR-DTR-1, LOTR-DTR-2, LOTR-DTR-3, LOTR-DTR-4, LOTR-DTR-5, LOTR-DTR-6, and LOTR-DTR-7: disable
    /// clears enabled/pending state, emits, is idempotent, and keeps config immutable across pending cases.
    function test_LOTR_DTR_1__LOTR_DTR_2__LOTR_DTR_3__LOTR_DTR_4__LOTR_DTR_5__LOTR_DTR_6__LOTR_DTR_7_disable_semantics()
        public
    {
        // Setup
        harness.initiateEnableTxRecovery();
        uint256 pending = harness.getTxRecoveryState().pendingEnableTimestamp;

        // LOTR-DTR-5: disable during pending enable BEFORE expiry
        harness.setTxRecoveryState(
            TxRecoveryState({
                recoveryAddress: recoveryAddress,
                isEnabled: true,
                timelockDurationSeconds: TX_TIMELOCK,
                pendingEnableTimestamp: pending,
                pendingInit: PendingRecoveryInitTimelock({
                    pendingRecoveryAddress: address(0), pendingTimelockDurationSeconds: 0, pendingTimestamp: 0
                })
            })
        );

        vm.expectEmit(true, true, true, true);
        emit IOrganizationTxRecovery.TxRecoveryDisabled();

        // Call
        harness.disableTxRecovery();

        // Verify
        TxRecoveryState memory state = harness.getTxRecoveryState();
        assertFalse(state.isEnabled, "disable before expiry should set enabled=false");
        assertEq(state.pendingEnableTimestamp, 0, "disable before expiry should clear pending enable");
        assertEq(state.recoveryAddress, recoveryAddress, "disable before expiry should not alter recovery address");
        assertEq(state.timelockDurationSeconds, TX_TIMELOCK, "disable before expiry should not alter timelock");

        // LOTR-DTR-6: disable during pending enable AFTER expiry (before finalize)
        vm.warp(pending + 1);

        harness.setTxRecoveryState(
            TxRecoveryState({
                recoveryAddress: recoveryAddress,
                isEnabled: true,
                timelockDurationSeconds: TX_TIMELOCK,
                pendingEnableTimestamp: pending,
                pendingInit: PendingRecoveryInitTimelock({
                    pendingRecoveryAddress: address(0), pendingTimelockDurationSeconds: 0, pendingTimestamp: 0
                })
            })
        );

        vm.expectEmit(true, true, true, true);
        emit IOrganizationTxRecovery.TxRecoveryDisabled();

        // Call
        harness.disableTxRecovery();

        // Verify
        state = harness.getTxRecoveryState();
        assertFalse(state.isEnabled, "disable after expiry should set enabled=false");
        assertEq(state.pendingEnableTimestamp, 0, "disable after expiry should clear pending enable");
        assertEq(state.recoveryAddress, recoveryAddress, "disable after expiry should not alter recovery address");
        assertEq(state.timelockDurationSeconds, TX_TIMELOCK, "disable after expiry should not alter timelock");

        // LOTR-DTR-4: idempotent
        harness.disableTxRecovery();
        assertFalse(harness.getTxRecoveryState().isEnabled, "second disable should remain idempotent");
    }

    /// @dev Verifies LOTR-DTR-8: post-disable validation rejects recovery account transactions.
    function test_LOTR_DTR_8_disable_thenValidateAllowed_revertsTxRecoveryNotEnabled() public {
        // Setup
        harness.initiateEnableTxRecovery();
        vm.warp(harness.getTxRecoveryState().pendingEnableTimestamp);
        harness.finalizeEnableTxRecovery();
        harness.disableTxRecovery();

        // Call
        vm.expectRevert(IOrganizationTxRecovery.TxRecoveryNotEnabled.selector);
        harness.validateRecoveryAccountTransactionAllowedOrRevert();

        // Verify
    }

    /// @dev Verifies LOTR-DTR-9: recovery signature validation result is independent of `isEnabled`.
    function test_LOTR_DTR_9_isValidRecoverySignature_independentOfIsEnabled() public {
        // Setup
        bytes memory validSignature = _signHash(RECOVERY_PK, MESSAGE_HASH);

        harness.setTxRecoveryState(
            TxRecoveryState({
                recoveryAddress: recoveryAddress,
                isEnabled: true,
                timelockDurationSeconds: TX_TIMELOCK,
                pendingEnableTimestamp: 0,
                pendingInit: PendingRecoveryInitTimelock({
                    pendingRecoveryAddress: address(0), pendingTimelockDurationSeconds: 0, pendingTimestamp: 0
                })
            })
        );
        bool enabledResult = harness.isValidRecoverySignature(MESSAGE_HASH, validSignature);

        // Call
        harness.setTxRecoveryState(
            TxRecoveryState({
                recoveryAddress: recoveryAddress,
                isEnabled: false,
                timelockDurationSeconds: TX_TIMELOCK,
                pendingEnableTimestamp: 0,
                pendingInit: PendingRecoveryInitTimelock({
                    pendingRecoveryAddress: address(0), pendingTimelockDurationSeconds: 0, pendingTimestamp: 0
                })
            })
        );
        bool disabledResult = harness.isValidRecoverySignature(MESSAGE_HASH, validSignature);

        // Verify
        assertTrue(enabledResult, "sanity: signature should be valid");
        assertEq(disabledResult, enabledResult, "signature validity should not depend on enabled flag");
    }

    /// @dev Verifies LOTR-IITR-1, LOTR-IITR-2, LOTR-IITR-3, and LOTR-IITR-4: deferred-init initiation writes pending
    /// fields and emits expected event tuple.
    /// Plan rows: LOTR-AOTIITR-1, LOTR-AOTIITR-2, LOTR-AOTIITR-3, LOTR-AOTIITR-4.
    function test_LOTR_IITR_1__LOTR_IITR_2__LOTR_IITR_3__LOTR_IITR_4__LOTR_AOTIITR_1__LOTR_AOTIITR_2__LOTR_AOTIITR_3__LOTR_AOTIITR_4_initiateInitialize_writesPendingAndEmits()
        public
    {
        // Setup
        harness.resetTxRecoveryState();
        uint256 expectedFinalizeAt = block.timestamp + ADMIN_OPERATION_TIMELOCK;

        vm.expectEmit(true, true, true, true);
        emit IOrganizationTxRecovery.TxRecoveryInitializationInitiated(recoveryAddress, TX_TIMELOCK, expectedFinalizeAt);

        // Call
        harness.initiateInitializeTxRecovery(recoveryAddress, TX_TIMELOCK);

        // Verify
        TxRecoveryState memory state = harness.getTxRecoveryState();
        assertEq(state.pendingInit.pendingRecoveryAddress, recoveryAddress, "pending recovery address mismatch");
        assertEq(state.pendingInit.pendingTimelockDurationSeconds, TX_TIMELOCK, "pending timelock duration mismatch");
        assertEq(state.pendingInit.pendingTimestamp, expectedFinalizeAt, "pending finalize timestamp mismatch");
    }

    /// @dev Verifies `LibOrganizationTxRecovery.finalizeInitializeTxRecovery` reverts in the same block the deferred
    /// initialization was initiated.
    /// Plan rows: LOTR-AOTIITR-5.
    function test_LOTR_AOTIITR_5_finalizeInitializeTxRecovery_sameBlockRevertsTimelockNotExpired() public {
        // Setup: reset to an unconfigured state and stage a deferred initialization in the current block.
        harness.resetTxRecoveryState();
        harness.initiateInitializeTxRecovery(recoveryAddress, TX_TIMELOCK);
        uint256 pendingTimestamp = harness.getTxRecoveryState().pendingInit.pendingTimestamp;

        // Call: finalize immediately in the same block, expecting the shared timelock-not-expired revert.
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationAdminOperationTimelock.TimelockNotExpired.selector, pendingTimestamp, block.timestamp
            )
        );
        harness.finalizeInitializeTxRecovery();

        // Verify: same-block finalization leaves the deferred-init tuple untouched.
        TxRecoveryState memory state = harness.getTxRecoveryState();
        assertEq(
            state.pendingInit.pendingRecoveryAddress,
            recoveryAddress,
            "same-block finalize should preserve the pending recovery address"
        );
        assertEq(
            state.pendingInit.pendingTimelockDurationSeconds,
            TX_TIMELOCK,
            "same-block finalize should preserve the pending timelock"
        );
        assertEq(
            state.pendingInit.pendingTimestamp,
            pendingTimestamp,
            "same-block finalize should preserve the pending timestamp"
        );
    }

    /// @dev Verifies LOTR-IITR-5, LOTR-IITR-6, LOTR-IITR-7, LOTR-IITR-8, and LOTR-IITR-9: deferred-init initiation
    /// rejects configured/pending/invalid params.
    function test_LOTR_IITR_5__LOTR_IITR_6__LOTR_IITR_7__LOTR_IITR_8__LOTR_IITR_9_initiateInitialize_rejectsInvalidStatesAndParams()
        public
    {
        // Setup

        // Call
        vm.expectRevert(IOrganizationTxRecovery.TransactionRecoveryAlreadyConfigured.selector);
        harness.initiateInitializeTxRecovery(address(0x777), TX_TIMELOCK);

        harness.resetTxRecoveryState();
        harness.initiateInitializeTxRecovery(recoveryAddress, TX_TIMELOCK);
        vm.expectRevert(IOrganizationTxRecovery.TxRecoveryInitializationAlreadyPending.selector);
        harness.initiateInitializeTxRecovery(address(0x888), TX_TIMELOCK);

        harness.resetTxRecoveryState();
        vm.expectRevert(IOrganizationTxRecovery.InvalidTxRecoveryAddress.selector);
        harness.initiateInitializeTxRecovery(address(0), TX_TIMELOCK);

        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockUtils.InvalidTimelockDuration.selector,
                TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS - 1,
                TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS,
                TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
            )
        );
        harness.initiateInitializeTxRecovery(recoveryAddress, TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS - 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockUtils.InvalidTimelockDuration.selector,
                TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS + 1,
                TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS,
                TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
            )
        );
        harness.initiateInitializeTxRecovery(recoveryAddress, TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS + 1);

        // Verify
    }

    /// @dev Verifies LOTR-IITR-10 and LOTR-IITR-11: min/max timelock boundaries are accepted in deferred-init
    /// initiation.
    function test_LOTR_IITR_10__LOTR_IITR_11_initiateInitialize_minAndMaxBoundaryAccepted() public {
        // Setup
        harness.resetTxRecoveryState();

        // Call
        harness.initiateInitializeTxRecovery(recoveryAddress, TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS);

        // Verify
        assertEq(
            harness.getTxRecoveryState().pendingInit.pendingTimelockDurationSeconds,
            TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS,
            "min boundary should be accepted"
        );

        harness.resetTxRecoveryState();
        harness.initiateInitializeTxRecovery(recoveryAddress, TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS);
        assertEq(
            harness.getTxRecoveryState().pendingInit.pendingTimelockDurationSeconds,
            TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS,
            "max boundary should be accepted"
        );
    }

    /// @dev Verifies LOTR-IITR-12: active config and enabled state are unchanged while deferred-init is pending.
    function test_LOTR_IITR_12_initiateInitialize_doesNotMutateActiveConfigWhilePending() public {
        // Setup
        harness.setTxRecoveryState(
            TxRecoveryState({
                recoveryAddress: address(0),
                isEnabled: true,
                timelockDurationSeconds: 0,
                pendingEnableTimestamp: 123,
                pendingInit: PendingRecoveryInitTimelock({
                    pendingRecoveryAddress: address(0), pendingTimelockDurationSeconds: 0, pendingTimestamp: 0
                })
            })
        );
        harness.resetTxRecoveryState();

        // Call
        harness.initiateInitializeTxRecovery(recoveryAddress, TX_TIMELOCK);

        // Verify
        TxRecoveryState memory state = harness.getTxRecoveryState();
        assertEq(state.recoveryAddress, address(0), "active recovery address should remain unchanged");
        assertFalse(state.isEnabled, "active enabled flag should remain unchanged");
        assertEq(state.timelockDurationSeconds, 0, "active timelock should remain unchanged");
    }

    /// @dev Verifies LOTR-FITR-1 and LOTR-FITR-2: finalize-deferred-init reverts when no pending init exists or
    /// timelock has not expired.
    /// Plan rows: LOTR-AOTFITR-1.
    function test_LOTR_FITR_1__LOTR_FITR_2__LOTR_AOTFITR_1_finalizeInitialize_noPendingOrPreExpiry_reverts() public {
        // Setup
        harness.resetTxRecoveryState();

        // Call
        vm.expectRevert(IOrganizationTxRecovery.NoTxRecoveryInitializationPending.selector);
        harness.finalizeInitializeTxRecovery();

        harness.initiateInitializeTxRecovery(recoveryAddress, TX_TIMELOCK);
        uint256 pendingTimestamp = harness.getTxRecoveryState().pendingInit.pendingTimestamp;

        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationAdminOperationTimelock.TimelockNotExpired.selector, pendingTimestamp, block.timestamp
            )
        );
        harness.finalizeInitializeTxRecovery();

        // Verify
    }

    /// @dev Verifies LOTR-FITR-3, LOTR-FITR-4, LOTR-FITR-5, LOTR-FITR-6, and LOTR-FITR-7: finalize-deferred-init
    /// succeeds at boundary, writes config, clears pending, emits event, and leaves recovery disabled.
    /// Plan rows: LOTR-AOTFITR-2, LOTR-AOTFITR-4, LOTR-AOTFITR-5.
    function test_LOTR_FITR_3__LOTR_FITR_4__LOTR_FITR_5__LOTR_FITR_6__LOTR_FITR_7__LOTR_AOTFITR_2__LOTR_AOTFITR_4__LOTR_AOTFITR_5_finalizeInitialize_successSemantics()
        public
    {
        // Setup
        harness.resetTxRecoveryState();
        harness.initiateInitializeTxRecovery(recoveryAddress, TX_TIMELOCK);
        uint256 pendingTimestamp = harness.getTxRecoveryState().pendingInit.pendingTimestamp;
        vm.warp(pendingTimestamp);

        vm.expectEmit(true, true, true, true);
        emit IOrganizationTxRecovery.TxRecoveryInitializationFinalized(recoveryAddress, TX_TIMELOCK);

        // Call
        harness.finalizeInitializeTxRecovery();

        // Verify
        TxRecoveryState memory state = harness.getTxRecoveryState();
        assertEq(state.recoveryAddress, recoveryAddress, "recovery address should be finalized");
        assertEq(state.timelockDurationSeconds, TX_TIMELOCK, "timelock should be finalized");
        assertFalse(state.isEnabled, "finalize init should not auto-enable recovery");
        assertEq(state.pendingInit.pendingRecoveryAddress, address(0), "pending address should clear");
        assertEq(state.pendingInit.pendingTimelockDurationSeconds, 0, "pending timelock should clear");
        assertEq(state.pendingInit.pendingTimestamp, 0, "pending timestamp should clear");
    }

    /// @dev Verifies LOTR-FITR-8: after deferred-init finalize, normal enable flow can be initiated and finalized.
    function test_LOTR_FITR_8_finalizeInitialize_thenEnableFlow_executesNormally() public {
        // Setup
        harness.resetTxRecoveryState();
        harness.initiateInitializeTxRecovery(recoveryAddress, TX_TIMELOCK);
        vm.warp(harness.getTxRecoveryState().pendingInit.pendingTimestamp);
        harness.finalizeInitializeTxRecovery();

        // Call
        harness.initiateEnableTxRecovery();
        vm.warp(harness.getTxRecoveryState().pendingEnableTimestamp);
        harness.finalizeEnableTxRecovery();

        // Verify
        assertTrue(harness.getTxRecoveryState().isEnabled, "recovery should become enabled after finalize-enable");
    }

    /// @dev Verifies LOTR-FITR-9 and LOTR-FITR-10: if downstream initialize reverts, pending init remains unchanged and
    /// finalization event is not emitted.
    /// Plan rows: LOTR-AOTFITR-7.
    function test_LOTR_FITR_9__LOTR_FITR_10__LOTR_AOTFITR_7_finalizeInitialize_downstreamRevert_keepsPendingAndNoEvent()
        public
    {
        // Setup
        uint256 pendingTimestamp = block.timestamp + ADMIN_OPERATION_TIMELOCK;
        harness.setTxRecoveryState(
            TxRecoveryState({
                recoveryAddress: recoveryAddress,
                isEnabled: false,
                timelockDurationSeconds: TX_TIMELOCK,
                pendingEnableTimestamp: 0,
                pendingInit: PendingRecoveryInitTimelock({
                    pendingRecoveryAddress: address(0x9999),
                    pendingTimelockDurationSeconds: TX_TIMELOCK,
                    pendingTimestamp: pendingTimestamp
                })
            })
        );

        vm.warp(pendingTimestamp);
        vm.recordLogs();

        // Call
        vm.expectRevert(IOrganizationTxRecovery.TransactionRecoveryAlreadyConfigured.selector);
        harness.finalizeInitializeTxRecovery();

        // Verify
        TxRecoveryState memory state = harness.getTxRecoveryState();
        assertEq(
            state.pendingInit.pendingRecoveryAddress,
            address(0x9999),
            "pending address should rollback on downstream revert"
        );
        assertEq(
            state.pendingInit.pendingTimelockDurationSeconds,
            TX_TIMELOCK,
            "pending timelock should rollback on downstream revert"
        );
        assertEq(state.pendingInit.pendingTimestamp, pendingTimestamp, "pending timestamp should rollback on revert");

        bytes32 finalizedTopic = keccak256("TxRecoveryInitializationFinalized(address,uint256)");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            assertTrue(
                logs[i].topics.length == 0 || logs[i].topics[0] != finalizedTopic, "finalized event must not emit"
            );
        }
    }

    /// @dev Verifies LOTR-CITR-1: cancel-deferred-init reverts when no pending init exists.
    /// Plan rows: LOTR-AOTCITR-3.
    function test_LOTR_CITR_1__LOTR_AOTCITR_3_cancelInitialize_withoutPending_revertsNoTxRecoveryInitializationPending()
        public
    {
        // Setup

        // Call
        vm.expectRevert(IOrganizationTxRecovery.NoTxRecoveryInitializationPending.selector);
        harness.cancelInitializeTxRecovery();

        // Verify
    }

    /// @dev Verifies LOTR-CITR-2, LOTR-CITR-3, LOTR-CITR-4, LOTR-CITR-5, LOTR-CITR-6, and LOTR-CITR-7:
    /// cancel-deferred-init clears pending fields, emits event, preserves active config, and allows re-initiation.
    /// Plan rows: LOTR-AOTCITR-1.
    function test_LOTR_CITR_2__LOTR_CITR_3__LOTR_CITR_4__LOTR_CITR_5__LOTR_CITR_6__LOTR_CITR_7__LOTR_AOTCITR_1_cancelInitialize_successSemantics()
        public
    {
        // Setup
        harness.resetTxRecoveryState();
        harness.initiateInitializeTxRecovery(recoveryAddress, TX_TIMELOCK);
        vm.expectEmit(true, true, true, true);
        emit IOrganizationTxRecovery.TxRecoveryInitializationCancelled();

        // Call
        harness.cancelInitializeTxRecovery();

        // Verify
        TxRecoveryState memory state = harness.getTxRecoveryState();
        assertEq(state.pendingInit.pendingRecoveryAddress, address(0), "pending address should clear");
        assertEq(state.pendingInit.pendingTimelockDurationSeconds, 0, "pending timelock should clear");
        assertEq(state.pendingInit.pendingTimestamp, 0, "pending timestamp should clear");
        assertEq(state.recoveryAddress, address(0), "active config should remain unchanged");

        harness.initiateInitializeTxRecovery(address(0xBEEF), TX_TIMELOCK);
        assertEq(
            harness.getTxRecoveryState().pendingInit.pendingRecoveryAddress,
            address(0xBEEF),
            "re-initiation should work after cancel"
        );
    }

    /// @dev Verifies LOTR-VRATOR-1, LOTR-VRATOR-2, LOTR-VRATOR-3, LOTR-VRATOR-4, LOTR-VRATOR-5, and LOTR-VRATOR-6:
    /// validation success/failure and check precedence.
    function test_LOTR_VRATOR_1__LOTR_VRATOR_2__LOTR_VRATOR_3__LOTR_VRATOR_4__LOTR_VRATOR_5__LOTR_VRATOR_6_validateRecoveryAccountTransactionAllowed_semantics()
        public
    {
        // Setup
        harness.setTxRecoveryState(
            TxRecoveryState({
                recoveryAddress: recoveryAddress,
                isEnabled: true,
                timelockDurationSeconds: TX_TIMELOCK,
                pendingEnableTimestamp: 0,
                pendingInit: PendingRecoveryInitTimelock({
                    pendingRecoveryAddress: address(0), pendingTimelockDurationSeconds: 0, pendingTimestamp: 0
                })
            })
        );

        // Call
        harness.validateRecoveryAccountTransactionAllowedOrRevert();

        harness.setTxRecoveryState(
            TxRecoveryState({
                recoveryAddress: address(0),
                isEnabled: true,
                timelockDurationSeconds: TX_TIMELOCK,
                pendingEnableTimestamp: 0,
                pendingInit: PendingRecoveryInitTimelock({
                    pendingRecoveryAddress: address(0), pendingTimelockDurationSeconds: 0, pendingTimestamp: 0
                })
            })
        );
        vm.expectRevert(IOrganizationTxRecovery.TxRecoveryNotConfigured.selector);
        harness.validateRecoveryAccountTransactionAllowedOrRevert();

        harness.setTxRecoveryState(
            TxRecoveryState({
                recoveryAddress: recoveryAddress,
                isEnabled: false,
                timelockDurationSeconds: 0,
                pendingEnableTimestamp: 0,
                pendingInit: PendingRecoveryInitTimelock({
                    pendingRecoveryAddress: address(0), pendingTimelockDurationSeconds: 0, pendingTimestamp: 0
                })
            })
        );
        vm.expectRevert(IOrganizationTxRecovery.TxRecoveryNotConfigured.selector);
        harness.validateRecoveryAccountTransactionAllowedOrRevert();

        harness.setTxRecoveryState(
            TxRecoveryState({
                recoveryAddress: recoveryAddress,
                isEnabled: false,
                timelockDurationSeconds: TX_TIMELOCK,
                pendingEnableTimestamp: block.timestamp + 7,
                pendingInit: PendingRecoveryInitTimelock({
                    pendingRecoveryAddress: address(0), pendingTimelockDurationSeconds: 0, pendingTimestamp: 0
                })
            })
        );
        vm.expectRevert(IOrganizationTxRecovery.TxRecoveryNotEnabled.selector);
        harness.validateRecoveryAccountTransactionAllowedOrRevert();

        // Both NotConfigured and NotEnabled conditions are true; NotConfigured has precedence
        harness.setTxRecoveryState(
            TxRecoveryState({
                recoveryAddress: address(0),
                isEnabled: false,
                timelockDurationSeconds: 0,
                pendingEnableTimestamp: 0,
                pendingInit: PendingRecoveryInitTimelock({
                    pendingRecoveryAddress: address(0), pendingTimelockDurationSeconds: 0, pendingTimestamp: 0
                })
            })
        );
        vm.expectRevert(IOrganizationTxRecovery.TxRecoveryNotConfigured.selector);
        harness.validateRecoveryAccountTransactionAllowedOrRevert();

        // Verify
    }

    /// @dev Verifies LOTR-IVRS-1, LOTR-IVRS-2, LOTR-IVRS-3, LOTR-IVRS-4, LOTR-IVRS-5, LOTR-IVRS-6, LOTR-IVRS-7,
    /// LOTR-IVRS-8, LOTR-IVRS-9, LOTR-IVRS-10, LOTR-IVRS-11, LOTR-IVRS-12, LOTR-IVRS-13, LOTR-IVRS-14, and LOTR-IVRS-15
    /// across EOA/ERC1271 and malformed-signature behaviors.
    function test_LOTR_IVRS_1__LOTR_IVRS_2__LOTR_IVRS_3__LOTR_IVRS_4__LOTR_IVRS_5__LOTR_IVRS_6__LOTR_IVRS_7__LOTR_IVRS_8__LOTR_IVRS_9__LOTR_IVRS_10__LOTR_IVRS_11__LOTR_IVRS_12__LOTR_IVRS_13__LOTR_IVRS_14__LOTR_IVRS_15_isValidRecoverySignature_comprehensiveSemantics()
        public
    {
        // Setup
        harness.setTxRecoveryState(
            TxRecoveryState({
                recoveryAddress: address(0),
                isEnabled: false,
                timelockDurationSeconds: 0,
                pendingEnableTimestamp: 0,
                pendingInit: PendingRecoveryInitTimelock({
                    pendingRecoveryAddress: address(0), pendingTimelockDurationSeconds: 0, pendingTimestamp: 0
                })
            })
        );
        assertFalse(harness.isValidRecoverySignature(MESSAGE_HASH, bytes("")), "unconfigured should return false");

        harness.setTxRecoveryState(
            TxRecoveryState({
                recoveryAddress: recoveryAddress,
                isEnabled: true,
                timelockDurationSeconds: TX_TIMELOCK,
                pendingEnableTimestamp: 0,
                pendingInit: PendingRecoveryInitTimelock({
                    pendingRecoveryAddress: address(0), pendingTimelockDurationSeconds: 0, pendingTimestamp: 0
                })
            })
        );

        bytes memory validEoa = _signHash(RECOVERY_PK, MESSAGE_HASH);
        bytes memory wrongEoa = _signHash(OTHER_PK, MESSAGE_HASH);
        bytes memory malformedShort = hex"1b";
        bytes memory malformedLength = abi.encodePacked(uint8(27), bytes32(uint256(1)));
        bytes memory highS = _makeHighSSignature(RECOVERY_PK, MESSAGE_HASH);
        bytes memory unknownType = abi.encodePacked(uint8(2), bytes31(0));

        MockERC1271ValidSigner validContract = new MockERC1271ValidSigner();
        MockERC1271WrongMagicSigner wrongMagicContract = new MockERC1271WrongMagicSigner();
        MockERC1271RevertingSigner revertingContract = new MockERC1271RevertingSigner();
        MockERC1271ShortReturnSigner shortReturnContract = new MockERC1271ShortReturnSigner();

        // Call
        assertTrue(harness.isValidRecoverySignature(MESSAGE_HASH, validEoa), "valid EOA signature should pass");
        assertFalse(harness.isValidRecoverySignature(MESSAGE_HASH, wrongEoa), "wrong EOA signer should fail");
        assertFalse(harness.isValidRecoverySignature(MESSAGE_HASH, malformedShort), "malformed short should fail");
        assertFalse(harness.isValidRecoverySignature(MESSAGE_HASH, malformedLength), "malformed length should fail");
        assertFalse(harness.isValidRecoverySignature(MESSAGE_HASH, highS), "high-s signature should fail");
        assertFalse(harness.isValidRecoverySignature(MESSAGE_HASH, unknownType), "unknown type should fail");

        harness.setTxRecoveryState(
            TxRecoveryState({
                recoveryAddress: address(validContract),
                isEnabled: true,
                timelockDurationSeconds: TX_TIMELOCK,
                pendingEnableTimestamp: 0,
                pendingInit: PendingRecoveryInitTimelock({
                    pendingRecoveryAddress: address(0), pendingTimelockDurationSeconds: 0, pendingTimestamp: 0
                })
            })
        );

        bytes memory validContractSig = _buildContractSignature(address(validContract), hex"AABB");
        assertTrue(harness.isValidRecoverySignature(MESSAGE_HASH, validContractSig), "valid ERC1271 should pass");

        harness.setTxRecoveryState(
            TxRecoveryState({
                recoveryAddress: address(wrongMagicContract),
                isEnabled: true,
                timelockDurationSeconds: TX_TIMELOCK,
                pendingEnableTimestamp: 0,
                pendingInit: PendingRecoveryInitTimelock({
                    pendingRecoveryAddress: address(0), pendingTimelockDurationSeconds: 0, pendingTimestamp: 0
                })
            })
        );
        bytes memory wrongMagicSig = _buildContractSignature(address(wrongMagicContract), hex"ABCD");
        assertFalse(harness.isValidRecoverySignature(MESSAGE_HASH, wrongMagicSig), "wrong magic should fail");

        harness.setTxRecoveryState(
            TxRecoveryState({
                recoveryAddress: address(revertingContract),
                isEnabled: true,
                timelockDurationSeconds: TX_TIMELOCK,
                pendingEnableTimestamp: 0,
                pendingInit: PendingRecoveryInitTimelock({
                    pendingRecoveryAddress: address(0), pendingTimelockDurationSeconds: 0, pendingTimestamp: 0
                })
            })
        );
        bytes memory revertingSig = _buildContractSignature(address(revertingContract), hex"BEEF");
        assertFalse(harness.isValidRecoverySignature(MESSAGE_HASH, revertingSig), "reverting ERC1271 should fail");

        bytes memory truncatedHeader = abi.encodePacked(uint8(0), bytes10(0));
        assertFalse(harness.isValidRecoverySignature(MESSAGE_HASH, truncatedHeader), "truncated header should fail");

        bytes memory oversizedLength = abi.encodePacked(uint8(0), address(validContract), uint16(99), bytes("AA"));
        assertFalse(
            harness.isValidRecoverySignature(MESSAGE_HASH, oversizedLength),
            "declared length larger than bytes should fail"
        );

        harness.setTxRecoveryState(
            TxRecoveryState({
                recoveryAddress: address(shortReturnContract),
                isEnabled: true,
                timelockDurationSeconds: TX_TIMELOCK,
                pendingEnableTimestamp: 0,
                pendingInit: PendingRecoveryInitTimelock({
                    pendingRecoveryAddress: address(0), pendingTimelockDurationSeconds: 0, pendingTimestamp: 0
                })
            })
        );
        bytes memory shortReturnSig = _buildContractSignature(address(shortReturnContract), hex"CAFE");
        assertFalse(
            harness.isValidRecoverySignature(MESSAGE_HASH, shortReturnSig), "short-return ERC1271 should fail closed"
        );

        harness.setTxRecoveryState(
            TxRecoveryState({
                recoveryAddress: recoveryAddress,
                isEnabled: false,
                timelockDurationSeconds: TX_TIMELOCK,
                pendingEnableTimestamp: 0,
                pendingInit: PendingRecoveryInitTimelock({
                    pendingRecoveryAddress: address(0), pendingTimelockDurationSeconds: 0, pendingTimestamp: 0
                })
            })
        );

        assertFalse(
            harness.isValidRecoverySignature(keccak256("different-hash"), validEoa),
            "same signature over different hash should fail"
        );
        bool disabledResult = harness.isValidRecoverySignature(MESSAGE_HASH, validEoa);

        harness.setTxRecoveryState(
            TxRecoveryState({
                recoveryAddress: recoveryAddress,
                isEnabled: true,
                timelockDurationSeconds: TX_TIMELOCK,
                pendingEnableTimestamp: 0,
                pendingInit: PendingRecoveryInitTimelock({
                    pendingRecoveryAddress: address(0), pendingTimelockDurationSeconds: 0, pendingTimestamp: 0
                })
            })
        );
        bool enabledResult = harness.isValidRecoverySignature(MESSAGE_HASH, validEoa);

        // Verify
        assertEq(disabledResult, enabledResult, "isValidRecoverySignature should be independent of isEnabled state");
    }

    /// @dev Verifies LOTR-EOTRA-1, LOTR-EOTRA-2, LOTR-EOTRA-3, and LOTR-EOTRA-4: caller enforcement accepts configured
    /// recovery address and rejects mismatches/zero-config.
    function test_LOTR_EOTRA_1__LOTR_EOTRA_2__LOTR_EOTRA_3__LOTR_EOTRA_4_enforceOnlyTxRecoveryAddress_semantics()
        public
    {
        // Setup

        // Call
        vm.prank(recoveryAddress);
        harness.enforceOnlyTxRecoveryAddress();

        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationTxRecovery.UnauthorizedTxRecoveryAddress.selector, otherSigner, recoveryAddress
            )
        );
        vm.prank(otherSigner);
        harness.enforceOnlyTxRecoveryAddress();

        harness.setTxRecoveryState(
            TxRecoveryState({
                recoveryAddress: address(0),
                isEnabled: false,
                timelockDurationSeconds: 0,
                pendingEnableTimestamp: 0,
                pendingInit: PendingRecoveryInitTimelock({
                    pendingRecoveryAddress: address(0), pendingTimelockDurationSeconds: 0, pendingTimestamp: 0
                })
            })
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationTxRecovery.UnauthorizedTxRecoveryAddress.selector, otherSigner, address(0)
            )
        );
        vm.prank(otherSigner);
        harness.enforceOnlyTxRecoveryAddress();

        // Verify
    }

    /// @dev Verifies LOTR-IRET-1, LOTR-IRET-2, LOTR-IRET-3, LOTR-IRET-4, and LOTR-IRET-5: enabled-view helper tracks
    /// unconfigured/configured/pending/enabled/disabled transitions.
    function test_LOTR_IRET_1__LOTR_IRET_2__LOTR_IRET_3__LOTR_IRET_4__LOTR_IRET_5_isRecoveryEnabledForTxAndERC1271_tracksStateTransitions()
        public
    {
        // Setup
        harness.resetTxRecoveryState();

        // Call
        bool unconfigured = harness.isRecoveryEnabledForTxAndERC1271();

        harness.initializeTxRecovery(recoveryAddress, TX_TIMELOCK);
        bool configuredDisabled = harness.isRecoveryEnabledForTxAndERC1271();

        harness.initiateEnableTxRecovery();
        bool pending = harness.isRecoveryEnabledForTxAndERC1271();

        vm.warp(harness.getTxRecoveryState().pendingEnableTimestamp);
        harness.finalizeEnableTxRecovery();
        bool enabled = harness.isRecoveryEnabledForTxAndERC1271();

        harness.disableTxRecovery();
        bool disabledAfterEnable = harness.isRecoveryEnabledForTxAndERC1271();

        // Verify
        assertFalse(unconfigured, "unconfigured should report false");
        assertFalse(configuredDisabled, "configured+disabled should report false");
        assertFalse(pending, "pending enable should report false");
        assertTrue(enabled, "enabled state should report true");
        assertFalse(disabledAfterEnable, "disabled-after-enable should report false");
    }

    /// @dev Verifies LOTR-CPTRI-1, LOTR-CPTRI-2, LOTR-CPTRI-3, and LOTR-CPTRI-4: internal clear-pending helper zeros
    /// all fields and is idempotent.
    /// Plan rows: LOTR-CPTRIT-1, LOTR-CPTRIT-2.
    function test_LOTR_CPTRI_1__LOTR_CPTRI_2__LOTR_CPTRI_3__LOTR_CPTRI_4__LOTR_CPTRIT_1__LOTR_CPTRIT_2_clearPendingTxRecoveryInitTimelock_internalHelper()
        public
    {
        // Setup
        harness.setTxRecoveryState(
            TxRecoveryState({
                recoveryAddress: recoveryAddress,
                isEnabled: false,
                timelockDurationSeconds: TX_TIMELOCK,
                pendingEnableTimestamp: 0,
                pendingInit: PendingRecoveryInitTimelock({
                    pendingRecoveryAddress: address(0xABC1),
                    pendingTimelockDurationSeconds: TX_TIMELOCK,
                    pendingTimestamp: block.timestamp + 100
                })
            })
        );

        // Call
        harness.clearPendingTxRecoveryInitTimelockViaHarness();

        // Verify
        TxRecoveryState memory state = harness.getTxRecoveryState();
        assertEq(state.pendingInit.pendingRecoveryAddress, address(0), "pending address should clear");
        assertEq(state.pendingInit.pendingTimelockDurationSeconds, 0, "pending timelock should clear");
        assertEq(state.pendingInit.pendingTimestamp, 0, "pending timestamp should clear");

        harness.clearPendingTxRecoveryInitTimelockViaHarness();
        state = harness.getTxRecoveryState();
        assertEq(state.pendingInit.pendingRecoveryAddress, address(0), "idempotent clear: address should stay zero");
        assertEq(state.pendingInit.pendingTimelockDurationSeconds, 0, "idempotent clear: timelock should stay zero");
        assertEq(state.pendingInit.pendingTimestamp, 0, "idempotent clear: timestamp should stay zero");
    }

    /// @dev Verifies LOTR-VTNCR-1, LOTR-VTNCR-2, LOTR-VTNCR-3, and LOTR-VTNCR-4: helper reverts whenever either/both
    /// config fields are non-zero.
    /// Plan rows: LOTR-VTRNCOR-1, LOTR-VTRNCOR-2, LOTR-VTRNCOR-3, LOTR-VTRNCOR-4.
    function test_LOTR_VTNCR_1__LOTR_VTNCR_2__LOTR_VTNCR_3__LOTR_VTNCR_4__LOTR_VTRNCOR_1__LOTR_VTRNCOR_2__LOTR_VTRNCOR_3__LOTR_VTRNCOR_4_validateNotConfigured_internalHelper()
        public
    {
        // Setup
        harness.resetTxRecoveryState();

        // Call
        harness.validateTxRecoveryNotConfiguredOrRevertViaHarness();

        harness.setTxRecoveryState(
            TxRecoveryState({
                recoveryAddress: recoveryAddress,
                isEnabled: false,
                timelockDurationSeconds: 0,
                pendingEnableTimestamp: 0,
                pendingInit: PendingRecoveryInitTimelock({
                    pendingRecoveryAddress: address(0), pendingTimelockDurationSeconds: 0, pendingTimestamp: 0
                })
            })
        );
        vm.expectRevert(IOrganizationTxRecovery.TransactionRecoveryAlreadyConfigured.selector);
        harness.validateTxRecoveryNotConfiguredOrRevertViaHarness();

        harness.setTxRecoveryState(
            TxRecoveryState({
                recoveryAddress: address(0),
                isEnabled: false,
                timelockDurationSeconds: TX_TIMELOCK,
                pendingEnableTimestamp: 0,
                pendingInit: PendingRecoveryInitTimelock({
                    pendingRecoveryAddress: address(0), pendingTimelockDurationSeconds: 0, pendingTimestamp: 0
                })
            })
        );
        vm.expectRevert(IOrganizationTxRecovery.TransactionRecoveryAlreadyConfigured.selector);
        harness.validateTxRecoveryNotConfiguredOrRevertViaHarness();

        harness.setTxRecoveryState(
            TxRecoveryState({
                recoveryAddress: recoveryAddress,
                isEnabled: false,
                timelockDurationSeconds: TX_TIMELOCK,
                pendingEnableTimestamp: 0,
                pendingInit: PendingRecoveryInitTimelock({
                    pendingRecoveryAddress: address(0), pendingTimelockDurationSeconds: 0, pendingTimestamp: 0
                })
            })
        );
        vm.expectRevert(IOrganizationTxRecovery.TransactionRecoveryAlreadyConfigured.selector);
        harness.validateTxRecoveryNotConfiguredOrRevertViaHarness();

        // Verify
    }

    /// @dev Verifies LOTR-VTPR-1, LOTR-VTPR-2, LOTR-VTPR-3, LOTR-VTPR-4, LOTR-VTPR-5, and LOTR-VTPR-6: internal param
    /// helper accepts valid boundaries and rejects zero-address/out-of-range timelocks.
    /// Plan rows: LOTR-VTRPOR-1, LOTR-VTRPOR-2, LOTR-VTRPOR-3, LOTR-VTRPOR-4, LOTR-VTRPOR-5, LOTR-VTRPOR-6.
    function test_LOTR_VTPR_1__LOTR_VTPR_2__LOTR_VTPR_3__LOTR_VTPR_4__LOTR_VTPR_5__LOTR_VTPR_6__LOTR_VTRPOR_1__LOTR_VTRPOR_2__LOTR_VTRPOR_3__LOTR_VTRPOR_4__LOTR_VTRPOR_5__LOTR_VTRPOR_6_validateParams_internalHelper()
        public
    {
        // Setup

        // Call
        harness.validateTxRecoveryParamsOrRevertViaHarness(recoveryAddress, TX_TIMELOCK);

        vm.expectRevert(IOrganizationTxRecovery.InvalidTxRecoveryAddress.selector);
        harness.validateTxRecoveryParamsOrRevertViaHarness(address(0), TX_TIMELOCK);

        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockUtils.InvalidTimelockDuration.selector,
                TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS - 1,
                TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS,
                TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
            )
        );
        harness.validateTxRecoveryParamsOrRevertViaHarness(
            recoveryAddress, TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS - 1
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockUtils.InvalidTimelockDuration.selector,
                TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS + 1,
                TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS,
                TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
            )
        );
        harness.validateTxRecoveryParamsOrRevertViaHarness(
            recoveryAddress, TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS + 1
        );

        harness.validateTxRecoveryParamsOrRevertViaHarness(recoveryAddress, TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS);
        harness.validateTxRecoveryParamsOrRevertViaHarness(recoveryAddress, TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS);

        // Verify
    }

    /// @dev Verifies TXR-FZ-1: fuzz valid non-zero recovery addresses and in-range timelocks always initialize
    /// successfully.
    function testFuzz_TXR_FZ_1_initialize_validInputs_alwaysSucceed(address randomRecovery, uint256 rawTimelock)
        public
    {
        // Setup
        vm.assume(randomRecovery != address(0));
        uint256 timelock = bound(
            rawTimelock, TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS, TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
        );
        harness.resetTxRecoveryState();

        // Call
        harness.initializeTxRecovery(randomRecovery, timelock);

        // Verify
        TxRecoveryState memory state = harness.getTxRecoveryState();
        assertEq(state.recoveryAddress, randomRecovery, "recovery address should match fuzz input");
        assertEq(state.timelockDurationSeconds, timelock, "timelock should match bounded fuzz input");
        assertFalse(state.isEnabled, "initialization should not auto-enable recovery");
    }

    /// @dev Verifies TXR-FZ-2: fuzz out-of-range timelocks always revert for direct initialize and deferred-init
    /// initiate paths.
    function testFuzz_TXR_FZ_2_invalidTimelocks_initializeAndDeferredInitiate_revert(uint256 rawTimelock) public {
        // Setup
        vm.assume(
            rawTimelock < TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS
                || rawTimelock > TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
        );
        harness.resetTxRecoveryState();

        // Call
        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockUtils.InvalidTimelockDuration.selector,
                rawTimelock,
                TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS,
                TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
            )
        );
        harness.initializeTxRecovery(recoveryAddress, rawTimelock);

        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockUtils.InvalidTimelockDuration.selector,
                rawTimelock,
                TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS,
                TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
            )
        );
        harness.initiateInitializeTxRecovery(recoveryAddress, rawTimelock);

        // Verify
    }

    /// @dev Verifies TXR-FZ-3: fuzz timestamps before pending-enable finalization always fail.
    function testFuzz_TXR_FZ_3_finalizeEnable_beforePendingTimestamp_alwaysReverts(uint256 rawSecondsBefore) public {
        // Setup
        harness.initiateEnableTxRecovery();
        uint256 pending = harness.getTxRecoveryState().pendingEnableTimestamp;
        uint256 secondsBefore = bound(rawSecondsBefore, 1, TX_TIMELOCK);
        vm.warp(pending - secondsBefore);

        // Call
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationAdminOperationTimelock.TimelockNotExpired.selector, pending, block.timestamp
            )
        );
        harness.finalizeEnableTxRecovery();

        // Verify
        assertFalse(harness.getTxRecoveryState().isEnabled, "pre-expiry finalize should keep disabled state");
    }

    /// @dev Verifies TXR-FZ-4: fuzz timestamps at/after pending-enable timestamp succeed when pending exists.
    ///      Explicitly tests both the exact boundary (pending) and pending + 1 to verify GTE, then fuzzes
    ///      strictly-after offsets.
    function testFuzz_TXR_FZ_4_finalizeEnable_atOrAfterPendingTimestamp_succeeds(uint256 rawSecondsAfter) public {
        // Setup — exact boundary: warp to `pending` (the "at" case)
        harness.initiateEnableTxRecovery();
        uint256 pending = harness.getTxRecoveryState().pendingEnableTimestamp;
        vm.warp(pending);

        // Call
        harness.finalizeEnableTxRecovery();

        // Verify
        TxRecoveryState memory state = harness.getTxRecoveryState();
        assertTrue(state.isEnabled, "finalize at exact pending timestamp should enable recovery");
        assertEq(state.pendingEnableTimestamp, 0, "finalize at exact pending should clear pending timestamp");

        // Setup — boundary + 1: warp to `pending + 1` (the first "after" value, verifies GTE)
        harness.disableTxRecovery();
        harness.initiateEnableTxRecovery();
        pending = harness.getTxRecoveryState().pendingEnableTimestamp;
        vm.warp(pending + 1);

        // Call
        harness.finalizeEnableTxRecovery();

        // Verify
        state = harness.getTxRecoveryState();
        assertTrue(state.isEnabled, "finalize at pending + 1 should enable recovery");
        assertEq(state.pendingEnableTimestamp, 0, "finalize at pending + 1 should clear pending timestamp");

        // Setup — fuzz: warp to `pending + secondsAfter` where secondsAfter >= 1
        harness.disableTxRecovery();
        harness.initiateEnableTxRecovery();
        pending = harness.getTxRecoveryState().pendingEnableTimestamp;
        uint256 secondsAfter = bound(rawSecondsAfter, 1, 30 days);
        vm.warp(pending + secondsAfter);

        // Call
        harness.finalizeEnableTxRecovery();

        // Verify
        state = harness.getTxRecoveryState();
        assertTrue(state.isEnabled, "post-expiry finalize should enable recovery");
        assertEq(state.pendingEnableTimestamp, 0, "successful finalize should clear pending timestamp");
    }

    /// @dev Verifies TXR-FZ-5: fuzz arbitrary hashes/signature bytes for `isValidRecoverySignature` never reverts.
    function testFuzz_TXR_FZ_5_isValidRecoverySignature_arbitraryInputs_neverRevert(bytes32 hash, bytes calldata sig)
        public
        view
    {
        // Setup

        // Call
        bool result = harness.isValidRecoverySignature(hash, sig);

        // Verify
        result;
    }

    /// @dev Verifies `LibOrganizationTxRecovery.initializeTxRecovery` can configure tx recovery exactly once.
    /// @param firstRecovery The first configured tx-recovery address.
    /// @param firstTimelock The first configured tx-recovery timelock.
    /// @param secondRecovery The second attempted tx-recovery address.
    /// @param secondTimelock The second attempted tx-recovery timelock.
    function testFuzz_FLOTR_INIT_110_initializeTxRecovery_canOnlyBeConfiguredOnce(
        address firstRecovery,
        uint256 firstTimelock,
        address secondRecovery,
        uint256 secondTimelock
    ) public {
        vm.assume(firstRecovery != address(0));
        vm.assume(secondRecovery != address(0));
        vm.assume(firstRecovery != secondRecovery);

        uint256 boundedFirstTimelock = bound(
            firstTimelock, TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS, TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
        );
        uint256 boundedSecondTimelock = bound(
            secondTimelock, TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS, TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
        );
        vm.assume(boundedFirstTimelock != boundedSecondTimelock);

        // Setup: reset tx-recovery state and apply one successful initialization.
        harness.resetTxRecoveryState();
        harness.initializeTxRecovery(firstRecovery, boundedFirstTimelock);

        // Call: attempt to initialize again with a new tuple, expecting the one-time configuration revert.
        vm.expectRevert(IOrganizationTxRecovery.TransactionRecoveryAlreadyConfigured.selector);
        harness.initializeTxRecovery(secondRecovery, boundedSecondTimelock);

        // Verify: the originally configured tuple remains unchanged after the rejected second initialization.
        TxRecoveryState memory state = harness.getTxRecoveryState();
        assertEq(state.recoveryAddress, firstRecovery, "configured recovery address should remain unchanged");
        assertEq(state.timelockDurationSeconds, boundedFirstTimelock, "configured timelock should remain unchanged");
        assertFalse(state.isEnabled, "initialize should not auto-enable recovery");
    }

    /// @dev Verifies deferred tx-recovery initialization uses the admin-operation timelock for initiate, finalize,
    /// and cancel paths.
    /// @param pendingRecovery The recovery address proposed through deferred initialization.
    /// @param pendingTimelock The tx-recovery timelock proposed through deferred initialization.
    /// @param cancelAfterInitiate Whether to cancel immediately instead of finalizing after the timelock.
    function testFuzz_FLOTR_DINIT_112_deferredTxRecoveryInit_obeysAdminOperationTimelock(
        address pendingRecovery,
        uint256 pendingTimelock,
        bool cancelAfterInitiate
    ) public {
        vm.assume(pendingRecovery != address(0));
        uint256 boundedPendingTimelock = bound(
            pendingTimelock, TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS, TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
        );
        vm.assume(boundedPendingTimelock != ADMIN_OPERATION_TIMELOCK);

        // Setup: clear active tx-recovery config so deferred initialization is available.
        harness.resetTxRecoveryState();

        // Call: initiate deferred initialization, then either cancel immediately or finalize after the admin
        // timelock.
        harness.initiateInitializeTxRecovery(pendingRecovery, boundedPendingTimelock);
        TxRecoveryState memory pendingState = harness.getTxRecoveryState();

        assertEq(
            pendingState.pendingInit.pendingTimestamp,
            block.timestamp + ADMIN_OPERATION_TIMELOCK,
            "pending-init timestamp should use the admin-operation timelock"
        );

        if (cancelAfterInitiate) {
            harness.cancelInitializeTxRecovery();

            // Verify: cancel clears the pending tuple and leaves active tx recovery unconfigured.
            TxRecoveryState memory cancelledState = harness.getTxRecoveryState();
            assertEq(cancelledState.recoveryAddress, address(0), "cancel should not configure tx recovery");
            assertEq(
                cancelledState.pendingInit.pendingRecoveryAddress, address(0), "cancel should clear pending address"
            );
            assertEq(cancelledState.pendingInit.pendingTimestamp, 0, "cancel should clear pending timestamp");
            return;
        }

        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationAdminOperationTimelock.TimelockNotExpired.selector,
                pendingState.pendingInit.pendingTimestamp,
                block.timestamp
            )
        );
        harness.finalizeInitializeTxRecovery();

        vm.warp(pendingState.pendingInit.pendingTimestamp);
        harness.finalizeInitializeTxRecovery();

        // Verify: finalize succeeds only after the admin timelock and promotes the pending tuple into active config.
        TxRecoveryState memory finalizedState = harness.getTxRecoveryState();
        assertEq(finalizedState.recoveryAddress, pendingRecovery, "finalize should configure recovery address");
        assertEq(finalizedState.timelockDurationSeconds, boundedPendingTimelock, "finalize should configure timelock");
        assertEq(finalizedState.pendingInit.pendingRecoveryAddress, address(0), "finalize should clear pending address");
        assertEq(finalizedState.pendingInit.pendingTimestamp, 0, "finalize should clear pending timestamp");
        assertFalse(finalizedState.isEnabled, "finalize initialization should not auto-enable tx recovery");
    }

    /// @dev Verifies `LibOrganizationTxRecovery` requires the enable timelock to expire and makes disable immediate
    /// while clearing stale pending-enable state.
    /// @param rawSecondsBefore The offset used to land strictly before the pending-enable timestamp.
    function testFuzz_FLOTR_TOGGLE_114_enableRequiresTimelock_disableClearsPending(uint256 rawSecondsBefore) public {
        // Setup: initiate enable to seed a pending timestamp, then warp strictly before it.
        harness.initiateEnableTxRecovery();
        uint256 pendingTimestamp = harness.getTxRecoveryState().pendingEnableTimestamp;
        uint256 secondsBefore = bound(rawSecondsBefore, 1, TX_TIMELOCK);
        vm.warp(pendingTimestamp - secondsBefore);

        // Call: verify finalize reverts before expiry, then disable immediately and confirm the pending state is
        // cleared.
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationAdminOperationTimelock.TimelockNotExpired.selector, pendingTimestamp, block.timestamp
            )
        );
        harness.finalizeEnableTxRecovery();

        harness.disableTxRecovery();

        vm.expectRevert(IOrganizationTxRecovery.NoTxRecoveryEnablePending.selector);
        harness.finalizeEnableTxRecovery();

        // Verify: disable leaves recovery disabled and clears the stale pending-enable timestamp immediately.
        TxRecoveryState memory state = harness.getTxRecoveryState();
        assertFalse(state.isEnabled, "disable should keep recovery disabled");
        assertEq(state.pendingEnableTimestamp, 0, "disable should clear pending enable");
    }

    /// @dev Verifies `LibOrganizationTxRecovery.validateRecoveryAccountTransactionAllowedOrRevert` only allows the
    /// recovery transaction path when tx recovery is both configured and enabled.
    /// @param configuredRecoveryAddress Fuzzed non-zero recovery address used for the configured states.
    /// @param timelockDurationRaw Fuzzed entropy bounded into the valid recovery timelock range.
    function testFuzz_FLOTR_GATE_115_validateRecoveryAccountTransactionAllowed_requiresConfiguredAndEnabled(
        address configuredRecoveryAddress,
        uint256 timelockDurationRaw
    ) public {
        // Setup: bound a valid timelock and prepare configured+enabled, unconfigured, and configured+disabled
        // tx-recovery states around the fuzzed configured recovery address.
        vm.assume(configuredRecoveryAddress != address(0));
        uint256 boundedTimelock = bound(
            timelockDurationRaw,
            TimelockUtils.MIN_TIMELOCK_DURATION_SECONDS,
            TimelockUtils.MAX_TIMELOCK_DURATION_SECONDS
        );
        TxRecoveryState memory configuredEnabled = TxRecoveryState({
            recoveryAddress: configuredRecoveryAddress,
            isEnabled: true,
            timelockDurationSeconds: boundedTimelock,
            pendingEnableTimestamp: 0,
            pendingInit: PendingRecoveryInitTimelock({
                pendingRecoveryAddress: address(0), pendingTimelockDurationSeconds: 0, pendingTimestamp: 0
            })
        });
        TxRecoveryState memory unconfigured = TxRecoveryState({
            recoveryAddress: address(0),
            isEnabled: true,
            timelockDurationSeconds: boundedTimelock,
            pendingEnableTimestamp: 0,
            pendingInit: PendingRecoveryInitTimelock({
                pendingRecoveryAddress: address(0), pendingTimelockDurationSeconds: 0, pendingTimestamp: 0
            })
        });
        TxRecoveryState memory configuredDisabled = TxRecoveryState({
            recoveryAddress: configuredRecoveryAddress,
            isEnabled: false,
            timelockDurationSeconds: boundedTimelock,
            pendingEnableTimestamp: 0,
            pendingInit: PendingRecoveryInitTimelock({
                pendingRecoveryAddress: address(0), pendingTimelockDurationSeconds: 0, pendingTimestamp: 0
            })
        });

        // Call: evaluate the allowed path plus the unconfigured and disabled rejection branches.
        harness.setTxRecoveryState(configuredEnabled);
        harness.validateRecoveryAccountTransactionAllowedOrRevert();

        harness.setTxRecoveryState(unconfigured);
        vm.expectRevert(IOrganizationTxRecovery.TxRecoveryNotConfigured.selector);
        harness.validateRecoveryAccountTransactionAllowedOrRevert();

        harness.setTxRecoveryState(configuredDisabled);
        vm.expectRevert(IOrganizationTxRecovery.TxRecoveryNotEnabled.selector);
        harness.validateRecoveryAccountTransactionAllowedOrRevert();
    }

    /// @dev Verifies `LibOrganizationTxRecovery.isValidRecoverySignature` accepts both EOA and ERC-1271 recovery
    /// signers, rejects wrong signers for both paths, and does not depend on the enabled flag.
    /// @param startEnabled The initial enabled flag used for the first validation branch.
    function testFuzz_FLOTR_SIG_116_isValidRecoverySignature_supportsEOAAndERC1271IndependentOfEnabledFlag(bool startEnabled)
        public
    {
        // Setup: build valid EOA and ERC-1271 recovery signers plus wrong EOA and wrong contract signers for the
        // negative branches.
        bytes memory validEoaSignature = _signHash(RECOVERY_PK, MESSAGE_HASH);
        bytes memory wrongEoaSignature = _signHash(OTHER_PK, MESSAGE_HASH);
        MockERC1271ValidSigner validContract = new MockERC1271ValidSigner();
        bytes memory validContractSignature = _buildContractSignature(address(validContract), hex"CAFE");
        MockERC1271ValidSigner wrongContract = new MockERC1271ValidSigner();
        bytes memory wrongContractSignature = _buildContractSignature(address(wrongContract), hex"CAFE");

        // Call: validate the EOA path with both enabled states.
        harness.setTxRecoveryState(
            TxRecoveryState({
                recoveryAddress: recoveryAddress,
                isEnabled: startEnabled,
                timelockDurationSeconds: TX_TIMELOCK,
                pendingEnableTimestamp: 0,
                pendingInit: PendingRecoveryInitTimelock({
                    pendingRecoveryAddress: address(0), pendingTimelockDurationSeconds: 0, pendingTimestamp: 0
                })
            })
        );
        bool eoaFirst = harness.isValidRecoverySignature(MESSAGE_HASH, validEoaSignature);
        bool eoaWrong = harness.isValidRecoverySignature(MESSAGE_HASH, wrongEoaSignature);

        harness.setTxRecoveryState(
            TxRecoveryState({
                recoveryAddress: recoveryAddress,
                isEnabled: !startEnabled,
                timelockDurationSeconds: TX_TIMELOCK,
                pendingEnableTimestamp: 0,
                pendingInit: PendingRecoveryInitTimelock({
                    pendingRecoveryAddress: address(0), pendingTimelockDurationSeconds: 0, pendingTimestamp: 0
                })
            })
        );
        bool eoaSecond = harness.isValidRecoverySignature(MESSAGE_HASH, validEoaSignature);

        // Call: validate the ERC-1271 path with both enabled states.
        harness.setTxRecoveryState(
            TxRecoveryState({
                recoveryAddress: address(validContract),
                isEnabled: startEnabled,
                timelockDurationSeconds: TX_TIMELOCK,
                pendingEnableTimestamp: 0,
                pendingInit: PendingRecoveryInitTimelock({
                    pendingRecoveryAddress: address(0), pendingTimelockDurationSeconds: 0, pendingTimestamp: 0
                })
            })
        );
        bool contractFirst = harness.isValidRecoverySignature(MESSAGE_HASH, validContractSignature);
        bool contractWrong = harness.isValidRecoverySignature(MESSAGE_HASH, wrongContractSignature);

        harness.setTxRecoveryState(
            TxRecoveryState({
                recoveryAddress: address(validContract),
                isEnabled: !startEnabled,
                timelockDurationSeconds: TX_TIMELOCK,
                pendingEnableTimestamp: 0,
                pendingInit: PendingRecoveryInitTimelock({
                    pendingRecoveryAddress: address(0), pendingTimelockDurationSeconds: 0, pendingTimestamp: 0
                })
            })
        );
        bool contractSecond = harness.isValidRecoverySignature(MESSAGE_HASH, validContractSignature);

        // Verify: valid EOA and ERC-1271 recovery signatures pass regardless of enabled state, while wrong signers
        // still fail.
        assertTrue(eoaFirst, "valid EOA recovery signature should pass");
        assertTrue(eoaSecond, "valid EOA recovery signature should be independent of enabled state");
        assertFalse(eoaWrong, "wrong EOA signer should fail");
        assertTrue(contractFirst, "valid ERC1271 recovery signature should pass");
        assertTrue(contractSecond, "valid ERC1271 recovery signature should be independent of enabled state");
        assertFalse(contractWrong, "wrong contract signer should fail");
    }

    /// @dev Verifies recovery signatures cannot replay across a different signed hash even when the signer stays
    /// configured.
    /// @param originalHash The hash actually signed by the configured recovery signer.
    /// @param replayHash The distinct hash used for the replay attempt.
    function testFuzz_FLOTR_SIG_116__FCF_SIGSYS_161_isValidRecoverySignature_sameSignatureCannotReplayAcrossDifferentHashes(
        bytes32 originalHash,
        bytes32 replayHash
    ) public {
        vm.assume(originalHash != replayHash);

        // Setup: configure the deterministic recovery signer and build one signature over the original hash only.
        harness.setTxRecoveryState(
            TxRecoveryState({
                recoveryAddress: recoveryAddress,
                isEnabled: true,
                timelockDurationSeconds: TX_TIMELOCK,
                pendingEnableTimestamp: 0,
                pendingInit: PendingRecoveryInitTimelock({
                    pendingRecoveryAddress: address(0), pendingTimelockDurationSeconds: 0, pendingTimestamp: 0
                })
            })
        );
        bytes memory signature = _signHash(RECOVERY_PK, originalHash);

        // Call: validate the same signature against both the original hash and a distinct replay hash.
        bool originalValid = harness.isValidRecoverySignature(originalHash, signature);
        bool replayValid = harness.isValidRecoverySignature(replayHash, signature);

        // Verify: the configured signer validates only for the exact signed hash.
        assertTrue(originalValid, "configured recovery signer should validate the original hash");
        assertFalse(replayValid, "same signature must fail when replayed against a different hash");
    }

    /// @dev Verifies `LibOrganizationTxRecovery.finalizeInitializeTxRecovery` succeeds when `block.timestamp` is
    /// strictly greater than the pending initialization timestamp.
    function test_LOTR_AOTFITR_3_finalizeInitializeTxRecovery_afterPendingTimestampSucceeds() public {
        // Setup: reset to an unconfigured state, stage a deferred tx-recovery initialization, and advance past expiry.
        harness.resetTxRecoveryState();
        harness.initiateInitializeTxRecovery(otherSigner, 5 days);
        vm.warp(harness.getTxRecoveryState().pendingInit.pendingTimestamp + 1);

        // Call: finalize the deferred tx-recovery initialization after the admin-op timelock has already expired.
        harness.finalizeInitializeTxRecovery();

        // Verify: post-expiry finalization succeeds and installs the pending recovery configuration.
        TxRecoveryState memory state = harness.getTxRecoveryState();
        assertEq(state.recoveryAddress, otherSigner, "post-expiry finalize should configure the recovery address");
        assertEq(state.timelockDurationSeconds, 5 days, "post-expiry finalize should configure the pending timelock");
        assertEq(state.pendingInit.pendingTimestamp, 0, "post-expiry finalize should clear the pending timestamp");
    }

    /// @dev Verifies `LibOrganizationTxRecovery.finalizeInitializeTxRecovery` reverts with
    /// `NoTxRecoveryInitializationPending` after cancellation even once the cancelled timestamp has passed.
    function test_LOTR_AOTFITR_6_finalizeInitializeTxRecovery_afterCancellationAndExpiryRevertsNoPending() public {
        // Setup: reset to an unconfigured state, stage and cancel a deferred init, then advance past the old expiry.
        harness.resetTxRecoveryState();
        harness.initiateInitializeTxRecovery(otherSigner, 5 days);
        uint256 cancelledPendingTimestamp = harness.getTxRecoveryState().pendingInit.pendingTimestamp;
        harness.cancelInitializeTxRecovery();
        vm.warp(cancelledPendingTimestamp + 1);

        // Call: attempt to finalize the cancelled deferred initialization after the old timestamp has elapsed.
        vm.expectRevert(IOrganizationTxRecovery.NoTxRecoveryInitializationPending.selector);
        harness.finalizeInitializeTxRecovery();

        // Verify: cancellation remains authoritative and leaves the pending tuple cleared.
        assertEq(
            harness.getTxRecoveryState().pendingInit.pendingTimestamp, 0, "cancelled pending init should stay zero"
        );
    }

    /// @dev Verifies `LibOrganizationTxRecovery.cancelInitializeTxRecovery` succeeds after the admin-op timelock has
    /// expired as long as finalization has not occurred yet.
    function test_LOTR_AOTCITR_2_cancelInitializeTxRecovery_afterPendingTimestampStillSucceeds() public {
        // Setup: reset to an unconfigured state, stage a deferred init, and advance one second past its expiry.
        harness.resetTxRecoveryState();
        harness.initiateInitializeTxRecovery(otherSigner, 5 days);
        vm.warp(harness.getTxRecoveryState().pendingInit.pendingTimestamp + 1);

        // Call: cancel the deferred initialization after expiry but before any finalize call.
        harness.cancelInitializeTxRecovery();

        // Verify: post-expiry cancel still clears the staged pending tuple.
        TxRecoveryState memory state = harness.getTxRecoveryState();
        assertEq(state.pendingInit.pendingRecoveryAddress, address(0), "post-expiry cancel should clear address");
        assertEq(state.pendingInit.pendingTimelockDurationSeconds, 0, "post-expiry cancel should clear timelock");
        assertEq(state.pendingInit.pendingTimestamp, 0, "post-expiry cancel should clear timestamp");
    }

    /// @dev Verifies `LibOrganizationTxRecovery.cancelInitializeTxRecovery` allows a later re-initiation to compute a
    /// fresh admin-operation timelock timestamp from the new start time.
    function test_LOTR_AOTCITR_4_cancelInitializeTxRecovery_reinitiationComputesFreshPendingTimestamp() public {
        // Setup: reset to an unconfigured state, stage and cancel one deferred init, then move time forward.
        harness.resetTxRecoveryState();
        harness.initiateInitializeTxRecovery(otherSigner, 5 days);
        harness.cancelInitializeTxRecovery();
        vm.warp(block.timestamp + 4 days);
        uint256 expectedFreshPendingTimestamp = block.timestamp + ADMIN_OPERATION_TIMELOCK;

        // Call: initiate the deferred tx-recovery configuration again after the cancellation.
        harness.initiateInitializeTxRecovery(recoveryAddress, TX_TIMELOCK);

        // Verify: the new pending timestamp is recomputed from the new start time instead of reusing stale state.
        TxRecoveryState memory state = harness.getTxRecoveryState();
        assertEq(
            state.pendingInit.pendingTimestamp,
            expectedFreshPendingTimestamp,
            "re-initiation should compute a fresh pending timestamp"
        );
        assertEq(
            state.pendingInit.pendingRecoveryAddress,
            recoveryAddress,
            "re-initiation should store the new pending recovery address"
        );
    }

    /// @dev Verifies `LibOrganizationTxRecovery._validateTxRecoveryParamsOrRevert` accepts non-boundary in-range
    /// timelock durations for non-zero recovery addresses.
    function test_LOTR_VTRPOR_5_validateTxRecoveryParams_nonBoundaryInRangeTimelockSucceeds() public view {
        // Setup: choose a non-zero recovery address and an in-range timelock strictly between the min and max bounds.
        uint256 inRangeTimelock = 7 days;

        // Call: validate the in-range recovery parameters through the internal-helper harness wrapper.
        harness.validateTxRecoveryParamsOrRevertViaHarness(recoveryAddress, inRangeTimelock);

        // Verify: in-range non-boundary recovery params return successfully.
        assertTrue(true, "in-range non-boundary tx-recovery params should be accepted");
    }
}
