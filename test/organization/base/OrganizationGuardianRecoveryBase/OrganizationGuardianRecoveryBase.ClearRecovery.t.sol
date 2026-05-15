// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationAdmin} from "interfaces/organization/IOrganizationAdmin.sol";
import {IOrganizationGuardian} from "interfaces/organization/IOrganizationGuardian.sol";
import {IOrganizationGuardianRecovery} from "interfaces/organization/IOrganizationGuardianRecovery.sol";
import {IOrganizationSignatures} from "interfaces/organization/IOrganizationSignatures.sol";
import {IOrganizationTxRecovery} from "interfaces/organization/IOrganizationTxRecovery.sol";
import {TimelockUtils} from "libraries/TimelockUtils.sol";
import {LibOrganizationRecoveryStorage} from "organization/libraries/storage/LibOrganizationRecoveryStorage.sol";
import {
    OrganizationClearRecoveryHarness
} from "test/organization/base/OrganizationGuardianRecoveryBase/OrganizationClearRecoveryHarness.sol";
import {OrganizationAdminStateHarness} from "test/organization/shared/OrganizationAdminStateHarness.sol";
import {OrganizationAdminTestBase} from "test/organization/shared/OrganizationAdminTestBase.sol";
import {
    OrganizationGuardianRecoveryStateHarness
} from "test/organization/shared/OrganizationGuardianRecoveryStateHarness.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";
import {OperationType} from "types/CommonTypes.sol";
import {GuardianRecoveryState, PendingRecoveryInitTimelock, TxRecoveryState} from "types/RecoveryTypes.sol";

/**
 * @dev Unit tests for the cross-track `clearRecovery` entrypoint exposed by `OrganizationGuardianRecoveryBase`.
 *      Covers authorization, both-track reset semantics, event emission, race scenarios against the recovery
 *      enable timelock, pending-state cleanup, and the clear -> re-initialize loop.
 */
contract OrganizationGuardianRecoveryBaseClearRecoveryTest is OrganizationAdminTestBase {
    /// @dev Admin operation timelock used by deferred initialization flows.
    uint256 internal constant ADMIN_OPERATION_TIMELOCK = 2 days;

    /// @dev Default guardian-recovery and tx-recovery timelocks.
    uint256 internal constant GUARDIAN_RECOVERY_TIMELOCK = 2 days;
    uint256 internal constant TX_RECOVERY_TIMELOCK = 2 days;

    /// @dev Deterministic guardian-recovery fixtures.
    address internal constant GUARDIAN_RECOVERY_ADDRESS = address(0xAA11);
    address internal constant GUARDIAN_RECOVERY_ADDRESS_B = address(0xAA12);
    address internal constant NEW_GUARDIAN_A = address(0xAB11);

    /// @dev Deterministic tx-recovery fixtures.
    address internal constant TX_RECOVERY_ADDRESS = address(0xBB11);
    address internal constant TX_RECOVERY_ADDRESS_B = address(0xBB12);

    /// @dev Combined-base harness exposing both clear and tx-recovery entrypoints under one address.
    OrganizationClearRecoveryHarness internal harness;

    /// @dev Typed shared-state surface for recovery/guardian/admin storage helpers.
    OrganizationGuardianRecoveryStateHarness internal recoveryStateHarness;

    /**
     * @dev Deploys the combined-base harness used by this test suite.
     */
    function _deployHarness() internal override returns (OrganizationAdminStateHarness) {
        harness = new OrganizationClearRecoveryHarness();
        return OrganizationAdminStateHarness(address(harness));
    }

    /**
     * @dev Seeds the standard fixture state used across cases: admin timelock, fully configured guardian recovery,
     *      and fully configured tx recovery (with no pending state).
     */
    function setUp() public virtual override {
        super.setUp();
        recoveryStateHarness = OrganizationGuardianRecoveryStateHarness(address(harness));
        recoveryStateHarness.setAdminOperationTimelockDurationSeconds(ADMIN_OPERATION_TIMELOCK);
        recoveryStateHarness.setGuardianRecoveryConfig(GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK);
        _seedFullyConfiguredTxRecovery();
    }

    /**
     * @dev Builds admin auth for a `ClearRecovery` operation. The operation has no bound state so
     *      operationData is empty, matching what `OrganizationGuardianRecoveryBase.clearRecovery` signs.
     */
    function _buildClearRecoveryAuth(uint256 salt, uint256 expiration, bool isApproval, uint256[] memory privateKeys)
        internal
        view
        returns (AdminAuthParams memory auth, bytes memory operationData)
    {
        operationData = bytes("");
        auth = _buildAdminAuthParamsForEoa({
            operationType: OperationType.ClearRecovery,
            operationData: operationData,
            isApproval: isApproval,
            salt: salt,
            expirationTimestamp: expiration,
            privateKeys: privateKeys
        });
    }

    /**
     * @dev Seeds a fully configured tx recovery state with no pending state.
     */
    function _seedFullyConfiguredTxRecovery() internal {
        recoveryStateHarness.setTxRecoveryState(
            TxRecoveryState({
                recoveryAddress: TX_RECOVERY_ADDRESS,
                isEnabled: false,
                timelockDurationSeconds: TX_RECOVERY_TIMELOCK,
                pendingEnableTimestamp: 0,
                pendingInit: PendingRecoveryInitTimelock({
                    pendingRecoveryAddress: address(0), pendingTimelockDurationSeconds: 0, pendingTimestamp: 0
                }),
                initAttemptId: 0
            })
        );
    }

    /// @dev Verifies `clearRecovery` reverts when called by a non-guardian, before any auth check runs.
    function test_nonGuardianCaller_revertsOnlyGuardian() public {
        // Setup: build valid admin auth so the only failing check is the guardian gate.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
        (AdminAuthParams memory auth,) = _buildClearRecoveryAuth({
            salt: 12_001,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call: clear as a non-guardian and expect the `onlyGuardian` revert payload.
        _expectOnlyGuardianRevert(NON_GUARDIAN);
        vm.prank(NON_GUARDIAN);
        harness.clearRecovery(auth);

        // Verify: both recovery configurations remain untouched.
        assertEq(
            harness.getGuardianRecoveryState().recoveryAddress,
            GUARDIAN_RECOVERY_ADDRESS,
            "guardian recovery address must remain configured"
        );
        assertEq(
            harness.getTxRecoveryState().recoveryAddress,
            TX_RECOVERY_ADDRESS,
            "tx recovery address must remain configured"
        );
    }

    /// @dev Verifies the recovery addresses themselves cannot satisfy the `onlyGuardian` gate. A compromised
    /// recovery key cannot block its own revocation.
    function test_recoveryAddressCaller_cannotBlockClear() public {
        // Setup: build valid admin auth so the only failing check is the guardian gate.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
        (AdminAuthParams memory auth,) = _buildClearRecoveryAuth({
            salt: 12_002,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call: both recovery addresses attempt to clear and are rejected as non-guardian callers.
        _expectOnlyGuardianRevert(TX_RECOVERY_ADDRESS);
        vm.prank(TX_RECOVERY_ADDRESS);
        harness.clearRecovery(auth);

        _expectOnlyGuardianRevert(GUARDIAN_RECOVERY_ADDRESS);
        vm.prank(GUARDIAN_RECOVERY_ADDRESS);
        harness.clearRecovery(auth);

        // Verify: both recovery configurations remain untouched after both attempts.
        assertEq(
            harness.getGuardianRecoveryState().recoveryAddress,
            GUARDIAN_RECOVERY_ADDRESS,
            "guardian recovery address must remain configured"
        );
        assertEq(
            harness.getTxRecoveryState().recoveryAddress,
            TX_RECOVERY_ADDRESS,
            "tx recovery address must remain configured"
        );
    }

    /// @dev Verifies `clearRecovery` reverts when admin signatures do not satisfy the current threshold.
    function test_insufficientAdminSignatures_reverts() public {
        // Setup: require two admin signatures but provide only one.
        _setMembersAndAdmins({members: buildArray(admin1, admin2), admins: buildArray(admin1, admin2), threshold: 2});
        (AdminAuthParams memory auth,) = _buildClearRecoveryAuth({
            salt: 12_003,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call: guardian invokes clear with single-admin signatures while threshold requires two.
        vm.expectRevert(IOrganizationAdmin.InsufficientAdminAuthorization.selector);
        vm.prank(GUARDIAN);
        harness.clearRecovery(auth);

        // Verify: neither track is mutated after the rejected authorization.
        assertEq(
            harness.getGuardianRecoveryState().recoveryAddress,
            GUARDIAN_RECOVERY_ADDRESS,
            "guardian recovery address must remain configured"
        );
        assertEq(
            harness.getTxRecoveryState().recoveryAddress,
            TX_RECOVERY_ADDRESS,
            "tx recovery address must remain configured"
        );
    }

    /// @dev Verifies `clearRecovery` rejects rejection-flavored admin signatures (isApproval = false).
    function test_rejectionSignaturesAreRejected() public {
        // Setup: build admin auth with `isApproval = false`, so signatures are signed over the rejection hash.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
        (AdminAuthParams memory rejectionAuth,) = _buildClearRecoveryAuth({
            salt: 12_004,
            expiration: block.timestamp + 1 days,
            isApproval: false,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call: guardian submits rejection-signed auth and the recovered signer fails to match an admin signing
        // the approval hash.
        vm.expectPartialRevert(IOrganizationAdmin.SignerIsNotAdmin.selector);
        vm.prank(GUARDIAN);
        harness.clearRecovery(rejectionAuth);

        // Verify: neither track is mutated.
        assertEq(
            harness.getGuardianRecoveryState().recoveryAddress,
            GUARDIAN_RECOVERY_ADDRESS,
            "guardian recovery address must remain configured"
        );
        assertEq(
            harness.getTxRecoveryState().recoveryAddress,
            TX_RECOVERY_ADDRESS,
            "tx recovery address must remain configured"
        );
    }

    /// @dev Verifies `clearRecovery` reverts when the same admin auth payload is replayed.
    function test_replaySameAuth_revertsNonceAlreadyUsed() public {
        // Setup: build admin auth and remember the nonce that the operation will consume.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
        (AdminAuthParams memory auth, bytes memory operationData) = _buildClearRecoveryAuth({
            salt: 12_005,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        uint256 nonce = harness.computeNonce(OperationType.ClearRecovery, operationData, 12_005);

        // Call: first clear succeeds and consumes the nonce. Re-seed both tracks so the second clear could otherwise
        // succeed at the library level, then replay the same auth and expect `NonceAlreadyUsed`.
        vm.prank(GUARDIAN);
        harness.clearRecovery(auth);
        assertTrue(harness.getUsedNonce(nonce), "first clear should consume the nonce");

        _seedFullyConfiguredTxRecovery();
        recoveryStateHarness.setGuardianRecoveryConfig(GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK);

        vm.expectRevert(abi.encodeWithSelector(IOrganizationSignatures.NonceAlreadyUsed.selector, nonce));
        vm.prank(GUARDIAN);
        harness.clearRecovery(auth);
    }

    /// @dev Verifies a successful `clearRecovery` resets every field on both tracks, emits one event per track,
    /// and leaves the state in a re-initializable shape for both tracks.
    function test_clearRecovery_resetsBothTracksAndEmitsEvents() public {
        // Setup: seed every field on both tracks, including pending enable, pending recovery guardian update, and
        // pending deferred initialization state, so the clear has the maximum surface area to wipe.
        recoveryStateHarness.setTxRecoveryState(
            TxRecoveryState({
                recoveryAddress: TX_RECOVERY_ADDRESS,
                isEnabled: true,
                timelockDurationSeconds: TX_RECOVERY_TIMELOCK,
                pendingEnableTimestamp: block.timestamp + 1 hours,
                pendingInit: PendingRecoveryInitTimelock({
                    pendingRecoveryAddress: TX_RECOVERY_ADDRESS_B,
                    pendingTimelockDurationSeconds: TX_RECOVERY_TIMELOCK + 1 days,
                    pendingTimestamp: block.timestamp + 2 hours
                }),
                initAttemptId: 7
            })
        );
        recoveryStateHarness.setGuardianRecoveryState(
            GuardianRecoveryState({
                recoveryAddress: GUARDIAN_RECOVERY_ADDRESS,
                isUpdateReadyForAcceptance: true,
                pendingGuardian: NEW_GUARDIAN_A,
                timelockDurationSeconds: GUARDIAN_RECOVERY_TIMELOCK,
                pendingGuardianTimestamp: block.timestamp + 3 hours,
                pendingInit: PendingRecoveryInitTimelock({
                    pendingRecoveryAddress: GUARDIAN_RECOVERY_ADDRESS_B,
                    pendingTimelockDurationSeconds: GUARDIAN_RECOVERY_TIMELOCK + 1 days,
                    pendingTimestamp: block.timestamp + 4 hours
                }),
                initAttemptId: 9
            })
        );
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
        (AdminAuthParams memory auth,) = _buildClearRecoveryAuth({
            salt: 12_006,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call: expect one `TxRecoveryCleared` and one `GuardianRecoveryCleared` event with the prior recovery
        // addresses, then perform the clear.
        vm.expectEmit(true, true, true, true);
        emit IOrganizationTxRecovery.TxRecoveryCleared(TX_RECOVERY_ADDRESS);
        vm.expectEmit(true, true, true, true);
        emit IOrganizationGuardianRecovery.GuardianRecoveryCleared(GUARDIAN_RECOVERY_ADDRESS);
        vm.prank(GUARDIAN);
        harness.clearRecovery(auth);

        // Verify: every tx recovery field except the monotonic initAttemptId is reset to its zero value.
        TxRecoveryState memory txState = harness.getTxRecoveryState();
        assertEq(txState.recoveryAddress, address(0), "tx recovery address should clear");
        assertFalse(txState.isEnabled, "tx isEnabled should clear");
        assertEq(txState.timelockDurationSeconds, 0, "tx timelock duration should clear");
        assertEq(txState.pendingEnableTimestamp, 0, "tx pending enable timestamp should clear");
        assertEq(txState.pendingInit.pendingRecoveryAddress, address(0), "tx pending init address should clear");
        assertEq(txState.pendingInit.pendingTimelockDurationSeconds, 0, "tx pending init timelock should clear");
        assertEq(txState.pendingInit.pendingTimestamp, 0, "tx pending init timestamp should clear");

        // Verify: every guardian recovery field except the monotonic initAttemptId is reset.
        GuardianRecoveryState memory grState = harness.getGuardianRecoveryState();
        assertEq(grState.recoveryAddress, address(0), "guardian recovery address should clear");
        assertEq(grState.timelockDurationSeconds, 0, "guardian recovery timelock duration should clear");
        assertEq(grState.pendingGuardian, address(0), "pending guardian should clear");
        assertEq(grState.pendingGuardianTimestamp, 0, "pending guardian timestamp should clear");
        assertFalse(grState.isUpdateReadyForAcceptance, "ready-for-acceptance flag should clear");
        assertEq(grState.pendingInit.pendingRecoveryAddress, address(0), "guardian pending init address should clear");
        assertEq(grState.pendingInit.pendingTimelockDurationSeconds, 0, "guardian pending init timelock should clear");
        assertEq(grState.pendingInit.pendingTimestamp, 0, "guardian pending init timestamp should clear");
    }

    /// @dev Verifies that after a clear, both deferred-init flows can re-stage a pending initialization for a fresh
    /// recovery address. Exercises the clear -> re-initialize loop end to end for guardian recovery.
    function test_clearRecovery_thenReInitializeGuardianRecovery() public {
        // Setup: stage admin auth for the clear and a follow-up initiate-init payload bound to a fresh recovery
        // address with a different timelock duration.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
        (AdminAuthParams memory clearAuth,) = _buildClearRecoveryAuth({
            salt: 12_007,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        bytes memory reInitGuardianOpData = abi.encode(GUARDIAN_RECOVERY_ADDRESS_B, GUARDIAN_RECOVERY_TIMELOCK + 1 days);
        AdminAuthParams memory reInitGuardianAuth = _buildAdminAuthParamsForEoa({
            operationType: OperationType.InitiateInitializeGuardianRecovery,
            operationData: reInitGuardianOpData,
            isApproval: true,
            salt: 12_008,
            expirationTimestamp: block.timestamp + 1 days,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call: clear both tracks, then re-initiate a fresh guardian-recovery deferred init.
        vm.prank(GUARDIAN);
        harness.clearRecovery(clearAuth);
        vm.prank(GUARDIAN);
        harness.initiateInitializeGuardianRecovery(
            GUARDIAN_RECOVERY_ADDRESS_B, GUARDIAN_RECOVERY_TIMELOCK + 1 days, reInitGuardianAuth
        );

        // Verify: guardian recovery now has a fresh pending init tuple staged for the new recovery address.
        GuardianRecoveryState memory grState = harness.getGuardianRecoveryState();
        assertEq(
            grState.pendingInit.pendingRecoveryAddress,
            GUARDIAN_RECOVERY_ADDRESS_B,
            "guardian recovery pending init address should match the fresh deferred init"
        );
        assertEq(
            grState.pendingInit.pendingTimelockDurationSeconds,
            GUARDIAN_RECOVERY_TIMELOCK + 1 days,
            "guardian recovery pending init timelock should match the fresh deferred init"
        );
        assertEq(grState.recoveryAddress, address(0), "guardian recovery should still be unconfigured during pending");
    }

    /// @dev Verifies the race-the-attacker scenario: a compromised tx recovery key initiates the enable flow,
    /// admins call `clearRecovery` before the recovery timelock elapses, and the attacker's later `finalizeEnable...`
    /// call reverts because the recovery state has been fully wiped.
    function test_racesAttackerCallingInitiateEnable_clearWipesPendingEnable() public {
        // Setup: the compromised tx-recovery address calls `initiateEnable...`, staging `pendingEnableTimestamp`
        // in the future and starting the race window.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
        vm.prank(TX_RECOVERY_ADDRESS);
        harness.initiateEnableTransactionAndERC1271Recovery();
        uint256 pendingEnableBefore = harness.getTxRecoveryState().pendingEnableTimestamp;
        assertTrue(pendingEnableBefore > block.timestamp, "test sanity: pending enable must be staged in the future");

        // Call: admins clear recovery before the recovery timelock elapses.
        (AdminAuthParams memory clearAuth,) = _buildClearRecoveryAuth({
            salt: 12_009,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        vm.prank(GUARDIAN);
        harness.clearRecovery(clearAuth);

        // Verify: clear wipes the pending enable timestamp; warping past it does not let the attacker finalize because
        // the `onlyTxRecoveryAddress` modifier now compares against address(0).
        assertEq(
            harness.getTxRecoveryState().pendingEnableTimestamp,
            0,
            "clear must wipe the staged pending enable timestamp"
        );
        vm.warp(pendingEnableBefore + 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationTxRecovery.UnauthorizedTxRecoveryAddress.selector, TX_RECOVERY_ADDRESS, address(0)
            )
        );
        vm.prank(TX_RECOVERY_ADDRESS);
        harness.finalizeEnableTransactionAndERC1271Recovery();
    }

    /// @dev Verifies that clearing recovery is idempotent against an already-empty state. The clear must succeed
    /// even when there is nothing to clear, so admins can call it defensively without inspecting storage first.
    function test_clearRecovery_idempotentAgainstEmptyState() public {
        // Setup: wipe both tracks so every field is already zero.
        recoveryStateHarness.resetGuardianRecoveryStorage();
        recoveryStateHarness.setTxRecoveryState(
            TxRecoveryState({
                recoveryAddress: address(0),
                isEnabled: false,
                timelockDurationSeconds: 0,
                pendingEnableTimestamp: 0,
                pendingInit: PendingRecoveryInitTimelock({
                    pendingRecoveryAddress: address(0), pendingTimelockDurationSeconds: 0, pendingTimestamp: 0
                }),
                initAttemptId: 0
            })
        );
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
        (AdminAuthParams memory auth,) = _buildClearRecoveryAuth({
            salt: 12_010,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call: clear on already-empty state must still succeed and emit one event per track with a zero address.
        vm.expectEmit(true, true, true, true);
        emit IOrganizationTxRecovery.TxRecoveryCleared(address(0));
        vm.expectEmit(true, true, true, true);
        emit IOrganizationGuardianRecovery.GuardianRecoveryCleared(address(0));
        vm.prank(GUARDIAN);
        harness.clearRecovery(auth);

        // Verify: state remains empty, no spurious mutation.
        assertEq(harness.getTxRecoveryState().recoveryAddress, address(0), "tx recovery address should remain zero");
        assertEq(
            harness.getGuardianRecoveryState().recoveryAddress,
            address(0),
            "guardian recovery address should remain zero"
        );
    }

    /// @dev Verifies an expired admin auth payload is rejected before any state mutation.
    function test_expiredAuth_revertsAdminOperationExpired() public {
        // Setup: pin block.timestamp to a known absolute value, build auth that expires at that instant, then warp
        // one second past it. Using explicit absolute values avoids any evaluation-order ambiguity in the
        // expectRevert payload between `pastExpiration` and `block.timestamp`.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
        uint256 expirationAt = 1_000_000;
        vm.warp(expirationAt);
        (AdminAuthParams memory auth,) = _buildClearRecoveryAuth({
            salt: 12_011, expiration: expirationAt, isApproval: true, privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call: warp one second past the expiration and expect the dedicated expired-auth revert.
        uint256 nowAfter = expirationAt + 1;
        vm.warp(nowAfter);
        vm.expectRevert(
            abi.encodeWithSelector(IOrganizationAdmin.AdminOperationExpired.selector, expirationAt, nowAfter)
        );
        vm.prank(GUARDIAN);
        harness.clearRecovery(auth);

        // Verify: neither track is mutated by an expired-auth rejection.
        assertEq(
            harness.getGuardianRecoveryState().recoveryAddress,
            GUARDIAN_RECOVERY_ADDRESS,
            "guardian recovery address must remain configured"
        );
        assertEq(
            harness.getTxRecoveryState().recoveryAddress,
            TX_RECOVERY_ADDRESS,
            "tx recovery address must remain configured"
        );
    }

    /// @dev Verifies admin auth bound to a different OperationType is rejected.
    function test_wrongOperationType_revertsSignerIsNotAdmin() public {
        // Setup: build admin auth signed against a different OperationType so the recovered signer fails to match
        // any admin under the `ClearRecovery` hash.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
        AdminAuthParams memory wrongTypeAuth = _buildAdminAuthParamsForEoa({
            operationType: OperationType.ModifyAdmins,
            operationData: bytes(""),
            isApproval: true,
            salt: 12_012,
            expirationTimestamp: block.timestamp + 1 days,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call: guardian submits the mismatched auth and the signature recovery fails to find an admin signer.
        vm.expectPartialRevert(IOrganizationAdmin.SignerIsNotAdmin.selector);
        vm.prank(GUARDIAN);
        harness.clearRecovery(wrongTypeAuth);

        // Verify: state untouched.
        assertEq(
            harness.getTxRecoveryState().recoveryAddress,
            TX_RECOVERY_ADDRESS,
            "tx recovery address must remain configured"
        );
    }

    /// @dev Verifies `clearRecovery` zeros the underlying ERC-7201 namespaced storage slots for both recovery tracks
    /// when read directly via `vm.load`. Goes beyond the typed-getter assertions in the other tests by confirming the
    /// reset reaches all the way to raw EVM storage (no shadowed copies, no slot offset mistakes), and confirms the
    /// monotonic `initAttemptId` counters are preserved across the clear (they are not part of the reset by design).
    ///
    /// Slot layout (relative to `LibOrganizationRecoveryStorage.STORAGE_LOCATION`):
    ///  TxRecoveryState (7 slots):
    ///   - +0: recoveryAddress (20B) + isEnabled (1B) packed
    ///   - +1: timelockDurationSeconds
    ///   - +2: pendingEnableTimestamp
    ///   - +3: pendingInit.pendingRecoveryAddress
    ///   - +4: pendingInit.pendingTimelockDurationSeconds
    ///   - +5: pendingInit.pendingTimestamp
    ///   - +6: initAttemptId  (preserved across clear)
    ///  GuardianRecoveryState (8 slots, starts at +7):
    ///   - +7:  recoveryAddress (20B) + isUpdateReadyForAcceptance (1B) packed
    ///   - +8:  pendingGuardian
    ///   - +9:  timelockDurationSeconds
    ///   - +10: pendingGuardianTimestamp
    ///   - +11: pendingInit.pendingRecoveryAddress
    ///   - +12: pendingInit.pendingTimelockDurationSeconds
    ///   - +13: pendingInit.pendingTimestamp
    ///   - +14: initAttemptId  (preserved across clear)
    function test_clearRecovery_directStorageSlotsBeforeAndAfter() public {
        // Setup: seed every field on both tracks with a unique non-zero value, including the monotonic initAttemptIds,
        // so each slot has a recognizable "before" value and the "preserved" assertion on initAttemptId is meaningful.
        uint256 txInitAttemptId = 42;
        uint256 grInitAttemptId = 73;
        recoveryStateHarness.setTxRecoveryState(
            TxRecoveryState({
                recoveryAddress: TX_RECOVERY_ADDRESS,
                isEnabled: true,
                timelockDurationSeconds: TX_RECOVERY_TIMELOCK,
                pendingEnableTimestamp: block.timestamp + 1 hours,
                pendingInit: PendingRecoveryInitTimelock({
                    pendingRecoveryAddress: TX_RECOVERY_ADDRESS_B,
                    pendingTimelockDurationSeconds: TX_RECOVERY_TIMELOCK + 1 days,
                    pendingTimestamp: block.timestamp + 2 hours
                }),
                initAttemptId: txInitAttemptId
            })
        );
        recoveryStateHarness.setGuardianRecoveryState(
            GuardianRecoveryState({
                recoveryAddress: GUARDIAN_RECOVERY_ADDRESS,
                isUpdateReadyForAcceptance: true,
                pendingGuardian: NEW_GUARDIAN_A,
                timelockDurationSeconds: GUARDIAN_RECOVERY_TIMELOCK,
                pendingGuardianTimestamp: block.timestamp + 3 hours,
                pendingInit: PendingRecoveryInitTimelock({
                    pendingRecoveryAddress: GUARDIAN_RECOVERY_ADDRESS_B,
                    pendingTimelockDurationSeconds: GUARDIAN_RECOVERY_TIMELOCK + 1 days,
                    pendingTimestamp: block.timestamp + 4 hours
                }),
                initAttemptId: grInitAttemptId
            })
        );
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        bytes32 base = LibOrganizationRecoveryStorage.STORAGE_LOCATION;
        address harnessAddr = address(harness);

        // Read every slot of both recovery sub-structs before the clear and assert each is non-zero. Using vm.load
        // sidesteps the typed-getter path entirely so a getter-side bug could not mask a missed slot.
        bytes32[15] memory beforeSlots;
        for (uint256 i = 0; i < 15; i++) {
            beforeSlots[i] = vm.load(harnessAddr, bytes32(uint256(base) + i));
        }
        for (uint256 i = 0; i < 15; i++) {
            // initAttemptId slots are also non-zero (we seeded them), so the entire 15-slot window must be non-zero
            // now.
            assertTrue(beforeSlots[i] != bytes32(0), "every recovery storage slot should be non-zero before clear");
        }

        // Call: clear both tracks via the admin-gated entrypoint as guardian.
        (AdminAuthParams memory clearAuth,) = _buildClearRecoveryAuth({
            salt: 12_013,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        vm.prank(GUARDIAN);
        harness.clearRecovery(clearAuth);

        // Verify: every reset slot is now zero, and the two `initAttemptId` slots are preserved unchanged.
        // TxRecoveryState reset slots: 0..5 (slot 6 is initAttemptId).
        for (uint256 i = 0; i <= 5; i++) {
            assertEq(
                vm.load(harnessAddr, bytes32(uint256(base) + i)),
                bytes32(0),
                "TxRecovery reset slot should be zero after clear"
            );
        }
        // TxRecovery initAttemptId slot 6 is preserved.
        assertEq(
            vm.load(harnessAddr, bytes32(uint256(base) + 6)),
            bytes32(txInitAttemptId),
            "TxRecovery initAttemptId slot should be preserved across clear"
        );
        // GuardianRecoveryState reset slots: 7..13 (slot 14 is initAttemptId).
        for (uint256 i = 7; i <= 13; i++) {
            assertEq(
                vm.load(harnessAddr, bytes32(uint256(base) + i)),
                bytes32(0),
                "GuardianRecovery reset slot should be zero after clear"
            );
        }
        // GuardianRecovery initAttemptId slot 14 is preserved.
        assertEq(
            vm.load(harnessAddr, bytes32(uint256(base) + 14)),
            bytes32(grInitAttemptId),
            "GuardianRecovery initAttemptId slot should be preserved across clear"
        );
    }

    /// @dev Verifies the clear unlocks the deferred-init flow for both tracks. Before the clear, both
    /// `initiateInitializeTransactionAndERC1271Recovery` and `initiateInitializeGuardianRecovery` revert with the
    /// `AlreadyConfigured` guards (because both tracks are configured). After the clear, the exact same parameters
    /// succeed and a fresh pending-init tuple is staged on each track.
    function test_clearRecovery_unblocksDeferredInitOnBothTracks() public {
        // Setup: build the clear-auth payload and the two re-init payloads up front so the auth digests are bound
        // to the pre-clear state. Using a fresh recovery address per track makes the post-clear assertions distinct
        // from the seeded values.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
        (AdminAuthParams memory clearAuth,) = _buildClearRecoveryAuth({
            salt: 13_001,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        bytes memory txInitOpData = abi.encode(TX_RECOVERY_ADDRESS_B, TX_RECOVERY_TIMELOCK + 1 days);
        AdminAuthParams memory txInitAuth = _buildAdminAuthParamsForEoa({
            operationType: OperationType.InitiateInitializeTransactionRecovery,
            operationData: txInitOpData,
            isApproval: true,
            salt: 13_002,
            expirationTimestamp: block.timestamp + 1 days,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        bytes memory guardianInitOpData = abi.encode(GUARDIAN_RECOVERY_ADDRESS_B, GUARDIAN_RECOVERY_TIMELOCK + 1 days);
        AdminAuthParams memory guardianInitAuth = _buildAdminAuthParamsForEoa({
            operationType: OperationType.InitiateInitializeGuardianRecovery,
            operationData: guardianInitOpData,
            isApproval: true,
            salt: 13_003,
            expirationTimestamp: block.timestamp + 1 days,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call (BEFORE clear): tx initiate-init reverts because the track is already configured.
        vm.expectRevert(IOrganizationTxRecovery.TransactionRecoveryAlreadyConfigured.selector);
        vm.prank(GUARDIAN);
        harness.initiateInitializeTransactionAndERC1271Recovery(
            TX_RECOVERY_ADDRESS_B, TX_RECOVERY_TIMELOCK + 1 days, txInitAuth
        );

        // Call (BEFORE clear): guardian initiate-init reverts because the track is already configured.
        vm.expectRevert(IOrganizationGuardianRecovery.GuardianRecoveryAlreadyConfigured.selector);
        vm.prank(GUARDIAN);
        harness.initiateInitializeGuardianRecovery(
            GUARDIAN_RECOVERY_ADDRESS_B, GUARDIAN_RECOVERY_TIMELOCK + 1 days, guardianInitAuth
        );

        // Call: clear both tracks.
        vm.prank(GUARDIAN);
        harness.clearRecovery(clearAuth);

        // Call (AFTER clear): both initiate-inits now succeed and stage fresh pending-init tuples.
        vm.prank(GUARDIAN);
        harness.initiateInitializeTransactionAndERC1271Recovery(
            TX_RECOVERY_ADDRESS_B, TX_RECOVERY_TIMELOCK + 1 days, txInitAuth
        );
        vm.prank(GUARDIAN);
        harness.initiateInitializeGuardianRecovery(
            GUARDIAN_RECOVERY_ADDRESS_B, GUARDIAN_RECOVERY_TIMELOCK + 1 days, guardianInitAuth
        );

        // Verify: each track has a pending-init tuple matching the post-clear deferred-init parameters.
        TxRecoveryState memory txState = harness.getTxRecoveryState();
        assertEq(
            txState.pendingInit.pendingRecoveryAddress,
            TX_RECOVERY_ADDRESS_B,
            "tx recovery pending init address should match post-clear deferred init"
        );
        assertEq(
            txState.pendingInit.pendingTimelockDurationSeconds,
            TX_RECOVERY_TIMELOCK + 1 days,
            "tx recovery pending init timelock should match post-clear deferred init"
        );
        assertTrue(
            txState.pendingInit.pendingTimestamp > block.timestamp,
            "tx recovery pending init timestamp should be in the future"
        );
        assertEq(txState.recoveryAddress, address(0), "tx recovery should still be unconfigured during pending init");

        GuardianRecoveryState memory grState = harness.getGuardianRecoveryState();
        assertEq(
            grState.pendingInit.pendingRecoveryAddress,
            GUARDIAN_RECOVERY_ADDRESS_B,
            "guardian recovery pending init address should match post-clear deferred init"
        );
        assertEq(
            grState.pendingInit.pendingTimelockDurationSeconds,
            GUARDIAN_RECOVERY_TIMELOCK + 1 days,
            "guardian recovery pending init timelock should match post-clear deferred init"
        );
        assertTrue(
            grState.pendingInit.pendingTimestamp > block.timestamp,
            "guardian recovery pending init timestamp should be in the future"
        );
        assertEq(
            grState.recoveryAddress, address(0), "guardian recovery should still be unconfigured during pending init"
        );
    }

    /// @dev Verifies the tx recovery address loses every privileged capability after the clear. Before the clear
    /// `TX_RECOVERY_ADDRESS` is the configured recovery key and can initiate the enable flow. After the clear, the
    /// stored `recoveryAddress` is zero, so every `onlyTxRecoveryAddress`-gated call reverts when made by the
    /// previously-authorized key — including the disable path that does not even read the `isEnabled` flag.
    function test_clearRecovery_revokesTxRecoveryAddressCapabilities() public {
        // Setup: standard fixture has tx recovery configured with TX_RECOVERY_ADDRESS, isEnabled=false, no pending.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        // Call (BEFORE clear): TX_RECOVERY_ADDRESS can initiate the enable flow on its own track.
        vm.prank(TX_RECOVERY_ADDRESS);
        harness.initiateEnableTransactionAndERC1271Recovery();
        assertTrue(
            harness.getTxRecoveryState().pendingEnableTimestamp > block.timestamp,
            "pre-clear: TX_RECOVERY_ADDRESS should have staged a pending enable"
        );

        // Call: clear both tracks.
        (AdminAuthParams memory clearAuth,) = _buildClearRecoveryAuth({
            salt: 13_010,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        vm.prank(GUARDIAN);
        harness.clearRecovery(clearAuth);

        // Call (AFTER clear): every privileged tx-recovery entrypoint reverts when made by the formerly-authorized
        // key. The `onlyTxRecoveryAddress` modifier now compares msg.sender against address(0), so the (caller,
        // expected) revert payload reports (TX_RECOVERY_ADDRESS, address(0)).
        bytes memory expectedRevert = abi.encodeWithSelector(
            IOrganizationTxRecovery.UnauthorizedTxRecoveryAddress.selector, TX_RECOVERY_ADDRESS, address(0)
        );

        vm.expectRevert(expectedRevert);
        vm.prank(TX_RECOVERY_ADDRESS);
        harness.initiateEnableTransactionAndERC1271Recovery();

        vm.expectRevert(expectedRevert);
        vm.prank(TX_RECOVERY_ADDRESS);
        harness.finalizeEnableTransactionAndERC1271Recovery();

        vm.expectRevert(expectedRevert);
        vm.prank(TX_RECOVERY_ADDRESS);
        harness.cancelEnableTransactionAndERC1271Recovery();

        vm.expectRevert(expectedRevert);
        vm.prank(TX_RECOVERY_ADDRESS);
        harness.disableTransactionAndERC1271Recovery();

        vm.expectRevert(expectedRevert);
        vm.prank(TX_RECOVERY_ADDRESS);
        harness.executeRecoveryAccountTransaction(address(0xDEAD), address(0xBEEF), 0, bytes(""));

        // Verify: state remains cleared after the failed re-attempts.
        assertEq(
            harness.getTxRecoveryState().recoveryAddress,
            address(0),
            "tx recovery address should remain cleared after failed re-attempts"
        );
        assertEq(
            harness.getTxRecoveryState().pendingEnableTimestamp,
            0,
            "tx recovery pending enable should remain cleared after failed re-attempts"
        );
    }

    /// @dev Verifies the guardian recovery address loses every privileged capability after the clear. Before the
    /// clear `GUARDIAN_RECOVERY_ADDRESS` can drive the recovery guardian update flow. After the clear, the stored
    /// `recoveryAddress` is zero, so every `onlyGuardianRecoveryAddress`-gated call reverts when made by the
    /// previously-authorized key.
    function test_clearRecovery_revokesGuardianRecoveryAddressCapabilities() public {
        // Setup: standard fixture has guardian recovery configured with GUARDIAN_RECOVERY_ADDRESS, no pending.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        // Call (BEFORE clear): GUARDIAN_RECOVERY_ADDRESS can initiate a recovery guardian update.
        vm.prank(GUARDIAN_RECOVERY_ADDRESS);
        harness.initiateRecoveryGuardianUpdate(NEW_GUARDIAN_A);
        assertEq(
            harness.getGuardianRecoveryState().pendingGuardian,
            NEW_GUARDIAN_A,
            "pre-clear: GUARDIAN_RECOVERY_ADDRESS should have staged a pending recovery guardian update"
        );

        // Call: clear both tracks.
        (AdminAuthParams memory clearAuth,) = _buildClearRecoveryAuth({
            salt: 13_020,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        vm.prank(GUARDIAN);
        harness.clearRecovery(clearAuth);

        // Call (AFTER clear): every privileged guardian-recovery entrypoint reverts when made by the
        // formerly-authorized key. The `onlyGuardianRecoveryAddress` modifier now compares msg.sender against
        // address(0), so the (caller, expected) revert payload reports (GUARDIAN_RECOVERY_ADDRESS, address(0)).
        bytes memory expectedRevert = abi.encodeWithSelector(
            IOrganizationGuardianRecovery.UnauthorizedGuardianRecoveryAddress.selector,
            GUARDIAN_RECOVERY_ADDRESS,
            address(0)
        );

        vm.expectRevert(expectedRevert);
        vm.prank(GUARDIAN_RECOVERY_ADDRESS);
        harness.initiateRecoveryGuardianUpdate(NEW_GUARDIAN_A);

        vm.expectRevert(expectedRevert);
        vm.prank(GUARDIAN_RECOVERY_ADDRESS);
        harness.finalizeRecoveryGuardianUpdate();

        vm.expectRevert(expectedRevert);
        vm.prank(GUARDIAN_RECOVERY_ADDRESS);
        harness.cancelRecoveryGuardianUpdate();

        // Verify: state remains cleared after the failed re-attempts.
        assertEq(
            harness.getGuardianRecoveryState().recoveryAddress,
            address(0),
            "guardian recovery address should remain cleared after failed re-attempts"
        );
        assertEq(
            harness.getGuardianRecoveryState().pendingGuardian,
            address(0),
            "guardian recovery pending guardian should remain cleared after failed re-attempts"
        );
    }

    /// @dev End-to-end happy path with a realistic multi-admin threshold. Two EOA admins jointly sign a single
    /// `ClearRecovery` admin payload, the Guardian submits it, and we verify everything an off-chain operator would
    /// want to observe after a successful clear:
    ///   - both tracks are fully reset
    ///   - both distinct cleared-events fire (one per track)
    ///   - the derived nonce is consumed exactly once and the same auth cannot be replayed
    ///   - the post-clear state is immediately re-initializable (proves the validate-not-configured guard passes)
    /// Mirrors the multi-admin coverage that other *Base test suites have for their externally-callable functions.
    function test_endToEnd_multiAdminHappyPath() public {
        // Setup: pin block.timestamp to a clean baseline so all derived timestamps are deterministic. Configure two
        // EOA admins with a threshold of 2 so both signatures are required.
        vm.warp(1_000_000);
        _setMembersAndAdmins({members: buildArray(admin1, admin2), admins: buildArray(admin1, admin2), threshold: 2});
        recoveryStateHarness.setTxRecoveryState(
            TxRecoveryState({
                recoveryAddress: TX_RECOVERY_ADDRESS,
                isEnabled: true,
                timelockDurationSeconds: TX_RECOVERY_TIMELOCK,
                pendingEnableTimestamp: block.timestamp + 1 hours,
                pendingInit: PendingRecoveryInitTimelock({
                    pendingRecoveryAddress: address(0), pendingTimelockDurationSeconds: 0, pendingTimestamp: 0
                }),
                initAttemptId: 0
            })
        );
        recoveryStateHarness.setGuardianRecoveryState(
            GuardianRecoveryState({
                recoveryAddress: GUARDIAN_RECOVERY_ADDRESS,
                isUpdateReadyForAcceptance: false,
                pendingGuardian: NEW_GUARDIAN_A,
                timelockDurationSeconds: GUARDIAN_RECOVERY_TIMELOCK,
                pendingGuardianTimestamp: block.timestamp + 2 hours,
                pendingInit: PendingRecoveryInitTimelock({
                    pendingRecoveryAddress: address(0), pendingTimelockDurationSeconds: 0, pendingTimestamp: 0
                }),
                initAttemptId: 0
            })
        );

        // Setup: build the joint clear-auth signed by admin1 AND admin2, satisfying the threshold-of-2.
        (AdminAuthParams memory jointAuth, bytes memory operationData) = _buildClearRecoveryAuth({
            salt: 14_001,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1, ADMIN_PK_2)
        });
        uint256 expectedNonce = harness.computeNonce(OperationType.ClearRecovery, operationData, 14_001);
        assertFalse(harness.getUsedNonce(expectedNonce), "test sanity: nonce should not be used before the call");

        // Sanity: the same auth bundle is insufficient on a higher threshold. Bump threshold to 3 and confirm the
        // call reverts with `InsufficientAdminAuthorization`. This mirrors the pattern used by other *Base end-to-end
        // tests that prove threshold enforcement is binding rather than ornamental.
        stateHarness.setVotingThreshold(3);
        vm.expectRevert(IOrganizationAdmin.InsufficientAdminAuthorization.selector);
        vm.prank(GUARDIAN);
        harness.clearRecovery(jointAuth);
        stateHarness.setVotingThreshold(2);

        // Sanity: even with the right signatures, a non-Guardian caller cannot bypass the gate. Mirrors the
        // Guardian-protection coverage used across the *Base test suites.
        _expectOnlyGuardianRevert(NON_GUARDIAN);
        vm.prank(NON_GUARDIAN);
        harness.clearRecovery(jointAuth);

        // Call: Guardian submits the joint admin auth. Expect both cleared-events in order, then perform the call.
        vm.expectEmit(true, true, true, true);
        emit IOrganizationTxRecovery.TxRecoveryCleared(TX_RECOVERY_ADDRESS);
        vm.expectEmit(true, true, true, true);
        emit IOrganizationGuardianRecovery.GuardianRecoveryCleared(GUARDIAN_RECOVERY_ADDRESS);
        vm.prank(GUARDIAN);
        harness.clearRecovery(jointAuth);

        // Verify: nonce was consumed exactly once. A replay of the same auth must revert with `NonceAlreadyUsed`.
        assertTrue(harness.getUsedNonce(expectedNonce), "clear must consume the derived nonce");
        vm.expectRevert(abi.encodeWithSelector(IOrganizationSignatures.NonceAlreadyUsed.selector, expectedNonce));
        vm.prank(GUARDIAN);
        harness.clearRecovery(jointAuth);

        // Verify: both tracks are fully reset.
        TxRecoveryState memory txState = harness.getTxRecoveryState();
        assertEq(txState.recoveryAddress, address(0), "tx recovery address should clear");
        assertFalse(txState.isEnabled, "tx isEnabled should clear");
        assertEq(txState.timelockDurationSeconds, 0, "tx timelock duration should clear");
        assertEq(txState.pendingEnableTimestamp, 0, "tx pending enable timestamp should clear");
        GuardianRecoveryState memory grState = harness.getGuardianRecoveryState();
        assertEq(grState.recoveryAddress, address(0), "guardian recovery address should clear");
        assertEq(grState.timelockDurationSeconds, 0, "guardian recovery timelock duration should clear");
        assertEq(grState.pendingGuardian, address(0), "pending guardian should clear");
        assertEq(grState.pendingGuardianTimestamp, 0, "pending guardian timestamp should clear");

        // Verify: post-clear state is immediately re-initializable on the tx recovery track. Building a fresh joint
        // auth for `InitiateInitializeTransactionRecovery` and submitting it as Guardian must succeed and stage a
        // pending init tuple. Proves the clear leaves the state in the exact shape the deferred-init flow expects.
        bytes memory txInitOpData = abi.encode(TX_RECOVERY_ADDRESS_B, TX_RECOVERY_TIMELOCK + 1 days);
        AdminAuthParams memory txInitAuth = _buildAdminAuthParamsForEoa({
            operationType: OperationType.InitiateInitializeTransactionRecovery,
            operationData: txInitOpData,
            isApproval: true,
            salt: 14_002,
            expirationTimestamp: block.timestamp + 1 days,
            privateKeys: buildUint256Array(ADMIN_PK_1, ADMIN_PK_2)
        });
        vm.prank(GUARDIAN);
        harness.initiateInitializeTransactionAndERC1271Recovery(
            TX_RECOVERY_ADDRESS_B, TX_RECOVERY_TIMELOCK + 1 days, txInitAuth
        );
        assertEq(
            harness.getTxRecoveryState().pendingInit.pendingRecoveryAddress,
            TX_RECOVERY_ADDRESS_B,
            "post-clear tx re-init should stage the new recovery address"
        );
    }
}
