// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

import {LibOrganizationEIP712} from "organization/libraries/LibOrganizationEIP712.sol";
import {
    LibOrganizationEIP712Harness
} from "test/organization/libraries/LibOrganizationEIP712/LibOrganizationEIP712Harness.sol";
import {
    LibOrganizationEIP712TestBase
} from "test/organization/libraries/LibOrganizationEIP712/LibOrganizationEIP712TestBase.sol";

/**
 * @dev Unit tests for `LibOrganizationEIP712` type hashes, domain separation, and typed-data hashing.
 */
contract LibOrganizationEIP712Test is LibOrganizationEIP712TestBase {
    /// @dev Deterministic struct hash used by typed-data helper tests.
    bytes32 internal constant BASE_STRUCT_HASH = keccak256("eip712-base-struct");

    /// @dev Verifies `LibOrganizationEIP712.EIP712_DOMAIN_TYPEHASH` matches the documented EIP-712 domain string.
    function test_LOEIP_THC_1_domainTypehash_matchesDocumentedTypeString() public pure {
        // Setup: keep the documented type string explicit in the test body.
        bytes32 expected =
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

        // Call: read the library constant.
        bytes32 actual = LibOrganizationEIP712.EIP712_DOMAIN_TYPEHASH;

        // Verify: the library constant matches the documented domain schema.
        assertEq(actual, expected, "domain typehash should match documented EIP-712 domain string");
    }

    /// @dev Verifies `LibOrganizationEIP712.ADMIN_OPERATION_TYPEHASH` matches the documented admin-operation schema.
    function test_LOEIP_THC_2_adminOperationTypehash_matchesDocumentedTypeString() public pure {
        // Setup: keep the documented type string explicit in the test body.
        bytes32 expected = keccak256(
            "AdminOperation(uint8 operationType,bytes operationData,uint256 salt,uint256 expirationTimestamp,bool isApproval,uint256 chainId,address organization)"
        );

        // Call: read the library constant.
        bytes32 actual = LibOrganizationEIP712.ADMIN_OPERATION_TYPEHASH;

        // Verify: the library constant matches the documented admin-operation schema.
        assertEq(actual, expected, "admin-operation typehash should match documented schema");
    }

    /// @dev Verifies `LibOrganizationEIP712.INITIATE_ACCOUNT_TRANSACTION_TYPEHASH` matches the documented initiator
    /// schema.
    function test_LOEIP_THC_3_initiateAccountTransactionTypehash_matchesDocumentedTypeString() public pure {
        // Setup: keep the documented type string explicit in the test body.
        bytes32 expected = keccak256(
            "InitiateAccountTransaction(address organization,address account,address to,uint256 value,bytes data,uint256 salt,uint256 expirationTimestamp,uint256 policyId,bool isApproval,uint256 chainId)"
        );

        // Call: read the library constant.
        bytes32 actual = LibOrganizationEIP712.INITIATE_ACCOUNT_TRANSACTION_TYPEHASH;

        // Verify: the library constant matches the documented initiator schema.
        assertEq(actual, expected, "initiate-account-transaction typehash should match documented schema");
    }

    /// @dev Verifies `LibOrganizationEIP712.REVIEW_ACCOUNT_TRANSACTION_TYPEHASH` matches the documented reviewer
    /// schema.
    function test_LOEIP_THC_4_reviewAccountTransactionTypehash_matchesDocumentedTypeString() public pure {
        // Setup: keep the documented type string explicit in the test body.
        bytes32 expected = keccak256(
            "ReviewAccountTransaction(address organization,address account,address to,uint256 value,bytes data,uint256 salt,uint256 expirationTimestamp,uint256 policyId,bool isApproval,uint256 chainId,bytes initiatorSignature)"
        );

        // Call: read the library constant.
        bytes32 actual = LibOrganizationEIP712.REVIEW_ACCOUNT_TRANSACTION_TYPEHASH;

        // Verify: the library constant matches the documented reviewer schema.
        assertEq(actual, expected, "review-account-transaction typehash should match documented schema");
    }

    /// @dev Verifies `LibOrganizationEIP712.INITIATE_SIGNATURE_VALIDATION_TYPEHASH` matches the documented initiator
    /// schema.
    function test_LOEIP_THC_5_initiateSignatureValidationTypehash_matchesDocumentedTypeString() public pure {
        // Setup: keep the documented type string explicit in the test body.
        bytes32 expected = keccak256(
            "InitiateSignatureValidation(address organization,address account,bytes32 hash,uint256 policyId,uint256 expirationTimestamp,uint256 chainId)"
        );

        // Call: read the library constant.
        bytes32 actual = LibOrganizationEIP712.INITIATE_SIGNATURE_VALIDATION_TYPEHASH;

        // Verify: the library constant matches the documented initiator schema.
        assertEq(actual, expected, "initiate-signature-validation typehash should match documented schema");
    }

    /// @dev Verifies `LibOrganizationEIP712.REVIEW_SIGNATURE_VALIDATION_TYPEHASH` matches the documented reviewer
    /// schema.
    function test_LOEIP_THC_6_reviewSignatureValidationTypehash_matchesDocumentedTypeString() public pure {
        // Setup: keep the documented type string explicit in the test body.
        bytes32 expected = keccak256(
            "ReviewSignatureValidation(address organization,address account,bytes32 hash,uint256 policyId,uint256 expirationTimestamp,uint256 chainId,bytes initiatorSignature)"
        );

        // Call: read the library constant.
        bytes32 actual = LibOrganizationEIP712.REVIEW_SIGNATURE_VALIDATION_TYPEHASH;

        // Verify: the library constant matches the documented reviewer schema.
        assertEq(actual, expected, "review-signature-validation typehash should match documented schema");
    }

    /// @dev Verifies all Organization EIP-712 type hashes remain unique across system-defined message types.
    function test_LOEIP_THC_7_allSystemTypehashes_areUnique() public pure {
        // Setup: collect the six system-defined type hashes under test.
        bytes32[6] memory hashes = [
            LibOrganizationEIP712.EIP712_DOMAIN_TYPEHASH,
            LibOrganizationEIP712.ADMIN_OPERATION_TYPEHASH,
            LibOrganizationEIP712.INITIATE_ACCOUNT_TRANSACTION_TYPEHASH,
            LibOrganizationEIP712.REVIEW_ACCOUNT_TRANSACTION_TYPEHASH,
            LibOrganizationEIP712.INITIATE_SIGNATURE_VALIDATION_TYPEHASH,
            LibOrganizationEIP712.REVIEW_SIGNATURE_VALIDATION_TYPEHASH
        ];

        // Call: compare each type hash against every later entry.
        for (uint256 i = 0; i < hashes.length; ++i) {
            for (uint256 j = i + 1; j < hashes.length; ++j) {
                // Verify: no two documented message types collide.
                assertTrue(hashes[i] != hashes[j], "type hashes should be unique");
            }
        }
    }

    /// @dev Verifies `LibOrganizationEIP712.getDomainSeparator` uses the documented name, version, chain id, verifier,
    /// and field order.
    function test_LOEIP_GDS_1_LOEIP_GDS_2_LOEIP_GDS_3_LOEIP_GDS_4_LOEIP_GDS_8_getDomainSeparator_matchesDocumentedReference()
        public
        view
    {
        // Setup: independently reconstruct the documented domain separator for this harness and chain.
        bytes32 expected = _manualDomainSeparator(address(harness), block.chainid);

        // Call: compute the domain separator through the library wrapper.
        bytes32 actual = harness.getDomainSeparatorViaLibrary();

        // Verify: the library output matches the documented name/version/chain/verifier encoding exactly.
        assertEq(actual, expected, "domain separator should match documented reference encoding");
    }

    /// @dev Verifies `LibOrganizationEIP712.getDomainSeparator` is deterministic for a fixed chain and organization.
    function test_E712_HASH_1_NMEIP_E712_1_LOEIP_GDS_5_getDomainSeparator_sameDomainIsDeterministic() public view {
        // Setup: keep the harness address and chain id fixed for repeated calls.

        // Call: compute the same domain separator twice.
        bytes32 first = harness.getDomainSeparatorViaLibrary();
        bytes32 second = harness.getDomainSeparatorViaLibrary();

        // Verify: repeated calls under one domain return the same separator.
        assertEq(first, second, "domain separator should be deterministic");
    }

    /// @dev Verifies `LibOrganizationEIP712.getDomainSeparator` changes when the chain id changes.
    function test_E712_HASH_2_A_NMEIP_E712_2_LOEIP_GDS_6_getDomainSeparator_chainIdMutationChangesSeparator() public {
        // Setup: snapshot the baseline separator before mutating the chain id.
        bytes32 baseline = harness.getDomainSeparatorViaLibrary();
        uint256 originalChainId = block.chainid;

        // Call: recompute the separator on a different chain id.
        vm.chainId(originalChainId + 1);
        bytes32 changed = harness.getDomainSeparatorViaLibrary();
        vm.chainId(originalChainId);

        // Verify: chain-id changes produce a different domain separator.
        assertTrue(baseline != changed, "domain separator should bind chain id");
    }

    /// @dev Verifies `LibOrganizationEIP712.getDomainSeparator` changes when the verifying contract changes.
    function test_E712_HASH_2_B_NMEIP_E712_3_LOEIP_GDS_7_getDomainSeparator_verifierMutationChangesSeparator() public {
        // Setup: deploy a second harness with a different verifying-contract address.
        LibOrganizationEIP712Harness otherHarness = new LibOrganizationEIP712Harness();

        // Call: compute domain separators for both harness addresses.
        bytes32 first = harness.getDomainSeparatorViaLibrary();
        bytes32 second = otherHarness.getDomainSeparatorViaLibrary();

        // Verify: verifying-contract changes produce a different separator.
        assertTrue(first != second, "domain separator should bind organization address");
    }

    /// @dev Verifies `LibOrganizationEIP712.computeTypedDataHash` matches both the documented prefix composition and
    /// the OpenZeppelin reference helper.
    function test_NMEIP_E712_4_LOEIP_CTDH_1_LOEIP_CTDH_2_computeTypedDataHash_matchesPrefixAndOpenZeppelinReference()
        public
        view
    {
        // Setup: choose a deterministic struct hash and build independent manual references.
        bytes32 expectedManual = _manualTypedDataHash(address(harness), block.chainid, BASE_STRUCT_HASH);
        bytes32 expectedOZ =
            MessageHashUtils.toTypedDataHash(_manualDomainSeparator(address(harness), block.chainid), BASE_STRUCT_HASH);

        // Call: compute the typed-data hash through the library wrapper.
        bytes32 actual = harness.computeTypedDataHashViaLibrary(BASE_STRUCT_HASH);

        // Verify: the helper matches both documented prefix composition and OpenZeppelin's reference helper.
        assertEq(actual, expectedManual, "typed-data hash should match documented prefix composition");
        assertEq(actual, expectedOZ, "typed-data hash should match OpenZeppelin reference");
    }

    /// @dev Verifies `LibOrganizationEIP712.computeTypedDataHash` changes when the struct hash changes.
    function test_LOEIP_CTDH_3_computeTypedDataHash_structHashMutationChangesOutput() public view {
        // Setup: derive two distinct struct hashes within the same domain.
        bytes32 structHashA = BASE_STRUCT_HASH;
        bytes32 structHashB = keccak256("eip712-mutated-struct");

        // Call: compute typed-data hashes for both struct hashes.
        bytes32 hashA = harness.computeTypedDataHashViaLibrary(structHashA);
        bytes32 hashB = harness.computeTypedDataHashViaLibrary(structHashB);

        // Verify: mutating the struct hash changes the final typed-data hash.
        assertTrue(hashA != hashB, "typed-data hash should change when struct hash changes");
    }

    /// @dev Verifies `LibOrganizationEIP712.computeTypedDataHash` binds the verifying-contract address.
    function test_LOEIP_CTDH_4_computeTypedDataHash_sameStructHashDifferentOrganizations_changesOutput() public {
        // Setup: deploy a second harness with a different verifying-contract address.
        LibOrganizationEIP712Harness otherHarness = new LibOrganizationEIP712Harness();

        // Call: compute the same struct hash on two organization addresses.
        bytes32 hashA = harness.computeTypedDataHashViaLibrary(BASE_STRUCT_HASH);
        bytes32 hashB = otherHarness.computeTypedDataHashViaLibrary(BASE_STRUCT_HASH);

        // Verify: cross-organization replay is prevented by the domain separator.
        assertTrue(hashA != hashB, "typed-data hash should bind organization address");
    }

    /// @dev Verifies `LibOrganizationEIP712.computeTypedDataHash` binds the current chain id.
    function test_LOEIP_CTDH_5_computeTypedDataHash_sameStructHashDifferentChains_changesOutput() public {
        // Setup: snapshot the baseline typed-data hash before mutating the chain id.
        bytes32 baseline = harness.computeTypedDataHashViaLibrary(BASE_STRUCT_HASH);
        uint256 originalChainId = block.chainid;

        // Call: recompute the typed-data hash on a different chain id.
        vm.chainId(originalChainId + 1);
        bytes32 changed = harness.computeTypedDataHashViaLibrary(BASE_STRUCT_HASH);
        vm.chainId(originalChainId);

        // Verify: cross-chain replay is prevented by the domain separator.
        assertTrue(baseline != changed, "typed-data hash should bind chain id");
    }

    /// @dev Verifies `LibOrganizationEIP712.computeTypedDataHash` handles `bytes32(0)` deterministically without
    /// reverting.
    function test_LOEIP_CTDH_6_computeTypedDataHash_zeroStructHash_isDeterministicAndNonReverting() public view {
        // Setup: keep the zero struct hash explicit.
        bytes32 zeroStructHash = bytes32(0);
        bytes32 expected = _manualTypedDataHash(address(harness), block.chainid, zeroStructHash);

        // Call: compute the zero-struct typed-data hash twice.
        bytes32 first = harness.computeTypedDataHashViaLibrary(zeroStructHash);
        bytes32 second = harness.computeTypedDataHashViaLibrary(zeroStructHash);

        // Verify: zero struct hashes are accepted and remain deterministic.
        assertEq(first, expected, "zero struct hash should use the documented typed-data composition");
        assertEq(first, second, "zero struct hash should remain deterministic");
    }
}
