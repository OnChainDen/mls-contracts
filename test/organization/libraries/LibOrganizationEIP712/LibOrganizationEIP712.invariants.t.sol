// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {LibOrganizationEIP712} from "organization/libraries/LibOrganizationEIP712.sol";
import {
    LibOrganizationEIP712Harness
} from "test/organization/libraries/LibOrganizationEIP712/LibOrganizationEIP712Harness.sol";
import {
    LibOrganizationEIP712InvariantHandler
} from "test/organization/libraries/LibOrganizationEIP712/LibOrganizationEIP712InvariantHandler.sol";
import {
    LibOrganizationEIP712TestBase
} from "test/organization/libraries/LibOrganizationEIP712/LibOrganizationEIP712TestBase.sol";

/**
 * @dev Invariant checks for `LibOrganizationEIP712` domain stability and typed-data composition.
 */
contract LibOrganizationEIP712Invariants is LibOrganizationEIP712TestBase {
    /// @dev Representative struct hash used by typed-data invariants.
    bytes32 internal constant STRUCT_HASH = keccak256("eip712-invariant-struct");

    /// @dev Stateful handler registered as the invariant fuzz target.
    LibOrganizationEIP712InvariantHandler internal handler;

    /**
     * @dev Registers the harness as the invariant fuzz target.
     */
    function setUp() public override {
        super.setUp();
        handler = new LibOrganizationEIP712InvariantHandler(harness);
        targetContract(address(handler));
    }

    /// @dev Verifies fixed `(chainId, organization)` pairs always produce the same domain separator.
    function invariant_E712_INV_1_domainSeparator_isDeterministicForFixedDomain() public view {
        // Setup: keep the current harness and chain id fixed.

        // Call: compute the same domain separator twice.
        bytes32 first = harness.getDomainSeparatorViaLibrary();
        bytes32 second = harness.getDomainSeparatorViaLibrary();

        // Verify: a fixed domain always yields the same separator.
        assertEq(first, second, "fixed domain should yield a stable domain separator");
    }

    /// @dev Verifies typed-data hashes always use the documented `\\x19\\x01 || domain || structHash` composition.
    function invariant_E712_INV_2_typedDataHash_usesPrefixCompliantComposition() public view {
        // Setup: build the manual reference typed-data hash for one representative struct hash.
        bytes32 expected = _manualTypedDataHash(address(harness), block.chainid, STRUCT_HASH);

        // Call: compute the typed-data hash through the library wrapper.
        bytes32 actual = harness.computeTypedDataHashViaLibrary(STRUCT_HASH);

        // Verify: the helper always follows the documented EIP-712 prefix composition.
        assertEq(actual, expected, "typed-data hash should remain prefix compliant");
    }

    /// @dev Verifies identical struct hashes stay isolated across different organization addresses and chain ids.
    function invariant_E712_INV_3_crossDomainIsolation_changesTypedDataHash() public {
        // Setup: deploy a second harness and preserve the original chain id for cleanup.
        LibOrganizationEIP712Harness otherHarness = new LibOrganizationEIP712Harness();
        uint256 originalChainId = block.chainid;
        bytes32 baseline = harness.computeTypedDataHashViaLibrary(STRUCT_HASH);

        // Call: recompute the same struct hash under a different verifier and a different chain id.
        bytes32 changedVerifier = otherHarness.computeTypedDataHashViaLibrary(STRUCT_HASH);
        vm.chainId(originalChainId + 1);
        bytes32 changedChainId = harness.computeTypedDataHashViaLibrary(STRUCT_HASH);
        vm.chainId(originalChainId);

        // Verify: the same struct hash cannot produce the same typed-data hash across domains.
        assertTrue(baseline != changedVerifier, "organization changes should isolate typed-data hashes");
        assertTrue(baseline != changedChainId, "chain changes should isolate typed-data hashes");
    }

    /// @dev Verifies system-defined EIP-712 message type hashes remain unique and non-interchangeable.
    function invariant_E712_INV_4_systemTypehashes_remainUnique() public pure {
        // Setup: collect the six system-defined type hashes.
        bytes32[6] memory hashes = [
            LibOrganizationEIP712.EIP712_DOMAIN_TYPEHASH,
            LibOrganizationEIP712.ADMIN_OPERATION_TYPEHASH,
            LibOrganizationEIP712.INITIATE_ACCOUNT_TRANSACTION_TYPEHASH,
            LibOrganizationEIP712.REVIEW_ACCOUNT_TRANSACTION_TYPEHASH,
            LibOrganizationEIP712.INITIATE_SIGNATURE_VALIDATION_TYPEHASH,
            LibOrganizationEIP712.REVIEW_SIGNATURE_VALIDATION_TYPEHASH
        ];

        // Call: compare every type hash against the later entries.
        for (uint256 i = 0; i < hashes.length; ++i) {
            for (uint256 j = i + 1; j < hashes.length; ++j) {
                // Verify: no documented message type collides with another.
                assertTrue(hashes[i] != hashes[j], "system-defined type hashes should remain unique");
            }
        }
    }
}
