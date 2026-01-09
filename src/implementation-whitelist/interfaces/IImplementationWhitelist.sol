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
     * @notice Checks if an implementation address is whitelisted
     * @param contractType The type of contract (Account or Organization)
     * @param implementation The implementation address to check
     * @return True if the implementation is whitelisted, false otherwise
     * @dev The contract maintains separate whitelists for Account and Organization implementations
     */
    function isImplementationWhitelisted(
        ContractType contractType,
        address implementation
    )
        external
        view
        returns (bool);
}
