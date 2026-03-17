// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {
    LibOrganizationAccountFactoryStorage
} from "organization/libraries/storage/LibOrganizationAccountFactoryStorage.sol";
import {LibOrganizationPolicyStorage} from "organization/libraries/storage/LibOrganizationPolicyStorage.sol";
import {LibOrganizationRecoveryStorage} from "organization/libraries/storage/LibOrganizationRecoveryStorage.sol";
import {OrganizationGroupsStateHarness} from "test/organization/shared/OrganizationGroupsStateHarness.sol";
import {TxRecoveryState} from "types/RecoveryTypes.sol";

/**
 * @dev Shared policy-focused state harness surface.
 *      Extends groups/admin helpers with policy/account/recovery storage setters used by policy tests.
 */
contract OrganizationPolicyStateHarness is OrganizationGroupsStateHarness {
    /**
     * @dev Sets policies merkle root directly in storage.
     */
    function setPoliciesRoot(bytes32 policiesRoot) external {
        LibOrganizationPolicyStorage.layout().policiesRoot = policiesRoot;
    }

    /**
     * @dev Reads policies merkle root directly from storage.
     */
    function getPoliciesRoot() external view returns (bytes32) {
        return LibOrganizationPolicyStorage.layout().policiesRoot;
    }

    /**
     * @dev Sets policy usage value for `(usageKey, timeWindow)`.
     */
    function setPolicyUsage(bytes32 usageKey, uint256 timeWindow, uint256 usage) external {
        LibOrganizationPolicyStorage.layout().policyUsage[usageKey][timeWindow] = usage;
    }

    /**
     * @dev Reads policy usage value for `(usageKey, timeWindow)`.
     */
    function getPolicyUsage(bytes32 usageKey, uint256 timeWindow) external view returns (uint256) {
        return LibOrganizationPolicyStorage.layout().policyUsage[usageKey][timeWindow];
    }

    /**
     * @dev Sets deployed-account status in account-factory storage.
     */
    function setDeployedAccount(address account, bool isDeployed) external {
        LibOrganizationAccountFactoryStorage.layout().deployedAccounts[account] = isDeployed;
    }

    /**
     * @dev Reads deployed-account status in account-factory storage.
     */
    function isDeployedAccount(address account) external view returns (bool) {
        return LibOrganizationAccountFactoryStorage.layout().deployedAccounts[account];
    }

    /**
     * @dev Sets full tx-recovery state.
     */
    function setTxRecoveryState(TxRecoveryState calldata state) external {
        LibOrganizationRecoveryStorage.layout().txRecovery = state;
    }

    /**
     * @dev Reads full tx-recovery state.
     */
    function getTxRecoveryState() external view returns (TxRecoveryState memory) {
        return LibOrganizationRecoveryStorage.layout().txRecovery;
    }
}
