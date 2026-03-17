// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {SignatureUtils} from "libraries/SignatureUtils.sol";
import {MockERC1271ShortReturnSigner, MockERC1271ValidSigner} from "test/helpers/MockERC1271Signers.sol";
import {
    LibOrganizationAccountSignatureTestBase
} from "test/organization/libraries/LibOrganizationAccountSignature/LibOrganizationAccountSignatureTestBase.sol";

/**
 * @dev Unit tests for `LibOrganizationAccountSignature._validateRecoverySignature`.
 */
contract LibOrganizationAccountSignatureValidateRecoverySignatureTest is LibOrganizationAccountSignatureTestBase {
    /// @dev Verifies unconfigured recovery returns invalid value instead of magic. [ASIG-INV-2]
    function test_OAS_VRS_1__ASIG_INV_2_A_LOAS_VRS_1__LOAS_AHELP_1_validateRecoverySignature_recoveryAddressNotConfigured_returnsInvalidValue()
        public
    {
        // Setup: configure recovery as enabled but with zero recovery address.
        _setTxRecoveryState(address(0), true);
        bytes memory signatureData = _signHash(GUARDIAN_PK, MESSAGE_HASH);

        // Call: execute `validateRecoverySignatureViaLibrary` with an otherwise valid EOA signature.
        bytes4 actual = harness.validateRecoverySignatureViaLibrary(MESSAGE_HASH, signatureData);

        // Verify: unconfigured recovery address must fail closed.
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "zero recovery address should be invalid");
    }

    /// @dev Verifies enabled recovery with the configured signer returns magic value. [ASIG-INV-2]
    function test_ASIG_INV_2_B_LOAS_VRS_2_LOACS_VRS_1_validateRecoverySignature_recoveryEnabledAndValidSignature_returnsMagicValue()
        public
    {
        // Setup: configure enabled recovery state for the deterministic guardian signer.
        _setTxRecoveryState(guardianSigner, true);
        bytes memory signatureData = _signHash(GUARDIAN_PK, MESSAGE_HASH);

        // Call: execute `validateRecoverySignatureViaLibrary` with a valid recovery signature.
        bytes4 actual = harness.validateRecoverySignatureViaLibrary(MESSAGE_HASH, signatureData);

        // Verify: valid recovery signatures should be accepted.
        assertEq(actual, SignatureUtils.ERC1271_MAGIC_VALUE, "valid recovery signature should return magic");
    }

    /// @dev Verifies configured but disabled recovery returns invalid value. [ASIG-INV-2]
    function test_ASIG_INV_2_C_LOAS_VRS_3_LOACS_VRS_2__OAS_VRS_2_validateRecoverySignature_recoveryDisabled_returnsInvalidValue()
        public
    {
        // Setup: configure recovery address with `isEnabled=false`.
        _setTxRecoveryState(guardianSigner, false);
        bytes memory signatureData = _signHash(GUARDIAN_PK, MESSAGE_HASH);

        // Call: execute `validateRecoverySignatureViaLibrary` while recovery is disabled.
        bytes4 actual = harness.validateRecoverySignatureViaLibrary(MESSAGE_HASH, signatureData);

        // Verify: disabled recovery must fail closed.
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "disabled recovery should be invalid");
    }

    /// @dev Verifies LOAS-VRS-4: after disabling recovery, previously-valid recovery signatures are rejected.
    function test_LOAS_VRS_4_validateRecoverySignature_afterDisable_previouslyValidSignatureRejected() public {
        // Setup: enable recovery and confirm signature is accepted.
        _setTxRecoveryState(guardianSigner, true);
        bytes memory signatureData = _signHash(GUARDIAN_PK, MESSAGE_HASH);
        bytes4 enabledResult = harness.validateRecoverySignatureViaLibrary(MESSAGE_HASH, signatureData);
        assertEq(enabledResult, SignatureUtils.ERC1271_MAGIC_VALUE, "pre-condition: enabled recovery should accept");

        // Call: disable recovery and re-validate the same signature.
        _setTxRecoveryState(guardianSigner, false);
        bytes4 actual = harness.validateRecoverySignatureViaLibrary(MESSAGE_HASH, signatureData);

        // Verify: previously-valid signature must be rejected after disable.
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "signature should be rejected after disable");
    }

    /// @dev Verifies that a signature from a different configured recovery address is rejected.
    function test_ASIG_INV_2_D_LOAS_VRS_5_LOACS_VRS_2__OAS_VRS_5_LOAS_AHELP_1_validateRecoverySignature_wrongConfiguredRecoveryAddressSigner_returnsInvalidValue()
        public
    {
        // Setup: configure enabled recovery for `initiator2` and sign as guardian.
        _setTxRecoveryState(initiator2, true);
        bytes memory signatureData = _signHash(GUARDIAN_PK, MESSAGE_HASH);

        // Call: execute `validateRecoverySignatureViaLibrary` with non-matching signer/address pair.
        bytes4 actual = harness.validateRecoverySignatureViaLibrary(MESSAGE_HASH, signatureData);

        // Verify: signer must match configured recovery address.
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "mismatched recovery signer should be invalid");
    }

    /// @dev Verifies that valid EOA recovery signatures are accepted.
    function test_LOAS_VRS_6__OAS_VRS_3_validateRecoverySignature_validEOASignature_returnsMagicValue() public {
        // Setup: configure enabled recovery for deterministic guardian signer.
        _setTxRecoveryState(guardianSigner, true);
        bytes memory signatureData = _signHash(GUARDIAN_PK, MESSAGE_HASH);

        // Call: execute `validateRecoverySignatureViaLibrary` with an EOA signature.
        bytes4 actual = harness.validateRecoverySignatureViaLibrary(MESSAGE_HASH, signatureData);

        // Verify: EOA recovery signatures should be accepted.
        assertEq(actual, SignatureUtils.ERC1271_MAGIC_VALUE, "valid EOA recovery signature should return magic");
    }

    /// @dev Verifies that valid ERC-1271 recovery signatures are accepted.
    function test_LOAS_VRS_7__OAS_VRS_4_validateRecoverySignature_validERC1271Signature_returnsMagicValue() public {
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
    function test_LOAS_VRS_8__OAS_VRS_6__LOAS_AHELP_1_validateRecoverySignature_malformedSignatureBytes_returnsInvalidValue()
        public
    {
        // Setup: configure enabled recovery and build malformed packed signature bytes.
        _setTxRecoveryState(guardianSigner, true);
        bytes memory malformed = hex"1b";

        // Call: execute `validateRecoverySignatureViaLibrary` with malformed bytes.
        bytes4 actual = harness.validateRecoverySignatureViaLibrary(MESSAGE_HASH, malformed);

        // Verify: malformed recovery payloads should return invalid and never revert.
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "malformed recovery payload should fail closed");
    }

    /// @dev Verifies that malformed ERC-1271 signatures with truncated headers fail closed.
    function test_LOAS_VRS_9_validateRecoverySignature_malformedContractSignatureTruncatedHeader_returnsInvalidValue()
        public
    {
        // Setup: configure enabled recovery and build a truncated ERC-1271 payload (<23 bytes).
        _setTxRecoveryState(guardianSigner, true);
        bytes memory truncatedHeader = abi.encodePacked(uint8(0), bytes10(0));

        // Call: execute validation with malformed contract-signature bytes.
        bytes4 actual = harness.validateRecoverySignatureViaLibrary(MESSAGE_HASH, truncatedHeader);

        // Verify: malformed truncated headers should fail closed.
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "truncated ERC-1271 header should fail closed");
    }

    /// @dev Verifies that malformed ERC-1271 signatures with oversized declared inner length fail closed.
    function test_LOAS_VRS_10_validateRecoverySignature_malformedContractSignatureOversizedLength_returnsInvalidValue()
        public
    {
        // Setup: configure enabled recovery with a valid contract signer and craft invalid declared inner length.
        MockERC1271ValidSigner contractRecovery = new MockERC1271ValidSigner();
        _setTxRecoveryState(address(contractRecovery), true);
        bytes memory oversized = abi.encodePacked(uint8(0), address(contractRecovery), uint16(99), bytes("AA"));

        // Call: execute validation with malformed oversized-length payload.
        bytes4 actual = harness.validateRecoverySignatureViaLibrary(MESSAGE_HASH, oversized);

        // Verify: declared-inner-length overflow should fail closed.
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "oversized ERC-1271 inner length should fail closed");
    }

    /// @dev Verifies that ERC-1271 signers returning <32 bytes fail closed.
    function test_LOAS_VRS_11_validateRecoverySignature_shortReturnERC1271Signer_returnsInvalidValue() public {
        // Setup: configure enabled recovery with short-return ERC-1271 signer and build a contract signature payload.
        MockERC1271ShortReturnSigner contractRecovery = new MockERC1271ShortReturnSigner();
        _setTxRecoveryState(address(contractRecovery), true);
        bytes memory signatureData = _buildContractSignature(address(contractRecovery), hex"CAFE");

        // Call: execute validation against short-return signer.
        bytes4 actual = harness.validateRecoverySignatureViaLibrary(MESSAGE_HASH, signatureData);

        // Verify: <32-byte return data should fail closed.
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "short-return ERC-1271 signer should fail closed");
    }

    /// @dev Verifies that a high-s (malleable) EOA recovery signature returns ERC-1271 invalid value.
    function test_LOAS_VRS_12_validateRecoverySignature_highSEOASignature_returnsInvalidValue() public {
        // Setup: configure enabled recovery and build a malleable high-s signature from the guardian key.
        _setTxRecoveryState(guardianSigner, true);
        bytes memory highSSig = _makeHighSSignature(GUARDIAN_PK, MESSAGE_HASH);

        // Call: execute `validateRecoverySignatureViaLibrary` with a high-s signature.
        bytes4 actual = harness.validateRecoverySignatureViaLibrary(MESSAGE_HASH, highSSig);

        // Verify: malleable signatures should be rejected at the wrapper level.
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "high-s recovery signature should fail closed");
    }

    /// @dev Verifies TXR-INT-4: signature lifecycle transitions with tx recovery enable/disable/re-enable.
    function test_TXR_INT_4_recoverySignatureLifecycle_enableDisableReenable_tracksAcceptance() public {
        // Setup
        bytes memory signatureData = _signHash(GUARDIAN_PK, MESSAGE_HASH);

        // Call
        _setTxRecoveryState(guardianSigner, true);
        bytes4 enabledResult = harness.validateRecoverySignatureViaLibrary(MESSAGE_HASH, signatureData);

        _setTxRecoveryState(guardianSigner, false);
        bytes4 disabledResult = harness.validateRecoverySignatureViaLibrary(MESSAGE_HASH, signatureData);

        _setTxRecoveryState(guardianSigner, true);
        bytes4 reenabledResult = harness.validateRecoverySignatureViaLibrary(MESSAGE_HASH, signatureData);

        // Verify
        assertEq(enabledResult, SignatureUtils.ERC1271_MAGIC_VALUE, "enabled recovery should accept valid signatures");
        assertEq(disabledResult, SignatureUtils.ERC1271_INVALID_VALUE, "disabled recovery should reject signatures");
        assertEq(
            reenabledResult, SignatureUtils.ERC1271_MAGIC_VALUE, "re-enabling recovery should accept signatures again"
        );
    }
}
