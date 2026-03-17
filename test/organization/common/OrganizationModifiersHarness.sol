// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {OrganizationModifiers} from "organization/common/OrganizationModifiers.sol";
import {LibOrganizationDeployerAddressStorage} from "organization/libraries/storage/LibOrganizationDeployerAddressStorage.sol";
import {LibOrganizationGuardianStorage} from "organization/libraries/storage/LibOrganizationGuardianStorage.sol";
import {LibOrganizationRecoveryStorage} from "organization/libraries/storage/LibOrganizationRecoveryStorage.sol";

/**
 * @dev Harness that exposes one guarded function per modifier plus direct storage setters for test setup.
 */
contract OrganizationModifiersHarness is OrganizationModifiers {
    uint256 public lastModifierId;

    /// @dev Calls through the `onlyGuardian` modifier and records success.
    function guardianOnlyAction() external onlyGuardian {
        lastModifierId = 1;
    }

    /// @dev Calls through the `onlyDeployer` modifier and records success.
    function deployerOnlyAction() external onlyDeployer {
        lastModifierId = 2;
    }

    /// @dev Calls through the `onlyTxRecoveryAddress` modifier and records success.
    function txRecoveryOnlyAction() external onlyTxRecoveryAddress {
        lastModifierId = 3;
    }

    /// @dev Calls through the `onlyGuardianRecoveryAddress` modifier and records success.
    function guardianRecoveryOnlyAction() external onlyGuardianRecoveryAddress {
        lastModifierId = 4;
    }

    /// @dev Calls through the `onlyPendingGuardian` modifier and records success.
    function pendingGuardianOnlyAction() external onlyPendingGuardian {
        lastModifierId = 5;
    }

    /// @dev Calls through the `onlyRecoveryPendingGuardian` modifier and records success.
    function recoveryPendingGuardianOnlyAction() external onlyRecoveryPendingGuardian {
        lastModifierId = 6;
    }

    /// @dev Simulates pending-guardian acceptance through a function that uses `onlyPendingGuardian`.
    function acceptPendingGuardianAction() external onlyPendingGuardian {
        LibOrganizationGuardianStorage.Layout storage guardianLayout = LibOrganizationGuardianStorage.layout();
        guardianLayout.guardian = guardianLayout.pendingGuardian;
        guardianLayout.pendingGuardian = address(0);
        guardianLayout.pendingGuardianUpdateTimestamp = 0;
        guardianLayout.isGuardianUpdateReadyForAcceptance = false;
        lastModifierId = 7;
    }

    /// @dev Simulates recovery-pending-guardian acceptance through a function that uses `onlyRecoveryPendingGuardian`.
    function acceptRecoveryPendingGuardianAction() external onlyRecoveryPendingGuardian {
        LibOrganizationGuardianStorage.Layout storage guardianLayout = LibOrganizationGuardianStorage.layout();
        LibOrganizationRecoveryStorage.Layout storage recoveryLayout = LibOrganizationRecoveryStorage.layout();

        guardianLayout.guardian = recoveryLayout.guardianRecovery.pendingGuardian;
        recoveryLayout.guardianRecovery.pendingGuardian = address(0);
        recoveryLayout.guardianRecovery.pendingGuardianTimestamp = 0;
        recoveryLayout.guardianRecovery.isUpdateReadyForAcceptance = false;
        lastModifierId = 8;
    }

    /// @dev Sets guardian and pending-guardian storage for modifier tests.
    function setGuardianState(address guardian, address pendingGuardian, bool readyForAcceptance) external {
        LibOrganizationGuardianStorage.Layout storage guardianLayout = LibOrganizationGuardianStorage.layout();
        guardianLayout.guardian = guardian;
        guardianLayout.pendingGuardian = pendingGuardian;
        guardianLayout.isGuardianUpdateReadyForAcceptance = readyForAcceptance;
    }

    /// @dev Sets deployer-address storage for modifier tests.
    function setDeployer(address deployer) external {
        LibOrganizationDeployerAddressStorage.layout().deployerAddress = deployer;
    }

    /// @dev Sets tx-recovery-address storage for modifier tests.
    function setTxRecoveryAddress(address recoveryAddress) external {
        LibOrganizationRecoveryStorage.layout().txRecovery.recoveryAddress = recoveryAddress;
    }

    /// @dev Sets guardian-recovery storage for modifier tests.
    function setGuardianRecoveryState(address recoveryAddress, address pendingGuardian, bool readyForAcceptance)
        external
    {
        LibOrganizationRecoveryStorage.Layout storage recoveryLayout = LibOrganizationRecoveryStorage.layout();
        recoveryLayout.guardianRecovery.recoveryAddress = recoveryAddress;
        recoveryLayout.guardianRecovery.pendingGuardian = pendingGuardian;
        recoveryLayout.guardianRecovery.isUpdateReadyForAcceptance = readyForAcceptance;
    }

}
