// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {LibOrganizationRecoveryStorage} from "organization/libraries/storage/LibOrganizationRecoveryStorage.sol";
import {OrganizationGuardianStateHarness} from "test/organization/shared/OrganizationGuardianStateHarness.sol";
import {GuardianRecoveryState, TxRecoveryState} from "types/RecoveryTypes.sol";

/**
 * @dev Shared guardian-recovery-focused state harness surface.
 *      Extends guardian/admin helpers with direct guardian-recovery and tx-recovery storage accessors.
 */
contract OrganizationGuardianRecoveryStateHarness is OrganizationGuardianStateHarness {
    /**
     * @dev Sets full guardian-recovery state directly in storage.
     */
    function setGuardianRecoveryState(GuardianRecoveryState calldata state) external {
        LibOrganizationRecoveryStorage.layout().guardianRecovery = state;
    }

    /**
     * @dev Reads full guardian-recovery state from storage.
     */
    function getGuardianRecoveryStateStorage() external view returns (GuardianRecoveryState memory) {
        return LibOrganizationRecoveryStorage.layout().guardianRecovery;
    }

    /**
     * @dev Sets guardian-recovery config fields.
     */
    function setGuardianRecoveryConfig(address recoveryAddress, uint256 timelockDurationSeconds) external {
        GuardianRecoveryState storage state = LibOrganizationRecoveryStorage.layout().guardianRecovery;
        state.recoveryAddress = recoveryAddress;
        state.timelockDurationSeconds = timelockDurationSeconds;
    }

    /**
     * @dev Sets recovery-update pending fields.
     */
    function setGuardianRecoveryPendingUpdate(address pendingGuardian, uint256 pendingTimestamp, bool isReady)
        external
    {
        GuardianRecoveryState storage state = LibOrganizationRecoveryStorage.layout().guardianRecovery;
        state.pendingGuardian = pendingGuardian;
        state.pendingGuardianTimestamp = pendingTimestamp;
        state.isUpdateReadyForAcceptance = isReady;
    }

    /**
     * @dev Sets deferred-init pending fields.
     */
    function setGuardianRecoveryPendingInit(address pendingAddress, uint256 pendingTimelock, uint256 pendingTimestamp)
        external
    {
        GuardianRecoveryState storage state = LibOrganizationRecoveryStorage.layout().guardianRecovery;
        state.pendingInit.pendingRecoveryAddress = pendingAddress;
        state.pendingInit.pendingTimelockDurationSeconds = pendingTimelock;
        state.pendingInit.pendingTimestamp = pendingTimestamp;
    }

    /**
     * @dev Resets guardian-recovery storage to a zero baseline.
     */
    function resetGuardianRecoveryStorage() external {
        GuardianRecoveryState storage state = LibOrganizationRecoveryStorage.layout().guardianRecovery;
        state.recoveryAddress = address(0);
        state.isUpdateReadyForAcceptance = false;
        state.pendingGuardian = address(0);
        state.timelockDurationSeconds = 0;
        state.pendingGuardianTimestamp = 0;
        state.pendingInit.pendingRecoveryAddress = address(0);
        state.pendingInit.pendingTimelockDurationSeconds = 0;
        state.pendingInit.pendingTimestamp = 0;
    }

    /**
     * @dev Sets full tx-recovery state directly in storage.
     */
    function setTxRecoveryState(TxRecoveryState calldata state) external {
        LibOrganizationRecoveryStorage.layout().txRecovery = state;
    }

    /**
     * @dev Reads full tx-recovery state directly from storage.
     */
    function getTxRecoveryStateStorage() external view returns (TxRecoveryState memory) {
        return LibOrganizationRecoveryStorage.layout().txRecovery;
    }
}
