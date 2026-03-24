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
    uint256 internal constant DEFAULT_EXPIRATION_OFFSET = 1 days;

    /// @dev Verifies unconfigured recovery returns invalid value instead of magic.
    function test_validateRecoverySignature_recoveryAddressNotConfigured_returnsInvalidValue() public {
        // Setup: configure recovery as enabled but with zero recovery address.
        _setTxRecoveryState(address(0), true);
        uint256 expiration = block.timestamp + DEFAULT_EXPIRATION_OFFSET;
        bytes memory signatureData =
            abi.encode(expiration, _signRecoverySignature(GUARDIAN_PK, ACCOUNT, MESSAGE_HASH, expiration));

        // Call: execute `validateRecoverySignatureViaLibrary` with an otherwise valid EOA signature.
        bytes4 actual = harness.validateRecoverySignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signatureData);

        // Verify: unconfigured recovery address must fail closed.
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "zero recovery address should be invalid");
    }

    /// @dev Verifies enabled recovery with the configured signer returns magic value.
    function test_validateRecoverySignature_recoveryEnabledAndValidSignature_returnsMagicValue() public {
        // Setup: configure enabled recovery state for the deterministic guardian signer.
        _setTxRecoveryState(guardianSigner, true);
        uint256 expiration = block.timestamp + DEFAULT_EXPIRATION_OFFSET;
        bytes memory signatureData =
            abi.encode(expiration, _signRecoverySignature(GUARDIAN_PK, ACCOUNT, MESSAGE_HASH, expiration));

        // Call: execute `validateRecoverySignatureViaLibrary` with a valid recovery signature.
        bytes4 actual = harness.validateRecoverySignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signatureData);

        // Verify: valid recovery signatures should be accepted.
        assertEq(actual, SignatureUtils.ERC1271_MAGIC_VALUE, "valid recovery signature should return magic");
    }

    /// @dev Verifies configured but disabled recovery returns invalid value.
    function test_validateRecoverySignature_recoveryDisabled_returnsInvalidValue() public {
        // Setup: configure recovery address with `isEnabled=false`.
        _setTxRecoveryState(guardianSigner, false);
        uint256 expiration = block.timestamp + DEFAULT_EXPIRATION_OFFSET;
        bytes memory signatureData =
            abi.encode(expiration, _signRecoverySignature(GUARDIAN_PK, ACCOUNT, MESSAGE_HASH, expiration));

        // Call: execute `validateRecoverySignatureViaLibrary` while recovery is disabled.
        bytes4 actual = harness.validateRecoverySignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signatureData);

        // Verify: disabled recovery must fail closed.
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "disabled recovery should be invalid");
    }

    /// @dev Verifies after disabling recovery, previously-valid recovery signatures are rejected.
    function test_validateRecoverySignature_afterDisable_previouslyValidSignatureRejected() public {
        // Setup: enable recovery and confirm signature is accepted.
        _setTxRecoveryState(guardianSigner, true);
        uint256 expiration = block.timestamp + DEFAULT_EXPIRATION_OFFSET;
        bytes memory signatureData =
            abi.encode(expiration, _signRecoverySignature(GUARDIAN_PK, ACCOUNT, MESSAGE_HASH, expiration));
        bytes4 enabledResult = harness.validateRecoverySignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signatureData);
        assertEq(enabledResult, SignatureUtils.ERC1271_MAGIC_VALUE, "pre-condition: enabled recovery should accept");

        // Call: disable recovery and re-validate the same signature.
        _setTxRecoveryState(guardianSigner, false);
        bytes4 actual = harness.validateRecoverySignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signatureData);

        // Verify: previously-valid signature must be rejected after disable.
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "signature should be rejected after disable");
    }

    /// @dev Verifies that a signature from a different configured recovery address is rejected.
    function test_validateRecoverySignature_wrongConfiguredRecoveryAddressSigner_returnsInvalidValue() public {
        // Setup: configure enabled recovery for `initiator2` and sign as guardian.
        _setTxRecoveryState(initiator2, true);
        uint256 expiration = block.timestamp + DEFAULT_EXPIRATION_OFFSET;
        bytes memory signatureData =
            abi.encode(expiration, _signRecoverySignature(GUARDIAN_PK, ACCOUNT, MESSAGE_HASH, expiration));

        // Call: execute `validateRecoverySignatureViaLibrary` with non-matching signer/address pair.
        bytes4 actual = harness.validateRecoverySignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signatureData);

        // Verify: signer must match configured recovery address.
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "mismatched recovery signer should be invalid");
    }

    /// @dev Verifies that valid EOA recovery signatures are accepted.
    function test_validateRecoverySignature_validEOASignature_returnsMagicValue() public {
        // Setup: configure enabled recovery for deterministic guardian signer.
        _setTxRecoveryState(guardianSigner, true);
        uint256 expiration = block.timestamp + DEFAULT_EXPIRATION_OFFSET;
        bytes memory signatureData =
            abi.encode(expiration, _signRecoverySignature(GUARDIAN_PK, ACCOUNT, MESSAGE_HASH, expiration));

        // Call: execute `validateRecoverySignatureViaLibrary` with an EOA signature.
        bytes4 actual = harness.validateRecoverySignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signatureData);

        // Verify: EOA recovery signatures should be accepted.
        assertEq(actual, SignatureUtils.ERC1271_MAGIC_VALUE, "valid EOA recovery signature should return magic");
    }

    /// @dev Verifies that valid ERC-1271 recovery signatures are accepted.
    function test_validateRecoverySignature_validERC1271Signature_returnsMagicValue() public {
        // Setup: configure enabled recovery for an ERC-1271 signer contract.
        MockERC1271ValidSigner contractRecovery = new MockERC1271ValidSigner();
        _setTxRecoveryState(address(contractRecovery), true);

        uint256 expiration = block.timestamp + DEFAULT_EXPIRATION_OFFSET;
        bytes memory signatureData =
            abi.encode(expiration, _buildContractSignature(address(contractRecovery), hex"AABB"));

        // Call: execute `validateRecoverySignatureViaLibrary` with a contract-signature payload.
        bytes4 actual = harness.validateRecoverySignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signatureData);

        // Verify: valid ERC-1271 recovery signatures should be accepted.
        assertEq(actual, SignatureUtils.ERC1271_MAGIC_VALUE, "valid ERC-1271 recovery signature should return magic");
    }

    /// @dev Verifies that malformed recovery signature bytes fail closed with ERC-1271 invalid value.
    function test_validateRecoverySignature_malformedSignatureBytes_returnsInvalidValue() public {
        // Setup: configure enabled recovery and build malformed packed signature bytes.
        _setTxRecoveryState(guardianSigner, true);
        bytes memory malformed = hex"1b";

        // Call: execute `validateRecoverySignatureViaLibrary` with malformed bytes.
        bytes4 actual = harness.validateRecoverySignatureViaLibrary(ACCOUNT, MESSAGE_HASH, malformed);

        // Verify: malformed recovery payloads should return invalid and never revert.
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "malformed recovery payload should fail closed");
    }

    /// @dev Verifies that malformed ERC-1271 signatures with truncated headers fail closed.
    function test_validateRecoverySignature_malformedContractSignatureTruncatedHeader_returnsInvalidValue() public {
        // Setup: configure enabled recovery and build a truncated ERC-1271 payload (<23 bytes).
        _setTxRecoveryState(guardianSigner, true);
        uint256 expiration = block.timestamp + DEFAULT_EXPIRATION_OFFSET;
        bytes memory signatureData = abi.encode(expiration, abi.encodePacked(uint8(0), bytes10(0)));

        // Call: execute validation with malformed contract-signature bytes.
        bytes4 actual = harness.validateRecoverySignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signatureData);

        // Verify: malformed truncated headers should fail closed.
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "truncated ERC-1271 header should fail closed");
    }

    /// @dev Verifies that malformed ERC-1271 signatures with oversized declared inner length fail closed.
    function test_validateRecoverySignature_malformedContractSignatureOversizedLength_returnsInvalidValue() public {
        // Setup: configure enabled recovery with a valid contract signer and craft invalid declared inner length.
        MockERC1271ValidSigner contractRecovery = new MockERC1271ValidSigner();
        _setTxRecoveryState(address(contractRecovery), true);
        uint256 expiration = block.timestamp + DEFAULT_EXPIRATION_OFFSET;
        bytes memory oversized = abi.encodePacked(uint8(0), address(contractRecovery), uint16(99), bytes("AA"));
        bytes memory signatureData = abi.encode(expiration, oversized);

        // Call: execute validation with malformed oversized-length payload.
        bytes4 actual = harness.validateRecoverySignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signatureData);

        // Verify: declared-inner-length overflow should fail closed.
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "oversized ERC-1271 inner length should fail closed");
    }

    /// @dev Verifies that ERC-1271 signers returning <32 bytes fail closed.
    function test_validateRecoverySignature_shortReturnERC1271Signer_returnsInvalidValue() public {
        // Setup: configure enabled recovery with short-return ERC-1271 signer and build a contract signature payload.
        MockERC1271ShortReturnSigner contractRecovery = new MockERC1271ShortReturnSigner();
        _setTxRecoveryState(address(contractRecovery), true);
        uint256 expiration = block.timestamp + DEFAULT_EXPIRATION_OFFSET;
        bytes memory signatureData =
            abi.encode(expiration, _buildContractSignature(address(contractRecovery), hex"CAFE"));

        // Call: execute validation against short-return signer.
        bytes4 actual = harness.validateRecoverySignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signatureData);

        // Verify: <32-byte return data should fail closed.
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "short-return ERC-1271 signer should fail closed");
    }

    /// @dev Verifies that a high-s (malleable) EOA recovery signature returns ERC-1271 invalid value.
    function test_validateRecoverySignature_highSEOASignature_returnsInvalidValue() public {
        // Setup: configure enabled recovery and build a malleable high-s signature from the guardian key.
        _setTxRecoveryState(guardianSigner, true);
        uint256 expiration = block.timestamp + DEFAULT_EXPIRATION_OFFSET;
        bytes32 recoveryHash = harness.getRecoverySignatureHashViaLibrary(ACCOUNT, MESSAGE_HASH, expiration);
        bytes memory highSSig = _makeHighSSignature(GUARDIAN_PK, recoveryHash);
        bytes memory signatureData = abi.encode(expiration, highSSig);

        // Call: execute `validateRecoverySignatureViaLibrary` with a high-s signature.
        bytes4 actual = harness.validateRecoverySignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signatureData);

        // Verify: malleable signatures should be rejected at the wrapper level.
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "high-s recovery signature should fail closed");
    }

    /// @dev Verifies signature lifecycle transitions with tx recovery enable/disable/re-enable.
    function test_recoverySignatureLifecycle_enableDisableReenable_tracksAcceptance() public {
        // Setup
        uint256 expiration = block.timestamp + DEFAULT_EXPIRATION_OFFSET;
        bytes memory signatureData =
            abi.encode(expiration, _signRecoverySignature(GUARDIAN_PK, ACCOUNT, MESSAGE_HASH, expiration));

        // Call
        _setTxRecoveryState(guardianSigner, true);
        bytes4 enabledResult = harness.validateRecoverySignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signatureData);

        _setTxRecoveryState(guardianSigner, false);
        bytes4 disabledResult = harness.validateRecoverySignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signatureData);

        _setTxRecoveryState(guardianSigner, true);
        bytes4 reenabledResult = harness.validateRecoverySignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signatureData);

        // Verify
        assertEq(enabledResult, SignatureUtils.ERC1271_MAGIC_VALUE, "enabled recovery should accept valid signatures");
        assertEq(disabledResult, SignatureUtils.ERC1271_INVALID_VALUE, "disabled recovery should reject signatures");
        assertEq(
            reenabledResult, SignatureUtils.ERC1271_MAGIC_VALUE, "re-enabling recovery should accept signatures again"
        );
    }

    /// @dev Verifies that a recovery signature valid for one account is rejected for a different sibling account.
    function test_validateRecoverySignature_crossAccountReplay_returnsInvalidValue() public {
        // Setup: configure enabled recovery and build a valid recovery signature for ACCOUNT.
        _setTxRecoveryState(guardianSigner, true);
        uint256 expiration = block.timestamp + DEFAULT_EXPIRATION_OFFSET;
        bytes memory signatureData =
            abi.encode(expiration, _signRecoverySignature(GUARDIAN_PK, ACCOUNT, MESSAGE_HASH, expiration));

        // Call: validate for the signed account, then replay against a sibling account.
        bytes4 signedAccountResult = harness.validateRecoverySignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signatureData);
        // forgefmt: disable-next-item
        bytes4 replayAccountResult = harness.validateRecoverySignatureViaLibrary(
            OTHER_ACCOUNT, MESSAGE_HASH, signatureData
        );

        // Verify: cross-account replay should fail within same organization.
        assertEq(signedAccountResult, SignatureUtils.ERC1271_MAGIC_VALUE, "signed account should validate");
        assertEq(replayAccountResult, SignatureUtils.ERC1271_INVALID_VALUE, "cross-account replay should be invalid");
    }

    /// @dev Verifies that an expired recovery signature returns ERC-1271 invalid value.
    function test_validateRecoverySignature_expired_returnsInvalidValue() public {
        // Setup: configure enabled recovery and build a recovery signature that has already expired.
        _setTxRecoveryState(guardianSigner, true);
        uint256 expiration = block.timestamp - 1;
        bytes memory signatureData =
            abi.encode(expiration, _signRecoverySignature(GUARDIAN_PK, ACCOUNT, MESSAGE_HASH, expiration));

        // Call: execute `validateRecoverySignatureViaLibrary` with an expired recovery signature.
        bytes4 actual = harness.validateRecoverySignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signatureData);

        // Verify: expired recovery signatures must fail closed.
        assertEq(actual, SignatureUtils.ERC1271_INVALID_VALUE, "expired recovery signature should be invalid");
    }

    /// @dev Verifies that `block.timestamp == expirationTimestamp` passes (strictly-greater check).
    function test_validateRecoverySignature_expirationBoundary_exactTimestampPasses() public {
        // Setup: configure enabled recovery and build a recovery signature expiring at exactly the current timestamp.
        _setTxRecoveryState(guardianSigner, true);
        uint256 expiration = block.timestamp;
        bytes memory signatureData =
            abi.encode(expiration, _signRecoverySignature(GUARDIAN_PK, ACCOUNT, MESSAGE_HASH, expiration));

        // Call: execute `validateRecoverySignatureViaLibrary` at the exact expiration boundary.
        bytes4 actual = harness.validateRecoverySignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signatureData);

        // Verify: exact boundary (block.timestamp == expirationTimestamp) should pass.
        assertEq(actual, SignatureUtils.ERC1271_MAGIC_VALUE, "exact expiration boundary should pass");
    }

    /// @dev Verifies that a recovery signature expires after the timestamp elapses.
    function test_validateRecoverySignature_expiresAfterTimestampElapses() public {
        // Setup: configure enabled recovery and sign at the current expiration.
        _setTxRecoveryState(guardianSigner, true);
        uint256 expiration = block.timestamp + DEFAULT_EXPIRATION_OFFSET;
        bytes memory signatureData =
            abi.encode(expiration, _signRecoverySignature(GUARDIAN_PK, ACCOUNT, MESSAGE_HASH, expiration));

        // Call: verify signature is valid before expiration.
        bytes4 beforeResult = harness.validateRecoverySignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signatureData);

        // Call: warp past expiration and re-validate.
        vm.warp(expiration + 1);
        bytes4 afterResult = harness.validateRecoverySignatureViaLibrary(ACCOUNT, MESSAGE_HASH, signatureData);

        // Verify: signature should be valid before and invalid after expiration.
        assertEq(beforeResult, SignatureUtils.ERC1271_MAGIC_VALUE, "pre-expiration signature should be valid");
        assertEq(afterResult, SignatureUtils.ERC1271_INVALID_VALUE, "post-expiration signature should be invalid");
    }
}
