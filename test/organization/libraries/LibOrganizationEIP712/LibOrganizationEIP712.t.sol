// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {Test} from "forge-std/Test.sol";

import {LibOrganizationEIP712} from "organization/libraries/LibOrganizationEIP712.sol";
import {
    LibOrganizationEIP712Harness
} from "test/organization/libraries/LibOrganizationEIP712/LibOrganizationEIP712Harness.sol";

/**
 * @dev Unit tests for `LibOrganizationEIP712` domain and typed-data hashing helpers.
 */
contract LibOrganizationEIP712Test is Test {
    /// @dev Fresh harness deployed per test so the verifying-contract address is explicit.
    LibOrganizationEIP712Harness internal harness;

    /**
     * @dev Deploys a fresh EIP-712 harness before each test.
     */
    function setUp() public {
        harness = new LibOrganizationEIP712Harness();
    }

    /// @dev Verifies `LibOrganizationEIP712.getDomainSeparator` is deterministic for one chain and organization.
    function test_NMEIP_E712_1_getDomainSeparator_isDeterministicForSameChainAndOrganization() public view {
        // Setup: keep chain id and harness address fixed.

        // Call: compute the domain separator twice.
        bytes32 separatorA = harness.getDomainSeparatorViaLibrary();
        bytes32 separatorB = harness.getDomainSeparatorViaLibrary();

        // Verify: repeated calls under the same domain return the same separator.
        assertEq(separatorA, separatorB, "domain separator should be deterministic");
    }

    /// @dev Verifies `LibOrganizationEIP712.getDomainSeparator` changes when the chain id changes.
    function test_NMEIP_E712_2_getDomainSeparator_changesAcrossChainIds() public {
        // Setup: snapshot the baseline domain separator before mutating the chain id.
        bytes32 separatorA = harness.getDomainSeparatorViaLibrary();
        uint256 originalChainId = block.chainid;

        // Call: recompute the domain separator after changing the chain id.
        vm.chainId(originalChainId + 1);
        bytes32 separatorB = harness.getDomainSeparatorViaLibrary();
        vm.chainId(originalChainId);

        // Verify: the domain separator binds the chain id.
        assertTrue(separatorA != separatorB, "domain separator should bind chain id");
    }

    /// @dev Verifies `LibOrganizationEIP712.getDomainSeparator` changes when the organization address changes.
    function test_NMEIP_E712_3_getDomainSeparator_changesAcrossOrganizations() public {
        // Setup: deploy a second harness to vary the verifying-contract address.
        LibOrganizationEIP712Harness secondHarness = new LibOrganizationEIP712Harness();

        // Call: compute domain separators for both harness addresses.
        bytes32 separatorA = harness.getDomainSeparatorViaLibrary();
        bytes32 separatorB = secondHarness.getDomainSeparatorViaLibrary();

        // Verify: the domain separator binds the organization address.
        assertTrue(separatorA != separatorB, "domain separator should bind organization address");
    }

    /// @dev Verifies `LibOrganizationEIP712.computeTypedDataHash` matches the reference EIP-712 output.
    function test_NMEIP_E712_4_computeTypedDataHash_matchesReferenceVector() public view {
        // Setup: define a fixed struct hash and independently reconstruct the expected domain separator.
        bytes32 structHash = keccak256("nonce-management-struct");
        bytes32 domainSeparator = keccak256(
            abi.encode(
                LibOrganizationEIP712.EIP712_DOMAIN_TYPEHASH,
                keccak256("MLSWalletOrganization"),
                keccak256("1"),
                block.chainid,
                address(harness)
            )
        );

        // Call: compute the typed-data hash through the library wrapper.
        bytes32 actual = harness.computeTypedDataHashViaLibrary(structHash);

        // Verify: the wrapper matches OpenZeppelin's EIP-712 reference composition.
        assertEq(actual, MessageHashUtils.toTypedDataHash(domainSeparator, structHash), "typed data hash mismatch");
    }
}
