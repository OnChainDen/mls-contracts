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
 * @dev Unit tests for `LibOrganizationAccountSignature._getInitiatorSignatureHash`.
 */
contract LibOrganizationAccountSignatureGetInitiatorSignatureHashTest is LibOrganizationAccountSignatureTestBase {
    uint256 internal constant GOLDEN_POLICY_ID = 9001;
    uint256 internal constant GOLDEN_EXPIRATION = 1_900_000_001;
    address internal constant GOLDEN_ACCOUNT = address(0xABCDEF01);
    bytes32 internal constant GOLDEN_MESSAGE_HASH = keccak256("golden-initiator-hash");

    /// @dev Verifies that different organization addresses produce different initiator hashes.
    function test_LOAS_GISH_1_getInitiatorSignatureHash_differentOrganizations_returnsDifferentHashes() public {
        // Setup: deploy an additional harness with a different verifying-contract address.
        LibOrganizationAccountSignatureHarness otherHarness = new LibOrganizationAccountSignatureHarness();

        // Call: compute initiator hashes on two different organization addresses.
        bytes32 hashA =
            harness.getInitiatorSignatureHashViaLibrary(ACCOUNT, MESSAGE_HASH, DEFAULT_POLICY_ID, block.timestamp + 1);
        bytes32 hashB = otherHarness.getInitiatorSignatureHashViaLibrary(
            ACCOUNT, MESSAGE_HASH, DEFAULT_POLICY_ID, block.timestamp + 1
        );

        // Verify: organization address should be bound into hash derivation.
        assertTrue(hashA != hashB, "different organization addresses should produce different hashes");
    }

    /// @dev Verifies that changing account changes the initiator signature hash.
    function test_LOAS_GISH_2_getInitiatorSignatureHash_differentAccount_returnsDifferentHash() public {
        // Setup: select baseline policy/message/expiration inputs.
        uint256 expiration = block.timestamp + 1 days;

        // Call: compute initiator hashes for two different account addresses.
        bytes32 hashA =
            harness.getInitiatorSignatureHashViaLibrary(ACCOUNT, MESSAGE_HASH, DEFAULT_POLICY_ID, expiration);
        bytes32 hashB =
            harness.getInitiatorSignatureHashViaLibrary(OTHER_ACCOUNT, MESSAGE_HASH, DEFAULT_POLICY_ID, expiration);

        // Verify: account should be bound into initiator hash derivation.
        assertTrue(hashA != hashB, "account changes should change initiator hash");
    }

    /// @dev Verifies that changing message hash changes the initiator signature hash.
    function test_LOAS_GISH_3_getInitiatorSignatureHash_differentMessageHash_returnsDifferentHash() public {
        // Setup: select baseline account/policy/expiration inputs.
        uint256 expiration = block.timestamp + 1 days;

        // Call: compute initiator hashes for two different message hashes.
        bytes32 hashA =
            harness.getInitiatorSignatureHashViaLibrary(ACCOUNT, MESSAGE_HASH, DEFAULT_POLICY_ID, expiration);
        bytes32 hashB =
            harness.getInitiatorSignatureHashViaLibrary(ACCOUNT, OTHER_MESSAGE_HASH, DEFAULT_POLICY_ID, expiration);

        // Verify: message hash should be bound into initiator hash derivation.
        assertTrue(hashA != hashB, "message hash changes should change initiator hash");
    }

    /// @dev Verifies that changing policy id changes the initiator signature hash.
    function test_LOAS_GISH_4_getInitiatorSignatureHash_differentPolicyId_returnsDifferentHash() public {
        // Setup: select baseline account/message/expiration inputs.
        uint256 expiration = block.timestamp + 1 days;

        // Call: compute initiator hashes for two policy ids.
        bytes32 hashA =
            harness.getInitiatorSignatureHashViaLibrary(ACCOUNT, MESSAGE_HASH, DEFAULT_POLICY_ID, expiration);
        bytes32 hashB =
            harness.getInitiatorSignatureHashViaLibrary(ACCOUNT, MESSAGE_HASH, DEFAULT_POLICY_ID + 1, expiration);

        // Verify: policy id should be bound into initiator hash derivation.
        assertTrue(hashA != hashB, "policy id changes should change initiator hash");
    }

    /// @dev Verifies that changing expiration timestamp changes the initiator signature hash.
    function test_LOAS_GISH_5_getInitiatorSignatureHash_differentExpiration_returnsDifferentHash() public {
        // Setup: select baseline account/message/policy inputs.
        uint256 expirationA = block.timestamp + 1 days;
        uint256 expirationB = expirationA + 1;

        // Call: compute initiator hashes for two expiration timestamps.
        bytes32 hashA =
            harness.getInitiatorSignatureHashViaLibrary(ACCOUNT, MESSAGE_HASH, DEFAULT_POLICY_ID, expirationA);
        bytes32 hashB =
            harness.getInitiatorSignatureHashViaLibrary(ACCOUNT, MESSAGE_HASH, DEFAULT_POLICY_ID, expirationB);

        // Verify: expiration should be bound into initiator hash derivation.
        assertTrue(hashA != hashB, "expiration changes should change initiator hash");
    }

    /// @dev Verifies that changing chain id changes the initiator signature hash.
    function test_LOAS_GISH_6_getInitiatorSignatureHash_differentChainId_returnsDifferentHash() public {
        // Setup: snapshot baseline hash inputs.
        uint256 expiration = block.timestamp + 1 days;
        bytes32 baseline =
            harness.getInitiatorSignatureHashViaLibrary(ACCOUNT, MESSAGE_HASH, DEFAULT_POLICY_ID, expiration);

        // Call: recompute after changing chain id.
        uint256 originalChainId = block.chainid;
        vm.chainId(originalChainId + 1);
        bytes32 changed =
            harness.getInitiatorSignatureHashViaLibrary(ACCOUNT, MESSAGE_HASH, DEFAULT_POLICY_ID, expiration);
        vm.chainId(originalChainId);

        // Verify: chain id should be bound into initiator hash derivation.
        assertTrue(baseline != changed, "chain id changes should change initiator hash");
    }

    /// @dev Verifies that the initiator hash uses `INITIATE_SIGNATURE_VALIDATION_TYPEHASH`.
    function test_LOAS_GISH_7_getInitiatorSignatureHash_usesInitiatorTypehash() public view {
        // Setup: select deterministic baseline inputs.
        uint256 expiration = block.timestamp + 1 days;

        bytes32 structHash = keccak256(
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

        bytes32 wrongStructHash = keccak256(
            abi.encode(
                LibOrganizationEIP712.REVIEW_SIGNATURE_VALIDATION_TYPEHASH,
                address(harness),
                ACCOUNT,
                MESSAGE_HASH,
                DEFAULT_POLICY_ID,
                expiration,
                block.chainid
            )
        );

        bytes32 domainSeparator = _computeDomainSeparator(address(harness), block.chainid);
        bytes32 expected = MessageHashUtils.toTypedDataHash(domainSeparator, structHash);
        bytes32 wrongExpected = MessageHashUtils.toTypedDataHash(domainSeparator, wrongStructHash);

        // Call: execute `getInitiatorSignatureHashViaLibrary` for baseline inputs.
        bytes32 actual =
            harness.getInitiatorSignatureHashViaLibrary(ACCOUNT, MESSAGE_HASH, DEFAULT_POLICY_ID, expiration);

        // Verify: expected typehash must be used.
        assertEq(actual, expected, "initiator hash should use INITIATE_SIGNATURE_VALIDATION_TYPEHASH");
        assertTrue(actual != wrongExpected, "review typehash should not match initiator hash derivation");
    }

    /// @dev Verifies that initiator hash uses EIP-712 typed-data hashing with domain separator.
    function test_LOAS_GISH_8_getInitiatorSignatureHash_usesTypedDataHashWithDomainSeparator() public view {
        // Setup: select deterministic baseline inputs.
        uint256 expiration = block.timestamp + 1 days;
        bytes32 structHash = keccak256(
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
        bytes32 domainSeparator = _computeDomainSeparator(address(harness), block.chainid);

        // Call: execute `getInitiatorSignatureHashViaLibrary` and manual typed-data derivation.
        bytes32 actual =
            harness.getInitiatorSignatureHashViaLibrary(ACCOUNT, MESSAGE_HASH, DEFAULT_POLICY_ID, expiration);
        bytes32 expectedTypedDataHash = MessageHashUtils.toTypedDataHash(domainSeparator, structHash);

        // Verify: typed-data hash wrapping should be applied over struct hash.
        assertEq(actual, expectedTypedDataHash, "initiator hash should be typed-data hash");
        assertTrue(actual != structHash, "raw struct hash should not equal final typed-data hash");
    }

    /// @dev Verifies that identical inputs always produce identical initiator hashes.
    function test_LOAS_GISH_9_getInitiatorSignatureHash_sameInputs_isDeterministic() public view {
        // Setup: choose deterministic baseline inputs.
        uint256 expiration = block.timestamp + 1 days;

        // Call: compute initiator hash twice with identical inputs.
        bytes32 first =
            harness.getInitiatorSignatureHashViaLibrary(ACCOUNT, MESSAGE_HASH, DEFAULT_POLICY_ID, expiration);
        bytes32 second =
            harness.getInitiatorSignatureHashViaLibrary(ACCOUNT, MESSAGE_HASH, DEFAULT_POLICY_ID, expiration);

        // Verify: identical inputs should produce deterministic outputs.
        assertEq(first, second, "initiator hash should be deterministic for identical inputs");
    }

    /// @dev Verifies that known golden inputs produce the expected precomputed initiator hash.
    function test_LOAS_GISH_10_getInitiatorSignatureHash_goldenInputs_matchesExpectedHash() public view {
        // Setup: use the deterministic golden input fixture.
        bytes32 expected = MessageHashUtils.toTypedDataHash(
            _computeDomainSeparator(address(harness), block.chainid),
            keccak256(
                abi.encode(
                    LibOrganizationEIP712.INITIATE_SIGNATURE_VALIDATION_TYPEHASH,
                    address(harness),
                    GOLDEN_ACCOUNT,
                    GOLDEN_MESSAGE_HASH,
                    GOLDEN_POLICY_ID,
                    GOLDEN_EXPIRATION,
                    block.chainid
                )
            )
        );

        // Call: compute initiator hash for golden inputs.
        bytes32 actual = harness.getInitiatorSignatureHashViaLibrary(
            GOLDEN_ACCOUNT, GOLDEN_MESSAGE_HASH, GOLDEN_POLICY_ID, GOLDEN_EXPIRATION
        );

        // Verify: golden inputs should match the precomputed expected hash.
        assertEq(actual, expected, "golden initiator hash mismatch");
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
