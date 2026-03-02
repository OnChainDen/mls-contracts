// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationGuardian} from "interfaces/organization/IOrganizationGuardian.sol";
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
                })
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
        operationData = abi.encode(recoveryAddress, timelockDurationSeconds);
        auth = _buildAdminAuthParamsForEOA({
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
}
