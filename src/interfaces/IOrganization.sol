// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Module interfaces (spokes)
import {IOrganizationAdmin} from "./organization/IOrganizationAdmin.sol";
import {IOrganizationMembers} from "./organization/IOrganizationMembers.sol";
import {IOrganizationGroups} from "./organization/IOrganizationGroups.sol";
import {IOrganizationPolicy} from "./organization/IOrganizationPolicy.sol";
import {IOrganizationGuardian} from "./organization/IOrganizationGuardian.sol";
import {IOrganizationAccountFactory} from "./organization/IOrganizationAccountFactory.sol";
import {IOrganizationAccountTransaction} from "./organization/IOrganizationAccountTransaction.sol";
import {IOrganizationSignatures} from "./organization/IOrganizationSignatures.sol";
import {IOrganizationInitialization} from "./organization/IOrganizationInitialization.sol";

// Types
import {AdminAuthParams} from "../types/AdminTypes.sol";

// Re-export types for backward compatibility
// solhint-disable-next-line no-unused-import
import {OperationType, InitializationParams} from "../types/CommonTypes.sol";

/**
 * @title IOrganizationSignatureValidator
 * @notice Interface for validating ERC-1271 signatures on behalf of accounts
 * @author Den Technologies Inc
 */
interface IOrganizationSignatureValidator {
    /**
     * @notice Validates an ERC-1271 signature for a given account
     * @dev Note: Time-based policy limits are NOT supported for ERC-1271 signatures because the standard
     *      requires isValidSignature to be a view function (cannot modify storage to track usage).
     * @param account The account address on behalf of which the signature is being validated
     * @param hash The hash that was signed
     * @param signature The signature to validate (encoded with policyId, approver signatures, guardian signature)
     * @return magicValue 0x1626ba7e if valid, 0xffffffff otherwise
     */
    function isValidSignatureForAccount(address account, bytes32 hash, bytes calldata signature)
        external
        view
        returns (bytes4 magicValue);
}

/**
 * @title IOrganization
 * @notice Hub interface that aggregates all Organization module interfaces
 * @dev This is a composite interface that inherits from all module interfaces.
 *      Each module interface maps 1:1 to a library for easy auditor navigation.
 *      The hub itself contains only functions that don't belong to any specific module.
 * @author Den Technologies Inc
 */
interface IOrganization is
    IOrganizationAdmin,
    IOrganizationMembers,
    IOrganizationGroups,
    IOrganizationPolicy,
    IOrganizationGuardian,
    IOrganizationAccountFactory,
    IOrganizationAccountTransaction,
    IOrganizationSignatures,
    IOrganizationInitialization,
    IOrganizationSignatureValidator
{
    // ═══════════════════════════════════════════════════════════════════════════
    // Errors (OrganizationImplementation-specific errors that don't belong to modules)
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Emitted when a transaction is rejected because of wrong chain ID
     * @param expected The expected chain ID
     * @param provided The provided chain ID
     */
    error InvalidChainId(uint256 expected, uint256 provided);

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
     * @notice Returns the current implementation address for all Account BeaconProxies
     * @dev Required by IBeacon interface. Called by BeaconProxy to get the implementation.
     * @return The current account implementation address
     */
    function implementation() external view returns (address);

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
}
