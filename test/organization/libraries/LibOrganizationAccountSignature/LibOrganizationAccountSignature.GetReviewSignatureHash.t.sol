// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

import {LibOrganizationEIP712} from "organization/libraries/LibOrganizationEIP712.sol";
import {
    LibOrganizationAccountSignatureHarness
} from "test/organization/libraries/LibOrganizationAccountSignature/LibOrganizationAccountSignatureHarness.sol";
import {
    LibOrganizationAccountSignatureTestBase
} from "test/organization/libraries/LibOrganizationAccountSignature/LibOrganizationAccountSignatureTestBase.sol";

/**
 * @dev Unit tests for `LibOrganizationAccountSignature._getReviewSignatureHash`.
 */
contract LibOrganizationAccountSignatureGetReviewSignatureHashTest is LibOrganizationAccountSignatureTestBase {
    uint256 internal constant GOLDEN_POLICY_ID = 9002;
    uint256 internal constant GOLDEN_EXPIRATION = 1_900_000_002;
    address internal constant GOLDEN_ACCOUNT = address(0xABCDEF02);
    bytes32 internal constant GOLDEN_MESSAGE_HASH = keccak256("golden-review-hash");

    /// @dev Verifies that different organization addresses produce different review hashes.
    function test_LOAS_GRSH_1_LOACS_GRSH_3_getReviewSignatureHash_differentOrganizations_returnsDifferentHashes()
        public
    {
        // Setup: deploy a second harness with a different organization address.
        LibOrganizationAccountSignatureHarness otherHarness = new LibOrganizationAccountSignatureHarness();
        bytes memory initiatorSignature = _signHash(INITIATOR_PK_1, MESSAGE_HASH);

        // Call: compute review hashes on two different organization addresses.
        bytes32 hashA = harness.getReviewSignatureHashViaLibrary({
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: block.timestamp + 1,
            initiatorSignature: initiatorSignature
        });
        bytes32 hashB = otherHarness.getReviewSignatureHashViaLibrary({
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: block.timestamp + 1,
            initiatorSignature: initiatorSignature
        });

        // Verify: organization address should be bound into review hash derivation.
        assertTrue(hashA != hashB, "different organization addresses should produce different review hashes");
    }

    /// @dev Verifies that changing account changes the review signature hash.
    function test_LOAS_GRSH_2_getReviewSignatureHash_differentAccount_returnsDifferentHash() public {
        // Setup: select deterministic initiator signature fixture.
        bytes memory initiatorSignature = _signHash(INITIATOR_PK_1, MESSAGE_HASH);
        uint256 expiration = block.timestamp + 1 days;

        // Call: compute review hashes for two account addresses.
        bytes32 hashA = harness.getReviewSignatureHashViaLibrary({
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature
        });
        bytes32 hashB = harness.getReviewSignatureHashViaLibrary({
            account: OTHER_ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature
        });

        // Verify: account should be bound into review hash derivation.
        assertTrue(hashA != hashB, "account changes should change review hash");
    }

    /// @dev Verifies that changing message hash changes the review signature hash.
    function test_LOAS_GRSH_3_getReviewSignatureHash_differentMessageHash_returnsDifferentHash() public {
        // Setup: select deterministic initiator signature fixture.
        bytes memory initiatorSignature = _signHash(INITIATOR_PK_1, MESSAGE_HASH);
        uint256 expiration = block.timestamp + 1 days;

        // Call: compute review hashes for two message hashes.
        bytes32 hashA = harness.getReviewSignatureHashViaLibrary({
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature
        });
        bytes32 hashB = harness.getReviewSignatureHashViaLibrary({
            account: ACCOUNT,
            hash: OTHER_MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature
        });

        // Verify: message hash should be bound into review hash derivation.
        assertTrue(hashA != hashB, "message hash changes should change review hash");
    }

    /// @dev Verifies that changing policy id changes the review signature hash.
    function test_LOAS_GRSH_4_getReviewSignatureHash_differentPolicyId_returnsDifferentHash() public {
        // Setup: select deterministic initiator signature fixture.
        bytes memory initiatorSignature = _signHash(INITIATOR_PK_1, MESSAGE_HASH);
        uint256 expiration = block.timestamp + 1 days;

        // Call: compute review hashes for two policy ids.
        bytes32 hashA = harness.getReviewSignatureHashViaLibrary({
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature
        });
        bytes32 hashB = harness.getReviewSignatureHashViaLibrary({
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID + 1,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature
        });

        // Verify: policy id should be bound into review hash derivation.
        assertTrue(hashA != hashB, "policy id changes should change review hash");
    }

    /// @dev Verifies that changing expiration timestamp changes the review signature hash.
    function test_LOAS_GRSH_5_getReviewSignatureHash_differentExpiration_returnsDifferentHash() public {
        // Setup: select deterministic initiator signature fixture.
        bytes memory initiatorSignature = _signHash(INITIATOR_PK_1, MESSAGE_HASH);
        uint256 expirationA = block.timestamp + 1 days;
        uint256 expirationB = expirationA + 1;

        // Call: compute review hashes for two expiration timestamps.
        bytes32 hashA = harness.getReviewSignatureHashViaLibrary({
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expirationA,
            initiatorSignature: initiatorSignature
        });
        bytes32 hashB = harness.getReviewSignatureHashViaLibrary({
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expirationB,
            initiatorSignature: initiatorSignature
        });

        // Verify: expiration should be bound into review hash derivation.
        assertTrue(hashA != hashB, "expiration changes should change review hash");
    }

    /// @dev Verifies that changing chain id changes the review signature hash.
    function test_LOAS_GRSH_6_LOACS_GRSH_3_getReviewSignatureHash_differentChainId_returnsDifferentHash() public {
        // Setup: select deterministic review-hash inputs.
        bytes memory initiatorSignature = _signHash(INITIATOR_PK_1, MESSAGE_HASH);
        uint256 expiration = block.timestamp + 1 days;

        bytes32 baseline = harness.getReviewSignatureHashViaLibrary({
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature
        });

        // Call: recompute after changing chain id.
        uint256 originalChainId = block.chainid;
        vm.chainId(originalChainId + 1);
        bytes32 changed = harness.getReviewSignatureHashViaLibrary({
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature
        });
        vm.chainId(originalChainId);

        // Verify: chain id should be bound into review hash derivation.
        assertTrue(baseline != changed, "chain id changes should change review hash");
    }

    /// @dev Verifies that review hash derivation includes `keccak256(initiatorSignature)`.
    function test_E712_HASH_4_LOAS_GRSH_7_LOACS_GRSH_1_getReviewSignatureHash_includesInitiatorSignatureHashField()
        public
        view
    {
        // Setup: choose deterministic review-hash inputs.
        bytes memory initiatorSignature = _signHash(INITIATOR_PK_1, MESSAGE_HASH);
        uint256 expiration = block.timestamp + 1 days;

        bytes32 structHash = keccak256(
            abi.encode(
                LibOrganizationEIP712.REVIEW_SIGNATURE_VALIDATION_TYPEHASH,
                address(harness),
                ACCOUNT,
                MESSAGE_HASH,
                DEFAULT_POLICY_ID,
                expiration,
                block.chainid,
                keccak256(initiatorSignature)
            )
        );

        bytes32 wrongStructHash = keccak256(
            abi.encode(
                LibOrganizationEIP712.REVIEW_SIGNATURE_VALIDATION_TYPEHASH,
                address(harness),
                ACCOUNT,
                MESSAGE_HASH,
                DEFAULT_POLICY_ID,
                expiration,
                block.chainid,
                keccak256(bytes("different"))
            )
        );

        bytes32 domainSeparator = _computeDomainSeparator(address(harness), block.chainid);
        bytes32 expected = MessageHashUtils.toTypedDataHash(domainSeparator, structHash);
        bytes32 wrongExpected = MessageHashUtils.toTypedDataHash(domainSeparator, wrongStructHash);

        // Call: execute `getReviewSignatureHashViaLibrary` for baseline inputs.
        bytes32 actual = harness.getReviewSignatureHashViaLibrary({
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature
        });

        // Verify: review hash must include initiator signature hash field.
        assertEq(actual, expected, "review hash should include keccak256(initiatorSignature)");
        assertTrue(actual != wrongExpected, "changing initiator signature hash field should change review hash");
    }

    /// @dev Verifies that different initiator signatures produce different review hashes.
    function test_LOAS_GRSH_8_LOACS_GRSH_2_getReviewSignatureHash_differentInitiatorSignatures_returnsDifferentHash()
        public
        view
    {
        // Setup: select deterministic baseline inputs and two different initiator signatures.
        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSignatureA = _signHash(INITIATOR_PK_1, MESSAGE_HASH);
        bytes memory initiatorSignatureB = _signHash(INITIATOR_PK_2, MESSAGE_HASH);

        // Call: compute review hashes for each initiator signature variant.
        bytes32 hashA = harness.getReviewSignatureHashViaLibrary({
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignatureA
        });
        bytes32 hashB = harness.getReviewSignatureHashViaLibrary({
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignatureB
        });

        // Verify: different initiator signature bytes should change review hash.
        assertTrue(hashA != hashB, "initiator signature bytes should affect review hash");
    }

    /// @dev Verifies empty initiator signatures are hashed as `keccak256(\"\")`.
    function test_LOACS_GRSH_4_getReviewSignatureHash_emptyInitiatorSignature_usesKeccakOfEmptyBytes() public view {
        // Setup: choose deterministic review-hash inputs with an empty initiator signature.
        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSignature = bytes("");

        bytes32 structHash = keccak256(
            abi.encode(
                LibOrganizationEIP712.REVIEW_SIGNATURE_VALIDATION_TYPEHASH,
                address(harness),
                ACCOUNT,
                MESSAGE_HASH,
                DEFAULT_POLICY_ID,
                expiration,
                block.chainid,
                keccak256(bytes(""))
            )
        );
        bytes32 expected =
            MessageHashUtils.toTypedDataHash(_computeDomainSeparator(address(harness), block.chainid), structHash);

        // Call: execute `getReviewSignatureHashViaLibrary` with the empty initiator signature.
        bytes32 actual = harness.getReviewSignatureHashViaLibrary({
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature
        });

        // Verify: empty initiator signatures do not revert and hash through the empty-bytes digest.
        assertEq(actual, expected, "empty initiator signatures should hash as keccak256(empty)");
    }

    /// @dev Verifies review hash remains distinct from the initiator hash for the same request metadata.
    function test_LOACS_GRSH_6_getReviewSignatureHash_isDistinctFromInitiatorHash() public view {
        // Setup: choose deterministic request inputs and one concrete initiator signature payload.
        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSignature = _signHash(INITIATOR_PK_1, MESSAGE_HASH);

        // Call: compute both initiator and review hashes for the same logical request.
        bytes32 initiatorHash =
            harness.getInitiatorSignatureHashViaLibrary(ACCOUNT, MESSAGE_HASH, DEFAULT_POLICY_ID, expiration);
        bytes32 reviewHash = harness.getReviewSignatureHashViaLibrary({
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature
        });

        // Verify: initiator and review flows stay domain-separated by their type hashes and field layouts.
        assertTrue(reviewHash != initiatorHash, "review hash should remain distinct from initiator hash");
    }

    /// @dev Verifies that review hash uses `REVIEW_SIGNATURE_VALIDATION_TYPEHASH` and not initiator typehash.
    function test_LOAS_GRSH_9_getReviewSignatureHash_usesReviewTypehash() public view {
        // Setup: choose deterministic review-hash inputs.
        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSignature = _signHash(INITIATOR_PK_1, MESSAGE_HASH);
        bytes32 domainSeparator = _computeDomainSeparator(address(harness), block.chainid);

        bytes32 reviewStructHash = keccak256(
            abi.encode(
                LibOrganizationEIP712.REVIEW_SIGNATURE_VALIDATION_TYPEHASH,
                address(harness),
                ACCOUNT,
                MESSAGE_HASH,
                DEFAULT_POLICY_ID,
                expiration,
                block.chainid,
                keccak256(initiatorSignature)
            )
        );
        bytes32 initiatorStructHash = keccak256(
            abi.encode(
                LibOrganizationEIP712.INITIATE_SIGNATURE_VALIDATION_TYPEHASH,
                address(harness),
                ACCOUNT,
                MESSAGE_HASH,
                DEFAULT_POLICY_ID,
                expiration,
                block.chainid
            )
        );

        bytes32 expected = MessageHashUtils.toTypedDataHash(domainSeparator, reviewStructHash);
        bytes32 wrongExpected = MessageHashUtils.toTypedDataHash(domainSeparator, initiatorStructHash);

        // Call: execute `getReviewSignatureHashViaLibrary` for baseline inputs.
        bytes32 actual = harness.getReviewSignatureHashViaLibrary({
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature
        });

        // Verify: review typehash must be used.
        assertEq(actual, expected, "review hash should use REVIEW_SIGNATURE_VALIDATION_TYPEHASH");
        assertTrue(actual != wrongExpected, "initiator typehash should not match review hash derivation");
    }

    /// @dev Verifies that review hash uses EIP-712 typed-data hashing with domain separator.
    function test_LOAS_GRSH_10_LOACS_GRSH_7_getReviewSignatureHash_usesTypedDataHashWithDomainSeparator() public view {
        // Setup: choose deterministic review-hash inputs.
        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSignature = _signHash(INITIATOR_PK_1, MESSAGE_HASH);

        bytes32 structHash = keccak256(
            abi.encode(
                LibOrganizationEIP712.REVIEW_SIGNATURE_VALIDATION_TYPEHASH,
                address(harness),
                ACCOUNT,
                MESSAGE_HASH,
                DEFAULT_POLICY_ID,
                expiration,
                block.chainid,
                keccak256(initiatorSignature)
            )
        );
        bytes32 domainSeparator = _computeDomainSeparator(address(harness), block.chainid);

        // Call: execute `getReviewSignatureHashViaLibrary` and manual typed-data derivation.
        bytes32 actual = harness.getReviewSignatureHashViaLibrary({
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature
        });
        bytes32 expectedTypedDataHash = MessageHashUtils.toTypedDataHash(domainSeparator, structHash);

        // Verify: typed-data hash wrapping should be applied over review struct hash.
        assertEq(actual, expectedTypedDataHash, "review hash should be typed-data hash");
        assertTrue(actual != structHash, "raw struct hash should not equal final typed-data hash");
    }

    /// @dev Verifies that identical inputs always produce identical review hashes.
    function test_LOAS_GRSH_11_getReviewSignatureHash_sameInputs_isDeterministic() public view {
        // Setup: choose deterministic baseline inputs.
        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSignature = _signHash(INITIATOR_PK_1, MESSAGE_HASH);

        // Call: compute review hash twice with identical inputs.
        bytes32 first = harness.getReviewSignatureHashViaLibrary({
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature
        });
        bytes32 second = harness.getReviewSignatureHashViaLibrary({
            account: ACCOUNT,
            hash: MESSAGE_HASH,
            policyId: DEFAULT_POLICY_ID,
            expirationTimestamp: expiration,
            initiatorSignature: initiatorSignature
        });

        // Verify: identical inputs should produce deterministic outputs.
        assertEq(first, second, "review hash should be deterministic for identical inputs");
    }

    /// @dev Verifies that known golden inputs produce the expected precomputed review hash.
    function test_LOAS_GRSH_12_LOACS_GRSH_5_getReviewSignatureHash_goldenInputs_matchesExpectedHash() public view {
        // Setup: use the deterministic golden input fixture.
        bytes memory initiatorSignature =
            hex"1b36495ecf0f3b4f4e8b6b65b0d8b73f53da5ea8327f24df1920525f9f93072ee88f40f2bc74fbad801f28cd26ecee6a10d1f294f4f3696f9de7b51176efdc7d54";
        bytes32 expected = MessageHashUtils.toTypedDataHash(
            _computeDomainSeparator(address(harness), block.chainid),
            keccak256(
                abi.encode(
                    LibOrganizationEIP712.REVIEW_SIGNATURE_VALIDATION_TYPEHASH,
                    address(harness),
                    GOLDEN_ACCOUNT,
                    GOLDEN_MESSAGE_HASH,
                    GOLDEN_POLICY_ID,
                    GOLDEN_EXPIRATION,
                    block.chainid,
                    keccak256(initiatorSignature)
                )
            )
        );

        // Call: compute review hash for golden inputs.
        bytes32 actual = harness.getReviewSignatureHashViaLibrary({
            account: GOLDEN_ACCOUNT,
            hash: GOLDEN_MESSAGE_HASH,
            policyId: GOLDEN_POLICY_ID,
            expirationTimestamp: GOLDEN_EXPIRATION,
            initiatorSignature: initiatorSignature
        });

        // Verify: golden inputs should match the precomputed expected hash.
        assertEq(actual, expected, "golden review hash mismatch");
    }

    /**
     * @dev Computes Organization EIP-712 domain separator for a specific verifier and chain id.
     */
    function _computeDomainSeparator(address verifyingContract, uint256 chainId) internal pure returns (bytes32) {
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
}
