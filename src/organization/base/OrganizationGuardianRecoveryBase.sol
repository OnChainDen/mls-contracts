// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationGuardianRecovery} from "interfaces/organization/IOrganizationGuardianRecovery.sol";
import {OrganizationModifiers} from "organization/common/OrganizationModifiers.sol";
import {LibOrganizationGuardianRecovery} from "organization/libraries/LibOrganizationGuardianRecovery.sol";

/**
 * @title OrganizationGuardianRecoveryBase
 * @dev Abstract contract implementing IOrganizationGuardianRecovery.
 *      Handles guardian recovery flow: initiate → finalize → accept.
 *      Uses separate storage from normal guardian updates.
 * @author Den Technologies Inc
 */
abstract contract OrganizationGuardianRecoveryBase is OrganizationModifiers, IOrganizationGuardianRecovery {
    /// @inheritdoc IOrganizationGuardianRecovery
    function initiateRecoveryGuardianUpdate(address newGuardian) external override onlyGuardianRecoveryAddress {
        LibOrganizationGuardianRecovery.initiateRecoveryGuardianUpdate(newGuardian);
    }

    /// @inheritdoc IOrganizationGuardianRecovery
    function finalizeRecoveryGuardianUpdate() external override onlyGuardianRecoveryAddress {
        LibOrganizationGuardianRecovery.finalizeRecoveryGuardianUpdate();
    }

    /// @inheritdoc IOrganizationGuardianRecovery
    function cancelRecoveryGuardianUpdate() external override onlyGuardianRecoveryAddress {
        LibOrganizationGuardianRecovery.cancelRecoveryGuardianUpdate();
    }

    /// @inheritdoc IOrganizationGuardianRecovery
    function acceptGuardianRecovery() external override onlyRecoveryPendingGuardian {
        LibOrganizationGuardianRecovery.acceptGuardianRecovery();
    }

    /// @inheritdoc IOrganizationGuardianRecovery
    function guardianRecoveryAddress() external view override returns (address) {
        return LibOrganizationGuardianRecovery.getGuardianRecoveryAddress();
    }

    /// @inheritdoc IOrganizationGuardianRecovery
    function guardianRecoveryTimelockDurationSeconds() external view override returns (uint256) {
        return LibOrganizationGuardianRecovery.getGuardianRecoveryTimelockDurationSeconds();
    }

    /// @inheritdoc IOrganizationGuardianRecovery
    function recoveryPendingGuardian() external view override returns (address) {
        return LibOrganizationGuardianRecovery.getRecoveryPendingGuardian();
    }

    /// @inheritdoc IOrganizationGuardianRecovery
    function recoveryPendingGuardianTimestamp() external view override returns (uint256) {
        return LibOrganizationGuardianRecovery.getRecoveryPendingGuardianTimestamp();
    }

    /// @inheritdoc IOrganizationGuardianRecovery
    function isRecoveryGuardianUpdateReadyForAcceptance() external view override returns (bool) {
        return LibOrganizationGuardianRecovery.getIsRecoveryGuardianUpdateReadyForAcceptance();
    }
}
