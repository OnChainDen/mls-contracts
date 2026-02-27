// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {SignatureUtils} from "libraries/SignatureUtils.sol";
import {AccountOrganizationBeaconMock} from "test/account/AccountImplementationMocks.sol";
import {AccountImplementationSuiteBase} from "test/account/AccountImplementationSuiteBase.sol";

/**
 * @dev Tests focused on `AccountImplementation.isValidSignature`.
 */
contract AccountImplementationIsValidSignatureTest is AccountImplementationSuiteBase {
    /// @dev Verifies exact `(account, hash, signature)` delegation to organization signature validation.
    function test_isValidSignature_delegatesExactArguments_returnsOrganizationResult() public {
        // Setup: configure expected delegated tuple and organization approval result.
        bytes32 hash = keccak256("account-signature-delegation-exact");
        bytes memory signature = hex"010203040506";
        beacon.setExpectedSignatureValidation(address(account), hash, signature);
        beacon.setSignatureValidationMode(AccountOrganizationBeaconMock.SignatureValidationMode.ReturnConfigured);
        beacon.setSignatureResult(SignatureUtils.ERC1271_MAGIC_VALUE);

        // Call: invoke account-side ERC-1271 validation.
        bytes4 result = account.isValidSignature(hash, signature);

        // Verify: delegated call succeeds and result is returned unchanged.
        assertEq(result, SignatureUtils.ERC1271_MAGIC_VALUE, "delegated organization result should bubble through");
    }

    /// @dev Verifies delegation preserves empty signature payloads.
    function test_isValidSignature_delegatesEmptySignature_returnsOrganizationResult() public {
        // Setup: enforce exact empty-signature delegation tuple.
        bytes32 hash = keccak256("account-signature-empty");
        bytes memory signature = bytes("");
        beacon.setExpectedSignatureValidation(address(account), hash, signature);
        beacon.setSignatureValidationMode(AccountOrganizationBeaconMock.SignatureValidationMode.ReturnConfigured);
        beacon.setSignatureResult(SignatureUtils.ERC1271_INVALID_VALUE);

        // Call: execute account-side validation with empty signature.
        bytes4 result = account.isValidSignature(hash, signature);

        // Verify: empty signature bytes are delegated exactly and returned value is preserved.
        assertEq(result, SignatureUtils.ERC1271_INVALID_VALUE, "empty signature delegation should preserve org result");
    }

    /// @dev Verifies delegation preserves long signature payloads.
    function test_isValidSignature_delegatesLargeSignature_returnsOrganizationResult() public {
        // Setup: build long signature payload and enforce exact delegation tuple.
        bytes32 hash = keccak256("account-signature-large");
        bytes memory signature = new bytes(1024);
        for (uint256 i = 0; i < signature.length; i++) {
            signature[i] = bytes1(uint8(i));
        }
        beacon.setExpectedSignatureValidation(address(account), hash, signature);
        beacon.setSignatureValidationMode(AccountOrganizationBeaconMock.SignatureValidationMode.ReturnConfigured);
        beacon.setSignatureResult(SignatureUtils.ERC1271_MAGIC_VALUE);

        // Call: execute account-side validation with large signature bytes.
        bytes4 result = account.isValidSignature(hash, signature);

        // Verify: large payload delegation succeeds and returns configured result.
        assertEq(result, SignatureUtils.ERC1271_MAGIC_VALUE, "large signature delegation should preserve org result");
    }

    /// @dev Verifies organization-provided invalid value is returned as-is.
    function test_isValidSignature_organizationReturnsInvalidValue_bubblesInvalidValue() public {
        // Setup: configure organization return mode and invalid signature result.
        beacon.clearExpectedSignatureValidation();
        beacon.setSignatureValidationMode(AccountOrganizationBeaconMock.SignatureValidationMode.ReturnConfigured);
        beacon.setSignatureResult(SignatureUtils.ERC1271_INVALID_VALUE);

        // Call: execute account-side validation.
        bytes4 result = account.isValidSignature(keccak256("org-invalid"), hex"AA");

        // Verify: invalid organization value is propagated.
        assertEq(result, SignatureUtils.ERC1271_INVALID_VALUE, "organization invalid value should bubble through");
    }

    /// @dev Verifies arbitrary non-magic organization values are returned unchanged.
    function test_isValidSignature_organizationReturnsCustomValue_bubblesCustomValue() public {
        // Setup: configure custom non-standard bytes4 return.
        bytes4 custom = 0xDEADBEEF;
        beacon.clearExpectedSignatureValidation();
        beacon.setSignatureValidationMode(AccountOrganizationBeaconMock.SignatureValidationMode.ReturnConfigured);
        beacon.setSignatureResult(custom);

        // Call: execute account-side validation.
        bytes4 result = account.isValidSignature(keccak256("org-custom"), hex"BB");

        // Verify: custom value is propagated unchanged.
        assertEq(result, custom, "custom organization value should bubble through");
    }

    /// @dev Verifies 32-byte custom return words are interpreted using their first four bytes.
    function test_isValidSignature_organizationReturnsCustomWord_usesFirstFourBytes() public {
        // Setup: configure custom 32-byte return payload from organization.
        bytes4 custom = 0xAABBCCDD;
        beacon.clearExpectedSignatureValidation();
        beacon.setSignatureValidationMode(AccountOrganizationBeaconMock.SignatureValidationMode.ReturnCustomWord);
        beacon.setSignatureResultWord(bytes32(custom));

        // Call: execute account-side validation.
        bytes4 result = account.isValidSignature(keccak256("org-word"), hex"CC");

        // Verify: first four bytes of returned word are surfaced as bytes4.
        assertEq(result, custom, "custom 32-byte return should decode to first four bytes");
    }

    /// @dev Verifies organization custom-error reverts are converted to invalid value.
    function test_isValidSignature_organizationRevertsWithCustomError_returnsInvalidValue() public {
        // Setup: configure organization to revert with a custom error.
        beacon.clearExpectedSignatureValidation();
        beacon.setSignatureValidationMode(AccountOrganizationBeaconMock.SignatureValidationMode.RevertWithCustomError);

        // Call: execute account-side validation.
        bytes4 result = account.isValidSignature(keccak256("org-revert-custom"), hex"DD");

        // Verify: revert does not bubble and invalid value is returned.
        assertEq(result, SignatureUtils.ERC1271_INVALID_VALUE, "custom-error revert should fail closed to invalid");
    }

    /// @dev Verifies organization revert-string failures are converted to invalid value.
    function test_isValidSignature_organizationRevertsWithString_returnsInvalidValue() public {
        // Setup: configure organization to revert with a string reason.
        beacon.clearExpectedSignatureValidation();
        beacon.setSignatureValidationMode(AccountOrganizationBeaconMock.SignatureValidationMode.RevertWithString);

        // Call: execute account-side validation.
        bytes4 result = account.isValidSignature(keccak256("org-revert-string"), hex"EE");

        // Verify: revert does not bubble and invalid value is returned.
        assertEq(result, SignatureUtils.ERC1271_INVALID_VALUE, "string revert should fail closed to invalid");
    }

    /// @dev Verifies organization panic reverts are converted to invalid value.
    function test_isValidSignature_organizationRevertsWithPanic_returnsInvalidValue() public {
        // Setup: configure organization to revert with a panic.
        beacon.clearExpectedSignatureValidation();
        beacon.setSignatureValidationMode(AccountOrganizationBeaconMock.SignatureValidationMode.RevertWithPanic);

        // Call: execute account-side validation.
        bytes4 result = account.isValidSignature(keccak256("org-revert-panic"), hex"FF");

        // Verify: panic does not bubble and invalid value is returned.
        assertEq(result, SignatureUtils.ERC1271_INVALID_VALUE, "panic revert should fail closed to invalid");
    }

    /// @dev Verifies organization no-data reverts are converted to invalid value.
    function test_isValidSignature_organizationRevertsWithoutData_returnsInvalidValue() public {
        // Setup: configure organization to revert with empty revert data.
        beacon.clearExpectedSignatureValidation();
        beacon.setSignatureValidationMode(AccountOrganizationBeaconMock.SignatureValidationMode.RevertWithoutData);

        // Call: execute account-side validation.
        bytes4 result = account.isValidSignature(keccak256("org-revert-empty"), hex"11");

        // Verify: revert does not bubble and invalid value is returned.
        assertEq(result, SignatureUtils.ERC1271_INVALID_VALUE, "empty-data revert should fail closed to invalid");
    }

    /// @dev Verifies empty successful return payloads are treated as invalid signatures.
    function test_isValidSignature_organizationReturnsEmptyData_returnsInvalidValue() public {
        // Setup: configure organization to return empty data without reverting.
        beacon.clearExpectedSignatureValidation();
        beacon.setSignatureValidationMode(AccountOrganizationBeaconMock.SignatureValidationMode.ReturnEmptyData);

        // Call: execute account-side validation.
        bytes4 result = account.isValidSignature(keccak256("org-empty-return"), hex"22");

        // Verify: short successful responses fail closed to invalid.
        assertEq(result, SignatureUtils.ERC1271_INVALID_VALUE, "empty return should fail closed to invalid");
    }

    /// @dev Verifies short successful return payloads are treated as invalid signatures.
    function test_isValidSignature_organizationReturnsShortData_returnsInvalidValue() public {
        // Setup: configure organization to return 31-byte payload.
        beacon.clearExpectedSignatureValidation();
        beacon.setSignatureValidationMode(AccountOrganizationBeaconMock.SignatureValidationMode.ReturnShortData);
        beacon.setSignatureResultWord(bytes32(SignatureUtils.ERC1271_MAGIC_VALUE));

        // Call: execute account-side validation.
        bytes4 result = account.isValidSignature(keccak256("org-short-return"), hex"33");

        // Verify: short successful responses fail closed to invalid.
        assertEq(result, SignatureUtils.ERC1271_INVALID_VALUE, "short return should fail closed to invalid");
    }

    /// @dev Verifies delegated-call argument mismatches in organization are converted to invalid value.
    function test_isValidSignature_organizationArgumentGuardReverts_returnsInvalidValue() public {
        // Setup: enforce mismatched expected delegated tuple so organization reverts.
        bytes32 hash = keccak256("org-argument-guard");
        bytes memory signature = hex"445566";
        beacon.setExpectedSignatureValidation(address(0xF00D), hash, signature);
        beacon.setSignatureValidationMode(AccountOrganizationBeaconMock.SignatureValidationMode.ReturnConfigured);

        // Call: execute account-side validation with real account address.
        bytes4 result = account.isValidSignature(hash, signature);

        // Verify: organization revert does not bubble and returns invalid.
        assertEq(result, SignatureUtils.ERC1271_INVALID_VALUE, "delegation guard reverts should fail closed");
    }
}
