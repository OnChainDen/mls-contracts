// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganization} from "interfaces/IOrganization.sol";
import {IOrganizationAccountFactory} from "interfaces/organization/IOrganizationAccountFactory.sol";
import {IOrganizationAccountTransaction} from "interfaces/organization/IOrganizationAccountTransaction.sol";
import {IOrganizationAdmin} from "interfaces/organization/IOrganizationAdmin.sol";
import {IOrganizationGroups} from "interfaces/organization/IOrganizationGroups.sol";
import {IOrganizationGuardian} from "interfaces/organization/IOrganizationGuardian.sol";
import {IOrganizationGuardianRecovery} from "interfaces/organization/IOrganizationGuardianRecovery.sol";
import {IOrganizationInitialization} from "interfaces/organization/IOrganizationInitialization.sol";
import {IOrganizationMembers} from "interfaces/organization/IOrganizationMembers.sol";
import {IOrganizationPolicy} from "interfaces/organization/IOrganizationPolicy.sol";
import {IOrganizationTxRecovery} from "interfaces/organization/IOrganizationTxRecovery.sol";
import {
    OrganizationTxRecoveryBaseHarness
} from "test/organization/base/OrganizationTxRecoveryBase/OrganizationTxRecoveryBaseHarness.sol";
import {OrganizationAdminStateHarness} from "test/organization/shared/OrganizationAdminStateHarness.sol";
import {OrganizationAdminTestBase} from "test/organization/shared/OrganizationAdminTestBase.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";
import {OperationType} from "types/CommonTypes.sol";
import {PendingRecoveryInitTimelock, TxRecoveryState} from "types/RecoveryTypes.sol";

/**
 * @dev Shared deployment/auth/state helpers for `OrganizationTxRecoveryBase` suites.
 */
abstract contract OrganizationTxRecoveryBaseSuiteBase is OrganizationAdminTestBase {
    uint256 internal constant TX_RECOVERY_TIMELOCK = 2 days;
    uint256 internal constant ADMIN_OPERATION_TIMELOCK = 3 days;

    address internal constant TX_RECOVERY = address(0x71001);
    address internal constant ACCOUNT = address(0x71002);
    address internal constant DESTINATION = address(0x71003);

    OrganizationTxRecoveryBaseHarness internal harness;

    /**
     * @dev Deploys the base-contract-focused tx-recovery harness.
     */
    function _deployHarness() internal override returns (OrganizationAdminStateHarness) {
        harness = new OrganizationTxRecoveryBaseHarness();
        return OrganizationAdminStateHarness(address(harness));
    }

    /**
     * @dev Seeds deterministic admin/timelock/tx-recovery baseline state.
     */
    function setUp() public virtual override {
        super.setUp();

        harness.setAdminOperationTimelockDurationSeconds(ADMIN_OPERATION_TIMELOCK);
        _setMembersAndAdmins({members: buildArray(admin1, admin2), admins: buildArray(admin1, admin2), threshold: 1});
        _setTxRecoveryState({
            recoveryAddress: TX_RECOVERY,
            isEnabled: false,
            timelockDurationSeconds: TX_RECOVERY_TIMELOCK,
            pendingEnableTimestamp: 0,
            pendingRecoveryAddress: address(0),
            pendingTimelockDurationSeconds: 0,
            pendingTimestamp: 0
        });
    }

    /**
     * @dev Sets full tx-recovery storage state.
     */
    function _setTxRecoveryState(
        address recoveryAddress,
        bool isEnabled,
        uint256 timelockDurationSeconds,
        uint256 pendingEnableTimestamp,
        address pendingRecoveryAddress,
        uint256 pendingTimelockDurationSeconds,
        uint256 pendingTimestamp
    ) internal {
        harness.setTxRecoveryState(
            TxRecoveryState({
                recoveryAddress: recoveryAddress,
                isEnabled: isEnabled,
                timelockDurationSeconds: timelockDurationSeconds,
                pendingEnableTimestamp: pendingEnableTimestamp,
                pendingInit: PendingRecoveryInitTimelock({
                    pendingRecoveryAddress: pendingRecoveryAddress,
                    pendingTimelockDurationSeconds: pendingTimelockDurationSeconds,
                    pendingTimestamp: pendingTimestamp
                }),
                initAttemptId: 0
            })
        );
    }

    /**
     * @dev Builds auth payload for tx-recovery deferred-init operations.
     */
    function _buildTxRecoveryAuth(
        OperationType operationType,
        address recoveryAddress,
        uint256 timelockDurationSeconds,
        uint256 salt,
        bool isApproval,
        uint256[] memory privateKeys
    ) internal view returns (AdminAuthParams memory auth, bytes memory operationData) {
        // Finalize and cancel include the attempt ID to bind signatures to a specific initialization attempt
        if (
            operationType == OperationType.FinalizeInitializeTransactionRecovery
                || operationType == OperationType.CancelInitializeTransactionRecovery
        ) {
            operationData =
                abi.encode(recoveryAddress, timelockDurationSeconds, harness.getTxRecoveryState().initAttemptId);
        } else {
            operationData = abi.encode(recoveryAddress, timelockDurationSeconds);
        }
        auth = _buildAdminAuthParamsForEoa({
            operationType: operationType,
            operationData: operationData,
            isApproval: isApproval,
            salt: salt,
            expirationTimestamp: block.timestamp + 30 days,
            privateKeys: privateKeys
        });
    }

    /**
     * @dev Asserts `onlyTxRecoveryAddress` revert payload for a caller.
     */
    function _expectOnlyTxRecoveryRevert(address caller) internal {
        vm.expectRevert(
            abi.encodeWithSelector(IOrganizationTxRecovery.UnauthorizedTxRecoveryAddress.selector, caller, TX_RECOVERY)
        );
    }

    /**
     * @dev Asserts `onlyGuardian` revert payload for a caller.
     */
    function _expectOnlyGuardian(address caller) internal {
        vm.expectRevert(abi.encodeWithSelector(IOrganizationGuardian.UnauthorizedGuardian.selector, caller, GUARDIAN));
    }

    /**
     * @dev Enables tx recovery through initiate/finalize flow.
     */
    function _enableTxRecovery() internal {
        vm.prank(TX_RECOVERY);
        harness.initiateEnableTransactionAndERC1271Recovery();
        vm.warp(block.timestamp + TX_RECOVERY_TIMELOCK);
        vm.prank(TX_RECOVERY);
        harness.finalizeEnableTransactionAndERC1271Recovery();
    }

    /**
     * @dev Builds payloads for every state-changing (non-view) Organization function selector.
     *      Covers IOrganizationTxRecovery, IOrganizationAdmin, IOrganizationMembers, IOrganizationGroups,
     *      IOrganizationPolicy, IOrganizationGuardian, IOrganizationGuardianRecovery, IOrganizationAccountFactory,
     *      IOrganizationAccountTransaction, IOrganization, and IOrganizationInitialization.
     */
    function _buildOrganizationStateChangingPayloads(AdminAuthParams memory auth, address[] memory empty)
        internal
        view
        returns (bytes[] memory payloads)
    {
        payloads = new bytes[](30);

        // IOrganizationTxRecovery (8 selectors)
        payloads[0] = abi.encodeWithSelector(harness.initiateEnableTransactionAndERC1271Recovery.selector);
        payloads[1] = abi.encodeWithSelector(harness.finalizeEnableTransactionAndERC1271Recovery.selector);
        payloads[2] = abi.encodeWithSelector(harness.cancelEnableTransactionAndERC1271Recovery.selector);
        payloads[3] = abi.encodeWithSelector(harness.disableTransactionAndERC1271Recovery.selector);
        payloads[4] = abi.encodeWithSelector(
            harness.executeRecoveryAccountTransaction.selector, address(0), address(0), uint256(0), bytes("")
        );
        payloads[5] = abi.encodeWithSelector(
            harness.initiateInitializeTransactionAndERC1271Recovery.selector, address(0x1), 2 days, auth
        );
        // forgefmt: disable-next-item
        payloads[6] = abi.encodeWithSelector(
            harness.finalizeInitializeTransactionAndERC1271Recovery.selector, auth
        );
        // forgefmt: disable-next-item
        payloads[7] = abi.encodeWithSelector(
            harness.cancelInitializeTransactionAndERC1271Recovery.selector, auth
        );

        // IOrganizationAdmin (2 selectors)
        payloads[8] = abi.encodeWithSelector(IOrganizationAdmin.modifyAdmins.selector, empty, empty, uint256(1), auth);
        payloads[9] = abi.encodeWithSelector(
            IOrganizationAdmin.rejectAdminOperation.selector, OperationType.ModifyAdmins, bytes(""), auth
        );

        // IOrganizationMembers (1 selector)
        payloads[10] = abi.encodeWithSelector(IOrganizationMembers.modifyMembers.selector, empty, empty, auth);

        // IOrganizationGroups (1 selector) – selector-only; no GroupModification[] needed to trigger revert.
        payloads[11] = abi.encodeWithSelector(IOrganizationGroups.modifyGroups.selector);

        // IOrganizationPolicy (1 selector)
        payloads[12] = abi.encodeWithSelector(
            IOrganizationPolicy.setPolicies.selector, bytes32(uint256(0x1234)), "ipfs://sweep", auth
        );

        // IOrganizationGuardian (4 selectors)
        payloads[13] = abi.encodeWithSelector(IOrganizationGuardian.initiateGuardianUpdate.selector, address(0x1), auth);
        payloads[14] = abi.encodeWithSelector(IOrganizationGuardian.finalizeGuardianUpdate.selector, auth);
        payloads[15] = abi.encodeWithSelector(IOrganizationGuardian.cancelGuardianUpdate.selector, auth);
        payloads[16] = abi.encodeWithSelector(IOrganizationGuardian.acceptGuardian.selector);

        // IOrganizationGuardianRecovery (7 selectors)
        payloads[17] =
            abi.encodeWithSelector(IOrganizationGuardianRecovery.initiateRecoveryGuardianUpdate.selector, address(0x1));
        payloads[18] = abi.encodeWithSelector(IOrganizationGuardianRecovery.finalizeRecoveryGuardianUpdate.selector);
        payloads[19] = abi.encodeWithSelector(IOrganizationGuardianRecovery.cancelRecoveryGuardianUpdate.selector);
        payloads[20] = abi.encodeWithSelector(IOrganizationGuardianRecovery.acceptGuardianRecovery.selector);
        payloads[21] = abi.encodeWithSelector(
            IOrganizationGuardianRecovery.initiateInitializeGuardianRecovery.selector, address(0x1), 2 days, auth
        );
        payloads[22] =
            abi.encodeWithSelector(IOrganizationGuardianRecovery.finalizeInitializeGuardianRecovery.selector, auth);
        payloads[23] =
            abi.encodeWithSelector(IOrganizationGuardianRecovery.cancelInitializeGuardianRecovery.selector, auth);

        // IOrganizationAccountFactory (2 selectors)
        payloads[24] = abi.encodeWithSelector(IOrganizationAccountFactory.deployAccount.selector, bytes32(0), auth);
        payloads[25] =
            abi.encodeWithSelector(IOrganizationAccountFactory.setAccountImplementation.selector, address(0x1), auth);

        // IOrganizationAccountTransaction (2 selectors) – selector-only; ValidationProofs omitted.
        payloads[26] = abi.encodeWithSelector(IOrganizationAccountTransaction.executeAccountTransaction.selector);
        payloads[27] = abi.encodeWithSelector(IOrganizationAccountTransaction.rejectAccountTransaction.selector);

        // IOrganization (1 selector)
        payloads[28] = abi.encodeWithSelector(
            IOrganization.upgradeToAndCallWithAuthorization.selector, address(0x1), bytes(""), auth
        );

        // IOrganizationInitialization (1 selector) – selector-only; InitializationParams omitted.
        payloads[29] = abi.encodeWithSelector(IOrganizationInitialization.initialize.selector);
    }
}
