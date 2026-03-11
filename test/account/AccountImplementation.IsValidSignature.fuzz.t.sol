// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {SignatureUtils} from "libraries/SignatureUtils.sol";
import {AccountOrganizationBeaconMock} from "test/account/AccountImplementationMocks.sol";
import {AccountImplementationSuiteBase} from "test/account/AccountImplementationSuiteBase.sol";

/**
 * @dev Fuzz tests focused on `AccountImplementation.isValidSignature`.
 */
contract AccountImplementationIsValidSignatureFuzzTest is AccountImplementationSuiteBase {
    /// @dev Verifies organization reverts never bubble for arbitrary callers and payloads.
    function testFuzz_ACI_IVS_14_isValidSignature_organizationRevertNeverBubbles(
        address caller,
        bytes32 hash,
        bytes calldata signature
    ) public {
        // Setup: configure organization to revert with custom error for all calls.
        beacon.clearExpectedSignatureValidation();
        beacon.setSignatureValidationMode(AccountOrganizationBeaconMock.SignatureValidationMode.RevertWithCustomError);

        vm.prank(caller);
        // Call: invoke account-side validation from arbitrary caller.
        bytes4 result = account.isValidSignature(hash, signature);

        // Verify: call never reverts and always fails closed to invalid.
        assertEq(result, SignatureUtils.ERC1271_INVALID_VALUE, "organization revert should not bubble to callers");
    }

    /// @dev Verifies exact delegation for arbitrary inputs and arbitrary organization `bytes4` results.
    function testFuzz_ACI_IVS_15__FAI_SIG_147_isValidSignature_delegatesExactTupleAndBubblesConfiguredResult(
        address caller,
        bytes32 hash,
        bytes calldata signature,
        bytes4 organizationResult
    ) public {
        // Setup: bound fuzzed signature bytes and configure exact delegated tuple + configurable return.
        vm.assume(signature.length <= 2048);
        beacon.setExpectedSignatureValidation(address(account), hash, signature);
        beacon.setSignatureValidationMode(AccountOrganizationBeaconMock.SignatureValidationMode.ReturnConfigured);
        beacon.setSignatureResult(organizationResult);

        vm.prank(caller);
        // Call: invoke account-side validation.
        bytes4 result = account.isValidSignature(hash, signature);

        // Verify: delegated tuple matches exactly and configured value is bubbled unchanged.
        assertEq(result, organizationResult, "configured organization result should bubble through");
    }

    /// @dev Verifies successful 32-byte organization responses are interpreted using first four bytes.
    function testFuzz_ACI_IVS_16_isValidSignature_successfulWordReturn_usesFirstFourBytes(
        address caller,
        bytes32 hash,
        bytes calldata signature,
        bytes4 organizationResult
    ) public {
        // Setup: bound fuzzed signature bytes and configure canonical 32-byte ABI encoding of a bytes4 result.
        vm.assume(signature.length <= 2048);
        beacon.clearExpectedSignatureValidation();
        beacon.setSignatureValidationMode(AccountOrganizationBeaconMock.SignatureValidationMode.ReturnCustomWord);
        beacon.setSignatureResultWord(bytes32(organizationResult));

        vm.prank(caller);
        // Call: invoke account-side validation.
        bytes4 result = account.isValidSignature(hash, signature);

        // Verify: canonical ABI-encoded bytes4 words decode to the original bytes4.
        assertEq(result, organizationResult, "canonical 32-byte bytes4 encoding should decode to original bytes4");
    }

    /// @dev Verifies short successful organization responses always fail closed to invalid.
    function testFuzz_ACI_IVS_17_isValidSignature_shortSuccessfulReturn_alwaysReturnsInvalid(
        address caller,
        bytes32 hash,
        bytes calldata signature,
        bytes32 organizationWord
    ) public {
        // Setup: bound fuzzed signature bytes and configure short successful return payload.
        vm.assume(signature.length <= 2048);
        beacon.clearExpectedSignatureValidation();
        beacon.setSignatureValidationMode(AccountOrganizationBeaconMock.SignatureValidationMode.ReturnShortData);
        beacon.setSignatureResultWord(organizationWord);

        vm.prank(caller);
        // Call: invoke account-side validation.
        bytes4 result = account.isValidSignature(hash, signature);

        // Verify: successful responses shorter than 32 bytes must fail closed.
        assertEq(result, SignatureUtils.ERC1271_INVALID_VALUE, "short successful returns should be invalid");
    }

    /// @dev Verifies every organization revert mode fails closed to invalid for arbitrary callers and payloads.
    function testFuzz_ACI_IVS_18_isValidSignature_revertModeVariants_alwaysReturnInvalid(
        address caller,
        bytes32 hash,
        bytes calldata signature,
        uint8 modeSeed
    ) public {
        // Setup: bound fuzzed signature bytes and select a revert mode.
        vm.assume(signature.length <= 2048);
        AccountOrganizationBeaconMock.SignatureValidationMode[4] memory revertModes = [
            AccountOrganizationBeaconMock.SignatureValidationMode.RevertWithCustomError,
            AccountOrganizationBeaconMock.SignatureValidationMode.RevertWithString,
            AccountOrganizationBeaconMock.SignatureValidationMode.RevertWithPanic,
            AccountOrganizationBeaconMock.SignatureValidationMode.RevertWithoutData
        ];
        beacon.clearExpectedSignatureValidation();
        beacon.setSignatureValidationMode(revertModes[modeSeed % revertModes.length]);

        vm.prank(caller);
        // Call: invoke account-side validation.
        bytes4 result = account.isValidSignature(hash, signature);

        // Verify: revert behavior must never bubble and always returns invalid.
        assertEq(result, SignatureUtils.ERC1271_INVALID_VALUE, "organization revert modes should fail closed");
    }
}
