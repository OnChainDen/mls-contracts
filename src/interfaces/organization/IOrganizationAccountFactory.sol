// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AdminAuthParams} from "types/AdminTypes.sol";

/**
 * @title IOrganizationAccountFactory
 * @notice Interface for account deployment and management in Organization contracts
 * @dev Maps to LibOrganizationAccountFactory library functionality
 * @author Den Technologies Inc
 */
interface IOrganizationAccountFactory {
    // ═══════════════════════════════════════════════════════════════════════════
    // Events
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Emitted when a new account proxy is deployed
     * @param accountAddress The address of the deployed account proxy
     * @param organizationAddress The address of the organization that deployed it (beacon)
     * @param salt The salt used for CREATE2 deployment
     */
    event AccountDeployed(address indexed accountAddress, address indexed organizationAddress, bytes32 indexed salt);

    /**
     * @notice Emitted when the account implementation is updated (affects all accounts via beacon)
     * @param newImplementation The new implementation address for all accounts
     */
    event AccountImplementationUpdated(address indexed newImplementation);

    // ═══════════════════════════════════════════════════════════════════════════
    // Errors
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Thrown when the deployed address does not match the computed address
     */
    error AccountDeploymentAddressMismatch();

    /**
     * @notice Thrown when an account was not deployed by this organization
     * @param accountAddress The address of the account that was not deployed by this organization
     */
    error AccountNotDeployedByOrganization(address accountAddress);

    // ═══════════════════════════════════════════════════════════════════════════
    // Functions
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Deploys a new Account BeaconProxy at a deterministic address
     * @dev The account uses this Organization as its beacon
     * @param create2Salt The salt for CREATE2 deployment
     * @param authParams The authorization parameters (salt, expiration, signatures, and admin proofs)
     * @return The address of the deployed account proxy
     */
    function deployAccount(bytes32 create2Salt, AdminAuthParams calldata authParams) external returns (address);

    /**
     * @notice Sets the account implementation address (upgrades all accounts at once)
     * @dev This function updates the implementation for all Account BeaconProxies
     * @param newImplementation The new implementation address
     * @param authParams The authorization parameters (salt, expiration, signatures, and admin proofs)
     */
    function setAccountImplementation(address newImplementation, AdminAuthParams calldata authParams) external;

    /**
     * @notice Computes the address where an account proxy would be deployed
     * @param salt The salt for CREATE2 deployment
     * @return The computed address
     */
    function computeAccountAddress(bytes32 salt) external view returns (address);
}
