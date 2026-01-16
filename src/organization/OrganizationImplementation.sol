// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

import {IAccount} from "interfaces/IAccount.sol";
import {IImplementationWhitelist} from "interfaces/IImplementationWhitelist.sol";
import {IOrganization} from "interfaces/IOrganization.sol";
import {LibOrganizationUpgradeStorage} from "organization/libraries/storage/LibOrganizationUpgradeStorage.sol";

// Types
import {AdminAuthParams, AdminConfig, AllAdminsInOrgProofs} from "types/AdminTypes.sol";
import {ContractType, InitializationParams, OperationType} from "types/CommonTypes.sol";
import {GroupData, Policy, ValidationProofs} from "types/PolicyTypes.sol";

// Libraries
import {LibOrganizationAccountFactory} from "organization/libraries/LibOrganizationAccountFactory.sol";
import {LibOrganizationAccountSignature} from "organization/libraries/LibOrganizationAccountSignature.sol";
import {LibOrganizationAccountTransaction} from "organization/libraries/LibOrganizationAccountTransaction.sol";
import {LibOrganizationAdmin} from "organization/libraries/LibOrganizationAdmin.sol";
import {LibOrganizationGroups} from "organization/libraries/LibOrganizationGroups.sol";
import {LibOrganizationGuardian} from "organization/libraries/LibOrganizationGuardian.sol";
import {LibOrganizationGuardianRecovery} from "organization/libraries/LibOrganizationGuardianRecovery.sol";
import {LibOrganizationInitialization} from "organization/libraries/LibOrganizationInitialization.sol";
import {LibOrganizationMembers} from "organization/libraries/LibOrganizationMembers.sol";
import {LibOrganizationPolicy} from "organization/libraries/LibOrganizationPolicy.sol";
import {LibOrganizationSignatures} from "organization/libraries/LibOrganizationSignatures.sol";
import {LibOrganizationTxRecovery} from "organization/libraries/LibOrganizationTxRecovery.sol";
import {
    LibOrganizationAccountFactoryStorage
} from "organization/libraries/storage/LibOrganizationAccountFactoryStorage.sol";
import {LibOrganizationPolicyStorage} from "organization/libraries/storage/LibOrganizationPolicyStorage.sol";

/**
 * @title Organization Implementation
 * @notice UUPS upgradeable implementation contract for Organization that also acts as a Beacon for Account proxies
 * @dev Policies, Members, and Groups are all stored as Merkle trees. Only the roots are stored on-chain.
 *      Full data is provided via calldata and verified against the roots.
 * @author Den Technologies Inc
 */
contract OrganizationImplementation is UUPSUpgradeable, Initializable, IOrganization {
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
     * @notice Modifier that enforces only the transaction recovery address can call the function
     */
    modifier onlyTxRecoveryAddress() {
        LibOrganizationTxRecovery.enforceOnlyTxRecoveryAddress();
        _;
    }

    /**
     * @notice Modifier that enforces only the guardian recovery address can call the function
     */
    modifier onlyGuardianRecoveryAddress() {
        LibOrganizationGuardianRecovery.enforceOnlyGuardianRecoveryAddress();
        _;
    }

    /**
     * @notice Modifier that enforces only the pending guardian can call the function
     */
    modifier onlyPendingGuardian() {
        LibOrganizationGuardian.enforceOnlyPendingGuardian();
        _;
    }

    /**
     * @notice Modifier that enforces only the recovery pending guardian can call the function
     */
    modifier onlyRecoveryPendingGuardian() {
        LibOrganizationGuardianRecovery.enforceOnlyRecoveryPendingGuardian();
        _;
    }

    /**
     * @notice Initialize the organization implementation with Merkle-based members and groups
     * @param params The initialization parameters struct containing all required configuration
     */
    function initialize(InitializationParams calldata params) external override initializer onlyDeployer {
        LibOrganizationInitialization.initialize(params);
    }

    /**
     * @notice Sets the admin permissions for the organization
     * @dev Validates that all new admins are current members before updating.
     * @param newAdminsRoot The new merkle root of admin addresses
     * @param newAdminCount The number of admins in the new tree
     * @param newVotingThreshold The new voting threshold
     * @param authParams The authorization parameters (salt, expiration, signatures, and admin proofs)
     * @param newAdminsInOrgProofs Proofs that all new admins are in the organization (admin tree and members tree)
     */
    function setAdmins(
        bytes32 newAdminsRoot,
        uint256 newAdminCount,
        uint256 newVotingThreshold,
        AdminAuthParams calldata authParams,
        AllAdminsInOrgProofs calldata newAdminsInOrgProofs
    ) external override onlyGuardian {
        // Encode the operation data for validation
        bytes memory operationData = abi.encode(newAdminsRoot, newAdminCount, newVotingThreshold);

        // Validate that the current admin has authorized this change (isApproval = true for execution)
        LibOrganizationAdmin.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins,
            operationData: operationData,
            isApproval: true,
            authParams: authParams
        });

        // Get current members root for validation
        bytes32 currentMembersRoot = LibOrganizationMembers.getMembersRoot();

        LibOrganizationAdmin.setAdmins({
            newAdminsRoot: newAdminsRoot,
            newAdminCount: newAdminCount,
            newVotingThreshold: newVotingThreshold,
            newAdminsInOrgProofs: newAdminsInOrgProofs,
            currentMembersRoot: currentMembersRoot
        });
    }

    /**
     * @notice Initiates a guardian update (starts timelock)
     * @dev Can only be called by the current guardian with admin authorization.
     *      After timelock expires, finalizeGuardianUpdate must be called, then the new guardian must call
     * acceptGuardian.
     * @param newGuardian The proposed new guardian address
     * @param authParams The authorization parameters (salt, expiration, signatures, and admin proofs)
     */
    function initiateGuardianUpdate(address newGuardian, AdminAuthParams calldata authParams)
        external
        override
        onlyGuardian
    {
        // Encode the operation data for validation
        bytes memory operationData = abi.encode(newGuardian);

        // Validate that the current admin has authorized this operation (isApproval = true for execution)
        LibOrganizationAdmin.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.UpdateGuardian,
            operationData: operationData,
            isApproval: true,
            authParams: authParams
        });

        LibOrganizationGuardian.initiateGuardianUpdate(newGuardian);
    }

    /**
     * @notice Finalizes a guardian update (after timelock, ready for new guardian to accept)
     * @dev Can only be called by the current guardian with admin authorization after timelock expires.
     * @param authParams The authorization parameters (salt, expiration, signatures, and admin proofs)
     */
    function finalizeGuardianUpdate(AdminAuthParams calldata authParams) external override onlyGuardian {
        // Get pending guardian for operation data
        address pendingGuardianAddr = LibOrganizationGuardian.getPendingGuardian();

        // Encode the operation data for validation (same as initiate)
        bytes memory operationData = abi.encode(pendingGuardianAddr);

        // Validate that the current admin has authorized this operation
        LibOrganizationAdmin.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.UpdateGuardian,
            operationData: operationData,
            isApproval: true,
            authParams: authParams
        });

        LibOrganizationGuardian.finalizeGuardianUpdate();
    }

    /**
     * @notice Cancels a pending guardian update
     * @dev Can only be called by the current guardian with admin authorization.
     * @param authParams The authorization parameters (salt, expiration, signatures, and admin proofs)
     */
    function cancelGuardianUpdate(AdminAuthParams calldata authParams) external override onlyGuardian {
        // Get pending guardian for operation data
        address pendingGuardianAddr = LibOrganizationGuardian.getPendingGuardian();

        // Encode the operation data for validation
        bytes memory operationData = abi.encode(pendingGuardianAddr);

        // Validate that the current admin has authorized this operation (isApproval = false for cancellation)
        LibOrganizationAdmin.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.UpdateGuardian,
            operationData: operationData,
            isApproval: false,
            authParams: authParams
        });

        LibOrganizationGuardian.cancelGuardianUpdate();
    }

    /**
     * @notice Accepts the guardian role (completes the update)
     * @dev Can only be called by the pending guardian after the update has been finalized.
     */
    function acceptGuardian() external override onlyPendingGuardian {
        LibOrganizationGuardian.acceptGuardian();
    }

    /**
     * @notice Rejects an admin operation by burning its nonce
     * @dev This allows admins to explicitly cancel a previously signed operation
     *      by consuming its nonce without executing the operation logic
     * @param operationType The type of admin operation to reject
     * @param operationData The ABI-encoded data of the operation
     * @param authParams The authorization parameters (salt, expiration, signatures, and admin proofs)
     */
    function rejectAdminOperation(
        OperationType operationType,
        bytes calldata operationData,
        AdminAuthParams calldata authParams
    ) external override onlyGuardian {
        // Compute nonce for this operation
        uint256 nonce = LibOrganizationSignatures.computeNonce(operationType, operationData, authParams.salt);

        // Validate admin authorization and consume the nonce (isApproval = false for rejection)
        LibOrganizationAdmin.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: operationType, operationData: operationData, isApproval: false, authParams: authParams
        });

        emit AdminOperationRejected(operationType, operationData, nonce);
    }

    /**
     * @notice Updates the global members merkle root
     * @dev This is the only way to set members. All member data is stored off-chain (IPFS).
     *      Validates that all admins remain members in the new tree to prevent bricking.
     * @param newMembersRoot The new merkle root containing all members
     * @param ipfsCid The IPFS CID where full member data is stored for disaster recovery
     * @param authParams The authorization parameters (salt, expiration, signatures, and admin proofs)
     * @param allAdminsInOrgProofs Proofs that all admins are in the new members tree
     */
    function setMembers(
        bytes32 newMembersRoot,
        string calldata ipfsCid,
        AdminAuthParams calldata authParams,
        AllAdminsInOrgProofs calldata allAdminsInOrgProofs
    ) external override onlyGuardian {
        // Encode the operation data for validation
        bytes memory operationData = abi.encode(newMembersRoot, keccak256(bytes(ipfsCid)));

        // Validate that the current admin has authorized this operation (isApproval = true for execution)
        LibOrganizationAdmin.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyMembers,
            operationData: operationData,
            isApproval: true,
            authParams: authParams
        });

        LibOrganizationMembers.setMembers(newMembersRoot, ipfsCid, allAdminsInOrgProofs);
    }

    /**
     * @notice Updates the global groups merkle root
     * @dev This is the only way to set groups. All group data is stored off-chain (IPFS).
     * @param newGroupsRoot The new merkle root containing all groups
     * @param ipfsCid The IPFS CID where full group data is stored for disaster recovery
     * @param authParams The authorization parameters (salt, expiration, signatures, and admin proofs)
     */
    function setGroups(bytes32 newGroupsRoot, string calldata ipfsCid, AdminAuthParams calldata authParams)
        external
        override
        onlyGuardian
    {
        // Encode the operation data for validation
        bytes memory operationData = abi.encode(newGroupsRoot, keccak256(bytes(ipfsCid)));

        // Validate that the current admin has authorized this operation (isApproval = true for execution)
        LibOrganizationAdmin.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyGroups,
            operationData: operationData,
            isApproval: true,
            authParams: authParams
        });

        LibOrganizationGroups.setGroups(newGroupsRoot, ipfsCid);
    }

    /**
     * @notice Updates the global policies merkle root
     * @dev This is the only way to set policies. All policy data is stored off-chain (IPFS).
     * @param newPoliciesRoot The new merkle root containing all policies
     * @param ipfsCid The IPFS CID where full policy data is stored for disaster recovery
     * @param authParams The authorization parameters (salt, expiration, signatures, and admin proofs)
     */
    function setPolicies(bytes32 newPoliciesRoot, string calldata ipfsCid, AdminAuthParams calldata authParams)
        external
        override
        onlyGuardian
    {
        // Encode the operation data for validation
        bytes memory operationData = abi.encode(newPoliciesRoot, keccak256(bytes(ipfsCid)));

        // Validate that the current admin has authorized this operation (isApproval = true for execution)
        LibOrganizationAdmin.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyPolicies,
            operationData: operationData,
            isApproval: true,
            authParams: authParams
        });

        LibOrganizationPolicy.setPolicies(newPoliciesRoot, ipfsCid);
    }

    /**
     * @notice Deploys a new Account BeaconProxy at a deterministic address
     * @dev The account uses this Organization as its beacon
     * @param create2Salt The salt for CREATE2 deployment
     * @param authParams The authorization parameters (salt, expiration, signatures, and admin proofs)
     * @return The address of the deployed account proxy
     */
    function deployAccount(bytes32 create2Salt, AdminAuthParams calldata authParams)
        external
        override
        onlyGuardian
        returns (address)
    {
        // Validate admin authorization for account deployment
        bytes memory operationData = abi.encode(create2Salt);

        // isApproval = true for execution
        LibOrganizationAdmin.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.DeployAccount,
            operationData: operationData,
            isApproval: true,
            authParams: authParams
        });

        return LibOrganizationAccountFactory.deployAccount(create2Salt);
    }

    /**
     * @notice Sets the account implementation address (upgrades all accounts at once)
     * @dev This function updates the implementation for all Account BeaconProxies
     * @param newImplementation The new implementation address
     * @param authParams The authorization parameters (salt, expiration, signatures, and admin proofs)
     */
    function setAccountImplementation(address newImplementation, AdminAuthParams calldata authParams)
        external
        override
        onlyGuardian
    {
        // 1. Validate admin authorization (isApproval = true for execution)
        bytes memory operationData = abi.encode(newImplementation);
        LibOrganizationAdmin.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.UpgradeAccount,
            operationData: operationData,
            isApproval: true,
            authParams: authParams
        });

        // 2. Validate implementation against whitelist
        // forgefmt: disable-next-item
        IImplementationWhitelist(LibOrganizationUpgradeStorage.layout().whitelistAddress)
            .validateIsImplementationWhitelistedOrRevert(
                ContractType.Account, 
                newImplementation
            );

        // 3. Update the account implementation in storage
        LibOrganizationAccountFactoryStorage.layout().accountImplementation = newImplementation;

        emit AccountImplementationUpdated(newImplementation);
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
        bytes calldata signatures,
        ValidationProofs calldata proofs
    ) external override onlyGuardian {
        // Verify the account is deployed by this organization
        LibOrganizationAccountFactory.validateIsAccountDeployedByOrgOrRevert(account);

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
            account: account, to: to, value: value, data: data, nonce: nonce, policyId: policyId
        });

        // Execute the transaction on the account
        // forgefmt: disable-next-item
        IAccount(payable(account)).executeTransaction({
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
        bytes calldata signatures,
        ValidationProofs calldata proofs
    ) external override onlyGuardian {
        // Verify the account is deployed by this organization
        LibOrganizationAccountFactory.validateIsAccountDeployedByOrgOrRevert(account);

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
            account: account, to: to, value: value, data: data, nonce: nonce, policyId: policyId
        });
    }

    /**
     * @notice Upgrade the organization implementation to a new address and optionally call a function
     * @dev This is the ONLY authorized way to upgrade this contract. Direct calls to the inherited
     *      `upgradeToAndCall` function will revert with `UnauthorizedUpgrade`.
     *
     *      SECURITY MODEL:
     *      1. Guardian must submit the transaction (onlyGuardian modifier)
     *      2. Admin(s) must have signed the upgrade (validated via LibOrganizationAdmin)
     *      3. New implementation must be on the whitelist (validated via IImplementationWhitelist)
     *      4. A storage flag is set to authorize the subsequent _authorizeUpgrade call
     *      5. The flag is reset after the upgrade completes (or if it reverts, the tx reverts entirely)
     *
     *      WHY THE AUTHORIZATION FLAG?
     *      OpenZeppelin's UUPSUpgradeable exposes a public `upgradeToAndCall` function that anyone
     *      can call. The authorization is supposed to happen in `_authorizeUpgrade`, but that hook
     *      only receives `newImplementation` - not our signatures/proofs. So we:
     *      1. Validate everything here (guardian, signatures, whitelist)
     *      2. Set a flag to signal "upgrade is authorized"
     *      3. Call the inherited upgradeToAndCall
     *      4. _authorizeUpgrade checks the flag and reverts if not set
     *      5. Reset the flag after completion
     *
     *      The flag is safe because:
     *      - It's set AFTER validation passes
     *      - If upgradeToAndCall reverts, the entire transaction reverts (flag never persists)
     *      - We explicitly reset it after success as defense-in-depth
     *
     * @param newImplementation The new implementation address (must be whitelisted)
     * @param data Optional calldata to execute on the new implementation after upgrade.
     *             Pass empty bytes ("") if no post-upgrade call is needed.
     * @param authParams The authorization parameters (salt, expiration, signatures, and admin proofs)
     */
    function upgradeToAndCallWithAuthorization(
        address newImplementation,
        bytes calldata data,
        AdminAuthParams calldata authParams
    ) external override onlyGuardian {
        // Validate admin authorization (isApproval = true for execution)
        bytes memory operationData = abi.encode(newImplementation);
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

        // Set authorization flag in namespaced storage
        // This flag tells _authorizeUpgrade that we've done proper validation.
        // Using EIP-7201 namespaced storage to prevent slot collisions during upgrades.
        LibOrganizationUpgradeStorage.layout().isUpgradeAuthorized = true;

        // Perform the upgrade
        // This calls the inherited UUPSUpgradeable.upgradeToAndCall which will:
        // 1. Call _authorizeUpgrade (which checks our flag)
        // 2. Upgrade the implementation
        // 3. Optionally call `data` on the new implementation
        upgradeToAndCall(newImplementation, data);

        // Reset the flag (defense-in-depth)
        // Even though the flag can't persist if the tx reverts, we reset it explicitly
        // as a security best practice. This also protects against any theoretical
        // scenario where the flag might persist.
        LibOrganizationUpgradeStorage.layout().isUpgradeAuthorized = false;
    }

    /**
     * @notice Initiates enabling transaction and ERC1271 recovery (starts timelock)
     * @dev Can only be called by the transaction recovery address.
     */
    function initiateEnableTransactionAndERC1271Recovery() external override onlyTxRecoveryAddress {
        LibOrganizationTxRecovery.initiateEnableTxRecovery();
    }

    /**
     * @notice Finalizes enabling transaction and ERC1271 recovery (after timelock)
     * @dev Can only be called by the transaction recovery address after timelock expires.
     */
    function finalizeEnableTransactionAndERC1271Recovery() external override onlyTxRecoveryAddress {
        LibOrganizationTxRecovery.finalizeEnableTxRecovery();
    }

    /**
     * @notice Cancels a pending transaction and ERC1271 recovery enable
     * @dev Can only be called by the transaction recovery address.
     */
    function cancelEnableTransactionAndERC1271Recovery() external override onlyTxRecoveryAddress {
        LibOrganizationTxRecovery.cancelEnableTxRecovery();
    }

    /**
     * @notice Immediately disables transaction and ERC1271 recovery
     * @dev Can only be called by the transaction recovery address. No timelock required.
     *      Also cancels any pending enable request, even if the timelock has already expired.
     *      This ensures recovery is fully disabled.
     */
    function disableTransactionAndERC1271Recovery() external override onlyTxRecoveryAddress {
        LibOrganizationTxRecovery.disableTxRecovery();
    }

    /**
     * @notice Executes an account transaction via recovery (bypassing guardian and policy checks)
     * @dev Can only be called by the transaction recovery address.
     *      Recovery must be both supported AND enabled.
     * @param account The account to execute the transaction from
     * @param to The destination address
     * @param value The ETH value to send
     * @param data The transaction calldata
     */
    function executeRecoveryAccountTransaction(address account, address to, uint256 value, bytes calldata data)
        external
        override
        onlyTxRecoveryAddress
    {
        // Validate recovery is allowed
        LibOrganizationTxRecovery.validateRecoveryAccountTransactionAllowedOrRevert();

        // Verify the account is deployed by this organization
        LibOrganizationAccountFactory.validateIsAccountDeployedByOrgOrRevert(account);

        // Emit event before external call (CEI pattern)
        emit RecoveryAccountTransactionExecuted(account, to, value, data);

        // Execute the transaction on the account (using nonce=0 and policyId=0 for recovery)
        IAccount(payable(account)).executeTransaction({to: to, value: value, data: data, nonce: 0, policyId: 0});
    }

    /**
     * @notice Initiates a recovery guardian update (starts timelock)
     * @dev Can only be called by the guardian recovery address.
     * @param newGuardian The proposed new guardian address
     */
    function initiateRecoveryGuardianUpdate(address newGuardian) external override onlyGuardianRecoveryAddress {
        LibOrganizationGuardianRecovery.initiateRecoveryGuardianUpdate(newGuardian);
    }

    /**
     * @notice Finalizes a recovery guardian update (after timelock, ready for new guardian to accept)
     * @dev Can only be called by the guardian recovery address after timelock expires.
     */
    function finalizeRecoveryGuardianUpdate() external override onlyGuardianRecoveryAddress {
        LibOrganizationGuardianRecovery.finalizeRecoveryGuardianUpdate();
    }

    /**
     * @notice Cancels a pending recovery guardian update
     * @dev Can only be called by the guardian recovery address.
     */
    function cancelRecoveryGuardianUpdate() external override onlyGuardianRecoveryAddress {
        LibOrganizationGuardianRecovery.cancelRecoveryGuardianUpdate();
    }

    /**
     * @notice Accepts the guardian role via recovery (completes the recovery update)
     * @dev Can only be called by the recovery pending guardian after the update has been finalized.
     */
    function acceptGuardianRecovery() external override onlyRecoveryPendingGuardian {
        LibOrganizationGuardianRecovery.acceptGuardianRecovery();
    }

    /**
     * @notice Returns the address that deployed this organization
     * @return The deployer address
     */
    function getDeployerAddress() external view override returns (address) {
        return LibOrganizationInitialization.getDeployerAddress();
    }

    /**
     * @notice Checks if the organization has been initialized
     * @return True if initialized, false otherwise
     */
    function isInitialized() external view override returns (bool) {
        return LibOrganizationInitialization.isInitialized();
    }

    /**
     * @notice Returns the current admin permission settings for the organization
     * @return The admin permission configuration including admins root, count, and voting threshold
     */
    function adminConfig() external view override returns (AdminConfig memory) {
        return LibOrganizationAdmin.getAdminConfig();
    }

    /**
     * @notice Returns the current guardian address
     * @return The address of the guardian
     */
    function guardian() external view override returns (address) {
        return LibOrganizationGuardian.getGuardian();
    }

    /**
     * @notice Returns the pending guardian address
     * @return The address of the pending guardian (zero if no pending update)
     */
    function pendingGuardian() external view override returns (address) {
        return LibOrganizationGuardian.getPendingGuardian();
    }

    /**
     * @notice Returns the timestamp when the pending guardian update can be finalized
     * @return The timestamp (0 if no pending update)
     */
    function pendingGuardianUpdateTimestamp() external view override returns (uint256) {
        return LibOrganizationGuardian.getPendingGuardianUpdateTimestamp();
    }

    /**
     * @notice Returns whether the guardian update is ready for acceptance (normal flow)
     * @return True if the update has been finalized and is waiting for the new guardian to accept
     */
    function isGuardianUpdateReadyForAcceptance() external view override returns (bool) {
        return LibOrganizationGuardian.getIsGuardianUpdateReadyForAcceptance();
    }

    /**
     * @notice Returns the guardian timelock duration in seconds
     * @return The timelock duration
     */
    function guardianTimelockDuration() external view override returns (uint256) {
        return LibOrganizationGuardian.getGuardianTimelockDuration();
    }

    /**
     * @notice Returns whether recovery is supported for transactions and ERC1271 signatures
     * @return True if recovery is supported, false otherwise
     */
    function isRecoverySupportedForTransactionsAndERC1271() external view override returns (bool) {
        return LibOrganizationTxRecovery.isRecoverySupportedForTxAndERC1271();
    }

    /**
     * @notice Returns whether recovery is enabled for transactions and ERC1271 signatures
     * @return True if recovery is enabled, false otherwise
     */
    function isRecoveryEnabledForTransactionsAndERC1271() external view override returns (bool) {
        return LibOrganizationTxRecovery.isRecoveryEnabledForTxAndERC1271();
    }

    /**
     * @notice Returns the transaction and ERC1271 recovery address
     * @return The recovery address
     */
    function transactionAndERC1271RecoveryAddress() external view override returns (address) {
        return LibOrganizationTxRecovery.getTxRecoveryAddress();
    }

    /**
     * @notice Returns the guardian recovery address
     * @return The recovery address
     */
    function guardianRecoveryAddress() external view override returns (address) {
        return LibOrganizationGuardianRecovery.getGuardianRecoveryAddress();
    }

    /**
     * @notice Returns the guardian recovery timelock duration in seconds
     * @return The timelock duration
     */
    function guardianRecoveryTimelockDuration() external view override returns (uint256) {
        return LibOrganizationGuardianRecovery.getGuardianRecoveryTimelockDuration();
    }

    /**
     * @notice Returns the timestamp when pending tx recovery enable can be finalized
     * @return The timestamp (0 if no pending request)
     */
    function pendingTxRecoveryEnableTimestamp() external view override returns (uint256) {
        return LibOrganizationTxRecovery.getPendingTxRecoveryEnableTimestamp();
    }

    /**
     * @notice Returns the tx recovery timelock duration in seconds
     * @return The timelock duration
     */
    function txRecoveryTimelockDuration() external view override returns (uint256) {
        return LibOrganizationTxRecovery.getTxRecoveryTimelockDuration();
    }

    /**
     * @notice Returns the recovery pending guardian address
     * @return The pending guardian address (zero if no pending recovery update)
     */
    function recoveryPendingGuardian() external view override returns (address) {
        return LibOrganizationGuardianRecovery.getRecoveryPendingGuardian();
    }

    /**
     * @notice Returns the recovery pending guardian timestamp
     * @return The timestamp when the recovery update can be finalized (0 if no pending)
     */
    function recoveryPendingGuardianTimestamp() external view override returns (uint256) {
        return LibOrganizationGuardianRecovery.getRecoveryPendingGuardianTimestamp();
    }

    /**
     * @notice Returns whether the recovery guardian update is ready for acceptance
     * @return True if the recovery update has been finalized and is waiting for the new guardian to accept
     */
    function isRecoveryGuardianUpdateReadyForAcceptance() external view override returns (bool) {
        return LibOrganizationGuardianRecovery.getIsRecoveryGuardianUpdateReadyForAcceptance();
    }

    /**
     * @notice Returns the current members merkle root
     * @return The members merkle root
     */
    function membersRoot() external view override returns (bytes32) {
        return LibOrganizationMembers.getMembersRoot();
    }

    /**
     * @notice Verifies that an address is a member of the organization
     * @param memberAddress The address to verify
     * @param proof The merkle proof for the address
     * @return True if the address is a verified member, false otherwise
     */
    function isMemberInOrg(address memberAddress, bytes32[] calldata proof) external view override returns (bool) {
        return LibOrganizationMembers.isMemberInOrg(memberAddress, proof);
    }

    /**
     * @notice Returns the current groups merkle root
     * @return The groups merkle root
     */
    function groupsRoot() external view override returns (bytes32) {
        return LibOrganizationGroups.getGroupsRoot();
    }

    /**
     * @notice Verifies that a group exists in the organization
     * @param groupData The group data containing groupId and groupMembersRoot
     * @param groupInOrgGroupsTreeProof The merkle proof for the group
     * @return True if the group exists, false otherwise
     */
    function isGroupInOrg(GroupData calldata groupData, bytes32[] calldata groupInOrgGroupsTreeProof)
        external
        view
        override
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
        GroupData calldata groupData,
        bytes32[] calldata groupInOrgGroupsTreeProof,
        bytes32[] calldata memberInGroupProof
    ) external view override returns (bool) {
        return LibOrganizationGroups.isMemberInGroupAndGroupInOrg(
            memberAddress, groupData, groupInOrgGroupsTreeProof, memberInGroupProof
        );
    }

    /**
     * @notice Returns the current global policies merkle root
     * @return The policies merkle root
     */
    function policiesRoot() external view override returns (bytes32) {
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
        Policy calldata policy,
        address account,
        address destination,
        address initiator,
        bytes32[] calldata policyProof
    ) external view override returns (uint256) {
        // Verify policy exists in merkle tree
        if (!LibOrganizationPolicy.isPolicyInOrg(policyId, policy, policyProof)) {
            revert PolicyVerificationFailed(policyId);
        }

        return LibOrganizationPolicy.getCurrentUsage({
            policyId: policyId, policy: policy, account: account, destination: destination, initiator: initiator
        });
    }

    /**
     * @notice Checks if a nonce has already been used
     * @param nonce The nonce to check
     * @return True if the nonce has been used, false otherwise
     */
    function isNonceUsed(uint256 nonce) external view override returns (bool) {
        return LibOrganizationSignatures.isNonceUsed(nonce);
    }

    /**
     * @notice Computes the nonce for a given operation
     * @param operationType The type of operation being performed
     * @param operationData The ABI-encoded data of the operation
     * @param salt A user-provided salt for nonce computation
     * @return The computed nonce
     */
    function computeNonce(OperationType operationType, bytes calldata operationData, uint256 salt)
        external
        view
        override
        returns (uint256)
    {
        return LibOrganizationSignatures.computeNonce(operationType, operationData, salt);
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
    function computeAccountAddress(bytes32 salt) external view override returns (address) {
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
    function isValidSignatureForAccount(address account, bytes32 hash, bytes calldata signature)
        external
        view
        override
        returns (bytes4 magicValue)
    {
        // Verify the caller is the account
        if (msg.sender != account) {
            revert AccountNotDeployedByOrganization(account);
        }

        // Verify the account is deployed by this organization
        LibOrganizationAccountFactory.validateIsAccountDeployedByOrgOrRevert(account);

        return LibOrganizationAccountSignature.isValidSignature(account, hash, signature);
    }

    /**
     * @notice Authorize an upgrade (required by UUPSUpgradeable)
     * @dev This function is called by the inherited `upgradeToAndCall` function from UUPSUpgradeable.
     *      It acts as a gatekeeper to ensure upgrades only happen through our authorized flow.
     *
     *      SECURITY EXPLANATION:
     *      OpenZeppelin's UUPSUpgradeable exposes a public `upgradeToAndCall(address, bytes)` function.
     *      Without protection, an attacker could call this directly on the proxy, bypassing:
     *      - Guardian check (onlyGuardian modifier)
     *      - Admin signature validation
     *      - Implementation whitelist check
     *
     *      Our solution uses a storage flag at a namespaced slot (EIP-7201):
     *      - `upgradeToAndCallWithAuthorization` sets the flag AFTER validating everything
     *      - This function checks that the flag is set
     *      - Direct calls to `upgradeToAndCall` will not have the flag set → revert
     *
     *      WHY NAMESPACED STORAGE (EIP-7201)?
     *      - Prevents storage slot collisions when upgrading contracts
     *      - Safe even if new state variables are added in future implementations
     *
     *      WHY REGULAR STORAGE (not transient)?
     *      We use regular storage instead of EIP-1153 transient storage for maximum EVM chain
     *      compatibility. This allows deployment to chains that haven't adopted the Cancun upgrade.
     *      The flag is explicitly reset after the upgrade completes as defense-in-depth.
     *
     * @param newImplementation The new implementation address (unused - validation already done)
     */
    function _authorizeUpgrade(address newImplementation) internal view override {
        // Silence unused variable warning - validation was already performed in
        // upgradeToAndCallWithAuthorization before setting the authorization flag
        (newImplementation);

        // Check the authorization flag from namespaced storage
        // If this is false, it means someone called upgradeToAndCall directly without
        // going through upgradeToAndCallWithAuthorization
        if (!LibOrganizationUpgradeStorage.layout().isUpgradeAuthorized) {
            revert UnauthorizedUpgrade();
        }
    }
}
