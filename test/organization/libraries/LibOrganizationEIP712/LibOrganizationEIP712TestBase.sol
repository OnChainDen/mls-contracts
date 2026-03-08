// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";

import {LibOrganizationEIP712} from "organization/libraries/LibOrganizationEIP712.sol";
import {
    LibOrganizationEIP712Harness
} from "test/organization/libraries/LibOrganizationEIP712/LibOrganizationEIP712Harness.sol";

/**
 * @dev Shared harness deployment and reference encoders for `LibOrganizationEIP712` suites.
 */
abstract contract LibOrganizationEIP712TestBase is Test {
    /// @dev Primary harness used by each EIP-712 test suite.
    LibOrganizationEIP712Harness internal harness;

    /**
     * @dev Deploys a fresh harness before each test.
     */
    function setUp() public virtual {
        harness = new LibOrganizationEIP712Harness();
    }

    /**
     * @dev Builds the documented Organization EIP-712 domain separator for a specific verifier and chain id.
     * @param verifyingContract The organization address bound into the domain.
     * @param chainId The chain id bound into the domain.
     * @return domainSeparator The expected domain separator.
     */
    function _manualDomainSeparator(address verifyingContract, uint256 chainId)
        internal
        pure
        returns (bytes32 domainSeparator)
    {
        return keccak256(
            abi.encode(
                LibOrganizationEIP712.EIP712_DOMAIN_TYPEHASH,
                keccak256("MLSWalletOrganization"),
                keccak256("1"),
                chainId,
                verifyingContract
            )
        );
    }

    /**
     * @dev Builds the documented EIP-712 typed-data hash for a specific verifier, chain id, and struct hash.
     * @param verifyingContract The organization address bound into the domain.
     * @param chainId The chain id bound into the domain.
     * @param structHash The struct hash being wrapped.
     * @return typedDataHash The expected typed-data hash.
     */
    function _manualTypedDataHash(address verifyingContract, uint256 chainId, bytes32 structHash)
        internal
        pure
        returns (bytes32 typedDataHash)
    {
        return keccak256(bytes.concat(hex"1901", _manualDomainSeparator(verifyingContract, chainId), structHash));
    }
}
