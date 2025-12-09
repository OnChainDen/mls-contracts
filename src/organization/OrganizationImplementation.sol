// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { UUPSUpgradeable } from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
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
import { AdminType, OperationType } from "../interfaces/IOrganization.sol";
import { Policies } from "../libraries/Policies.sol";
import { IUpgradeable } from "../interfaces/IUpgradeable.sol";
import { IImplementationWhitelist } from "../interfaces/IImplementationWhitelist.sol";
import { IAccountUpgradeable } from "../account/interfaces/IAccountUpgradeable.sol";
import { UpgradeAuthorizationStorage } from "../proxy/libraries/UpgradeAuthorizationStorage.sol";

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
contract OrganizationImplementation is UUPSUpgradeable, Initializable, IUpgradeable {
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
     * @notice Emitted when an account is upgraded
     * @param account The account that was upgraded
     * @param newImplementation The new implementation address
     */
    event AccountUpgraded(address indexed account, address indexed newImplementation);

    /**
     * @notice Emitted when an admin operation is rejected by authorized admins
     * @param operationType The type of admin operation that was rejected
     * @param operationData The encoded operation data
     * @param nonce The nonce that was consumed/burned
     */
    event AdminOperationRejected(OperationType indexed operationType, bytes operationData, uint256 indexed nonce);

    /**
     * @notice Emitted when an implementation is not whitelisted
     * @param implementation The implementation address that was not whitelisted
     */
    error ImplementationNotWhitelisted(address implementation);

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

        // Validate that the current admin has authorized this operation (isRejection = false for execution)
        LibOrganizationAdmin.validateAdminAuthorization(
            OperationType.AddMembers, operationData, salt, false, signatures
        );

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

        // Validate that the current admin has authorized this operation (isRejection = false for execution)
        LibOrganizationAdmin.validateAdminAuthorization(
            OperationType.ModifyMember, operationData, salt, false, signatures
        );

        LibOrganizationMembers.modifyMember(memberId, newAddress);
    }

    function removeMembers(uint8[] memory memberIds, uint256 salt, bytes memory signatures) external onlyGuardian {
        // Encode the operation data for validation
        bytes memory operationData = abi.encode(memberIds);

        // Validate that the current admin has authorized this operation (isRejection = false for execution)
        LibOrganizationAdmin.validateAdminAuthorization(
            OperationType.RemoveMembers, operationData, salt, false, signatures
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

        // Validate that the current admin has authorized this operation (isRejection = false for execution)
        LibOrganizationAdmin.validateAdminAuthorization(
            OperationType.CreateGroup, operationData, salt, false, signatures
        );

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

        // Validate that the current admin has authorized this operation (isRejection = false for execution)
        LibOrganizationAdmin.validateAdminAuthorization(
            OperationType.ModifyGroup, operationData, salt, false, signatures
        );

        LibOrganizationGroups.modifyGroup(groupId, membersToAdd, membersToRemove);
    }

    function removeGroup(uint8 groupId, uint256 salt, bytes memory signatures) external onlyGuardian {
        // Encode the operation data for validation
        bytes memory operationData = abi.encode(groupId);

        // Validate that the current admin has authorized this operation (isRejection = false for execution)
        LibOrganizationAdmin.validateAdminAuthorization(
            OperationType.RemoveGroup, operationData, salt, false, signatures
        );

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

        // Validate that the current admin has authorized this operation (isRejection = false for execution)
        LibOrganizationAdmin.validateAdminAuthorization(
            OperationType.ModifyPolicies, operationData, salt, false, signatures
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

        // Validate that the current admin has authorized this operation (isRejection = false for execution)
        LibOrganizationAdmin.validateAdminAuthorization(
            OperationType.ModifyWhitelist, operationData, salt, false, signatures
        );

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

        // Validate that the current admin has authorized this change (isRejection = false for execution)
        LibOrganizationAdmin.validateAdminAuthorization(
            OperationType.UpdateAdmin, operationData, salt, false, signatures
        );

        LibOrganizationAdmin.updateAdmin(newAdminType, newAdminId, newVotingThreshold);
    }

    /**
     * @notice Rejects an admin operation by burning its nonce
     * @dev This allows admins to explicitly cancel a previously signed operation
     *      by consuming its nonce without executing the operation logic
     * @param operationType The type of admin operation to reject
     * @param operationData The ABI-encoded data of the operation
     * @param salt The user-provided salt for nonce computation
     * @param signatures The signatures from admin(s) authorizing this rejection
     */
    function rejectAdminOperation(
        OperationType operationType,
        bytes calldata operationData,
        uint256 salt,
        bytes memory signatures
    )
        external
        onlyGuardian
    {
        // Compute nonce for this operation
        uint256 nonce = LibOrganizationSignatures.computeNonce(operationType, operationData, salt);

        // Validate admin authorization and consume the nonce (isRejection = true for rejection)
        // This verifies rejection-specific signatures and marks the nonce as used, effectively burning it
        LibOrganizationAdmin.validateAdminAuthorization(operationType, operationData, salt, true, signatures);

        emit AdminOperationRejected(operationType, operationData, nonce);
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

        // Validate that the current admin has authorized this operation (isRejection = false for execution)
        LibOrganizationAdmin.validateAdminAuthorization(
            OperationType.UpdateGuardian, operationData, salt, false, signatures
        );

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

        // isRejection = false for execution
        LibOrganizationAdmin.validateAdminAuthorization(
            OperationType.DeployAccount, operationData, adminSignatureSalt, false, signatures
        );

        return LibOrganizationAccountFactory.deployAccount(create2Salt, implementationAddress);
    }

    function computeAccountAddress(bytes32 salt, address implementationAddress) external view returns (address) {
        return LibOrganizationAccountFactory.computeAccountAddress(salt, implementationAddress);
    }

    /**
     * @notice Upgrades an account's implementation
     * @param account The account to upgrade
     * @param newImplementation The new implementation address
     * @param data Optional calldata to call on the new implementation after upgrade
     * @param salt A user-provided salt for nonce computation
     * @param signatures The signatures from admin(s) authorizing this upgrade
     */
    function upgradeAccount(
        address account,
        address newImplementation,
        bytes memory data,
        uint256 salt,
        bytes memory signatures
    )
        external
        onlyGuardian
    {
        // 1. Verify the account is deployed by this organization
        if (!LibOrganizationAccountFactory.isAccountDeployed(account)) {
            revert LibOrganizationAccountFactory.AccountNotDeployedByOrganization(account);
        }

        // 2. Validate admin authorization (isRejection = false for execution)
        bytes memory operationData = abi.encode(account, newImplementation, keccak256(data));
        LibOrganizationAdmin.validateAdminAuthorization(
            OperationType.UpgradeAccount, operationData, salt, false, signatures
        );

        // 3. Validate implementation against whitelist
        UpgradeAuthorizationStorage.Layout storage upgradeAuthLayout = UpgradeAuthorizationStorage.layout();
        if (
            !IImplementationWhitelist(upgradeAuthLayout.whitelistAddress).validateImplementation(
                IImplementationWhitelist.ContractType.Account, newImplementation
            )
        ) {
            revert ImplementationNotWhitelisted(newImplementation);
        }

        // 4. Call the account's upgrade function
        IAccountUpgradeable(account).upgradeToFromOrganization(newImplementation, data);

        emit AccountUpgraded(account, newImplementation);
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

    /**
     * @notice Upgrade the implementation to a new address with authorization
     * @param newImplementation The new implementation address
     * @param salt A user-provided salt for nonce computation
     * @param signatures The signatures from admin(s) authorizing this upgrade
     */
    function upgradeToWithAuthorization(
        address newImplementation,
        uint256 salt,
        bytes calldata signatures
    )
        external
        override
        onlyGuardian
    {
        _validateOrganizationUpgrade(newImplementation, salt, signatures);
        upgradeToAndCall(newImplementation, "");
    }

    /**
     * @notice Upgrade the implementation to a new address and call a function with authorization
     * @param newImplementation The new implementation address
     * @param data The calldata to call on the new implementation
     * @param salt A user-provided salt for nonce computation
     * @param signatures The signatures from admin(s) authorizing this upgrade
     */
    function upgradeToAndCallWithAuthorization(
        address newImplementation,
        bytes memory data,
        uint256 salt,
        bytes calldata signatures
    )
        external
        override
        onlyGuardian
    {
        _validateOrganizationUpgrade(newImplementation, salt, signatures);
        upgradeToAndCall(newImplementation, data);
    }

    /**
     * @notice Validates organization upgrade authorization
     * @dev Checks admin signatures and implementation whitelist
     * @param newImplementation The new implementation address
     * @param salt A user-provided salt for nonce computation
     * @param signatures The signatures from admin(s) authorizing this upgrade
     */
    function _validateOrganizationUpgrade(
        address newImplementation,
        uint256 salt,
        bytes calldata signatures
    )
        internal
    {
        // 1. Validate admin authorization (isRejection = false for execution)
        bytes memory operationData = abi.encode(newImplementation);
        LibOrganizationAdmin.validateAdminAuthorization(OperationType.Upgrade, operationData, salt, false, signatures);

        // 2. Validate implementation against whitelist
        UpgradeAuthorizationStorage.Layout storage upgradeAuthLayout = UpgradeAuthorizationStorage.layout();
        if (
            !IImplementationWhitelist(upgradeAuthLayout.whitelistAddress).validateImplementation(
                IImplementationWhitelist.ContractType.Organization, newImplementation
            )
        ) {
            revert ImplementationNotWhitelisted(newImplementation);
        }
    }

    /**
     * @notice Authorize an upgrade (required by UUPSUpgradeable)
     * @dev Authorization is handled by upgradeToWithAuthorization and upgradeToAndCallWithAuthorization
     *      which validate signatures before calling upgradeToAndCall
     * @param newImplementation The new implementation address (unused)
     */
    function _authorizeUpgrade(address newImplementation) internal override {
        // Authorization is already validated by upgradeToWithAuthorization or upgradeToAndCallWithAuthorization
        // before this function is called via upgradeToAndCall
    }
}
