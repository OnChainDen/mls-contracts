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
import { LibOrganizationSignatures } from "./libraries/LibOrganizationSignatures.sol";
import { LibOrganizationAccountTransaction } from "./libraries/LibOrganizationAccountTransaction.sol";
import { LibOrganizationAdminStorage } from "./libraries/storage/LibOrganizationAdminStorage.sol";
import { IAdminFacet, AdminType } from "../interfaces/IAdminFacet.sol";
import { OperationType } from "../interfaces/IOrganization.sol";
import { Policies } from "../libraries/Policies.sol";
import { IUpgradeable } from "../interfaces/IUpgradeable.sol";
import { IImplementationWhitelist } from "../interfaces/IImplementationWhitelist.sol";

/**
 * @notice Interface for the Account contract's execute function
 */
interface IAccountExecute {
    function executeTransaction(
        address to,
        uint256 value,
        bytes calldata data,
        uint256 nonce,
        uint256 policyId
    )
        external;
}

/**
 * @title Organization Implementation
 * @notice UUPS upgradeable implementation contract for Organization
 * @dev This contract exposes all Organization library functions as external wrappers
 * @author Den Technologies Inc
 */
contract OrganizationImplementation is BaseUUPSImplementation, IAdminFacet, IUpgradeable {
    /**
     * @notice Emitted when a transaction is executed on an account
     * @param account The account that executed the transaction
     * @param to The destination address of the transaction
     * @param value The value of the transaction
     * @param data The data of the transaction
     * @param nonce The nonce used for this transaction
     * @param policyId The policy ID that governed this transaction
     */
    event AccountTransactionExecuted(
        address indexed account, address indexed to, uint256 value, bytes data, uint256 indexed nonce, uint256 policyId
    );

    /**
     * @notice Emitted when a transaction is rejected by authorized users
     * @param account The account for which the transaction was rejected
     * @param to The destination address of the transaction
     * @param value The value of the transaction
     * @param data The data of the transaction
     * @param nonce The nonce used for this transaction
     * @param policyId The policy ID that governed this transaction
     */
    event AccountTransactionRejected(
        address indexed account, address indexed to, uint256 value, bytes data, uint256 indexed nonce, uint256 policyId
    );

    /**
     * @notice Emitted when a transaction is rejected because of wrong chain ID
     * @param expected The expected chain ID
     * @param provided The provided chain ID
     */
    error InvalidChainId(uint256 expected, uint256 provided);

    /**
     * @notice Modifier that enforces only the guardian can call the function
     */
    modifier onlyGuardian() {
        LibOrganizationGuardian.enforceOnlyGuardian();
        _;
    }

    /**
     * @notice Modifier that enforces only the deployer can call the function
     */
    modifier onlyDeployer() {
        LibOrganizationInitialization.enforceOnlyDeployer();
        _;
    }

    /**
     * @notice Initialize the organization implementation
     * @param adminType Type of admin (Member or Group)
     * @param adminAddresses Array of addresses to be added as admin members
     * @param votingThreshold Voting threshold (only used for Group admin type)
     * @param guardian Guardian address for the organization
     * @dev whitelistAddress and deployerAddress are set in the proxy constructor and should not be passed here
     */
    function initialize(
        AdminType adminType,
        address[] memory adminAddresses,
        uint256 votingThreshold,
        address guardian
    )
        external
        initializer
        onlyDeployer
    {
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
        LibOrganizationAdmin.validateAdminAuthorization(OperationType.AddMembers, operationData, salt, signatures);

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
        LibOrganizationAdmin.validateAdminAuthorization(OperationType.ModifyMember, operationData, salt, signatures);

        LibOrganizationMembers.modifyMember(memberId, newAddress);
    }

    function removeMembers(uint8[] memory memberIds, uint256 salt, bytes memory signatures) external onlyGuardian {
        // Encode the operation data for validation
        bytes memory operationData = abi.encode(memberIds);

        // Validate that the current admin has authorized this operation
        LibOrganizationAdmin.validateAdminAuthorization(OperationType.RemoveMembers, operationData, salt, signatures);

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
        LibOrganizationAdmin.validateAdminAuthorization(OperationType.CreateGroup, operationData, salt, signatures);

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
        LibOrganizationAdmin.validateAdminAuthorization(OperationType.ModifyGroup, operationData, salt, signatures);

        LibOrganizationGroups.modifyGroup(groupId, membersToAdd, membersToRemove);
    }

    function removeGroup(uint8 groupId, uint256 salt, bytes memory signatures) external onlyGuardian {
        // Encode the operation data for validation
        bytes memory operationData = abi.encode(groupId);

        // Validate that the current admin has authorized this operation
        LibOrganizationAdmin.validateAdminAuthorization(OperationType.RemoveGroup, operationData, salt, signatures);

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
        LibOrganizationAdmin.validateAdminAuthorization(OperationType.ModifyPolicies, operationData, salt, signatures);

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
        LibOrganizationAdmin.validateAdminAuthorization(OperationType.ModifyWhitelist, operationData, salt, signatures);

        LibOrganizationWhitelist.modifyWhitelist(addressesToAdd, addressesToRemove);
    }

    // ================================
    // LibOrganizationAdmin wrappers
    // ================================

    function adminPermission() external view returns (LibOrganizationAdminStorage.AdminPermission memory) {
        return LibOrganizationAdmin.adminPermission();
    }

    function isNonceUsed(uint256 nonce) external view returns (bool) {
        return LibOrganizationSignatures.isNonceUsed(nonce);
    }

    function computeNonce(
        OperationType operationType,
        bytes memory operationData,
        uint256 salt
    )
        external
        view
        returns (uint256)
    {
        return LibOrganizationSignatures.computeNonce(operationType, operationData, salt);
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
        LibOrganizationAdmin.validateAdminAuthorization(OperationType.UpdateAdmin, operationData, salt, signatures);

        LibOrganizationAdmin.updateAdmin(newAdminType, newAdminId, newVotingThreshold);
    }

    function validateAdminAuthorization(
        OperationType operationType,
        bytes memory operationData,
        uint256 salt,
        bytes memory signatures
    )
        external
        override
    {
        // Only allow calls from AccountProxy contracts deployed by this organization
        if (!LibOrganizationAccountFactory.isAccountDeployed(msg.sender)) {
            revert LibOrganizationAccountFactory.AccountNotDeployedByOrganization(msg.sender);
        }

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
        LibOrganizationAdmin.validateAdminAuthorization(OperationType.UpdateGuardian, operationData, salt, signatures);

        LibOrganizationGuardian.updateGuardian(newGuardian);
    }

    // ================================
    // LibOrganizationAccountFactory wrappers
    // ================================

    function deployAccount(
        bytes32 create2Salt,
        address implementationAddress,
        uint256 adminSignatureSalt,
        bytes memory signatures
    )
        external
        onlyGuardian
        returns (address)
    {
        // Validate admin authorization for account deployment
        bytes memory operationData = abi.encode(create2Salt, implementationAddress);

        LibOrganizationAdmin.validateAdminAuthorization(
            OperationType.DeployAccount, operationData, adminSignatureSalt, signatures
        );

        return LibOrganizationAccountFactory.deployAccount(create2Salt, implementationAddress);
    }

    function computeAccountAddress(bytes32 salt, address implementationAddress) external view returns (address) {
        return LibOrganizationAccountFactory.computeAccountAddress(salt, implementationAddress);
    }

    // ================================
    // LibOrganizationAccountTransaction wrappers
    // ================================

    /**
     * @notice Executes a transaction on an account through the organization
     * @param account The account to execute the transaction from
     * @param to The destination address of the transaction
     * @param value The value of the transaction
     * @param data The data of the transaction
     * @param salt A user-provided salt for nonce computation
     * @param policyId The ID of the policy that governs this transaction
     * @param signatures The signatures authorizing the transaction
     */
    function executeAccountTransaction(
        address account,
        address to,
        uint256 value,
        bytes calldata data,
        uint256 salt,
        uint256 policyId,
        bytes memory signatures
    )
        external
        onlyGuardian
    {
        // Verify the account is deployed by this organization
        if (!LibOrganizationAccountFactory.isAccountDeployed(account)) {
            revert LibOrganizationAccountFactory.AccountNotDeployedByOrganization(account);
        }

        // Encode operation data for nonce computation
        bytes memory operationData = abi.encode(account, to, value, keccak256(data), policyId);

        // Compute nonce
        uint256 nonce = LibOrganizationSignatures.computeNonce(OperationType.AccountTransaction, operationData, salt);

        // Validate and consume nonce (will revert if already used)
        LibOrganizationSignatures.validateAndConsumeNonce(nonce);

        // Validate the transaction against the policy and signatures
        LibOrganizationAccountTransaction.validateTransaction(account, to, value, data, salt, policyId, signatures);

        // Execute the transaction on the account
        IAccountExecute(account).executeTransaction(to, value, data, nonce, policyId);

        emit AccountTransactionExecuted(account, to, value, data, nonce, policyId);
    }

    /**
     * @notice Rejects a transaction that has been signed but not yet executed
     * @param account The account for which to reject the transaction
     * @param to The destination address of the transaction
     * @param value The value of the transaction
     * @param data The data of the transaction
     * @param salt A user-provided salt for nonce computation
     * @param policyId The ID of the policy that governs this transaction
     * @param chainId The chain ID for cross-chain replay protection - must match current chain ID
     * @param signatures The signatures authorizing the rejection
     */
    function rejectAccountTransaction(
        address account,
        address to,
        uint256 value,
        bytes calldata data,
        uint256 salt,
        uint256 policyId,
        bytes memory signatures
    )
        external
        onlyGuardian
    {
        // Verify the account is deployed by this organization
        if (!LibOrganizationAccountFactory.isAccountDeployed(account)) {
            revert LibOrganizationAccountFactory.AccountNotDeployedByOrganization(account);
        }

        // Encode operation data for nonce computation (same as executeAccountTransaction)
        bytes memory operationData = abi.encode(account, to, value, keccak256(data), policyId);

        // Compute nonce (same as for execution)
        uint256 nonce = LibOrganizationSignatures.computeNonce(OperationType.AccountTransaction, operationData, salt);

        // Validate and consume nonce (will revert if already used)
        LibOrganizationSignatures.validateAndConsumeNonce(nonce);

        // Validate the rejection authorization
        LibOrganizationAccountTransaction.validateRejectionAuthorization(
            account, to, value, data, salt, policyId, signatures
        );

        emit AccountTransactionRejected(account, to, value, data, nonce, policyId);
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
        uint256 salt,
        bytes calldata signatures
    )
        external
        override
    {
        super.upgradeToWithAuthorization(newImplementation, salt, signatures);
    }

    function upgradeToAndCallWithAuthorization(
        address newImplementation,
        bytes memory data,
        uint256 salt,
        bytes calldata signatures
    )
        external
        override
    {
        super.upgradeToAndCallWithAuthorization(newImplementation, data, salt, signatures);
    }
}
