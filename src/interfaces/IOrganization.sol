// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IBeacon} from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";

import {IOrganizationAccountFactory} from "interfaces/organization/IOrganizationAccountFactory.sol";
import {IOrganizationAccountSignature} from "interfaces/organization/IOrganizationAccountSignature.sol";
import {IOrganizationAccountTransaction} from "interfaces/organization/IOrganizationAccountTransaction.sol";
import {IOrganizationAdmin} from "interfaces/organization/IOrganizationAdmin.sol";
import {IOrganizationGroups} from "interfaces/organization/IOrganizationGroups.sol";
import {IOrganizationGuardian} from "interfaces/organization/IOrganizationGuardian.sol";
import {IOrganizationGuardianRecovery} from "interfaces/organization/IOrganizationGuardianRecovery.sol";
import {IOrganizationInitialization} from "interfaces/organization/IOrganizationInitialization.sol";
import {IOrganizationMembers} from "interfaces/organization/IOrganizationMembers.sol";
import {IOrganizationPolicy} from "interfaces/organization/IOrganizationPolicy.sol";
import {IOrganizationSignatures} from "interfaces/organization/IOrganizationSignatures.sol";
import {IOrganizationTxRecovery} from "interfaces/organization/IOrganizationTxRecovery.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";
// solhint-disable-next-line no-unused-import
import {InitializationParams, OperationType} from "types/CommonTypes.sol";

/**
 * @title IOrganization
 * @notice Hub interface that aggregates all Organization module interfaces
 * @dev This is a composite interface that inherits from all module interfaces.
 *      Each module interface maps 1:1 to a library for easy auditor navigation.
 *      The hub itself contains only functions that don't belong to any specific module.
 *      Extends IBeacon to act as a beacon for Account proxies.
 * @author Den Technologies Inc
 */
interface IOrganization is
    IBeacon,
    IOrganizationAdmin,
    IOrganizationMembers,
    IOrganizationGroups,
    IOrganizationPolicy,
    IOrganizationGuardian,
    IOrganizationAccountFactory,
    IOrganizationAccountTransaction,
    IOrganizationAccountSignature,
    IOrganizationSignatures,
    IOrganizationInitialization,
    IOrganizationGuardianRecovery,
    IOrganizationTxRecovery
{
    // ═══════════════════════════════════════════════════════════════════════════
    // Errors (OrganizationImplementation-specific errors that don't belong to modules)
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Thrown when the account implementation has not been set
     */
    error AccountImplementationNotSet();

    /**
     * @notice Emitted when someone tries to call upgradeToAndCall directly without going through
     *         the authorized upgrade flow (upgradeToAndCallWithAuthorization)
     * @dev This protects against attackers bypassing admin signature validation by calling
     *      the inherited public upgradeToAndCall function directly on the proxy
     */
    error UnauthorizedUpgrade();

    // ═══════════════════════════════════════════════════════════════════════════
    // Functions that don't belong to any specific module
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Upgrade the organization implementation to a new address and optionally call a function
     * @dev This is the ONLY authorized way to upgrade this contract. Direct calls to the inherited
     *      `upgradeToAndCall` function will revert with `UnauthorizedUpgrade`.
     * @param newImplementation The new implementation address (must be whitelisted)
     * @param data Optional calldata to execute on the new implementation after upgrade.
     *             Pass empty bytes ("") if no post-upgrade call is needed.
     * @param authParams The authorization parameters (salt, expiration, signatures, and admin proofs)
     */
    function upgradeToAndCallWithAuthorization(
        address newImplementation,
        bytes calldata data,
        AdminAuthParams calldata authParams
    ) external;

    // Note: implementation() is inherited from IBeacon.
    // It returns the current implementation address for all Account BeaconProxies.
}
