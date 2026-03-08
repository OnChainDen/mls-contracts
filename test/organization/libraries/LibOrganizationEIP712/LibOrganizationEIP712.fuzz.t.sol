// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

import {
    LibOrganizationEIP712Harness
} from "test/organization/libraries/LibOrganizationEIP712/LibOrganizationEIP712Harness.sol";
import {
    LibOrganizationEIP712TestBase
} from "test/organization/libraries/LibOrganizationEIP712/LibOrganizationEIP712TestBase.sol";

/**
 * @dev Fuzz tests for `LibOrganizationEIP712` determinism and domain isolation properties.
 */
contract LibOrganizationEIP712FuzzTest is LibOrganizationEIP712TestBase {
    /// @dev Verifies fixed-domain EIP-712 helpers remain deterministic for random struct hashes.
    function testFuzz_E712_FUZ_1_getDomainSeparatorAndTypedDataHash_sameInputsRemainDeterministic(bytes32 structHash)
        public
        view
    {
        // Setup: keep the current harness and chain id fixed while fuzzing the struct hash.

        // Call: compute the domain separator and typed-data hash twice with identical inputs.
        bytes32 domainA = harness.getDomainSeparatorViaLibrary();
        bytes32 domainB = harness.getDomainSeparatorViaLibrary();
        bytes32 typedDataHashA = harness.computeTypedDataHashViaLibrary(structHash);
        bytes32 typedDataHashB = harness.computeTypedDataHashViaLibrary(structHash);

        // Verify: both helpers remain deterministic for identical inputs.
        assertEq(domainA, domainB, "domain separator should remain deterministic");
        assertEq(typedDataHashA, typedDataHashB, "typed-data hash should remain deterministic");
    }

    /// @dev Verifies mutating exactly one bound EIP-712 input changes the final typed-data hash.
    function testFuzz_E712_FUZ_2_singleBoundInputMutation_changesTypedDataHash(bytes32 structHash, bytes32 mutatedStructHash)
        public
    {
        // Setup: derive a distinct struct hash and a second harness for verifier mutation checks.
        vm.assume(structHash != mutatedStructHash);
        LibOrganizationEIP712Harness otherHarness = new LibOrganizationEIP712Harness();
        uint256 originalChainId = block.chainid;
        bytes32 baseline = harness.computeTypedDataHashViaLibrary(structHash);

        // Call: mutate the struct hash, verifier, and chain id one at a time.
        bytes32 changedStructHash = harness.computeTypedDataHashViaLibrary(mutatedStructHash);
        bytes32 changedVerifier = otherHarness.computeTypedDataHashViaLibrary(structHash);
        vm.chainId(originalChainId + 1);
        bytes32 changedChainId = harness.computeTypedDataHashViaLibrary(structHash);
        vm.chainId(originalChainId);

        // Verify: each bound-input mutation changes the final typed-data hash.
        assertTrue(baseline != changedStructHash, "struct-hash mutation should change typed-data hash");
        assertTrue(baseline != changedVerifier, "verifier mutation should change typed-data hash");
        assertTrue(baseline != changedChainId, "chain-id mutation should change typed-data hash");
    }

    /// @dev Verifies random `(chainId, organization)` pairs isolate domains for one fixed struct hash.
    function testFuzz_E712_FUZ_3_randomChainAndOrganizationPairs_isolateDomains(
        bytes32 structHash,
        uint64 rawChainIdA,
        uint64 rawChainIdB
    ) public {
        // Setup: bound both chain ids to non-zero values and deploy a second harness.
        uint256 chainIdA = bound(uint256(rawChainIdA), 1, type(uint64).max);
        uint256 chainIdB = bound(uint256(rawChainIdB), 1, type(uint64).max);
        vm.assume(chainIdA != chainIdB);
        LibOrganizationEIP712Harness otherHarness = new LibOrganizationEIP712Harness();
        uint256 originalChainId = block.chainid;

        // Call: compute typed-data hashes for one struct hash under two chains and two verifiers.
        vm.chainId(chainIdA);
        bytes32 sameChainSameVerifier = harness.computeTypedDataHashViaLibrary(structHash);
        bytes32 sameChainOtherVerifier = otherHarness.computeTypedDataHashViaLibrary(structHash);

        vm.chainId(chainIdB);
        bytes32 otherChainSameVerifier = harness.computeTypedDataHashViaLibrary(structHash);
        bytes32 otherChainOtherVerifier = otherHarness.computeTypedDataHashViaLibrary(structHash);
        vm.chainId(originalChainId);

        // Verify: changing either chain id or verifier isolates the final typed-data hash.
        assertTrue(
            sameChainSameVerifier != sameChainOtherVerifier, "verifier changes should isolate typed-data hashes"
        );
        assertTrue(sameChainSameVerifier != otherChainSameVerifier, "chain changes should isolate typed-data hashes");
        assertTrue(
            sameChainSameVerifier != otherChainOtherVerifier,
            "changing both chain and verifier should isolate typed-data hashes"
        );
    }

    /// @dev Verifies random helper vectors match independent manual EIP-712 reference encoding.
    function testFuzz_E712_FUZ_6_randomVectors_matchIndependentReference(bytes32 structHash, uint64 rawChainId) public {
        // Setup: bind a non-zero chain id and preserve the original chain id for cleanup.
        uint256 chainId = bound(uint256(rawChainId), 1, type(uint64).max);
        uint256 originalChainId = block.chainid;
        bytes32 expectedDomain = _manualDomainSeparator(address(harness), chainId);
        bytes32 expectedTypedDataHash = _manualTypedDataHash(address(harness), chainId, structHash);
        bytes32 expectedOZ = MessageHashUtils.toTypedDataHash(expectedDomain, structHash);

        // Call: compute the domain separator and typed-data hash at the fuzzed chain id.
        vm.chainId(chainId);
        bytes32 actualDomain = harness.getDomainSeparatorViaLibrary();
        bytes32 actualTypedDataHash = harness.computeTypedDataHashViaLibrary(structHash);
        vm.chainId(originalChainId);

        // Verify: helper outputs match independent manual and OpenZeppelin reference encoders.
        assertEq(actualDomain, expectedDomain, "domain separator should match independent reference");
        assertEq(actualTypedDataHash, expectedTypedDataHash, "typed-data hash should match manual prefix composition");
        assertEq(actualTypedDataHash, expectedOZ, "typed-data hash should match OpenZeppelin reference");
    }
}
