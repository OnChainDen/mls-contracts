// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";
import {IAccount} from "interfaces/IAccount.sol";
import {IOrganizationAdmin} from "interfaces/organization/IOrganizationAdmin.sol";
import {IOrganizationMembers} from "interfaces/organization/IOrganizationMembers.sol";
import {IOrganizationPolicy} from "interfaces/organization/IOrganizationPolicy.sol";
import {
    MockAccountForOrganizationTransaction
} from "test/organization/base/OrganizationAccountTransactionBase/OrganizationAccountTransactionBaseMocks.sol";
import {
    OrganizationTxRecoveryBaseHarness
} from "test/organization/base/OrganizationTxRecoveryBase/OrganizationTxRecoveryBaseHarness.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";
import {GuardianRecoveryState, TxRecoveryState} from "types/RecoveryTypes.sol";

contract TxRecoveryInvariantReceiver {
    uint256 public calls;
    address public lastCaller;
    uint256 public lastValue;
    bytes public lastData;

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
 * @dev Stateful mutation handler for `OrganizationTxRecoveryBase` invariant checks.
 *      Uses low-level calls so expected reverts do not terminate invariant campaigns.
 */
contract OrganizationTxRecoveryBaseInvariantHandler is Test {
    struct AccountSnapshot {
        uint256 executionCount;
        address lastTo;
        uint256 lastValue;
        bytes32 lastDataHash;
        uint256 lastNonce;
        uint256 lastPolicyId;
    }

    struct GlobalSnapshot {
        TxRecoveryState txRecovery;
        GuardianRecoveryState guardianRecovery;
        bool admin1IsAdmin;
        bool admin2IsAdmin;
        bool admin1IsMember;
        bool admin2IsMember;
        uint256 adminCount;
        uint256 votingThreshold;
        bytes32 policiesRoot;
        AccountSnapshot account;
    }

    enum OrganizationPayloadKind {
        Generic,
        ModifyAdmins,
        ModifyMembers,
        SetPolicies,
        TxRecoveryManagement
    }

    OrganizationTxRecoveryBaseHarness public immutable harness;
    MockAccountForOrganizationTransaction public immutable account;
    TxRecoveryInvariantReceiver public immutable receiver;
    address public immutable txRecoveryAddress;
    address public immutable trackedAdmin1;
    address public immutable trackedAdmin2;

    bool public unauthorizedTxRecoveryBypassViolation;
    bool public enabledBecameTrueOutsideFinalizeViolation;
    bool public enabledBecameFalseOutsideDisableViolation;
    bool public disableDidNotClearPendingEnableViolation;
    bool public executeMutatedTxRecoveryViolation;
    bool public modifyAdminsMutationViolation;
    bool public modifyMembersMutationViolation;
    bool public setPoliciesMutationViolation;
    bool public txRecoveryManagementMutationViolation;
    bool public reentrantOrganizationSuccessViolation;
    bool public reentrantAccountSuccessViolation;
    bool public reentrantStateDriftViolation;
    bool public guardianRecoveryMutationViolation;
    bool public successfulRecoveryExecutionUsedNonZeroTupleViolation;

    /**
     * @dev Initializes invariant handler dependencies and tracked principals.
     * @param harness_ Harness under invariant testing.
     * @param account_ Mock account used for recovery execution paths.
     * @param receiver_ Receiver target used for successful recovery calls.
     * @param txRecoveryAddress_ Authorized tx recovery caller address.
     * @param trackedAdmin1_ First admin address tracked in global snapshots.
     * @param trackedAdmin2_ Second admin address tracked in global snapshots.
     */
    constructor(
        OrganizationTxRecoveryBaseHarness harness_,
        MockAccountForOrganizationTransaction account_,
        TxRecoveryInvariantReceiver receiver_,
        address txRecoveryAddress_,
        address trackedAdmin1_,
        address trackedAdmin2_
    ) {
        harness = harness_;
        account = account_;
        receiver = receiver_;
        txRecoveryAddress = txRecoveryAddress_;
        trackedAdmin1 = trackedAdmin1_;
        trackedAdmin2 = trackedAdmin2_;
        IS_TEST = false;
    }

    /**
     * @dev Attempts one tx-recovery-protected entrypoint from a non-recovery caller.
     * @param rawSelector Fuzzed selector index used to choose the protected entrypoint.
     * @param seed Fuzz seed used to derive a non-recovery caller address.
     */
    function attemptUnauthorizedTxRecoveryEntrypoint(uint8 rawSelector, uint256 seed) external {
        uint8 selectorIndex = uint8(bound(rawSelector, 0, 4));
        address caller = _unauthorizedCaller(seed);
        bytes memory payload;

        if (selectorIndex == 0) {
            payload = abi.encodeWithSelector(harness.initiateEnableTransactionAndERC1271Recovery.selector);
        } else if (selectorIndex == 1) {
            payload = abi.encodeWithSelector(harness.finalizeEnableTransactionAndERC1271Recovery.selector);
        } else if (selectorIndex == 2) {
            payload = abi.encodeWithSelector(harness.cancelEnableTransactionAndERC1271Recovery.selector);
        } else if (selectorIndex == 3) {
            payload = abi.encodeWithSelector(harness.disableTransactionAndERC1271Recovery.selector);
        } else {
            payload = abi.encodeWithSelector(
                harness.executeRecoveryAccountTransaction.selector, address(account), address(receiver), 0, bytes("")
            );
        }

        bool success = _callWithSender(caller, payload);
        if (success) {
            unauthorizedTxRecoveryBypassViolation = true;
        }
    }

    /**
     * @dev Attempts initiate-enable as the tx recovery address.
     */
    function initiateEnable() external {
        _callWithSender(
            txRecoveryAddress, abi.encodeWithSelector(harness.initiateEnableTransactionAndERC1271Recovery.selector)
        );
    }

    /**
     * @dev Attempts finalize-enable as the tx recovery address.
     * @param warpToPendingTimestamp Whether to warp to pending-enable timestamp before finalize attempt.
     */
    function finalizeEnable(bool warpToPendingTimestamp) external {
        if (warpToPendingTimestamp) {
            uint256 pendingTimestamp = harness.getTxRecoveryState().pendingEnableTimestamp;
            if (pendingTimestamp != 0 && block.timestamp < pendingTimestamp) {
                vm.warp(pendingTimestamp);
            }
        }
        _callWithSender(
            txRecoveryAddress, abi.encodeWithSelector(harness.finalizeEnableTransactionAndERC1271Recovery.selector)
        );
    }

    /**
     * @dev Attempts cancel-enable as the tx recovery address.
     */
    function cancelEnable() external {
        _callWithSender(
            txRecoveryAddress, abi.encodeWithSelector(harness.cancelEnableTransactionAndERC1271Recovery.selector)
        );
    }

    /**
     * @dev Attempts disable as the tx recovery address.
     */
    function disableRecovery() external {
        _callWithSender(
            txRecoveryAddress, abi.encodeWithSelector(harness.disableTransactionAndERC1271Recovery.selector)
        );
    }

    /**
     * @dev Executes a successful recovery transaction against a mutable receiver target.
     * @param seed Fuzz seed encoded into forwarded calldata.
     * @param rawValue Fuzzed value bounded to the funded account balance.
     */
    function executeRecoveryToReceiver(uint256 seed, uint96 rawValue) external {
        _ensureRecoveryEnabled();
        uint256 value = bound(uint256(rawValue), 0, 1 ether);
        vm.deal(address(account), value);
        _executeRecovery(address(receiver), value, abi.encode(seed));
    }

    /**
     * @dev Attempts recovery -> account -> organization `modifyAdmins`.
     * @param seed Fuzz seed used to build dummy admin auth params.
     */
    function attemptModifyAdminsReentrant(uint256 seed) external {
        address[] memory empty = new address[](0);
        bytes memory payload = abi.encodeWithSelector(
            IOrganizationAdmin.modifyAdmins.selector, empty, empty, uint256(1), _dummyAuth(seed)
        );
        _attemptOrganizationPayload(payload, OrganizationPayloadKind.ModifyAdmins);
    }

    /**
     * @dev Attempts recovery -> account -> organization `modifyMembers`.
     * @param seed Fuzz seed used to build dummy admin auth params.
     */
    function attemptModifyMembersReentrant(uint256 seed) external {
        address[] memory empty = new address[](0);
        bytes memory payload =
            abi.encodeWithSelector(IOrganizationMembers.modifyMembers.selector, empty, empty, _dummyAuth(seed));
        _attemptOrganizationPayload(payload, OrganizationPayloadKind.ModifyMembers);
    }

    /**
     * @dev Attempts recovery -> account -> organization `setPolicies`.
     * @param seed Fuzz seed used for policy-root payload and dummy auth params.
     */
    function attemptSetPoliciesReentrant(uint256 seed) external {
        bytes memory payload = abi.encodeWithSelector(
            IOrganizationPolicy.setPolicies.selector, bytes32(seed), "ipfs://txr-invariant", _dummyAuth(seed)
        );
        _attemptOrganizationPayload(payload, OrganizationPayloadKind.SetPolicies);
    }

    /**
     * @dev Attempts recovery -> account -> organization tx-recovery management selectors.
     * @param rawSelector Fuzzed selector index used to choose management entrypoint.
     */
    function attemptTxRecoveryManagementReentrant(uint8 rawSelector) external {
        uint8 selectorIndex = uint8(bound(rawSelector, 0, 3));
        bytes memory payload;
        if (selectorIndex == 0) {
            payload = abi.encodeWithSelector(harness.initiateEnableTransactionAndERC1271Recovery.selector);
        } else if (selectorIndex == 1) {
            payload = abi.encodeWithSelector(harness.finalizeEnableTransactionAndERC1271Recovery.selector);
        } else if (selectorIndex == 2) {
            payload = abi.encodeWithSelector(harness.cancelEnableTransactionAndERC1271Recovery.selector);
        } else {
            payload = abi.encodeWithSelector(harness.disableTransactionAndERC1271Recovery.selector);
        }
        _attemptOrganizationPayload(payload, OrganizationPayloadKind.TxRecoveryManagement);
    }

    /**
     * @dev Attempts one selector from a broader organization state-changing selector set via recovery call-chaining.
     * @param rawSelector Fuzzed selector index used to choose target payload.
     * @param seed Fuzz seed used for payload arguments and dummy auth params.
     */
    function attemptOrganizationStateChangingSelector(uint8 rawSelector, uint256 seed) external {
        uint8 selectorIndex = uint8(bound(rawSelector, 0, 9));
        bytes memory payload;
        OrganizationPayloadKind kind = OrganizationPayloadKind.Generic;

        // Build a compact selector matrix that spans tx-recovery, admin, member, policy, and deferred-init paths.
        if (selectorIndex == 0) {
            payload = abi.encodeWithSelector(harness.initiateEnableTransactionAndERC1271Recovery.selector);
            kind = OrganizationPayloadKind.TxRecoveryManagement;
        } else if (selectorIndex == 1) {
            payload = abi.encodeWithSelector(harness.finalizeEnableTransactionAndERC1271Recovery.selector);
            kind = OrganizationPayloadKind.TxRecoveryManagement;
        } else if (selectorIndex == 2) {
            payload = abi.encodeWithSelector(harness.cancelEnableTransactionAndERC1271Recovery.selector);
            kind = OrganizationPayloadKind.TxRecoveryManagement;
        } else if (selectorIndex == 3) {
            payload = abi.encodeWithSelector(harness.disableTransactionAndERC1271Recovery.selector);
            kind = OrganizationPayloadKind.TxRecoveryManagement;
        } else if (selectorIndex == 4) {
            address[] memory emptyAdmins = new address[](0);
            payload = abi.encodeWithSelector(
                IOrganizationAdmin.modifyAdmins.selector, emptyAdmins, emptyAdmins, uint256(1), _dummyAuth(seed)
            );
            kind = OrganizationPayloadKind.ModifyAdmins;
        } else if (selectorIndex == 5) {
            address[] memory emptyMembers = new address[](0);
            payload = abi.encodeWithSelector(
                IOrganizationMembers.modifyMembers.selector, emptyMembers, emptyMembers, _dummyAuth(seed)
            );
            kind = OrganizationPayloadKind.ModifyMembers;
        } else if (selectorIndex == 6) {
            payload = abi.encodeWithSelector(
                IOrganizationPolicy.setPolicies.selector, bytes32(seed), "ipfs://txr-selector", _dummyAuth(seed)
            );
            kind = OrganizationPayloadKind.SetPolicies;
        } else if (selectorIndex == 7) {
            payload = abi.encodeWithSelector(
                harness.initiateInitializeTransactionAndERC1271Recovery.selector,
                // forge-lint: disable-next-line(unsafe-typecast)
                address(uint160(seed) | 1),
                2 days,
                _dummyAuth(seed)
            );
        } else if (selectorIndex == 8) {
            payload = abi.encodeWithSelector(
                harness.finalizeInitializeTransactionAndERC1271Recovery.selector, _dummyAuth(seed)
            );
        } else {
            payload = abi.encodeWithSelector(
                harness.cancelInitializeTransactionAndERC1271Recovery.selector, _dummyAuth(seed)
            );
        }

        _attemptOrganizationPayload(payload, kind);
    }

    /**
     * @dev Attempts `executeTransaction` reentrancy through `to=account` via recovery execution.
     * @param nestedTo Nested account-call destination used in reentrant payload.
     * @param rawNestedValue Fuzzed nested value bounded before encoding payload.
     * @param nonce Nested nonce argument forwarded into account payload.
     * @param policyId Nested policyId argument forwarded into account payload.
     * @param seed Fuzz seed encoded into nested calldata.
     */
    function attemptAccountStateChangingSelector(
        address nestedTo,
        uint96 rawNestedValue,
        uint256 nonce,
        uint256 policyId,
        uint256 seed
    ) external {
        _ensureRecoveryEnabled();
        GlobalSnapshot memory before = _snapshotGlobal();

        bytes memory payload = abi.encodeWithSelector(
            IAccount.executeTransaction.selector,
            nestedTo,
            bound(uint256(rawNestedValue), 0, 1 ether),
            abi.encode(seed),
            nonce,
            policyId
        );

        bool success = _executeRecovery(address(account), 0, payload);
        GlobalSnapshot memory afterSnapshot = _snapshotGlobal();

        if (success) {
            reentrantAccountSuccessViolation = true;
        }
        if (!_sameGlobalSnapshot(before, afterSnapshot)) {
            reentrantStateDriftViolation = true;
        }
    }

    /**
     * @dev Advances time to exercise timelock boundary transitions.
     * @param delta Fuzzed time delta bounded to a 30-day forward warp.
     */
    function warpForward(uint256 delta) external {
        vm.warp(block.timestamp + bound(delta, 0, 30 days));
    }

    /**
     * @dev Executes a recovery->account->organization payload and records invariant-specific mutation flags.
     * @param payload Encoded organization call attempted through recovery execution.
     * @param kind Payload classification used for targeted mutation checks.
     */
    function _attemptOrganizationPayload(bytes memory payload, OrganizationPayloadKind kind) internal {
        // All organization-targeted attempts must run through enabled recovery execution.
        _ensureRecoveryEnabled();
        GlobalSnapshot memory before = _snapshotGlobal();

        // Execute the chain and snapshot post-state to detect any drift across organization/account/recovery domains.
        bool success = _executeRecovery(address(harness), 0, payload);
        GlobalSnapshot memory afterSnapshot = _snapshotGlobal();

        if (success) {
            reentrantOrganizationSuccessViolation = true;
        }
        if (!_sameGlobalSnapshot(before, afterSnapshot)) {
            reentrantStateDriftViolation = true;
        }

        // Track per-operation invariants with narrow field checks in addition to full snapshot equality.
        if (
            kind == OrganizationPayloadKind.ModifyAdmins
                && (before.admin1IsAdmin != afterSnapshot.admin1IsAdmin
                    || before.admin2IsAdmin != afterSnapshot.admin2IsAdmin
                    || before.adminCount != afterSnapshot.adminCount
                    || before.votingThreshold != afterSnapshot.votingThreshold)
        ) {
            modifyAdminsMutationViolation = true;
        }

        if (
            kind == OrganizationPayloadKind.ModifyMembers
                && (before.admin1IsMember != afterSnapshot.admin1IsMember
                    || before.admin2IsMember != afterSnapshot.admin2IsMember
                    || before.admin1IsAdmin != afterSnapshot.admin1IsAdmin
                    || before.admin2IsAdmin != afterSnapshot.admin2IsAdmin)
        ) {
            modifyMembersMutationViolation = true;
        }

        if (kind == OrganizationPayloadKind.SetPolicies && before.policiesRoot != afterSnapshot.policiesRoot) {
            setPoliciesMutationViolation = true;
        }

        if (
            kind == OrganizationPayloadKind.TxRecoveryManagement
                && !_sameTxState(before.txRecovery, afterSnapshot.txRecovery)
        ) {
            txRecoveryManagementMutationViolation = true;
        }
    }

    /**
     * @dev Executes `executeRecoveryAccountTransaction` and tracks tx-recovery and tuple invariants.
     * @param to Destination forwarded to account execution.
     * @param value ETH value forwarded to account execution.
     * @param data Calldata forwarded to account execution.
     * @return success True when the outer recovery entrypoint call succeeded.
     */
    function _executeRecovery(address to, uint256 value, bytes memory data) internal returns (bool success) {
        // Recovery execution should never mutate tx-recovery configuration or pending state.
        TxRecoveryState memory before = harness.getTxRecoveryState();

        success = _callWithSender(
            txRecoveryAddress,
            abi.encodeWithSelector(
                harness.executeRecoveryAccountTransaction.selector, address(account), to, value, data
            )
        );

        TxRecoveryState memory afterState = harness.getTxRecoveryState();
        if (!_sameTxState(before, afterState)) {
            executeMutatedTxRecoveryViolation = true;
        }

        // Successful recovery execution must always force nonce=0 and policyId=0.
        if (success && (account.lastNonce() != 0 || account.lastPolicyId() != 0)) {
            successfulRecoveryExecutionUsedNonZeroTupleViolation = true;
        }
    }

    /**
     * @dev Ensures tx recovery is enabled by driving initiate/finalize steps when required.
     */
    function _ensureRecoveryEnabled() internal {
        TxRecoveryState memory state = harness.getTxRecoveryState();
        if (state.isEnabled) {
            return;
        }

        // If no pending enable exists, initiate one first.
        if (state.pendingEnableTimestamp == 0) {
            _callWithSender(
                txRecoveryAddress, abi.encodeWithSelector(harness.initiateEnableTransactionAndERC1271Recovery.selector)
            );
            state = harness.getTxRecoveryState();
        }

        // If enable is pending, warp to timelock and attempt finalize.
        if (!state.isEnabled && state.pendingEnableTimestamp != 0) {
            if (block.timestamp < state.pendingEnableTimestamp) {
                vm.warp(state.pendingEnableTimestamp);
            }
            _callWithSender(
                txRecoveryAddress, abi.encodeWithSelector(harness.finalizeEnableTransactionAndERC1271Recovery.selector)
            );
        }
    }

    /**
     * @dev Executes a low-level harness call as `sender` and tracks transition/isolation invariants.
     * @param sender Caller address impersonated for the call.
     * @param callData ABI-encoded call data sent to the harness.
     * @return success True when the harness call succeeded.
     */
    function _callWithSender(address sender, bytes memory callData) internal returns (bool success) {
        // Capture selector plus pre-state snapshots for transition and isolation checks.
        bytes4 selector = _selector(callData);
        TxRecoveryState memory beforeTxRecovery = harness.getTxRecoveryState();
        GuardianRecoveryState memory beforeGuardianRecovery = harness.getGuardianRecoveryState();

        // Use low-level call so expected reverts do not abort invariant campaigns.
        vm.prank(sender);
        (success,) = address(harness).call(callData);

        TxRecoveryState memory afterTxRecovery = harness.getTxRecoveryState();
        GuardianRecoveryState memory afterGuardianRecovery = harness.getGuardianRecoveryState();

        // Validate enable/disable transition direction rules across the observed state delta.
        _trackEnableTransitions(beforeTxRecovery, afterTxRecovery, selector, success);

        // Successful disable must clear pending enable in the same state transition.
        if (
            selector == harness.disableTransactionAndERC1271Recovery.selector && success
                && afterTxRecovery.pendingEnableTimestamp != 0
        ) {
            disableDidNotClearPendingEnableViolation = true;
        }

        // Tx-recovery operations must never mutate guardian-recovery state.
        if (!_sameGuardianState(beforeGuardianRecovery, afterGuardianRecovery)) {
            guardianRecoveryMutationViolation = true;
        }
    }

    /**
     * @dev Tracks invalid `isEnabled` direction changes relative to the executed selector.
     * @param beforeState Tx-recovery state snapshot before call execution.
     * @param afterState Tx-recovery state snapshot after call execution.
     * @param selector Selector executed on the harness.
     * @param success Whether the call succeeded.
     */
    function _trackEnableTransitions(
        TxRecoveryState memory beforeState,
        TxRecoveryState memory afterState,
        bytes4 selector,
        bool success
    ) internal {
        if (
            !beforeState.isEnabled && afterState.isEnabled
                && !(success && selector == harness.finalizeEnableTransactionAndERC1271Recovery.selector)
        ) {
            enabledBecameTrueOutsideFinalizeViolation = true;
        }

        if (
            beforeState.isEnabled && !afterState.isEnabled
                && !(success && selector == harness.disableTransactionAndERC1271Recovery.selector)
        ) {
            enabledBecameFalseOutsideDisableViolation = true;
        }
    }

    /**
     * @dev Captures a full organization/account snapshot for reentrancy drift checks.
     * @return snapshot Current global snapshot.
     */
    function _snapshotGlobal() internal view returns (GlobalSnapshot memory snapshot) {
        snapshot.txRecovery = harness.getTxRecoveryState();
        snapshot.guardianRecovery = harness.getGuardianRecoveryState();
        snapshot.admin1IsAdmin = harness.getAdminStatus(trackedAdmin1);
        snapshot.admin2IsAdmin = harness.getAdminStatus(trackedAdmin2);
        snapshot.admin1IsMember = harness.getMemberStatus(trackedAdmin1);
        snapshot.admin2IsMember = harness.getMemberStatus(trackedAdmin2);
        snapshot.adminCount = harness.getAdminCount();
        snapshot.votingThreshold = harness.getVotingThreshold();
        snapshot.policiesRoot = harness.getPoliciesRoot();
        snapshot.account = _snapshotAccount();
    }

    /**
     * @dev Captures account execution-facing fields used by invariant snapshot comparisons.
     * @return snapshot Current account snapshot.
     */
    function _snapshotAccount() internal view returns (AccountSnapshot memory snapshot) {
        snapshot.executionCount = account.executionCount();
        snapshot.lastTo = account.lastTo();
        snapshot.lastValue = account.lastValue();
        snapshot.lastDataHash = keccak256(account.lastData());
        snapshot.lastNonce = account.lastNonce();
        snapshot.lastPolicyId = account.lastPolicyId();
    }

    /**
     * @dev Compares two global snapshots for exact equality.
     * @param a First global snapshot.
     * @param b Second global snapshot.
     * @return isSame True when all tracked global fields are equal.
     */
    function _sameGlobalSnapshot(GlobalSnapshot memory a, GlobalSnapshot memory b) internal pure returns (bool isSame) {
        return _sameTxState(a.txRecovery, b.txRecovery) && _sameGuardianState(a.guardianRecovery, b.guardianRecovery)
            && a.admin1IsAdmin == b.admin1IsAdmin && a.admin2IsAdmin == b.admin2IsAdmin
            && a.admin1IsMember == b.admin1IsMember && a.admin2IsMember == b.admin2IsMember
            && a.adminCount == b.adminCount && a.votingThreshold == b.votingThreshold
            && a.policiesRoot == b.policiesRoot && _sameAccountSnapshot(a.account, b.account);
    }

    /**
     * @dev Compares two account snapshots for exact equality.
     * @param a First account snapshot.
     * @param b Second account snapshot.
     * @return isSame True when all tracked account fields are equal.
     */
    function _sameAccountSnapshot(AccountSnapshot memory a, AccountSnapshot memory b)
        internal
        pure
        returns (bool isSame)
    {
        return a.executionCount == b.executionCount && a.lastTo == b.lastTo && a.lastValue == b.lastValue
            && a.lastDataHash == b.lastDataHash && a.lastNonce == b.lastNonce && a.lastPolicyId == b.lastPolicyId;
    }

    /**
     * @dev Compares two tx-recovery states for exact equality.
     * @param a First tx-recovery snapshot.
     * @param b Second tx-recovery snapshot.
     * @return isSame True when all tx-recovery fields are equal.
     */
    function _sameTxState(TxRecoveryState memory a, TxRecoveryState memory b) internal pure returns (bool isSame) {
        return a.recoveryAddress == b.recoveryAddress && a.isEnabled == b.isEnabled
            && a.timelockDurationSeconds == b.timelockDurationSeconds
            && a.pendingEnableTimestamp == b.pendingEnableTimestamp
            && a.pendingInit.pendingRecoveryAddress == b.pendingInit.pendingRecoveryAddress
            && a.pendingInit.pendingTimelockDurationSeconds == b.pendingInit.pendingTimelockDurationSeconds
            && a.pendingInit.pendingTimestamp == b.pendingInit.pendingTimestamp;
    }

    /**
     * @dev Compares two guardian-recovery states for exact equality.
     * @param a First guardian-recovery snapshot.
     * @param b Second guardian-recovery snapshot.
     * @return isSame True when all guardian-recovery fields are equal.
     */
    function _sameGuardianState(GuardianRecoveryState memory a, GuardianRecoveryState memory b)
        internal
        pure
        returns (bool isSame)
    {
        return a.recoveryAddress == b.recoveryAddress && a.isUpdateReadyForAcceptance == b.isUpdateReadyForAcceptance
            && a.pendingGuardian == b.pendingGuardian && a.timelockDurationSeconds == b.timelockDurationSeconds
            && a.pendingGuardianTimestamp == b.pendingGuardianTimestamp
            && a.pendingInit.pendingRecoveryAddress == b.pendingInit.pendingRecoveryAddress
            && a.pendingInit.pendingTimelockDurationSeconds == b.pendingInit.pendingTimelockDurationSeconds
            && a.pendingInit.pendingTimestamp == b.pendingInit.pendingTimestamp;
    }

    /**
     * @dev Builds deterministic dummy admin auth params for negative-path reentrancy payloads.
     * @param seed Salt used for nonce-domain diversification.
     * @return auth Synthetic admin auth params used only for invariant mutation attempts.
     */
    function _dummyAuth(uint256 seed) internal view returns (AdminAuthParams memory auth) {
        return AdminAuthParams({salt: seed, expirationTimestamp: block.timestamp + 1 days, signatures: hex"01"});
    }

    /**
     * @dev Derives a non-zero caller address guaranteed to differ from configured tx recovery address.
     * @param seed Fuzz seed used in caller derivation.
     * @return caller Unauthorized caller candidate.
     */
    function _unauthorizedCaller(uint256 seed) internal view returns (address caller) {
        address expected = harness.getTxRecoveryState().recoveryAddress;
        // Use a deterministic hash-derived address and patch edge cases where it equals expected/zero.
        caller = address(uint160(uint256(keccak256(abi.encode(seed, block.timestamp))) | 1));
        if (caller == expected) {
            caller = address(uint160(caller) + 2);
            if (caller == expected || caller == address(0)) {
                caller = address(0xCAFE);
            }
        }
    }

    /**
     * @dev Extracts the first four bytes of ABI-encoded call data as a selector.
     * @param data ABI-encoded call data.
     * @return selector Function selector, or `bytes4(0)` for short payloads.
     */
    function _selector(bytes memory data) internal pure returns (bytes4 selector) {
        if (data.length < 4) {
            return bytes4(0);
        }
        // Load the first 32-byte word and truncate to the leading 4-byte selector.
        assembly {
            selector := mload(add(data, 32))
        }
    }
}
