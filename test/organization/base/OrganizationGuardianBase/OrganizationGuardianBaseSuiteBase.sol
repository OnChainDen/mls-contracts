// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationGuardian} from "interfaces/organization/IOrganizationGuardian.sol";
import {
    OrganizationGuardianBaseHarness
} from "test/organization/base/OrganizationGuardianBase/OrganizationGuardianBaseHarness.sol";
import {OrganizationAdminStateHarness} from "test/organization/shared/OrganizationAdminStateHarness.sol";
import {OrganizationAdminTestBase} from "test/organization/shared/OrganizationAdminTestBase.sol";
import {OrganizationGuardianStateHarness} from "test/organization/shared/OrganizationGuardianStateHarness.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";
import {OperationType} from "types/CommonTypes.sol";

/**
 * @dev Shared deployment/auth-builder helpers for `OrganizationGuardianBase` unit suites.
 */
abstract contract OrganizationGuardianBaseSuiteBase is OrganizationAdminTestBase {
    /// @dev Default admin-operation timelock used by guardian update flow tests.
    uint256 internal constant ADMIN_OPERATION_TIMELOCK = 2 days;

    /// @dev Deterministic proposed guardian fixtures.
    address internal constant NEW_GUARDIAN_A = address(0xABCD1);
    address internal constant NEW_GUARDIAN_B = address(0xABCD2);

    /// @dev Concrete harness used by all base-contract-focused section suites.
    OrganizationGuardianBaseHarness internal harness;

    /// @dev Typed shared-state surface for guardian/timelock storage helpers.
    OrganizationGuardianStateHarness internal guardianStateHarness;

    /**
     * @dev Deploys the base-contract-focused harness for section suites.
     */
    function _deployHarness() internal override returns (OrganizationAdminStateHarness) {
        harness = new OrganizationGuardianBaseHarness();
        return OrganizationAdminStateHarness(address(harness));
    }

    /**
     * @dev Seeds the admin-operation timelock duration used by library logic.
     */
    function setUp() public virtual override {
        super.setUp();
        guardianStateHarness = OrganizationGuardianStateHarness(address(harness));
        guardianStateHarness.setAdminOperationTimelockDurationSeconds(ADMIN_OPERATION_TIMELOCK);
    }

    /**
     * @dev Builds auth for `initiateGuardianUpdate`.
     */
    function _buildInitiateGuardianUpdateAuth(
        address newGuardian,
        uint256 salt,
        uint256 expiration,
        bool isApproval,
        uint256[] memory privateKeys
    ) internal view returns (AdminAuthParams memory auth, bytes memory operationData) {
        operationData = abi.encode(newGuardian);
        auth = _buildAdminAuthParamsForEoa({
            operationType: OperationType.InitiateUpdateGuardian,
            operationData: operationData,
            isApproval: isApproval,
            salt: salt,
            expirationTimestamp: expiration,
            privateKeys: privateKeys
        });
    }

    /**
     * @dev Builds auth for `finalizeGuardianUpdate` against the current pending guardian.
     */
    function _buildFinalizeGuardianUpdateAuth(
        address pendingGuardian,
        uint256 salt,
        uint256 expiration,
        bool isApproval,
        uint256[] memory privateKeys
    ) internal view returns (AdminAuthParams memory auth, bytes memory operationData) {
        operationData = abi.encode(pendingGuardian);
        auth = _buildAdminAuthParamsForEoa({
            operationType: OperationType.FinalizeUpdateGuardian,
            operationData: operationData,
            isApproval: isApproval,
            salt: salt,
            expirationTimestamp: expiration,
            privateKeys: privateKeys
        });
    }

    /**
     * @dev Builds auth for `cancelGuardianUpdate` against the current pending guardian.
     */
    function _buildCancelGuardianUpdateAuth(
        address pendingGuardian,
        uint256 salt,
        uint256 expiration,
        bool isApproval,
        uint256[] memory privateKeys
    ) internal view returns (AdminAuthParams memory auth, bytes memory operationData) {
        operationData = abi.encode(pendingGuardian);
        auth = _buildAdminAuthParamsForEoa({
            operationType: OperationType.CancelUpdateGuardian,
            operationData: operationData,
            isApproval: isApproval,
            salt: salt,
            expirationTimestamp: expiration,
            privateKeys: privateKeys
        });
    }

    /**
     * @dev Computes nonce for a guardian operation.
     */
    function _computeGuardianNonce(OperationType operationType, bytes memory operationData, uint256 salt)
        internal
        view
        returns (uint256)
    {
        return guardianStateHarness.computeNonce(operationType, operationData, salt);
    }

    /**
     * @dev Creates a pending guardian update via base entry point with valid auth.
     */
    function _initiatePendingGuardianUpdate(address newGuardian, uint256 salt) internal {
        (AdminAuthParams memory auth,) = _buildInitiateGuardianUpdateAuth({
            newGuardian: newGuardian,
            salt: salt,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        vm.prank(GUARDIAN);
        harness.initiateGuardianUpdate(newGuardian, auth);
    }

    /**
     * @dev Finalizes the current pending guardian update via base entry point with valid auth.
     */
    function _finalizePendingGuardianUpdate(address pendingGuardian, uint256 salt) internal {
        (AdminAuthParams memory auth,) = _buildFinalizeGuardianUpdateAuth({
            pendingGuardian: pendingGuardian,
            salt: salt,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        vm.prank(GUARDIAN);
        harness.finalizeGuardianUpdate(auth);
    }

    /**
     * @dev Asserts the standard `onlyPendingGuardian` revert shape.
     */
    function _expectOnlyPendingGuardianRevert(address caller, address pendingGuardian) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationGuardian.UnauthorizedGuardianAcceptance.selector, caller, pendingGuardian
            )
        );
    }
}
