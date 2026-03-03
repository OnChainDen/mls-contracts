// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IBeacon} from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

import {IImplementationWhitelist} from "interfaces/IImplementationWhitelist.sol";
import {IOrganization} from "interfaces/IOrganization.sol";
import {OrganizationAccountFactoryBase} from "organization/base/OrganizationAccountFactoryBase.sol";
import {OrganizationAccountSignatureBase} from "organization/base/OrganizationAccountSignatureBase.sol";
import {OrganizationAccountTransactionBase} from "organization/base/OrganizationAccountTransactionBase.sol";
import {OrganizationAdminBase} from "organization/base/OrganizationAdminBase.sol";
import {OrganizationAdminOperationTimelockBase} from "organization/base/OrganizationAdminOperationTimelockBase.sol";
import {OrganizationGroupsBase} from "organization/base/OrganizationGroupsBase.sol";
import {OrganizationGuardianBase} from "organization/base/OrganizationGuardianBase.sol";
import {OrganizationGuardianRecoveryBase} from "organization/base/OrganizationGuardianRecoveryBase.sol";
import {OrganizationInitializationBase} from "organization/base/OrganizationInitializationBase.sol";
import {OrganizationMembersBase} from "organization/base/OrganizationMembersBase.sol";
import {OrganizationPolicyBase} from "organization/base/OrganizationPolicyBase.sol";
import {OrganizationSignaturesBase} from "organization/base/OrganizationSignaturesBase.sol";
import {OrganizationTxRecoveryBase} from "organization/base/OrganizationTxRecoveryBase.sol";
import {LibOrganizationAdmin} from "organization/libraries/LibOrganizationAdmin.sol";
import {LibOrganizationUpgradeStorage} from "organization/libraries/storage/LibOrganizationUpgradeStorage.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";
import {ContractType, OperationType} from "types/CommonTypes.sol";

/**
 * @title Organization Implementation
 * @notice UUPS upgradeable implementation contract for Organization that also acts as a Beacon for Account proxies
 * @dev Policies are stored as a Merkle tree (root stored on-chain, data provided via calldata).
 *      Members, Groups, and Admins are stored directly in onchain mappings.
 *
 *      This contract inherits from modular base contracts that each implement a specific interface:
 *      - OrganizationInitializationBase: Initialization logic
 *      - OrganizationAdminBase: Admin management
 *      - OrganizationMembersBase: Member management
 *      - OrganizationGroupsBase: Group management
 *      - OrganizationPolicyBase: Policy management
 *      - OrganizationAdminOperationTimelockBase: Organization-wide admin operation timelock configuration
 *      - OrganizationGuardianBase: Normal guardian update flow
 *      - OrganizationAccountFactoryBase: Account deployment and beacon implementation
 *      - OrganizationAccountTransactionBase: Account transaction execution
 *      - OrganizationAccountSignatureBase: ERC-1271 signature validation
 *      - OrganizationSignaturesBase: Nonce management
 *      - OrganizationGuardianRecoveryBase: Guardian recovery flow
 *      - OrganizationTxRecoveryBase: Transaction recovery flow
 *
 *      The hub (this contract) only contains the upgrade authorization logic.
 * @author Den Technologies Inc
 */
contract OrganizationImplementation is
    UUPSUpgradeable,
    IOrganization,
    OrganizationInitializationBase,
    OrganizationAdminBase,
    OrganizationMembersBase,
    OrganizationGroupsBase,
    OrganizationPolicyBase,
    OrganizationAdminOperationTimelockBase,
    OrganizationGuardianBase,
    OrganizationAccountFactoryBase,
    OrganizationAccountTransactionBase,
    OrganizationAccountSignatureBase,
    OrganizationSignaturesBase,
    OrganizationGuardianRecoveryBase,
    OrganizationTxRecoveryBase
{
    /// @inheritdoc IOrganization
    function upgradeToAndCallWithAuthorization(
        address newImplementation,
        bytes calldata data,
        AdminAuthParams calldata authParams
    ) external override onlyGuardian {
        // Validate admin authorization (isApproval = true for execution)
        bytes memory operationData = abi.encode(newImplementation, keccak256(data));
        LibOrganizationAdmin.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.Upgrade, operationData: operationData, isApproval: true, authParams: authParams
        });

        // Validate implementation against whitelist
        // forgefmt: disable-next-item
        IImplementationWhitelist(LibOrganizationUpgradeStorage.layout().whitelistAddress)
            .validateIsImplementationWhitelistedOrRevert(
                ContractType.Organization,
                newImplementation
            );

        // Bind authorization to this exact target implementation for the upcoming UUPS hook call.
        LibOrganizationUpgradeStorage.layout().authorizedUpgradeImplementation = newImplementation;

        // Perform the upgrade
        // This calls the inherited UUPSUpgradeable.upgradeToAndCall which will:
        // 1. Call _authorizeUpgrade (which checks the authorized target binding)
        // 2. Upgrade the implementation
        // 3. Optionally call `data` on the new implementation
        upgradeToAndCall(newImplementation, data);

        // Reset authorized target (defense-in-depth)
        // Even though this value can't persist if the tx reverts, we reset it explicitly
        // as a security best practice. This also protects against any theoretical
        // scenario where the value might persist.
        LibOrganizationUpgradeStorage.layout().authorizedUpgradeImplementation = address(0);
    }

    /// @inheritdoc IBeacon
    function implementation() public view override(IBeacon, OrganizationAccountFactoryBase) returns (address) {
        return OrganizationAccountFactoryBase.implementation();
    }

    /**
     * @dev Authorize an upgrade (required by UUPSUpgradeable)
     *      This function is called by the inherited `upgradeToAndCall` function from UUPSUpgradeable.
     *      It acts as a gatekeeper to ensure upgrades only happen through our authorized flow.
     *
     *      SECURITY EXPLANATION:
     *      OpenZeppelin's UUPSUpgradeable exposes a public `upgradeToAndCall(address, bytes)` function.
     *      Without protection, an attacker could call this directly on the proxy, bypassing:
     *      - Guardian check (onlyGuardian modifier)
     *      - Admin signature validation
     *      - Implementation whitelist check
     *
     *      Our solution uses an authorized target value at a namespaced slot (EIP-7201):
     *      - `upgradeToAndCallWithAuthorization` sets it to `newImplementation` AFTER validating everything
     *      - This function checks it is non-zero and exactly equals `newImplementation`
     *      - Direct calls to `upgradeToAndCall` will not have a matching authorized target → revert
     *
     *      WHY NAMESPACED STORAGE (EIP-7201)?
     *      - Prevents storage slot collisions when upgrading contracts
     *      - Safe even if new state variables are added in future implementations
     *
     *      WHY REGULAR STORAGE (not transient)?
     *      We use regular storage instead of EIP-1153 transient storage for maximum EVM chain
     *      compatibility. This allows deployment to chains that haven't adopted the Cancun upgrade.
     *      The authorized target is explicitly reset after the upgrade completes as defense-in-depth.
     *
     * @param newImplementation The new implementation address whose authorization is being checked.
     */
    function _authorizeUpgrade(address newImplementation) internal view override {
        address authorizedUpgradeImplementation = LibOrganizationUpgradeStorage.layout().authorizedUpgradeImplementation;
        // Check that a target has been authorized and that the authorized target matches this UUPS hook call.
        if (authorizedUpgradeImplementation == address(0) || authorizedUpgradeImplementation != newImplementation) {
            revert UnauthorizedUpgrade();
        }
    }
}
