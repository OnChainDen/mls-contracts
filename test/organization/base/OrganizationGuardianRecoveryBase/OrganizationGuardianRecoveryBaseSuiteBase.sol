// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationGuardianRecovery} from "interfaces/organization/IOrganizationGuardianRecovery.sol";
import {
    OrganizationGuardianRecoveryBaseHarness
} from "test/organization/base/OrganizationGuardianRecoveryBase/OrganizationGuardianRecoveryBaseHarness.sol";
import {OrganizationAdminStateHarness} from "test/organization/shared/OrganizationAdminStateHarness.sol";
import {OrganizationAdminTestBase} from "test/organization/shared/OrganizationAdminTestBase.sol";
import {
    OrganizationGuardianRecoveryStateHarness
} from "test/organization/shared/OrganizationGuardianRecoveryStateHarness.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";
import {OperationType} from "types/CommonTypes.sol";

/**
 * @dev Shared deployment/auth-builder helpers for `OrganizationGuardianRecoveryBase` suites.
 */
abstract contract OrganizationGuardianRecoveryBaseSuiteBase is OrganizationAdminTestBase {
    /// @dev Default admin-operation timelock used by deferred-init flows.
    uint256 internal constant ADMIN_OPERATION_TIMELOCK = 2 days;

    /// @dev Default guardian-recovery timelock used by recovery-update flow.
    uint256 internal constant GUARDIAN_RECOVERY_TIMELOCK = 2 days;

    /// @dev Deterministic guardian-recovery admin address fixture.
    address internal constant GUARDIAN_RECOVERY_ADDRESS = address(0xAA11);

    /// @dev Deterministic alternate recovery address fixture.
    address internal constant GUARDIAN_RECOVERY_ADDRESS_B = address(0xAA12);

    /// @dev Deterministic proposed guardian fixtures.
    address internal constant NEW_GUARDIAN_A = address(0xAB11);
    address internal constant NEW_GUARDIAN_B = address(0xAB12);

    /// @dev Concrete harness used by all base-contract-focused section suites.
    OrganizationGuardianRecoveryBaseHarness internal harness;

    /// @dev Typed shared-state surface for recovery/guardian/admin storage helpers.
    OrganizationGuardianRecoveryStateHarness internal recoveryStateHarness;

    /**
     * @dev Deploys the base-contract-focused harness for section suites.
     */
    function _deployHarness() internal override returns (OrganizationAdminStateHarness) {
        harness = new OrganizationGuardianRecoveryBaseHarness();
        return OrganizationAdminStateHarness(address(harness));
    }

    /**
     * @dev Seeds baseline admin timelock and guardian-recovery config used by non-deferred-init tests.
     */
    function setUp() public virtual override {
        super.setUp();
        recoveryStateHarness = OrganizationGuardianRecoveryStateHarness(address(harness));
        recoveryStateHarness.setAdminOperationTimelockDurationSeconds(ADMIN_OPERATION_TIMELOCK);
        recoveryStateHarness.setGuardianRecoveryConfig(GUARDIAN_RECOVERY_ADDRESS, GUARDIAN_RECOVERY_TIMELOCK);
    }

    /**
     * @dev Builds auth for `initiateInitializeGuardianRecovery`.
     */
    function _buildInitiateInitializeGuardianRecoveryAuth(
        address recoveryAddress,
        uint256 timelockDurationSeconds,
        uint256 salt,
        uint256 expiration,
        bool isApproval,
        uint256[] memory privateKeys
    ) internal view returns (AdminAuthParams memory auth, bytes memory operationData) {
        operationData = abi.encode(recoveryAddress, timelockDurationSeconds);
        auth = _buildAdminAuthParamsForEOA({
            operationType: OperationType.InitiateInitializeGuardianRecovery,
            operationData: operationData,
            isApproval: isApproval,
            salt: salt,
            expirationTimestamp: expiration,
            privateKeys: privateKeys
        });
    }

    /**
     * @dev Builds auth for `finalizeInitializeGuardianRecovery` against current pending tuple.
     */
    function _buildFinalizeInitializeGuardianRecoveryAuth(
        address pendingAddress,
        uint256 pendingTimelock,
        uint256 salt,
        uint256 expiration,
        bool isApproval,
        uint256[] memory privateKeys
    ) internal view returns (AdminAuthParams memory auth, bytes memory operationData) {
        operationData = abi.encode(pendingAddress, pendingTimelock);
        auth = _buildAdminAuthParamsForEOA({
            operationType: OperationType.FinalizeInitializeGuardianRecovery,
            operationData: operationData,
            isApproval: isApproval,
            salt: salt,
            expirationTimestamp: expiration,
            privateKeys: privateKeys
        });
    }

    /**
     * @dev Builds auth for `cancelInitializeGuardianRecovery` against current pending tuple.
     */
    function _buildCancelInitializeGuardianRecoveryAuth(
        address pendingAddress,
        uint256 pendingTimelock,
        uint256 salt,
        uint256 expiration,
        bool isApproval,
        uint256[] memory privateKeys
    ) internal view returns (AdminAuthParams memory auth, bytes memory operationData) {
        operationData = abi.encode(pendingAddress, pendingTimelock);
        auth = _buildAdminAuthParamsForEOA({
            operationType: OperationType.CancelInitializeGuardianRecovery,
            operationData: operationData,
            isApproval: isApproval,
            salt: salt,
            expirationTimestamp: expiration,
            privateKeys: privateKeys
        });
    }

    /**
     * @dev Computes nonce for guardian-recovery deferred-init operations.
     */
    function _computeRecoveryNonce(OperationType operationType, bytes memory operationData, uint256 salt)
        internal
        view
        returns (uint256)
    {
        return recoveryStateHarness.computeNonce(operationType, operationData, salt);
    }

    /**
     * @dev Asserts the standard `onlyGuardianRecoveryAddress` revert shape.
     */
    function _expectOnlyGuardianRecoveryAddressRevert(address caller, address expectedRecoveryAddress) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationGuardianRecovery.UnauthorizedGuardianRecoveryAddress.selector,
                caller,
                expectedRecoveryAddress
            )
        );
    }

    /**
     * @dev Asserts the standard `onlyRecoveryPendingGuardian` revert shape.
     */
    function _expectOnlyRecoveryPendingGuardianRevert(address caller, address pendingGuardian) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationGuardianRecovery.UnauthorizedRecoveryGuardianAcceptance.selector, caller, pendingGuardian
            )
        );
    }
}
