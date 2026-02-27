// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {SignatureUtils} from "libraries/SignatureUtils.sol";
import {
    LibOrganizationAccountSignatureTestBase
} from "test/organization/libraries/LibOrganizationAccountSignature/LibOrganizationAccountSignatureTestBase.sol";
import {PolicyType} from "types/PolicyTypes.sol";

/**
 * @dev Unit tests for `LibOrganizationAccountSignature.isValidSignature` signature-type routing.
 */
contract LibOrganizationAccountSignatureIsValidSignatureRoutingTest is LibOrganizationAccountSignatureTestBase {
    /// @dev Verifies that empty top-level signatures return ERC-1271 invalid value.
    function test_isValidSignature_emptySignature_returnsInvalidValue() public {
        // Setup: use the default seeded member fixture and an empty signature payload.

        // Call: execute `isValidSignatureViaLibrary` with an empty top-level signature.
        bytes4 actual = harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, bytes(""));

        // Verify: empty signatures must fail closed.
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "empty signatures should be invalid");
    }

    /// @dev Verifies that recovery-prefixed signatures route to recovery validation.
    function test_isValidSignature_recoveryTypePrefix_routesToRecoveryValidation() public {
        // Setup: configure enabled recovery and build a valid recovery payload.
        _setTxRecoveryState(guardianSigner, true);
        bytes memory recoverySignature = _buildRecoverySignature(_signHash(GUARDIAN_PK, MESSAGE_HASH));

        // Call: execute `isValidSignatureViaLibrary` with a recovery-prefixed payload.
        bytes4 actual = harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, recoverySignature);

        // Verify: recovery branch should return magic for a valid recovery signer.
        assertEq(actual, SignatureUtils.ERC1271_MAGIC_VALUE, "recovery prefix should route to recovery branch");
    }

    /// @dev Verifies that policy-prefixed signatures route to policy-based validation.
    function test_isValidSignature_policyTypePrefix_routesToPolicyValidation() public {
        // Setup: configure a valid auto-approve policy signature fixture.
        uint256 expiration = block.timestamp + 1 days;
        (bytes memory signature,,,,,) =
            _buildValidPolicySignature(PolicyType.AutoApprove, DEFAULT_POLICY_ID, expiration);

        // Call: execute `isValidSignatureViaLibrary` with a policy-prefixed payload.
        bytes4 actual = harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signature);

        // Verify: policy branch should return magic for a valid policy fixture.
        assertEq(actual, SignatureUtils.ERC1271_MAGIC_VALUE, "policy prefix should route to policy branch");
    }

    /// @dev Verifies that unknown type prefix `0x02` returns ERC-1271 invalid value.
    function test_isValidSignature_unknownType02_returnsInvalidValue() public {
        // Setup: create a payload with unsupported type prefix `0x02`.
        bytes memory signature = abi.encodePacked(uint8(0x02), hex"AABBCC");

        // Call: execute `isValidSignatureViaLibrary` with an unknown type prefix.
        bytes4 actual = harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signature);

        // Verify: unknown type values must fail closed.
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "unknown prefix 0x02 should be invalid");
    }

    /// @dev Verifies that unknown type prefix `0xFF` returns ERC-1271 invalid value.
    function test_isValidSignature_unknownTypeFF_returnsInvalidValue() public {
        // Setup: create a payload with unsupported type prefix `0xFF`.
        bytes memory signature = abi.encodePacked(uint8(0xFF), hex"11223344");

        // Call: execute `isValidSignatureViaLibrary` with an unknown type prefix.
        bytes4 actual = harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signature);

        // Verify: unknown type values must fail closed.
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "unknown prefix 0xFF should be invalid");
    }

    /// @dev Verifies type-only recovery payloads return invalid while type-only policy payloads revert.
    function test_isValidSignature_typeOnlyPayload_routesWithEmptySignatureData() public {
        // Setup: configure recovery to ensure both routing branches are reachable.
        _setTxRecoveryState(guardianSigner, true);

        // Call: execute recovery-only one-byte payload.
        bytes4 recoveryOnly = harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, abi.encodePacked(uint8(0x00)));

        // Verify: recovery branch should process empty data and return invalid.
        assertEq(recoveryOnly, SignatureUtils.ERC1271_INVALID_VALUE, "type-only recovery payload should fail closed");

        // Verify: policy branch with empty signature data should revert during decode.
        vm.expectRevert();
        // Call: execute policy-only one-byte payload.
        harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, abi.encodePacked(uint8(0x01)));
    }

    /// @dev Verifies that routing uses `signature[0]` as the authoritative type selector.
    function test_isValidSignature_firstByteDeterminesRouting() public {
        // Setup: build a valid policy signature and clone it with a recovery type prefix.
        _setTxRecoveryState(guardianSigner, true);

        uint256 expiration = block.timestamp + 1 days;
        (bytes memory policySignature,,,,,) =
            _buildValidPolicySignature(PolicyType.AutoApprove, DEFAULT_POLICY_ID, expiration);

        bytes memory forcedRecoverySignature = bytes.concat(policySignature);
        forcedRecoverySignature[0] = bytes1(uint8(0x00));

        // Call: execute both payload variants that only differ in the first byte.
        bytes4 policyResult = harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, policySignature);
        bytes4 forcedRecoveryResult = harness.isValidSignatureViaLibrary(ACCOUNT, MESSAGE_HASH, forcedRecoverySignature);

        // Verify: first-byte mutation must switch routing outcome.
        assertEq(policyResult, SignatureUtils.ERC1271_MAGIC_VALUE, "policy-prefixed payload should validate");
        assertEq(
            forcedRecoveryResult,
            SignatureUtils.ERC1271_INVALID_VALUE,
            "same payload with recovery prefix should route away from policy branch"
        );
    }
}
