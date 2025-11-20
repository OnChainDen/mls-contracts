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
     * @notice Validates that an implementation address is whitelisted
     * @param contractType The type of contract (Account or Organization)
     * @param whitelistSetId The whitelist set ID to validate against
     * @param implementation The implementation address to validate
     * @return True if the implementation is whitelisted, false otherwise
     */
    function validateImplementation(
        ContractType contractType,
        uint256 whitelistSetId,
        address implementation
    )
        external
        view
        returns (bool);
}
