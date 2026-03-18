// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganization} from "interfaces/IOrganization.sol";
import {LibOrganizationGuardian} from "organization/libraries/LibOrganizationGuardian.sol";
import {LibOrganizationGuardianRecovery} from "organization/libraries/LibOrganizationGuardianRecovery.sol";
import {LibOrganizationInitialization} from "organization/libraries/LibOrganizationInitialization.sol";
import {LibOrganizationTxRecovery} from "organization/libraries/LibOrganizationTxRecovery.sol";

/**
 * @title OrganizationModifiers
 * @dev Abstract contract providing centralized access control modifiers for Organization base contracts.
 *      All modifiers delegate to library functions that contain the actual enforcement logic.
 * @author Den Technologies Inc
 */
abstract contract OrganizationModifiers {
    /**
     * @dev Modifier that enforces only the guardian can call the function
     */
    modifier onlyGuardian() {
        LibOrganizationGuardian.enforceOnlyGuardian();
        _;
    }

    /**
     * @dev Modifier that enforces only the deployer can call the function
     */
    modifier onlyDeployer() {
        LibOrganizationInitialization.enforceOnlyDeployer();
        _;
    }

    /**
     * @dev Modifier that enforces only the transaction recovery address can call the function
     */
    modifier onlyTxRecoveryAddress() {
        LibOrganizationTxRecovery.enforceOnlyTxRecoveryAddress();
        _;
    }

    /**
     * @dev Modifier that enforces only the guardian recovery address can call the function
     */
    modifier onlyGuardianRecoveryAddress() {
        LibOrganizationGuardianRecovery.enforceOnlyGuardianRecoveryAddress();
        _;
    }

    /**
     * @dev Modifier that enforces only the pending guardian can call the function
     */
    modifier onlyPendingGuardian() {
        LibOrganizationGuardian.enforceOnlyPendingGuardian();
        _;
    }

    /**
     * @dev Modifier that enforces only the recovery pending guardian can call the function
     */
    modifier onlyRecoveryPendingGuardian() {
        LibOrganizationGuardianRecovery.enforceOnlyRecoveryPendingGuardian();
        _;
    }

    /**
     * @dev Modifier that enforces only the contract itself can call the function.
     *      Used by companion execution functions that are invoked via low-level self-calls
     *      to isolate reverts from the outer call frame.
     */
    modifier onlySelf() {
        _enforceSelfCall();
        _;
    }

    function _enforceSelfCall() internal view {
        if (msg.sender != address(this)) revert IOrganization.UnauthorizedSelfCall(msg.sender);
    }
}
