// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {SignatureUtils} from "libraries/SignatureUtils.sol";
import {MockERC1271ValidSigner} from "test/helpers/MockERC1271Signers.sol";
import {
    LibOrganizationAccountSignatureTestBase
} from "test/organization/libraries/LibOrganizationAccountSignature/LibOrganizationAccountSignatureTestBase.sol";

/**
 * @dev Unit tests for `LibOrganizationAccountSignature._validateRecoverySignature`.
 */
contract LibOrganizationAccountSignatureValidateRecoverySignatureTest is LibOrganizationAccountSignatureTestBase {
    /// @dev Verifies that enabled recovery with a valid recovery signature returns ERC-1271 magic value.
    function test_LOAS_VRS_1_validateRecoverySignature_recoveryEnabledAndValidSignature_returnsMagicValue() public {
        // Setup: configure enabled recovery state for the deterministic guardian signer.
        _setTxRecoveryState(guardianSigner, true);
        bytes memory signatureData = _signHash(GUARDIAN_PK, MESSAGE_HASH);

        // Call: execute `validateRecoverySignatureViaLibrary` with a valid recovery signature.
        bytes4 actual = harness.validateRecoverySignatureViaLibrary(MESSAGE_HASH, signatureData);

        // Verify: valid recovery signatures should be accepted.
        assertEq(actual, SignatureUtils.ERC1271_MAGIC_VALUE, "valid recovery signature should return magic");
    }

    /// @dev Verifies that disabled recovery returns ERC-1271 invalid value.
    function test_LOAS_VRS_2_validateRecoverySignature_recoveryDisabled_returnsInvalidValue() public {
        // Setup: configure recovery address with `isEnabled=false`.
        _setTxRecoveryState(guardianSigner, false);
        bytes memory signatureData = _signHash(GUARDIAN_PK, MESSAGE_HASH);

        // Call: execute `validateRecoverySignatureViaLibrary` while recovery is disabled.
        bytes4 actual = harness.validateRecoverySignatureViaLibrary(MESSAGE_HASH, signatureData);

        // Verify: disabled recovery must fail closed.
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "disabled recovery should be invalid");
    }

    /// @dev Verifies that enabled recovery with an invalid signer returns ERC-1271 invalid value.
    function test_LOAS_VRS_3_validateRecoverySignature_enabledRecoveryWrongSigner_returnsInvalidValue() public {
        // Setup: configure enabled recovery for guardian signer and sign with a different key.
        _setTxRecoveryState(guardianSigner, true);
        bytes memory signatureData = _signHash(REVIEWER_PK_1, MESSAGE_HASH);

        // Call: execute `validateRecoverySignatureViaLibrary` with a wrong-signer signature.
        bytes4 actual = harness.validateRecoverySignatureViaLibrary(MESSAGE_HASH, signatureData);

        // Verify: signatures from non-recovery signers should be rejected.
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "wrong signer should be invalid");
    }

    /// @dev Verifies that unconfigured recovery storage returns ERC-1271 invalid value.
    function test_LOAS_VRS_4_validateRecoverySignature_recoveryAddressNotConfigured_returnsInvalidValue() public {
        // Setup: configure recovery as enabled but with zero recovery address.
        _setTxRecoveryState(address(0), true);
        bytes memory signatureData = _signHash(GUARDIAN_PK, MESSAGE_HASH);

        // Call: execute `validateRecoverySignatureViaLibrary` with an otherwise valid EOA signature.
        bytes4 actual = harness.validateRecoverySignatureViaLibrary(MESSAGE_HASH, signatureData);

        // Verify: unconfigured recovery address must fail closed.
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "zero recovery address should be invalid");
    }

    /// @dev Verifies that a signature from a different configured recovery address is rejected.
    function test_LOAS_VRS_5_validateRecoverySignature_wrongConfiguredRecoveryAddressSigner_returnsInvalidValue() public {
        // Setup: configure enabled recovery for `initiator2` and sign as guardian.
        _setTxRecoveryState(initiator2, true);
        bytes memory signatureData = _signHash(GUARDIAN_PK, MESSAGE_HASH);

        // Call: execute `validateRecoverySignatureViaLibrary` with non-matching signer/address pair.
        bytes4 actual = harness.validateRecoverySignatureViaLibrary(MESSAGE_HASH, signatureData);

        // Verify: signer must match configured recovery address.
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "mismatched recovery signer should be invalid");
    }

    /// @dev Verifies that valid EOA recovery signatures are accepted.
    function test_LOAS_VRS_6_validateRecoverySignature_validEOASignature_returnsMagicValue() public {
        // Setup: configure enabled recovery for deterministic guardian signer.
        _setTxRecoveryState(guardianSigner, true);
        bytes memory signatureData = _signHash(GUARDIAN_PK, MESSAGE_HASH);

        // Call: execute `validateRecoverySignatureViaLibrary` with an EOA signature.
        bytes4 actual = harness.validateRecoverySignatureViaLibrary(MESSAGE_HASH, signatureData);

        // Verify: EOA recovery signatures should be accepted.
        assertEq(actual, SignatureUtils.ERC1271_MAGIC_VALUE, "valid EOA recovery signature should return magic");
    }

    /// @dev Verifies that valid ERC-1271 recovery signatures are accepted.
    function test_LOAS_VRS_7_validateRecoverySignature_validERC1271Signature_returnsMagicValue() public {
        // Setup: configure enabled recovery for an ERC-1271 signer contract.
        MockERC1271ValidSigner contractRecovery = new MockERC1271ValidSigner();
        _setTxRecoveryState(address(contractRecovery), true);

        bytes memory signatureData = _buildContractSignature(address(contractRecovery), hex"AABB");

        // Call: execute `validateRecoverySignatureViaLibrary` with a contract-signature payload.
        bytes4 actual = harness.validateRecoverySignatureViaLibrary(MESSAGE_HASH, signatureData);

        // Verify: valid ERC-1271 recovery signatures should be accepted.
        assertEq(actual, SignatureUtils.ERC1271_MAGIC_VALUE, "valid ERC-1271 recovery signature should return magic");
    }

    /// @dev Verifies that malformed recovery signature bytes fail closed with ERC-1271 invalid value.
    function test_LOAS_VRS_8_validateRecoverySignature_malformedSignatureBytes_returnsInvalidValue() public {
        // Setup: configure enabled recovery and build malformed packed signature bytes.
        _setTxRecoveryState(guardianSigner, true);
        bytes memory malformed = hex"1b";

        // Call: execute `validateRecoverySignatureViaLibrary` with malformed bytes.
        bytes4 actual = harness.validateRecoverySignatureViaLibrary(MESSAGE_HASH, malformed);

        // Verify: malformed recovery payloads should return invalid and never revert.
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "malformed recovery payload should fail closed");
    }
}
