// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {LibOrganizationAdmin} from "organization/libraries/LibOrganizationAdmin.sol";
import {LibOrganizationAdminStorage} from "organization/libraries/storage/LibOrganizationAdminStorage.sol";
import {OrganizationAdminStateHarness} from "test/organization/harness/OrganizationAdminStateHarness.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";
import {OperationType} from "types/CommonTypes.sol";

/**
 * @dev Library-focused test harness for `LibOrganizationAdmin`.
 *      Exposes direct wrappers around library entry points and internal helper functions.
 */
contract LibOrganizationAdminHarness is OrganizationAdminStateHarness {
    /**
     * @dev Storage-backed `isAdmin` view wrapper.
     *      Kept here so library tests can read the same surface they asserted before the harness split.
     */
    function isAdmin(address account) external view returns (bool) {
        return LibOrganizationAdminStorage.layout().isAdmin[account];
    }

    /**
     * @dev Storage-backed `adminCount` view wrapper.
     */
    function adminCount() external view returns (uint256) {
        return LibOrganizationAdminStorage.layout().adminCount;
    }

    /**
     * @dev Storage-backed `votingThreshold` view wrapper.
     */
    function votingThreshold() external view returns (uint256) {
        return LibOrganizationAdminStorage.layout().votingThreshold;
    }

    /**
     * @dev Wrapper around authorization validation + nonce consumption.
     */
    function validateAdminAuthAndConsumeNonceOrRevert(
        OperationType operationType,
        bytes calldata operationData,
        bool isApproval,
        AdminAuthParams calldata authParams
    ) external {
        // Intentionally forwards to the library entry point so tests can isolate auth behavior
        // without invoking additional side effects from higher-level module functions.
        LibOrganizationAdmin.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: operationType, operationData: operationData, isApproval: isApproval, authParams: authParams
        });
    }

    /**
     * @dev Wrapper around direct admin mutation library function.
     */
    function modifyAdminsViaLibrary(
        address[] calldata adminsToAdd,
        address[] calldata adminsToRemove,
        uint256 newVotingThreshold
    ) external {
        // This bypasses auth checks on purpose so tests can focus only on mutation invariants.
        LibOrganizationAdmin.modifyAdmins(adminsToAdd, adminsToRemove, newVotingThreshold);
    }

    /**
     * @dev Exposes internal helper used by auth validation.
     */
    function areAdminSignaturesValid(bytes calldata signatures, bytes32 operationHash) external view returns (bool) {
        return LibOrganizationAdmin._areAdminSignaturesValid(signatures, operationHash);
    }
}
