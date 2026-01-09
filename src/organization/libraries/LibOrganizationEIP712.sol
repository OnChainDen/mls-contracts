// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title Lib Organization EIP712
 * @notice Library for EIP-712 typed data hashing for Organization contracts
 * @dev Provides shared EIP-712 domain separator computation used across organization libraries
 */
library LibOrganizationEIP712 {
    /**
     * @notice Computes the EIP-712 domain separator for this organization
     * @dev Used for all EIP-712 typed data hashes in transaction and signature validation
     * @return The domain separator hash
     */
    function getDomainSeparator() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("OnchainCustodyOrganization"),
                keccak256("1"),
                block.chainid,
                address(this)
            )
        );
    }
}
