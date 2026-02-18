// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {OrganizationAdminBaseHarness} from "test/organization/harness/OrganizationAdminBaseHarness.sol";
import {OrganizationAdminStateHarness} from "test/organization/harness/OrganizationAdminStateHarness.sol";
import {OrganizationAdminTestBase} from "test/organization/helpers/OrganizationAdminTestBase.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";
import {OperationType} from "types/CommonTypes.sol";

/**
 * @dev Shared deployment/auth-builder helpers for `OrganizationAdminBase` unit suites.
 *      Suite files inherit this to avoid repeating harness plumbing and operation-data encoding details.
 */
abstract contract OrganizationAdminBaseSuiteBase is OrganizationAdminTestBase {
    /// @dev Concrete harness used by all base-contract-focused section suites.
    OrganizationAdminBaseHarness internal harness;

    /**
     * @dev Deploys the base-contract-focused harness for section suites.
     */
    function _deployHarness() internal override returns (OrganizationAdminStateHarness) {
        harness = new OrganizationAdminBaseHarness();
        return OrganizationAdminStateHarness(address(harness));
    }

    /**
     * @dev Builds auth for `modifyAdmins` using base contract operation-data encoding.
     */
    function _buildModifyAdminsAuth(
        address[] memory adminsToAdd,
        address[] memory adminsToRemove,
        uint256 newVotingThreshold,
        uint256 salt,
        uint256 expiration,
        bool isApproval,
        uint256[] memory privateKeys
    ) internal view returns (AdminAuthParams memory auth, bytes memory operationData) {
        // OrganizationAdminBase signs hashes of arrays + threshold, not raw arrays directly.
        operationData = _encodeOperationDataForModifyAdmins(adminsToAdd, adminsToRemove, newVotingThreshold);
        // Build signatures against the exact base-contract payload encoding.
        auth = _buildAdminAuthParamsForEOA({
            operationType: OperationType.ModifyAdmins,
            operationData: operationData,
            isApproval: isApproval,
            salt: salt,
            expirationTimestamp: expiration,
            privateKeys: privateKeys
        });
    }
}
