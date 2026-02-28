// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

import {LibOrganizationEIP712} from "organization/libraries/LibOrganizationEIP712.sol";
import {
    LibOrganizationAccountTransactionHarness
} from "test/organization/libraries/LibOrganizationAccountTransaction/LibOrganizationAccountTransactionHarness.sol";
import {
    LibOrganizationAccountTransactionTestBase
} from "test/organization/libraries/LibOrganizationAccountTransaction/LibOrganizationAccountTransactionTestBase.sol";

/**
 * @dev Hash-construction tests for account-transaction initiator/review signatures.
 */
contract LibOrganizationAccountTransactionHashesTest is LibOrganizationAccountTransactionTestBase {
    /// @dev Deterministic organization address used by golden-vector hash checks.
    address internal constant GOLDEN_ORGANIZATION = address(0x1111111111111111111111111111111111111111);

    /// @dev Chain ID used for deterministic golden-vector hash checks.
    uint256 internal constant GOLDEN_CHAIN_ID = 31_337;

    /// @dev Precomputed off-chain initiator hash for the golden-vector test payload.
    bytes32 internal constant GOLDEN_INITIATOR_HASH =
        0xaff0b07e863791178158884ee127b7f0b0c710359762e0e20390537c4b2a20d0;

    /// @dev Precomputed off-chain review hash for the golden-vector test payload.
    bytes32 internal constant GOLDEN_REVIEW_HASH =
        0x44e12a114477fe2befd3baccc5589b3e89909541e1fb3fe3d2c96e57d46bf64a;

    /// @dev Verifies initiator hash uses `INITIATE_ACCOUNT_TRANSACTION_TYPEHASH` in struct encoding.
    function test_LOAT_CIHFP_11_computeInitiatorHash_usesInitiatorTypehash() public view {
        // Setup: deterministic transaction tuple.
        bytes memory data = abi.encodeWithSelector(bytes4(0x61616161), uint256(1));
        uint256 salt = 91;
        uint256 expiration = block.timestamp + 1 days;
        bool isApproval = true;

        // Call: compute initiator hash through library wrapper.
        bytes32 actual = harness.computeInitiatorHashFromParamsViaLibrary(
            ACCOUNT, DESTINATION, 5, salt, expiration, DEFAULT_POLICY_ID, data, isApproval
        );

        // Build expected hash via independent EIP-712 encoding path.
        bytes32 domainSeparator = keccak256(
            abi.encode(
                LibOrganizationEIP712.EIP712_DOMAIN_TYPEHASH,
                keccak256("MLSWalletOrganization"),
                keccak256("1"),
                block.chainid,
                address(harness)
            )
        );
        bytes32 structHash = keccak256(
            abi.encode(
                LibOrganizationEIP712.INITIATE_ACCOUNT_TRANSACTION_TYPEHASH,
                address(harness),
                ACCOUNT,
                DESTINATION,
                5,
                keccak256(data),
                salt,
                expiration,
                DEFAULT_POLICY_ID,
                isApproval,
                block.chainid
            )
        );
        bytes32 expected = MessageHashUtils.toTypedDataHash(domainSeparator, structHash);

        // Verify: wrapper hash equals independently built typehash-based expectation.
        assertEq(actual, expected, "initiator hash must use initiate typehash encoding");
    }

    /// @dev Verifies initiator hash for empty calldata uses `keccak256(\"\")`.
    function test_LOAT_CIHFP_13_computeInitiatorHash_emptyData_usesKeccakOfEmptyBytes() public view {
        // Setup: empty calldata input.
        bytes memory data = bytes("");
        uint256 salt = 92;
        uint256 expiration = block.timestamp + 1 days;

        // Call: compute initiator hash through wrapper.
        bytes32 actual = harness.computeInitiatorHashFromParamsViaLibrary(
            ACCOUNT, DESTINATION, 0, salt, expiration, DEFAULT_POLICY_ID, data, true
        );

        bytes32 domainSeparator = keccak256(
            abi.encode(
                LibOrganizationEIP712.EIP712_DOMAIN_TYPEHASH,
                keccak256("MLSWalletOrganization"),
                keccak256("1"),
                block.chainid,
                address(harness)
            )
        );
        bytes32 structHash = keccak256(
            abi.encode(
                LibOrganizationEIP712.INITIATE_ACCOUNT_TRANSACTION_TYPEHASH,
                address(harness),
                ACCOUNT,
                DESTINATION,
                0,
                keccak256(bytes("")),
                salt,
                expiration,
                DEFAULT_POLICY_ID,
                true,
                block.chainid
            )
        );
        bytes32 expected = MessageHashUtils.toTypedDataHash(domainSeparator, structHash);

        // Verify: empty-data handling matches `keccak256(\"\")` expectation.
        assertEq(actual, expected, "empty calldata should hash as keccak256(empty)");
    }

    /// @dev Verifies initiator hash changes when organization binding (`address(this)`) changes.
    function test_LOAT_CIHFP_1_computeInitiatorHash_organizationBinding_changesAcrossHarnesses() public {
        // Setup: deploy second harness and keep shared transaction tuple.
        bytes memory data = abi.encodeWithSelector(bytes4(0x62626262), uint256(2));
        uint256 expiration = block.timestamp + 1 days;
        LibOrganizationAccountTransactionHarness harnessB = new LibOrganizationAccountTransactionHarness();

        // Call: compute hash on each harness.
        bytes32 hashA = harness.computeInitiatorHashFromParamsViaLibrary(
            ACCOUNT, DESTINATION, 0, 93, expiration, DEFAULT_POLICY_ID, data, true
        );
        bytes32 hashB = harnessB.computeInitiatorHashFromParamsViaLibrary(
            ACCOUNT, DESTINATION, 0, 93, expiration, DEFAULT_POLICY_ID, data, true
        );

        // Verify: different organization addresses produce different hashes.
        assertTrue(hashA != hashB, "organization address must be bound into initiator hash");
    }

    /// @dev Verifies review hash uses `REVIEW_ACCOUNT_TRANSACTION_TYPEHASH`.
    function test_LOAT_CRHFP_12_computeReviewHash_usesReviewTypehash() public view {
        // Setup: deterministic tuple and initiator signature bytes.
        bytes memory data = abi.encodeWithSelector(bytes4(0x63636363), uint256(3));
        uint256 salt = 94;
        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSignature = hex"010203";

        // Call: compute review hash through wrapper.
        bytes32 actual = harness.computeReviewHashFromParamsViaLibrary(
            ACCOUNT, DESTINATION, 7, salt, expiration, DEFAULT_POLICY_ID, data, true, initiatorSignature
        );

        bytes32 domainSeparator = keccak256(
            abi.encode(
                LibOrganizationEIP712.EIP712_DOMAIN_TYPEHASH,
                keccak256("MLSWalletOrganization"),
                keccak256("1"),
                block.chainid,
                address(harness)
            )
        );
        bytes32 structHash = keccak256(
            abi.encode(
                LibOrganizationEIP712.REVIEW_ACCOUNT_TRANSACTION_TYPEHASH,
                address(harness),
                ACCOUNT,
                DESTINATION,
                7,
                keccak256(data),
                salt,
                expiration,
                DEFAULT_POLICY_ID,
                true,
                block.chainid,
                keccak256(initiatorSignature)
            )
        );
        bytes32 expected = MessageHashUtils.toTypedDataHash(domainSeparator, structHash);

        // Verify: wrapper hash equals independently built review-typehash expectation.
        assertEq(actual, expected, "review hash must use review typehash encoding");
    }

    /// @dev Verifies review hash binds every transaction field and chain id.
    function test_LOAT_CRHFP_2__LOAT_CRHFP_3__LOAT_CRHFP_4__LOAT_CRHFP_5__LOAT_CRHFP_6__LOAT_CRHFP_7__LOAT_CRHFP_8__LOAT_CRHFP_9__LOAT_CRHFP_13_computeReviewHash_fieldBinding_changesHashWhenAnyFieldChanges() public {
        // Setup: compute baseline review hash.
        bytes memory data = abi.encodeWithSelector(bytes4(0x64646464), uint256(4));
        bytes memory initiatorSignature = hex"1122";
        uint256 expiration = block.timestamp + 1 days;
        bytes32 base = harness.computeReviewHashFromParamsViaLibrary(
            ACCOUNT, DESTINATION, 1, 95, expiration, DEFAULT_POLICY_ID, data, true, initiatorSignature
        );

        // Verify: each single-field mutation changes the review hash.
        assertTrue(
            base
                != harness.computeReviewHashFromParamsViaLibrary(
                    address(uint160(ACCOUNT) + 1),
                    DESTINATION,
                    1,
                    95,
                    expiration,
                    DEFAULT_POLICY_ID,
                    data,
                    true,
                    initiatorSignature
                ),
            "account should be bound"
        );
        assertTrue(
            base
                != harness.computeReviewHashFromParamsViaLibrary(
                    ACCOUNT,
                    address(uint160(DESTINATION) + 1),
                    1,
                    95,
                    expiration,
                    DEFAULT_POLICY_ID,
                    data,
                    true,
                    initiatorSignature
                ),
            "destination should be bound"
        );
        assertTrue(
            base
                != harness.computeReviewHashFromParamsViaLibrary(
                    ACCOUNT, DESTINATION, 2, 95, expiration, DEFAULT_POLICY_ID, data, true, initiatorSignature
                ),
            "value should be bound"
        );
        assertTrue(
            base
                != harness.computeReviewHashFromParamsViaLibrary(
                    ACCOUNT, DESTINATION, 1, 96, expiration, DEFAULT_POLICY_ID, data, true, initiatorSignature
                ),
            "salt should be bound"
        );
        assertTrue(
            base
                != harness.computeReviewHashFromParamsViaLibrary(
                    ACCOUNT, DESTINATION, 1, 95, expiration + 1, DEFAULT_POLICY_ID, data, true, initiatorSignature
                ),
            "expiration should be bound"
        );
        assertTrue(
            base
                != harness.computeReviewHashFromParamsViaLibrary(
                    ACCOUNT, DESTINATION, 1, 95, expiration, DEFAULT_POLICY_ID + 1, data, true, initiatorSignature
                ),
            "policyId should be bound"
        );
        assertTrue(
            base
                != harness.computeReviewHashFromParamsViaLibrary(
                    ACCOUNT,
                    DESTINATION,
                    1,
                    95,
                    expiration,
                    DEFAULT_POLICY_ID,
                    abi.encodeWithSelector(bytes4(0x64646465), uint256(4)),
                    true,
                    initiatorSignature
                ),
            "data should be bound"
        );
        assertTrue(
            base
                != harness.computeReviewHashFromParamsViaLibrary(
                    ACCOUNT, DESTINATION, 1, 95, expiration, DEFAULT_POLICY_ID, data, false, initiatorSignature
                ),
            "isApproval flag should be bound"
        );

        uint256 chainId = block.chainid;
        vm.chainId(chainId + 1);
        bytes32 changedChainHash = harness.computeReviewHashFromParamsViaLibrary(
            ACCOUNT, DESTINATION, 1, 95, expiration, DEFAULT_POLICY_ID, data, true, initiatorSignature
        );
        vm.chainId(chainId);
        assertTrue(base != changedChainHash, "chain id should be bound");
    }

    /// @dev Verifies review hash includes `keccak256(initiatorSignature)` binding.
    function test_LOAT_CRHFP_10__LOAT_CRHFP_11_computeReviewHash_initiatorSignatureBinding_changesHash() public view {
        // Setup: two different initiator-signature byte payloads.
        bytes memory data = abi.encodeWithSelector(bytes4(0x65656565), uint256(5));
        uint256 expiration = block.timestamp + 1 days;
        bytes memory initiatorSigA = hex"AAAA";
        bytes memory initiatorSigB = hex"BBBB";

        // Call: compute review hash for both initiator-signature variants.
        bytes32 hashA = harness.computeReviewHashFromParamsViaLibrary(
            ACCOUNT, DESTINATION, 0, 96, expiration, DEFAULT_POLICY_ID, data, true, initiatorSigA
        );
        bytes32 hashB = harness.computeReviewHashFromParamsViaLibrary(
            ACCOUNT, DESTINATION, 0, 96, expiration, DEFAULT_POLICY_ID, data, true, initiatorSigB
        );

        // Verify: different initiator signatures produce different review hashes.
        assertTrue(hashA != hashB, "review hash should include initiator signature hash");
    }

    /// @dev Verifies initiator hash matches a precomputed golden vector for known deterministic inputs.
    function test_LOAT_CIHFP_14_computeInitiatorHash_knownInputs_matchesPrecomputedGoldenHash() public {
        // Setup: pin chain ID and organization address to deterministic values used by off-chain vector generation.
        uint256 originalChainId = block.chainid;
        vm.chainId(GOLDEN_CHAIN_ID);
        vm.etch(GOLDEN_ORGANIZATION, address(harness).code);
        LibOrganizationAccountTransactionHarness goldenHarness =
            LibOrganizationAccountTransactionHarness(GOLDEN_ORGANIZATION);

        bytes memory data = abi.encodeWithSelector(bytes4(0x63636363), uint256(3));

        // Call: compute initiator hash for known tuple.
        bytes32 actual = goldenHarness.computeInitiatorHashFromParamsViaLibrary(
            address(uint160(0xA1101)),
            address(uint160(0xB2202)),
            7,
            94,
            1_800_000_000,
            DEFAULT_POLICY_ID,
            data,
            true
        );

        // Restore chain ID before assertions.
        vm.chainId(originalChainId);

        // Verify: on-chain hash matches precomputed golden vector.
        assertEq(actual, GOLDEN_INITIATOR_HASH, "initiator hash should match golden vector");
    }

    /// @dev Verifies review hash matches a precomputed golden vector for known deterministic inputs.
    function test_LOAT_CRHFP_14_computeReviewHash_knownInputs_matchesPrecomputedGoldenHash() public {
        // Setup: pin chain ID and organization address to deterministic values used by off-chain vector generation.
        uint256 originalChainId = block.chainid;
        vm.chainId(GOLDEN_CHAIN_ID);
        vm.etch(GOLDEN_ORGANIZATION, address(harness).code);
        LibOrganizationAccountTransactionHarness goldenHarness =
            LibOrganizationAccountTransactionHarness(GOLDEN_ORGANIZATION);

        bytes memory data = abi.encodeWithSelector(bytes4(0x63636363), uint256(3));
        bytes memory initiatorSignature = hex"010203";

        // Call: compute review hash for known tuple.
        bytes32 actual = goldenHarness.computeReviewHashFromParamsViaLibrary(
            address(uint160(0xA1101)),
            address(uint160(0xB2202)),
            7,
            94,
            1_800_000_000,
            DEFAULT_POLICY_ID,
            data,
            true,
            initiatorSignature
        );

        // Restore chain ID before assertions.
        vm.chainId(originalChainId);

        // Verify: on-chain hash matches precomputed golden vector.
        assertEq(actual, GOLDEN_REVIEW_HASH, "review hash should match golden vector");
    }
}
