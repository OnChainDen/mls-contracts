// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

/**
 * @dev Storage Layout Fuzz Derivation Helpers
 *      These helpers derive psuedo-random values from fuzz inputs.
 *      Values are derived as typed values generated from `(seed, salt)` pairs, to make fuzz tests
 *      more readable and deterministic.
 */
abstract contract StorageLayoutFuzzDerivationHelpers {
    /**
     * @dev Derives a pseudo-random address from a seed.
     * @param seed Fuzz seed.
     * @param salt Domain-separation salt.
     */
    function _deriveAddress(bytes32 seed, uint256 salt) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encode(seed, salt, "address")))));
    }

    /**
     * @dev Derives a pseudo-random boolean from a seed.
     * @param seed Fuzz seed.
     * @param salt Domain-separation salt.
     */
    function _deriveBool(bytes32 seed, uint256 salt) internal pure returns (bool) {
        return (uint256(keccak256(abi.encode(seed, salt, "bool"))) & 1) == 1;
    }

    /**
     * @dev Derives a pseudo-random uint256 from a seed.
     * @param seed Fuzz seed.
     * @param salt Domain-separation salt.
     */
    function _deriveUint(bytes32 seed, uint256 salt) internal pure returns (uint256) {
        return uint256(keccak256(abi.encode(seed, salt, "uint")));
    }
}
