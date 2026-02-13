// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationInitialization} from "interfaces/organization/IOrganizationInitialization.sol";
import {LibOrganizationAccountFactory} from "organization/libraries/LibOrganizationAccountFactory.sol";
import {LibOrganizationAdmin} from "organization/libraries/LibOrganizationAdmin.sol";
import {LibOrganizationAdminOperationTimelock} from "organization/libraries/LibOrganizationAdminOperationTimelock.sol";
import {LibOrganizationGroups} from "organization/libraries/LibOrganizationGroups.sol";
import {LibOrganizationGuardian} from "organization/libraries/LibOrganizationGuardian.sol";
import {LibOrganizationGuardianRecovery} from "organization/libraries/LibOrganizationGuardianRecovery.sol";
import {LibOrganizationMembers} from "organization/libraries/LibOrganizationMembers.sol";
import {LibOrganizationTxRecovery} from "organization/libraries/LibOrganizationTxRecovery.sol";
import {LibOrganizationAdminStorage} from "organization/libraries/storage/LibOrganizationAdminStorage.sol";
import {
    LibOrganizationDeployerAddressStorage
} from "organization/libraries/storage/LibOrganizationDeployerAddressStorage.sol";
import {InitializationParams} from "types/CommonTypes.sol";

/**
 * @title Lib Organization Initialization
 * @dev Library for post-deployment initialization of Organization contracts.
 *      This library should ONLY be used by Organization contracts.
 *      Members, admins, and groups are stored directly in onchain mappings.
 * @author Den Technologies Inc
 */
library LibOrganizationInitialization {
    /**
     * @dev Initializes the organization contract with mapping-based members, admins, and groups.
     *      Deployer authorization is enforced by the external wrapper function.
     *      Members are set first, then admins (which validates all admins are members),
     *      then groups, then remaining configuration.
     * @param params The initialization parameters struct
     */
    function initialize(InitializationParams calldata params) public {
        // Check if already initialized (adminCount > 0 is the sentinel)
        if (isInitialized()) {
            revert IOrganizationInitialization.AlreadyInitialized();
        }

        // Validate that at least one member is provided
        if (params.members.length == 0) {
            revert IOrganizationInitialization.NoMembersProvided();
        }

        // 1. Set initial members first (populates isMember mapping)
        LibOrganizationMembers.modifyMembers({
            membersToAdd: params.members,
            // Pass in an empty calldata array for `membersToRemove` parameter
            // This is a zero-length calldata slice of the `params.members` array
            membersToRemove: params.members[0:0]
        });

        // 2. Set initial admins (validates all admins are members via mapping lookup)
        LibOrganizationAdmin.modifyAdmins({
            adminsToAdd: params.admins,
            // Pass in an empty calldata array for `adminsToRemove` parameter
            // This is a zero-length calldata slice of the `params.admins` array
            adminsToRemove: params.admins[0:0],
            newVotingThreshold: params.votingThreshold
        });

        // 3. Set initial groups (if any)
        if (params.groups.length > 0) {
            LibOrganizationGroups.modifyGroups(params.groups);
        }

        // 4. Initialize admin operation timelock (organization-wide timelock for sensitive operations)
        LibOrganizationAdminOperationTimelock.initializeAdminOperationTimelock(
            params.adminOperationTimelockDurationSeconds
        );

        // 5. Initialize guardian configuration (sets guardian address)
        LibOrganizationGuardian.initializeGuardian(params.guardian);

        // 6. Initialize account implementation
        LibOrganizationAccountFactory.setAccountImplementation(params.accountImplementation);

        // 7. Initialize guardian recovery (if recovery address is provided)
        if (params.guardianRecoveryAddress != address(0)) {
            LibOrganizationGuardianRecovery.initializeGuardianRecovery({
                guardianRecoveryAddress: params.guardianRecoveryAddress,
                guardianRecoveryTimelockDurationSeconds: params.guardianRecoveryTimelockDurationSeconds
            });
        }

        // 8. Initialize tx/ERC1271 recovery (if recovery address is provided)
        if (params.transactionAndERC1271RecoveryAddress != address(0)) {
            LibOrganizationTxRecovery.initializeTxRecovery(
                params.transactionAndERC1271RecoveryAddress, params.txRecoveryTimelockDurationSeconds
            );
        }

        emit IOrganizationInitialization.OrganizationInitialized({
            adminAddresses: params.admins,
            votingThreshold: params.votingThreshold,
            guardian: params.guardian,
            accountImplementation: params.accountImplementation,
            adminOperationTimelockDurationSeconds: params.adminOperationTimelockDurationSeconds,
            transactionAndERC1271RecoveryAddress: params.transactionAndERC1271RecoveryAddress,
            txRecoveryTimelockDurationSeconds: params.txRecoveryTimelockDurationSeconds,
            guardianRecoveryAddress: params.guardianRecoveryAddress,
            guardianRecoveryTimelockDurationSeconds: params.guardianRecoveryTimelockDurationSeconds
        });
    }

    /**
     * @dev Enforces that the caller is the deployer address.
     *      This function will revert if msg.sender is not the deployer.
     */
    function enforceOnlyDeployer() public view {
        if (msg.sender != LibOrganizationDeployerAddressStorage.layout().deployerAddress) {
            revert IOrganizationInitialization.UnauthorizedDeployer();
        }
    }

    /**
     * @dev Gets the deployer address from storage
     * @return The deployer address
     */
    function getDeployerAddress() public view returns (address) {
        return LibOrganizationDeployerAddressStorage.layout().deployerAddress;
    }

    /**
     * @dev Checks if the organization has been initialized.
     *      Uses adminCount > 0 as the initialization sentinel since every
     *      organization must have at least one admin.
     * @return True if initialized, false otherwise
     */
    function isInitialized() public view returns (bool) {
        return LibOrganizationAdminStorage.layout().adminCount > 0;
    }
}
