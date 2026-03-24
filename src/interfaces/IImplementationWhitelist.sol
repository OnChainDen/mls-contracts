// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {ContractType} from "types/CommonTypes.sol";

/**
 * @title IImplementationWhitelist
 * @notice Interface for managing and validating whitelisted implementation addresses
 * @author Den Technologies Inc
 */
interface IImplementationWhitelist {
    // ═══════════════════════════════════════════════════════════════════════════
    // Events
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Emitted when an implementation is whitelisted
     * @param contractType The type of contract (Account or Organization)
     * @param implementation The implementation address
     */
    event ImplementationWhitelisted(ContractType indexed contractType, address indexed implementation);

    /**
     * @notice Emitted when an implementation is removed from the whitelist
     * @param contractType The type of contract (Account or Organization)
     * @param implementation The implementation address
     */
    event ImplementationUnwhitelisted(ContractType indexed contractType, address indexed implementation);

    /**
     * @notice Emitted when the implementation whitelist is initialized
     * @param owner The initial owner address
     */
    event ImplementationWhitelistInitialized(address indexed owner);

    // ═══════════════════════════════════════════════════════════════════════════
    // Errors
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Emitted when an implementation is not whitelisted
     * @param implementation The implementation address that was not whitelisted
     */
    error ImplementationNotWhitelisted(address implementation);

    // ═══════════════════════════════════════════════════════════════════════════
    // Functions
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Initialize the implementation whitelist
     * @param initialOwner The initial owner address
     * @param organizationImplementations Initial Organization implementations to whitelist
     * @param accountImplementations Initial Account implementations to whitelist
     */
    function initialize(
        address initialOwner,
        address[] calldata organizationImplementations,
        address[] calldata accountImplementations
    ) external;

    /**
     * @notice Whitelists and/or unwhitelists implementation addresses
     * @param contractType The type of contract (Account or Organization)
     * @param toWhitelist The implementation addresses to whitelist
     * @param toUnwhitelist The implementation addresses to remove from whitelist
     */
    function whitelistImplementations(
        ContractType contractType,
        address[] calldata toWhitelist,
        address[] calldata toUnwhitelist
    ) external;

    /**
     * @notice Checks if the implementation whitelist has been initialized
     * @return True if initialized, false otherwise
     */
    function isInitialized() external view returns (bool);

    /**
     * @notice Checks if an implementation address is whitelisted
     * @param contractType The type of contract (Account or Organization)
     * @param implementation The implementation address to check
     * @return True if the implementation is whitelisted, false otherwise
     * @dev The contract maintains separate whitelists for Account and Organization implementations
     */
    // forgefmt: disable-next-item
    function isImplementationWhitelisted(
        ContractType contractType, 
        address implementation
    ) external view returns (bool);

    /**
     * @notice Validates that an implementation address is whitelisted, reverts if not
     * @param contractType The type of contract (Account or Organization)
     * @param implementation The implementation address to check
     * @dev Reverts with ImplementationNotWhitelisted if the implementation is not whitelisted
     */
    function validateIsImplementationWhitelistedOrRevert(ContractType contractType, address implementation)
        external
        view;
}
