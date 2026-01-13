// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ContractInteractionUtils
 * @dev A library for contract interaction utility functions
 * @author Den Technologies Inc
 */
library ContractInteractionUtils {
    /// @dev Function selector length in calldata (first 4 bytes of keccak256 hash)
    uint256 internal constant SELECTOR_LENGTH = 4;

    /// @dev ABI encoding slot size (32 bytes per slot)
    uint256 internal constant SLOT_SIZE = 32;

    /**
     * @dev Extracts the function selector from transaction calldata
     * @dev The function selector is the first 4 bytes of the calldata
     * @param data The transaction calldata
     * @return The function selector (first 4 bytes)
     */
    function extractFunctionSelector(bytes calldata data) internal pure returns (bytes4) {
        return bytes4(data[:SELECTOR_LENGTH]);
    }
}
