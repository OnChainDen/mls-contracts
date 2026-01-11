// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAccountExecute} from "../account/interfaces/IAccountExecute.sol";
import {IImplementationWhitelist} from "../implementation-whitelist/interfaces/IImplementationWhitelist.sol";
import {IOrganizationSignatureValidator, InitializationParams, OperationType} from "../interfaces/IOrganization.sol";
import {IUpgradeable} from "../interfaces/IUpgradeable.sol";
import {Policies} from "../libraries/Policies.sol";

import {UpgradeAuthorizationStorage} from "../proxy/libraries/UpgradeAuthorizationStorage.sol";
import {LibOrganizationAccountFactory} from "./libraries/LibOrganizationAccountFactory.sol";
import {LibOrganizationAccountSignature} from "./libraries/LibOrganizationAccountSignature.sol";
import {LibOrganizationAccountTransaction} from "./libraries/LibOrganizationAccountTransaction.sol";
import {LibOrganizationAdmin} from "./libraries/LibOrganizationAdmin.sol";
import {LibOrganizationGroups} from "./libraries/LibOrganizationGroups.sol";
import {LibOrganizationGuardian} from "./libraries/LibOrganizationGuardian.sol";
import {LibOrganizationInitialization} from "./libraries/LibOrganizationInitialization.sol";
import {LibOrganizationMembers} from "./libraries/LibOrganizationMembers.sol";
import {LibOrganizationPolicy} from "./libraries/LibOrganizationPolicy.sol";
import {LibOrganizationSignatures} from "./libraries/LibOrganizationSignatures.sol";
import {LibOrganizationAccountFactoryStorage} from "./libraries/storage/LibOrganizationAccountFactoryStorage.sol";

import {LibOrganizationAdminStorage} from "./libraries/storage/LibOrganizationAdminStorage.sol";
import {LibOrganizationPolicyStorage} from "./libraries/storage/LibOrganizationPolicyStorage.sol";
import {IBeacon} from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title Organization Implementation
 * @notice UUPS upgradeable implementation contract for Organization that also acts as a Beacon for Account proxies
 * @dev Policies, Members, and Groups are all stored as Merkle trees. Only the roots are stored on-chain.
 *      Full data is provided via calldata and verified against the roots.
 * @author Den Technologies Inc
 */
contract OrganizationImplementation is
    UUPSUpgradeable,
    Initializable,
    IUpgradeable,
    IBeacon,
    IOrganizationSignatureValidator
{
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
     * @notice Emitted when the account implementation is updated (affects all accounts via beacon)
     * @param newImplementation The new implementation address for all accounts
     */
    event AccountImplementationUpdated(address indexed newImplementation);

    /**
     * @notice Emitted when an admin operation is rejected by authorized admins
     * @param operationType The type of admin operation that was rejected
     * @param operationData The encoded operation data
     * @param nonce The nonce that was consumed/burned
     */
    event AdminOperationRejected(OperationType indexed operationType, bytes operationData, uint256 indexed nonce);

    /**
     * @notice Emitted when a transaction is rejected because of wrong chain ID
     * @param expected The expected chain ID
     * @param provided The provided chain ID
     */
    error InvalidChainId(uint256 expected, uint256 provided);

    /**
     * @notice Emitted when the account implementation has not been set
     */
    error AccountImplementationNotSet();

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
     * @notice Initialize the organization implementation with Merkle-based members and groups
     * @param params The initialization parameters struct containing all required configuration
     */
    function initialize(InitializationParams calldata params) external initializer onlyDeployer {
        LibOrganizationInitialization.initialize(params);
    }

    /**
     * @notice Updates the global members merkle root
     * @dev This is the only way to set members. All member data is stored off-chain (IPFS).
     *      Validates that all admins remain members in the new tree to prevent bricking.
     * @param newMembersRoot The new merkle root containing all members
     * @param ipfsCid The IPFS CID where full member data is stored for disaster recovery
     * @param salt A user-provided salt for nonce computation
     * @param expirationTimestamp The timestamp after which the signatures are no longer valid
     * @param signatures The signatures from admin(s) authorizing this update
     * @param adminProofs The Merkle proofs for admin membership verification
     * @param adminValidation The validation data to verify all admins are in the new members tree
     */
    function setMembers(
        bytes32 newMembersRoot,
        string calldata ipfsCid,
        uint256 salt,
        uint256 expirationTimestamp,
        bytes memory signatures,
        LibOrganizationAdmin.AdminProofs calldata adminProofs,
        LibOrganizationAdmin.AdminMembershipValidation calldata adminValidation
    ) external onlyGuardian {
        // Encode the operation data for validation
        bytes memory operationData = abi.encode(newMembersRoot, keccak256(bytes(ipfsCid)));

        // Validate that the current admin has authorized this operation (isApproval = true for execution)
        LibOrganizationAdmin.validateAdminAuthorizationOrRevert({
            operationType: OperationType.ModifyMembers,
            operationData: operationData,
            salt: salt,
            expirationTimestamp: expirationTimestamp,
            isApproval: true,
            signatures: signatures,
            adminProofs: adminProofs
        });

        LibOrganizationMembers.setMembers(newMembersRoot, ipfsCid, adminValidation);
    }

    /**
     * @notice Updates the global groups merkle root
     * @dev This is the only way to set groups. All group data is stored off-chain (IPFS).
     * @param newGroupsRoot The new merkle root containing all groups
     * @param ipfsCid The IPFS CID where full group data is stored for disaster recovery
     * @param salt A user-provided salt for nonce computation
     * @param expirationTimestamp The timestamp after which the signatures are no longer valid
     * @param signatures The signatures from admin(s) authorizing this update
     * @param adminProofs The Merkle proofs for admin membership verification
     */
    function setGroups(
        bytes32 newGroupsRoot,
        string calldata ipfsCid,
        uint256 salt,
        uint256 expirationTimestamp,
        bytes memory signatures,
        LibOrganizationAdmin.AdminProofs calldata adminProofs
    ) external onlyGuardian {
        // Encode the operation data for validation
        bytes memory operationData = abi.encode(newGroupsRoot, keccak256(bytes(ipfsCid)));

        // Validate that the current admin has authorized this operation (isApproval = true for execution)
        LibOrganizationAdmin.validateAdminAuthorizationOrRevert({
            operationType: OperationType.ModifyGroups,
            operationData: operationData,
            salt: salt,
            expirationTimestamp: expirationTimestamp,
            isApproval: true,
            signatures: signatures,
            adminProofs: adminProofs
        });

        LibOrganizationGroups.setGroups(newGroupsRoot, ipfsCid);
    }

    /**
     * @notice Updates the global policies merkle root
     * @dev This is the only way to set policies. All policy data is stored off-chain (IPFS).
     * @param newPoliciesRoot The new merkle root containing all policies
     * @param ipfsCid The IPFS CID where full policy data is stored for disaster recovery
     * @param salt A user-provided salt for nonce computation
     * @param expirationTimestamp The timestamp after which the signatures are no longer valid
     * @param signatures The signatures from admin(s) authorizing this update
     * @param adminProofs The Merkle proofs for admin membership verification
     */
    function setPolicies(
        bytes32 newPoliciesRoot,
        string calldata ipfsCid,
        uint256 salt,
        uint256 expirationTimestamp,
        bytes memory signatures,
        LibOrganizationAdmin.AdminProofs calldata adminProofs
    ) external onlyGuardian {
        // Encode the operation data for validation
        bytes memory operationData = abi.encode(newPoliciesRoot, keccak256(bytes(ipfsCid)));

        // Validate that the current admin has authorized this operation (isApproval = true for execution)
        LibOrganizationAdmin.validateAdminAuthorizationOrRevert({
            operationType: OperationType.ModifyPolicies,
            operationData: operationData,
            salt: salt,
            expirationTimestamp: expirationTimestamp,
            isApproval: true,
            signatures: signatures,
            adminProofs: adminProofs
        });

        LibOrganizationPolicy.setPolicies(newPoliciesRoot, ipfsCid);
    }

    /**
     * @notice Sets the admin permissions for the organization
     * @dev Validates that all new admins are current members before updating.
     * @param newAdminsRoot The new merkle root of admin addresses
     * @param newAdminCount The number of admins in the new tree
     * @param newVotingThreshold The new voting threshold
     * @param salt A user-provided salt for nonce computation
     * @param expirationTimestamp The timestamp after which the signatures are no longer valid
     * @param signatures The signatures from admin(s) authorizing this update
     * @param adminProofs The Merkle proofs for admin membership verification
     * @param adminValidation The validation data to verify all new admins are members
     */
    function setAdmins(
        bytes32 newAdminsRoot,
        uint256 newAdminCount,
        uint256 newVotingThreshold,
        uint256 salt,
        uint256 expirationTimestamp,
        bytes memory signatures,
        LibOrganizationAdmin.AdminProofs calldata adminProofs,
        LibOrganizationAdmin.AdminMembershipValidation calldata adminValidation
    ) external onlyGuardian {
        // Encode the operation data for validation
        bytes memory operationData = abi.encode(newAdminsRoot, newAdminCount, newVotingThreshold);

        // Validate that the current admin has authorized this change (isApproval = true for execution)
        LibOrganizationAdmin.validateAdminAuthorizationOrRevert({
            operationType: OperationType.ModifyAdmins,
            operationData: operationData,
            salt: salt,
            expirationTimestamp: expirationTimestamp,
            isApproval: true,
            signatures: signatures,
            adminProofs: adminProofs
        });

        // Get current members root for validation
        bytes32 currentMembersRoot = LibOrganizationMembers.getMembersRoot();

        LibOrganizationAdmin.setAdmins({
            newAdminsRoot: newAdminsRoot,
            newAdminCount: newAdminCount,
            newVotingThreshold: newVotingThreshold,
            validation: adminValidation,
            currentMembersRoot: currentMembersRoot
        });
    }

    /**
     * @notice Rejects an admin operation by burning its nonce
     * @dev This allows admins to explicitly cancel a previously signed operation
     *      by consuming its nonce without executing the operation logic
     * @param operationType The type of admin operation to reject
     * @param operationData The ABI-encoded data of the operation
     * @param salt The user-provided salt for nonce computation
     * @param expirationTimestamp The timestamp after which the signatures are no longer valid
     * @param signatures The signatures from admin(s) authorizing this rejection
     * @param adminProofs The Merkle proofs for admin membership verification
     */
    function rejectAdminOperation(
        OperationType operationType,
        bytes calldata operationData,
        uint256 salt,
        uint256 expirationTimestamp,
        bytes memory signatures,
        LibOrganizationAdmin.AdminProofs calldata adminProofs
    ) external onlyGuardian {
        // Compute nonce for this operation
        uint256 nonce = LibOrganizationSignatures.computeNonce(operationType, operationData, salt);

        // Validate admin authorization and consume the nonce (isApproval = false for rejection)
        LibOrganizationAdmin.validateAdminAuthorizationOrRevert({
            operationType: operationType,
            operationData: operationData,
            salt: salt,
            expirationTimestamp: expirationTimestamp,
            isApproval: false,
            signatures: signatures,
            adminProofs: adminProofs
        });

        emit AdminOperationRejected(operationType, operationData, nonce);
    }

    function setGuardian(
        address newGuardian,
        uint256 salt,
        uint256 expirationTimestamp,
        bytes memory signatures,
        LibOrganizationAdmin.AdminProofs calldata adminProofs
    ) external onlyGuardian {
        // Encode the operation data for validation
        bytes memory operationData = abi.encode(newGuardian);

        // Validate that the current admin has authorized this operation (isApproval = true for execution)
        LibOrganizationAdmin.validateAdminAuthorizationOrRevert({
            operationType: OperationType.UpdateGuardian,
            operationData: operationData,
            salt: salt,
            expirationTimestamp: expirationTimestamp,
            isApproval: true,
            signatures: signatures,
            adminProofs: adminProofs
        });

        LibOrganizationGuardian.setGuardian(newGuardian);
    }

    /**
     * @notice Sets the account implementation address (upgrades all accounts at once)
     * @dev This function updates the implementation for all Account BeaconProxies
     * @param newImplementation The new implementation address
     * @param salt A user-provided salt for nonce computation
     * @param expirationTimestamp The timestamp after which the signatures are no longer valid
     * @param signatures The signatures from admin(s) authorizing this upgrade
     * @param adminProofs The Merkle proofs for admin membership verification
     */
    function setAccountImplementation(
        address newImplementation,
        uint256 salt,
        uint256 expirationTimestamp,
        bytes memory signatures,
        LibOrganizationAdmin.AdminProofs calldata adminProofs
    ) external onlyGuardian {
        // 1. Validate admin authorization (isApproval = true for execution)
        bytes memory operationData = abi.encode(newImplementation);
        LibOrganizationAdmin.validateAdminAuthorizationOrRevert({
            operationType: OperationType.UpgradeAccount,
            operationData: operationData,
            salt: salt,
            expirationTimestamp: expirationTimestamp,
            isApproval: true,
            signatures: signatures,
            adminProofs: adminProofs
        });

        // 2. Validate implementation against whitelist
        // forgefmt: disable-next-item
        IImplementationWhitelist(UpgradeAuthorizationStorage.layout().whitelistAddress)
            .validateIsImplementationWhitelistedOrRevert(
                IImplementationWhitelist.ContractType.Account, 
                newImplementation
            );

        // 3. Update the account implementation in storage
        LibOrganizationAccountFactoryStorage.layout().accountImplementation = newImplementation;

        emit AccountImplementationUpdated(newImplementation);
    }

    /**
     * @notice Deploys a new Account BeaconProxy at a deterministic address
     * @dev The account uses this Organization as its beacon
     * @param create2Salt The salt for CREATE2 deployment
     * @param adminSignatureSalt A user-provided salt for nonce computation
     * @param expirationTimestamp The timestamp after which the signatures are no longer valid
     * @param signatures The signatures from admin(s) authorizing this deployment
     * @param adminProofs The Merkle proofs for admin membership verification
     * @return The address of the deployed account proxy
     */
    function deployAccount(
        bytes32 create2Salt,
        uint256 adminSignatureSalt,
        uint256 expirationTimestamp,
        bytes memory signatures,
        LibOrganizationAdmin.AdminProofs calldata adminProofs
    ) external onlyGuardian returns (address) {
        // Validate admin authorization for account deployment
        bytes memory operationData = abi.encode(create2Salt);

        // isApproval = true for execution
        LibOrganizationAdmin.validateAdminAuthorizationOrRevert({
            operationType: OperationType.DeployAccount,
            operationData: operationData,
            salt: adminSignatureSalt,
            expirationTimestamp: expirationTimestamp,
            isApproval: true,
            signatures: signatures,
            adminProofs: adminProofs
        });

        return LibOrganizationAccountFactory.deployAccount(create2Salt);
    }

    /**
     * @notice Executes a transaction on an account through the organization
     * @dev Policy is verified via merkle proof in the proofs parameter
     * @param account The account to execute the transaction from
     * @param to The destination address of the transaction
     * @param value The value of the transaction
     * @param data The data of the transaction
     * @param salt A user-provided salt for nonce computation
     * @param expirationTimestamp The timestamp after which the signatures are no longer valid
     * @param policyId The ID of the policy that governs this transaction
     * @param signatures The signatures authorizing the transaction
     * @param proofs The validation proofs containing policy data and merkle proofs
     */
    function executeAccountTransaction(
        address account,
        address to,
        uint256 value,
        bytes calldata data,
        uint256 salt,
        uint256 expirationTimestamp,
        uint256 policyId,
        bytes memory signatures,
        Policies.ValidationProofs calldata proofs
    ) external onlyGuardian {
        // Verify the account is deployed by this organization
        if (!LibOrganizationAccountFactory.isAccountDeployedByOrganization(account)) {
            revert LibOrganizationAccountFactory.AccountNotDeployedByOrganization(account);
        }

        // Encode operation data for nonce computation
        bytes memory operationData = abi.encode(account, to, value, keccak256(data), policyId);

        // Compute nonce
        uint256 nonce = LibOrganizationSignatures.computeNonce(OperationType.AccountTransaction, operationData, salt);

        // Validate and consume nonce (will revert if already used)
        // REPLAY PROTECTION: Nonce is consumed BEFORE the external call to prevent reentrancy.
        LibOrganizationSignatures.validateAndConsumeNonceOrRevert(nonce);

        // Validate the transaction against the policy and signatures (with merkle proofs)
        LibOrganizationAccountTransaction.validateTransactionApprovalOrRevert({
            account: account,
            to: to,
            value: value,
            data: data,
            salt: salt,
            expirationTimestamp: expirationTimestamp,
            policyId: policyId,
            signatures: signatures,
            proofs: proofs
        });

        // Emit event before external call (CEI pattern) - if execution fails, transaction reverts
        emit AccountTransactionExecuted({
            account: account,
            to: to,
            value: value,
            data: data,
            nonce: nonce,
            policyId: policyId
        });

        // Execute the transaction on the account
        // forgefmt: disable-next-item
        IAccountExecute(account).executeTransaction({
            to: to,
            value: value, 
            data: data, 
            nonce: nonce, 
            policyId: policyId
        });
    }

    /**
     * @notice Rejects a transaction that has been signed but not yet executed
     * @dev Policy is verified via merkle proof in the proofs parameter
     * @param account The account for which to reject the transaction
     * @param to The destination address of the transaction
     * @param value The value of the transaction
     * @param data The data of the transaction
     * @param salt A user-provided salt for nonce computation
     * @param expirationTimestamp The timestamp after which the signatures are no longer valid
     * @param policyId The ID of the policy that governs this transaction
     * @param signatures The signatures authorizing the rejection
     * @param proofs The validation proofs containing policy data and merkle proofs
     */
    function rejectAccountTransaction(
        address account,
        address to,
        uint256 value,
        bytes calldata data,
        uint256 salt,
        uint256 expirationTimestamp,
        uint256 policyId,
        bytes memory signatures,
        Policies.ValidationProofs calldata proofs
    ) external onlyGuardian {
        // Verify the account is deployed by this organization
        if (!LibOrganizationAccountFactory.isAccountDeployedByOrganization(account)) {
            revert LibOrganizationAccountFactory.AccountNotDeployedByOrganization(account);
        }

        // Encode operation data for nonce computation (same as executeAccountTransaction)
        bytes memory operationData = abi.encode(account, to, value, keccak256(data), policyId);

        // Compute nonce (same as for execution)
        uint256 nonce = LibOrganizationSignatures.computeNonce(OperationType.AccountTransaction, operationData, salt);

        // Validate and consume nonce (will revert if already used)
        LibOrganizationSignatures.validateAndConsumeNonceOrRevert(nonce);

        // Validate the rejection authorization (with merkle proofs)
        LibOrganizationAccountTransaction.validateTransactionRejectionOrRevert({
            account: account,
            to: to,
            value: value,
            data: data,
            salt: salt,
            expirationTimestamp: expirationTimestamp,
            policyId: policyId,
            signatures: signatures,
            proofs: proofs
        });

        emit AccountTransactionRejected({
            account: account,
            to: to,
            value: value,
            data: data,
            nonce: nonce,
            policyId: policyId
        });
    }

    /**
     * @notice Upgrade the implementation to a new address with authorization
     * @param newImplementation The new implementation address
     * @param salt A user-provided salt for nonce computation
     * @param expirationTimestamp The timestamp after which the signatures are no longer valid
     * @param signatures The signatures from admin(s) authorizing this upgrade
     * @param adminProofs The Merkle proofs for admin membership verification
     */
    function upgradeToWithAuthorization(
        address newImplementation,
        uint256 salt,
        uint256 expirationTimestamp,
        bytes calldata signatures,
        LibOrganizationAdmin.AdminProofs calldata adminProofs
    ) external onlyGuardian {
        _validateOrganizationUpgrade({
            newImplementation: newImplementation,
            salt: salt,
            expirationTimestamp: expirationTimestamp,
            signatures: signatures,
            adminProofs: adminProofs
        });
        upgradeToAndCall(newImplementation, "");
    }

    /**
     * @notice Upgrade the implementation to a new address and call a function with authorization
     * @param newImplementation The new implementation address
     * @param data The calldata to call on the new implementation
     * @param salt A user-provided salt for nonce computation
     * @param expirationTimestamp The timestamp after which the signatures are no longer valid
     * @param signatures The signatures from admin(s) authorizing this upgrade
     * @param adminProofs The Merkle proofs for admin membership verification
     */
    function upgradeToAndCallWithAuthorization(
        address newImplementation,
        bytes memory data,
        uint256 salt,
        uint256 expirationTimestamp,
        bytes calldata signatures,
        LibOrganizationAdmin.AdminProofs calldata adminProofs
    ) external onlyGuardian {
        _validateOrganizationUpgrade({
            newImplementation: newImplementation,
            salt: salt,
            expirationTimestamp: expirationTimestamp,
            signatures: signatures,
            adminProofs: adminProofs
        });
        upgradeToAndCall(newImplementation, data);
    }

    /**
     * @notice Returns the current members merkle root
     * @return The members merkle root
     */
    function membersRoot() external view returns (bytes32) {
        return LibOrganizationMembers.getMembersRoot();
    }

    /**
     * @notice Verifies that an address is a member of the organization
     * @param memberAddress The address to verify
     * @param proof The merkle proof for the address
     * @return True if the address is a verified member, false otherwise
     */
    function isMemberInOrg(address memberAddress, bytes32[] calldata proof) external view returns (bool) {
        return LibOrganizationMembers.isMemberInOrg(memberAddress, proof);
    }

    /**
     * @notice Returns the current groups merkle root
     * @return The groups merkle root
     */
    function groupsRoot() external view returns (bytes32) {
        return LibOrganizationGroups.getGroupsRoot();
    }

    /**
     * @notice Verifies that a group exists in the organization
     * @param groupData The group data containing groupId and groupMembersRoot
     * @param groupInOrgGroupsTreeProof The merkle proof for the group
     * @return True if the group exists, false otherwise
     */
    function isGroupInOrg(Policies.GroupData calldata groupData, bytes32[] calldata groupInOrgGroupsTreeProof)
        external
        view
        returns (bool)
    {
        return LibOrganizationGroups.isGroupInOrg(groupData, groupInOrgGroupsTreeProof);
    }

    /**
     * @notice Verifies complete group membership (group exists AND member is in group)
     * @param memberAddress The address to verify
     * @param groupData The group data containing groupId and groupMembersRoot
     * @param groupInOrgGroupsTreeProof The merkle proof that the group exists
     * @param memberInGroupProof The merkle proof that the member is in the group
     * @return True if both verifications pass, false otherwise
     */
    function isMemberInGroupAndGroupInOrg(
        address memberAddress,
        Policies.GroupData calldata groupData,
        bytes32[] calldata groupInOrgGroupsTreeProof,
        bytes32[] calldata memberInGroupProof
    ) external view returns (bool) {
        return LibOrganizationGroups.isMemberInGroupAndGroupInOrg(
            memberAddress, groupData, groupInOrgGroupsTreeProof, memberInGroupProof
        );
    }

    /**
     * @notice Returns the current global policies merkle root
     * @return The policies merkle root
     */
    function policiesRoot() external view returns (bytes32) {
        return LibOrganizationPolicyStorage.layout().policiesRoot;
    }

    /**
     * @notice Gets the current usage for a time-based policy within the current time window
     * @param policyId The ID of the policy
     * @param policy The policy data (from calldata)
     * @param account The source account address
     * @param destination The destination address
     * @param initiator The initiator address
     * @param policyProof The merkle proof verifying the policy exists
     * @return The current usage amount within the current time window
     */
    function getPolicyUsage(
        uint256 policyId,
        Policies.Policy calldata policy,
        address account,
        address destination,
        address initiator,
        bytes32[] calldata policyProof
    ) external view returns (uint256) {
        // Verify policy exists in merkle tree
        if (!LibOrganizationPolicy.isPolicyInOrg(policyId, policy, policyProof)) {
            revert LibOrganizationPolicy.PolicyVerificationFailed(policyId);
        }

        return LibOrganizationPolicy.getCurrentUsage({
            policyId: policyId,
            policy: policy,
            account: account,
            destination: destination,
            initiator: initiator
        });
    }

    function adminPermission() external view returns (LibOrganizationAdminStorage.AdminPermission memory) {
        return LibOrganizationAdmin.getAdminPermission();
    }

    function isNonceUsed(uint256 nonce) external view returns (bool) {
        return LibOrganizationSignatures.isNonceUsed(nonce);
    }

    function computeNonce(OperationType operationType, bytes memory operationData, uint256 salt)
        external
        view
        returns (uint256)
    {
        return LibOrganizationSignatures.computeNonce(operationType, operationData, salt);
    }

    function enforceOnlyGuardian() external view {
        LibOrganizationGuardian.enforceOnlyGuardian();
    }

    function guardian() external view returns (address) {
        return LibOrganizationGuardian.getGuardian();
    }

    /**
     * @notice Returns the current implementation address for all Account BeaconProxies
     * @dev Required by IBeacon interface. Called by BeaconProxy to get the implementation.
     * @return The current account implementation address
     */
    function implementation() external view override returns (address) {
        address impl = LibOrganizationAccountFactoryStorage.layout().accountImplementation;
        if (impl == address(0)) {
            revert AccountImplementationNotSet();
        }
        return impl;
    }

    /**
     * @notice Computes the address where an account proxy would be deployed
     * @param salt The salt for CREATE2 deployment
     * @return The computed address
     */
    function computeAccountAddress(bytes32 salt) external view returns (address) {
        return LibOrganizationAccountFactory.computeAccountAddress(salt);
    }

    /**
     * @notice Validates an ERC-1271 signature for a given account
     * @dev This function is called by Account contracts to validate signatures.
     *      Policy is verified via merkle proof in the signature data.
     *      Note: Time-based policy limits are NOT supported for ERC-1271 signatures because the standard
     *      requires isValidSignature to be a view function (cannot modify storage to track usage).
     * @param account The account address on behalf of which the signature is being validated
     * @param hash The hash that was signed
     * @param signature The signature to validate (encoded with policyId, approver signatures, guardian signature,
     * proofs)
     * @return magicValue 0x1626ba7e if valid, 0xffffffff otherwise
     */
    function isValidSignatureForAccount(address account, bytes32 hash, bytes memory signature)
        external
        view
        override
        returns (bytes4 magicValue)
    {
        // Verify the caller is the account
        if (msg.sender != account) {
            revert LibOrganizationAccountFactory.AccountNotDeployedByOrganization(account);
        }

        // Verify the account is deployed by this organization
        if (!LibOrganizationAccountFactory.isAccountDeployedByOrganization(account)) {
            revert LibOrganizationAccountFactory.AccountNotDeployedByOrganization(account);
        }

        return LibOrganizationAccountSignature.isValidSignature(account, hash, signature);
    }

    function getDeployerAddress() external view returns (address) {
        return LibOrganizationInitialization.getDeployerAddress();
    }

    function isInitialized() external view returns (bool) {
        return LibOrganizationInitialization.isInitialized();
    }

    /**
     * @notice Validates organization upgrade authorization
     * @dev Checks admin signatures and implementation whitelist
     * @param newImplementation The new implementation address
     * @param salt A user-provided salt for nonce computation
     * @param expirationTimestamp The timestamp after which the signatures are no longer valid
     * @param signatures The signatures from admin(s) authorizing this upgrade
     * @param adminProofs The Merkle proofs for admin membership verification
     */
    function _validateOrganizationUpgrade(
        address newImplementation,
        uint256 salt,
        uint256 expirationTimestamp,
        bytes calldata signatures,
        LibOrganizationAdmin.AdminProofs calldata adminProofs
    ) internal {
        // 1. Validate admin authorization (isApproval = true for execution)
        bytes memory operationData = abi.encode(newImplementation);
        LibOrganizationAdmin.validateAdminAuthorizationOrRevert({
            operationType: OperationType.Upgrade,
            operationData: operationData,
            salt: salt,
            expirationTimestamp: expirationTimestamp,
            isApproval: true,
            signatures: signatures,
            adminProofs: adminProofs
        });

        // 2. Validate implementation against whitelist
        IImplementationWhitelist(UpgradeAuthorizationStorage.layout().whitelistAddress)
            .validateIsImplementationWhitelistedOrRevert(
            IImplementationWhitelist.ContractType.Organization, newImplementation
        );
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
