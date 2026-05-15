// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {OrganizationGuardianRecoveryBase} from "organization/base/OrganizationGuardianRecoveryBase.sol";
import {OrganizationTxRecoveryBase} from "organization/base/OrganizationTxRecoveryBase.sol";
import {
    LibOrganizationAccountFactoryStorage
} from "organization/libraries/storage/LibOrganizationAccountFactoryStorage.sol";
import {
    OrganizationGuardianRecoveryStateHarness
} from "test/organization/shared/OrganizationGuardianRecoveryStateHarness.sol";

/**
 * @dev Harness combining both `OrganizationGuardianRecoveryBase` and `OrganizationTxRecoveryBase` so a single
 *      test contract can exercise the cross-track `clearRecovery` entrypoint alongside the per-track tx-recovery
 *      entrypoints used by race-scenario tests.
 *      Exposes `setDeployedAccount` so end-to-end tests can mark a mock account as factory-deployed before
 *      calling `executeRecoveryAccountTransaction`.
 */
contract OrganizationClearRecoveryHarness is
    OrganizationGuardianRecoveryStateHarness,
    OrganizationGuardianRecoveryBase,
    OrganizationTxRecoveryBase
{
    /**
     * @dev Marks an account address as deployed by this organization so `executeRecoveryAccountTransaction`
     *      can route a recovery-path call to it.
     */
    function setDeployedAccount(address account, bool isDeployed) external {
        LibOrganizationAccountFactoryStorage.layout().deployedAccounts[account] = isDeployed;
    }
}
