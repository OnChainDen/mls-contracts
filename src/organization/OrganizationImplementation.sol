// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { BaseUUPSImplementation } from "../proxy/BaseUUPSImplementation.sol";
import { LibOrganizationMembers } from "./libraries/LibOrganizationMembers.sol";
import { LibOrganizationGroups } from "./libraries/LibOrganizationGroups.sol";
import { LibOrganizationPolicy } from "./libraries/LibOrganizationPolicy.sol";
import { LibOrganizationWhitelist } from "./libraries/LibOrganizationWhitelist.sol";
import { LibOrganizationAdmin } from "./libraries/LibOrganizationAdmin.sol";
import { LibOrganizationGuardian } from "./libraries/LibOrganizationGuardian.sol";
import { LibOrganizationAccountFactory } from "./libraries/LibOrganizationAccountFactory.sol";
import { LibOrganizationInitialization } from "./libraries/LibOrganizationInitialization.sol";
import { LibOrganizationDeployerAddressStorage } from "./libraries/storage/LibOrganizationDeployerAddressStorage.sol";
import { LibOrganizationAdminStorage } from "./libraries/storage/LibOrganizationAdminStorage.sol";
import { IAdminFacet, AdminType, AdminOperationType } from "../interfaces/IAdminFacet.sol";
import { Policies } from "../libraries/Policies.sol";
import { IUpgradeable } from "../interfaces/IUpgradeable.sol";

/**
 * @title Organization Implementation
 * @notice UUPS upgradeable implementation contract for Organization
 * @dev This contract exposes all Organization library functions as external wrappers
 * @author Den Technologies Inc
 */
contract OrganizationImplementation is BaseUUPSImplementation, IAdminFacet, IUpgradeable {
    /**
     * @notice Modifier that enforces only the guardian can call the function
     */
    modifier onlyGuardian() {
        LibOrganizationGuardian.enforceOnlyGuardian();
        _;
    }

    /**
     * @notice Initialize the organization implementation
     * @param whitelistAddress The address of the implementation whitelist contract
     * @param deployerAddress The address of the deployer (for initialization authorization)
     * @param adminType Type of admin (Member or Group)
     * @param adminAddresses Array of addresses to be added as admin members
     * @param votingThreshold Voting threshold (only used for Group admin type)
     * @param guardian Guardian address for the organization
     */
    function initialize(
        address whitelistAddress,
        address deployerAddress,
        AdminType adminType,
        address[] memory adminAddresses,
        uint256 votingThreshold,
        address guardian
    )
        external
        initializer
    {
        // Initialize base UUPS implementation (contractType = 1 for Organization)
        __BaseUUPSImplementation_init(whitelistAddress, 1);

        // Set deployer address
        LibOrganizationDeployerAddressStorage.layout().deployerAddress = deployerAddress;

        // Initialize organization
        LibOrganizationInitialization.initialize(adminType, adminAddresses, votingThreshold, guardian);
    }

    // ================================
    // LibOrganizationMembers wrappers
    // ================================

    function addressToMemberId(address memberAddress) external view returns (uint8) {
        return LibOrganizationMembers.addressToMemberId(memberAddress);
    }

    function getMemberAddress(uint8 memberId) external view returns (address) {
        return LibOrganizationMembers.getMemberAddress(memberId);
    }

    function memberExists(uint8 memberId) external view returns (bool) {
        return LibOrganizationMembers.memberExists(memberId);
    }

    function addMembers(
        address[] memory memberAddresses,
        uint256 salt,
        bytes memory signatures
    )
        external
        onlyGuardian
        returns (uint8[] memory)
    {
        // Encode the operation data for validation
        bytes memory operationData = abi.encode(memberAddresses);

        // Validate that the current admin has authorized this operation
        LibOrganizationAdmin.validateAdminAuthorization(AdminOperationType.AddMembers, operationData, salt, signatures);

        return LibOrganizationMembers.addMembers(memberAddresses);
    }

    function modifyMember(
        uint8 memberId,
        address newAddress,
        uint256 salt,
        bytes memory signatures
    )
        external
        onlyGuardian
    {
        // Encode the operation data for validation
        bytes memory operationData = abi.encode(memberId, newAddress);

        // Validate that the current admin has authorized this operation
        LibOrganizationAdmin.validateAdminAuthorization(
            AdminOperationType.ModifyMember, operationData, salt, signatures
        );

        LibOrganizationMembers.modifyMember(memberId, newAddress);
    }

    function removeMembers(uint8[] memory memberIds, uint256 salt, bytes memory signatures) external onlyGuardian {
        // Encode the operation data for validation
        bytes memory operationData = abi.encode(memberIds);

        // Validate that the current admin has authorized this operation
        LibOrganizationAdmin.validateAdminAuthorization(
            AdminOperationType.RemoveMembers, operationData, salt, signatures
        );

        LibOrganizationMembers.removeMembers(memberIds);
    }

    // ================================
    // LibOrganizationGroups wrappers
    // ================================

    function isMemberInGroup(uint8 memberId, uint8 groupId) external view returns (bool) {
        return LibOrganizationGroups.isMemberInGroup(memberId, groupId);
    }

    function isMemberInGroup(address memberAddress, uint8 groupId) external view returns (bool) {
        return LibOrganizationGroups.isMemberInGroup(memberAddress, groupId);
    }

    function groupExists(uint8 groupId) external view returns (bool) {
        return LibOrganizationGroups.groupExists(groupId);
    }

    function isValidGroupWithMembers(uint8 groupId) external view returns (bool) {
        return LibOrganizationGroups.isValidGroupWithMembers(groupId);
    }

    function createGroup(
        uint8[] memory memberIds,
        uint256 salt,
        bytes memory signatures
    )
        external
        onlyGuardian
        returns (uint8)
    {
        // Encode the operation data for validation
        bytes memory operationData = abi.encode(memberIds);

        // Validate that the current admin has authorized this operation
        LibOrganizationAdmin.validateAdminAuthorization(AdminOperationType.CreateGroup, operationData, salt, signatures);

        return LibOrganizationGroups.createGroup(memberIds);
    }

    function modifyGroup(
        uint8 groupId,
        uint8[] memory membersToAdd,
        uint8[] memory membersToRemove,
        uint256 salt,
        bytes memory signatures
    )
        external
        onlyGuardian
    {
        // Encode the operation data for validation
        bytes memory operationData = abi.encode(groupId, membersToAdd, membersToRemove);

        // Validate that the current admin has authorized this operation
        LibOrganizationAdmin.validateAdminAuthorization(AdminOperationType.ModifyGroup, operationData, salt, signatures);

        LibOrganizationGroups.modifyGroup(groupId, membersToAdd, membersToRemove);
    }

    function removeGroup(uint8 groupId, uint256 salt, bytes memory signatures) external onlyGuardian {
        // Encode the operation data for validation
        bytes memory operationData = abi.encode(groupId);

        // Validate that the current admin has authorized this operation
        LibOrganizationAdmin.validateAdminAuthorization(AdminOperationType.RemoveGroup, operationData, salt, signatures);

        LibOrganizationGroups.removeGroup(groupId);
    }

    // ================================
    // LibOrganizationPolicy wrappers
    // ================================

    function getPolicy(uint256 policyId) external view returns (Policies.Policy memory) {
        return LibOrganizationPolicy.getPolicy(policyId);
    }

    function policyExists(uint256 policyId) external view returns (bool) {
        return LibOrganizationPolicy.policyExists(policyId);
    }

    function modifyPolicies(
        uint256[] memory modifyPolicyIds,
        Policies.Policy[] memory policiesToModify,
        Policies.Policy[] memory addPolicies,
        uint256[] memory removePolicyIds,
        uint256 salt,
        bytes memory signatures
    )
        external
        onlyGuardian
    {
        // Encode the operation data for validation
        bytes memory operationData = abi.encode(modifyPolicyIds, policiesToModify, addPolicies, removePolicyIds);

        // Validate that the current admin has authorized this operation
        LibOrganizationAdmin.validateAdminAuthorization(
            AdminOperationType.ModifyPolicies, operationData, salt, signatures
        );

        LibOrganizationPolicy.modifyPolicies(modifyPolicyIds, policiesToModify, addPolicies, removePolicyIds);
    }

    function doesPolicyApplyToTransaction(
        Policies.Policy memory policy,
        address sourceAccount,
        address to,
        uint256 value,
        bytes memory data,
        address initiator
    )
        external
        view
        returns (bool)
    {
        return LibOrganizationPolicy.doesPolicyApplyToTransaction(policy, sourceAccount, to, value, data, initiator);
    }

    function getRequiredApprovals(Policies.Policy memory policy) external pure returns (uint256) {
        return LibOrganizationPolicy.getRequiredApprovals(policy);
    }

    function isSignerAuthorizedForPolicy(Policies.Policy memory policy, address signer) external view returns (bool) {
        return LibOrganizationPolicy.isSignerAuthorizedForPolicy(policy, signer);
    }

    function isSignerAuthorizedAsInitiator(
        Policies.Policy memory policy,
        address signer
    )
        external
        view
        returns (bool)
    {
        return LibOrganizationPolicy.isSignerAuthorizedAsInitiator(policy, signer);
    }

    // ================================
    // LibOrganizationWhitelist wrappers
    // ================================

    function isAddressWhitelisted(address addressToCheck) external view returns (bool) {
        return LibOrganizationWhitelist.isAddressWhitelisted(addressToCheck);
    }

    function modifyWhitelist(
        address[] memory addressesToAdd,
        address[] memory addressesToRemove,
        uint256 salt,
        bytes memory signatures
    )
        external
        onlyGuardian
    {
        // Encode the operation data for validation
        bytes memory operationData = abi.encode(addressesToAdd, addressesToRemove);

        // Validate that the current admin has authorized this operation
        LibOrganizationAdmin.validateAdminAuthorization(
            AdminOperationType.ModifyWhitelist, operationData, salt, signatures
        );

        LibOrganizationWhitelist.modifyWhitelist(addressesToAdd, addressesToRemove);
    }

    // ================================
    // LibOrganizationAdmin wrappers
    // ================================

    function adminPermission() external view returns (LibOrganizationAdminStorage.AdminPermission memory) {
        return LibOrganizationAdmin.adminPermission();
    }

    function isAdminNonceUsed(uint256 nonce) external view returns (bool) {
        return LibOrganizationAdmin.isAdminNonceUsed(nonce);
    }

    function computeAdminNonce(
        AdminOperationType operationType,
        bytes memory operationData,
        uint256 salt
    )
        external
        view
        returns (uint256)
    {
        return LibOrganizationAdmin.computeAdminNonce(operationType, operationData, salt);
    }

    function updateAdmin(
        AdminType newAdminType,
        uint8 newAdminId,
        uint256 newVotingThreshold,
        uint256 salt,
        bytes memory signatures
    )
        external
        onlyGuardian
    {
        // Encode the operation data for validation
        bytes memory operationData = abi.encode(newAdminType, newAdminId, newVotingThreshold);

        // Validate that the current admin has authorized this change
        LibOrganizationAdmin.validateAdminAuthorization(AdminOperationType.UpdateAdmin, operationData, salt, signatures);

        LibOrganizationAdmin.updateAdmin(newAdminType, newAdminId, newVotingThreshold);
    }

    function validateAdminAuthorization(
        AdminOperationType operationType,
        bytes memory operationData,
        uint256 salt,
        bytes memory signatures
    )
        external
        override
    {
        LibOrganizationAdmin.validateAdminAuthorization(operationType, operationData, salt, signatures);
    }

    // ================================
    // LibOrganizationGuardian wrappers
    // ================================

    function enforceOnlyGuardian() external view {
        LibOrganizationGuardian.enforceOnlyGuardian();
    }

    function guardian() external view returns (address) {
        return LibOrganizationGuardian.guardian();
    }

    function updateGuardian(address newGuardian, uint256 salt, bytes memory signatures) external onlyGuardian {
        // Encode the operation data for validation
        bytes memory operationData = abi.encode(newGuardian);

        // Validate that the current admin has authorized this operation
        LibOrganizationAdmin.validateAdminAuthorization(
            AdminOperationType.UpdateGuardian, operationData, salt, signatures
        );

        LibOrganizationGuardian.updateGuardian(newGuardian);
    }

    // ================================
    // LibOrganizationAccountFactory wrappers
    // ================================

    function deployAccount(
        bytes32 create2Salt,
        address implementationAddress,
        bytes memory initializationData,
        uint256 adminSignatureSalt,
        bytes memory signatures
    )
        external
        onlyGuardian
        returns (address)
    {
        // Validate admin authorization for account deployment
        bytes memory operationData =
            abi.encode(create2Salt, keccak256(abi.encode(implementationAddress, keccak256(initializationData))));

        LibOrganizationAdmin.validateAdminAuthorization(
            AdminOperationType.DeployAccount, operationData, adminSignatureSalt, signatures
        );

        return LibOrganizationAccountFactory.deployAccount(create2Salt, implementationAddress, initializationData);
    }

    function computeAccountAddress(
        bytes32 salt,
        address implementationAddress,
        bytes memory initializationData
    )
        external
        view
        returns (address)
    {
        return LibOrganizationAccountFactory.computeAccountAddress(salt, implementationAddress, initializationData);
    }

    // ================================
    // LibOrganizationInitialization wrappers
    // ================================

    function getDeployerAddress() external view returns (address) {
        return LibOrganizationInitialization.getDeployerAddress();
    }

    function isInitialized() external view returns (bool) {
        return LibOrganizationInitialization.isInitialized();
    }

    // ================================
    // IUpgradeable interface
    // ================================

    function upgradeToWithAuthorization(
        address newImplementation,
        uint256 whitelistSetId,
        uint256 salt,
        bytes calldata signatures
    )
        external
        override
    {
        super.upgradeToWithAuthorization(newImplementation, whitelistSetId, salt, signatures);
    }

    function upgradeToAndCallWithAuthorization(
        address newImplementation,
        bytes memory data,
        uint256 whitelistSetId,
        uint256 salt,
        bytes calldata signatures
    )
        external
        override
    {
        super.upgradeToAndCallWithAuthorization(newImplementation, data, whitelistSetId, salt, signatures);
    }
}
