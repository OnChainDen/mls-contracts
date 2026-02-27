// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {MockGuardianSafe, MockGuardianSafeShortReturn} from "test/helpers/MockGuardianSafe.sol";
import {
    MockGuardianModuleReverter,
    MockGuardianModuleUnexpectedReturn,
    MockGuardianSafeERC1271
} from "test/helpers/MockGuardianSignatureValidation.sol";
import {
    LibOrganizationAccountSignatureTestBase
} from "test/organization/libraries/LibOrganizationAccountSignature/LibOrganizationAccountSignatureTestBase.sol";

/**
 * @dev Unit tests for `LibOrganizationAccountSignature._isValidGuardianSignature`.
 */
contract LibOrganizationAccountSignatureIsValidGuardianSignatureTest is LibOrganizationAccountSignatureTestBase {
    /// @dev Verifies that EOA guardian signatures with matching signer return true.
    function test_isValidGuardianSignature_eoaGuardianMatchingSigner_returnsTrue() public {
        // Setup: configure guardian as deterministic EOA signer.
        policyStateHarness.setGuardian(guardianSigner);
        bytes memory guardianSignature = _signHash(GUARDIAN_PK, MESSAGE_HASH);

        // Call: execute `isValidGuardianSignatureViaLibrary` with matching EOA signature.
        bool actual = harness.isValidGuardianSignatureViaLibrary(guardianSignature, MESSAGE_HASH);

        // Verify: matching guardian signer should be accepted.
        assertTrue(actual, "matching guardian EOA signature should be valid");
    }

    /// @dev Verifies that EOA guardian signatures with non-matching signer return false.
    function test_isValidGuardianSignature_eoaGuardianNonMatchingSigner_returnsFalse() public {
        // Setup: configure guardian as deterministic EOA signer and sign with a different key.
        policyStateHarness.setGuardian(guardianSigner);
        bytes memory wrongSignature = _signHash(REVIEWER_PK_1, MESSAGE_HASH);

        // Call: execute `isValidGuardianSignatureViaLibrary` with non-matching EOA signature.
        bool actual = harness.isValidGuardianSignatureViaLibrary(wrongSignature, MESSAGE_HASH);

        // Verify: non-matching guardian signer should be rejected.
        assertFalse(actual, "non-matching guardian EOA signature should be invalid");
    }

    /// @dev Verifies that guardian Safe module signatures from enabled modules return true.
    function test_isValidGuardianSignature_guardianSafeEnabledModuleSigner_returnsTrue() public {
        // Setup: configure guardian as Safe mock with guardian signer enabled as module.
        MockGuardianSafe guardianSafe = new MockGuardianSafe();
        guardianSafe.setModuleEnabled(guardianSigner, true);
        policyStateHarness.setGuardian(address(guardianSafe));

        bytes memory moduleSignature = _signHash(GUARDIAN_PK, MESSAGE_HASH);

        // Call: execute `isValidGuardianSignatureViaLibrary` with enabled-module signer.
        bool actual = harness.isValidGuardianSignatureViaLibrary(moduleSignature, MESSAGE_HASH);

        // Verify: enabled Safe module signer should be accepted.
        assertTrue(actual, "enabled Safe module signer should be valid");
    }

    /// @dev Verifies that guardian Safe module signatures from disabled modules return false.
    function test_isValidGuardianSignature_guardianSafeDisabledModuleSigner_returnsFalse() public {
        // Setup: configure guardian as Safe mock without enabling recovered signer module.
        MockGuardianSafe guardianSafe = new MockGuardianSafe();
        policyStateHarness.setGuardian(address(guardianSafe));

        bytes memory moduleSignature = _signHash(GUARDIAN_PK, MESSAGE_HASH);

        // Call: execute `isValidGuardianSignatureViaLibrary` with disabled-module signer.
        bool actual = harness.isValidGuardianSignatureViaLibrary(moduleSignature, MESSAGE_HASH);

        // Verify: disabled Safe module signer should be rejected.
        assertFalse(actual, "disabled Safe module signer should be invalid");
    }

    /// @dev Verifies that direct guardian ERC-1271 signatures from Safe guardian address return true.
    function test_isValidGuardianSignature_guardianSafeDirectERC1271Signature_returnsTrue() public {
        // Setup: configure guardian as Safe-like ERC-1271 contract signer.
        MockGuardianSafeERC1271 guardianSafe = new MockGuardianSafeERC1271();
        policyStateHarness.setGuardian(address(guardianSafe));

        bytes memory contractGuardianSignature = _buildContractSignature(address(guardianSafe), hex"AA55");

        // Call: execute `isValidGuardianSignatureViaLibrary` with direct guardian contract signature.
        bool actual = harness.isValidGuardianSignatureViaLibrary(contractGuardianSignature, MESSAGE_HASH);

        // Verify: direct guardian contract signer should be accepted without module lookup.
        assertTrue(actual, "direct guardian contract signature should be valid");
    }

    /// @dev Verifies that malformed guardian signatures fail closed and return false.
    function test_isValidGuardianSignature_malformedSignature_returnsFalse() public {
        // Setup: configure guardian as deterministic EOA signer.
        policyStateHarness.setGuardian(guardianSigner);

        // Call: execute `isValidGuardianSignatureViaLibrary` with malformed signature bytes.
        bool actual = harness.isValidGuardianSignatureViaLibrary(hex"00", MESSAGE_HASH);

        // Verify: malformed guardian signatures should fail closed.
        assertFalse(actual, "malformed guardian signature should be invalid");
    }

    /// @dev Verifies that non-Safe guardian contracts that revert on module checks fail closed.
    function test_isValidGuardianSignature_nonSafeGuardianModuleCheckReverts_returnsFalse() public {
        // Setup: configure guardian as contract that reverts on unknown function selectors.
        MockGuardianModuleReverter revertingGuardian = new MockGuardianModuleReverter();
        policyStateHarness.setGuardian(address(revertingGuardian));

        bytes memory signature = _signHash(GUARDIAN_PK, MESSAGE_HASH);

        // Call: execute `isValidGuardianSignatureViaLibrary` with non-direct signer to trigger module path.
        bool actual = harness.isValidGuardianSignatureViaLibrary(signature, MESSAGE_HASH);

        // Verify: reverting module checks should fail closed.
        assertFalse(actual, "reverting guardian module checks should fail closed");
    }

    /// @dev Verifies that truncated `isModuleEnabled` return data fails closed.
    function test_isValidGuardianSignature_guardianModuleShortReturnData_returnsFalse() public {
        // Setup: configure guardian as mock returning one-byte payload for module checks.
        MockGuardianSafeShortReturn shortReturnGuardian = new MockGuardianSafeShortReturn();
        policyStateHarness.setGuardian(address(shortReturnGuardian));

        bytes memory signature = _signHash(GUARDIAN_PK, MESSAGE_HASH);

        // Call: execute `isValidGuardianSignatureViaLibrary` to hit short-return module path.
        bool actual = harness.isValidGuardianSignatureViaLibrary(signature, MESSAGE_HASH);

        // Verify: short return data should fail closed.
        assertFalse(actual, "short module-check return data should be invalid");
    }

    /// @dev Verifies that explicit `false` module checks from guardian Safe return false.
    function test_isValidGuardianSignature_guardianModuleReturnsFalse_returnsFalse() public {
        // Setup: configure guardian as Safe mock with no enabled modules.
        MockGuardianSafe guardianSafe = new MockGuardianSafe();
        policyStateHarness.setGuardian(address(guardianSafe));

        bytes memory signature = _signHash(GUARDIAN_PK, MESSAGE_HASH);

        // Call: execute `isValidGuardianSignatureViaLibrary` with non-enabled module signer.
        bool actual = harness.isValidGuardianSignatureViaLibrary(signature, MESSAGE_HASH);

        // Verify: explicit false module checks should be rejected.
        assertFalse(actual, "module false response should be invalid");
    }

    /// @dev Verifies that EOA guardians fail module-path checks gracefully when signer mismatches.
    function test_isValidGuardianSignature_eoaGuardianModulePathFailsGracefully_returnsFalse() public {
        // Setup: configure guardian as EOA address different from recovered signer.
        policyStateHarness.setGuardian(address(0xBEEFCAFE));
        bytes memory signature = _signHash(REVIEWER_PK_1, MESSAGE_HASH);

        // Call: execute `isValidGuardianSignatureViaLibrary` to trigger EOA module-check path.
        bool actual = harness.isValidGuardianSignatureViaLibrary(signature, MESSAGE_HASH);

        // Verify: module checks on EOAs should fail closed without revert.
        assertFalse(actual, "EOA module-check path should fail closed");
    }

    /// @dev Verifies that unexpected module-check return values fail closed without reverting.
    function test_isValidGuardianSignature_unexpectedModuleReturnData_failsClosedWithoutRevert() public {
        // Setup: configure guardian as contract returning non-boolean 32-byte payload.
        MockGuardianModuleUnexpectedReturn weirdGuardian = new MockGuardianModuleUnexpectedReturn();
        policyStateHarness.setGuardian(address(weirdGuardian));

        bytes memory signature = _signHash(GUARDIAN_PK, MESSAGE_HASH);

        // Call: execute low-level wrapper call to assert graceful handling.
        (bool success, bytes memory result) = address(harness)
            .staticcall(abi.encodeCall(harness.isValidGuardianSignatureViaLibrary, (signature, MESSAGE_HASH)));

        // Verify: unexpected return data should fail closed and never revert.
        assertTrue(success, "unexpected module return data should not revert");
        assertFalse(abi.decode(result, (bool)), "unexpected module return data should fail closed");
    }
}
