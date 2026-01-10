// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title I Implementation Whitelist
 * @notice Interface for validating implementation addresses
 * @author Den Technologies Inc
 */
interface IImplementationWhitelist {
    /**
     * @notice Enum to specify the contract type
     */
    enum ContractType {
        Account,
        Organization
    }

    /**
     * @notice Emitted when an implementation is not whitelisted
     * @param implementation The implementation address that was not whitelisted
     */
    error ImplementationNotWhitelisted(address implementation);

    /**
     * @notice Checks if an implementation address is whitelisted
     * @param contractType The type of contract (Account or Organization)
     * @param implementation The implementation address to check
     * @return True if the implementation is whitelisted, false otherwise
     * @dev The contract maintains separate whitelists for Account and Organization implementations
     */
    function isImplementationWhitelisted(ContractType contractType, address implementation)
        external
        view
        returns (bool);

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
