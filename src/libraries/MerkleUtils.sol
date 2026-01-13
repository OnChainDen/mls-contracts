// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title Merkle Utils
 * @dev Shared utility library for merkle tree leaf computation
 * @dev Provides standardized leaf computation using double hashing for security against second preimage attacks
 * @author Den Technologies Inc
 */
library MerkleUtils {
    /**
     * @dev Computes the merkle leaf for an address
     * @dev Uses double hashing (hash of hash) for security against second preimage attacks
     * @param addr The address to compute the leaf for
     * @return The computed merkle leaf
     */
    function computeAddressLeaf(address addr) internal pure returns (bytes32) {
        return keccak256(bytes.concat(keccak256(abi.encode(addr))));
    }
}
