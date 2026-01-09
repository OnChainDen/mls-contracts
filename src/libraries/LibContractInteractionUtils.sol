// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title LibContractInteractionUtils
 * @notice A library for contract interaction utility functions
 * @author Den Technologies Inc
 */
library LibContractInteractionUtils {
    /**
     * @notice Extracts the function selector from transaction calldata
     * @dev The function selector is the first 4 bytes of the calldata
     * @param data The transaction calldata
     * @return The function selector (first 4 bytes)
     */
    function extractFunctionSelector(bytes calldata data) internal pure returns (bytes4) {
        return bytes4(data[:4]);
    }
}
