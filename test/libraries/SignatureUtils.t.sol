// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";

import {SignatureUtils} from "libraries/SignatureUtils.sol";
import {SignatureTestHelpers} from "test/helpers/SignatureTestHelpers.sol";

import {
    MockERC1271CustomReturn,
    MockERC1271EmptyReturnSigner,
    MockERC1271ExtraBytesSigner,
    MockERC1271GasConsumer,
    MockERC1271LargeReturnSigner,
    MockERC1271Return31BytesSigner,
    MockERC1271RevertingSigner,
    MockERC1271RightPaddedSigner,
    MockERC1271ShortReturnSigner,
    MockERC1271StateModifierSigner,
    MockERC1271ValidSigner,
    MockERC1271WrongMagicSigner
} from "test/helpers/MockERC1271Signers.sol";

/**
 * @dev SignatureUtilsHarness
 *      Test harness that exposes all internal SignatureUtils library functions
 *      (both the public-facing ones and the previously-private helpers) via
 *      public wrappers so they can be called from the test contract.
 */
contract SignatureUtilsHarness {
    /// @param signature The signature bytes to recover from
    /// @param hash The hash that was signed
    /// @return The recovered signer address
    function recoverSignerOrRevert(bytes memory signature, bytes32 hash) external view returns (address) {
        return SignatureUtils.recoverSignerOrRevert(signature, hash);
    }

    /// @param signature The signature bytes to recover from
    /// @param hash The hash that was signed
    /// @return success True if recovery succeeded
    /// @return signer The recovered signer address, or address(0) on failure
    function tryRecoverSigner(bytes memory signature, bytes32 hash) external view returns (bool, address) {
        return SignatureUtils.tryRecoverSigner(signature, hash);
    }

    /// @param signatures Concatenated signature bytes
    /// @param offset Byte offset to start recovery at
    /// @param hash The hash that was signed
    /// @return signer The recovered signer address
    /// @return nextOffset The byte offset after the consumed signature
    function recoverSignerAtOffsetOrRevert(bytes memory signatures, uint256 offset, bytes32 hash)
        external
        view
        returns (address, uint256)
    {
        return SignatureUtils.recoverSignerAtOffsetOrRevert(signatures, offset, hash);
    }

    /// @param signatures Concatenated signature bytes
    /// @param offset Byte offset to start recovery at
    /// @param hash The hash that was signed
    /// @return success True if recovery succeeded
    /// @return signer The recovered signer address, or address(0) on failure
    /// @return nextOffset The byte offset after the consumed signature, or 0 on failure
    function tryRecoverSignerAtOffset(bytes memory signatures, uint256 offset, bytes32 hash)
        external
        view
        returns (bool, address, uint256)
    {
        return SignatureUtils.tryRecoverSignerAtOffset(signatures, offset, hash);
    }

    /// @param signer The contract address implementing ERC-1271
    /// @param hash The hash that was signed
    /// @param signature The signature bytes passed to isValidSignature
    /// @return True if the contract returns the ERC-1271 magic value
    function isValidERC1271SignatureNow(address signer, bytes32 hash, bytes memory signature)
        external
        view
        returns (bool)
    {
        return SignatureUtils._isValidERC1271SignatureNow(signer, hash, signature);
    }

    /// @param signatures Concatenated signature bytes
    /// @param offset Byte offset to start recovery at
    /// @param hash The hash that was signed
    /// @return success True if contract signer was recovered
    /// @return signer The recovered contract address, or address(0) on failure
    function tryRecoverContractSigner(bytes memory signatures, uint256 offset, bytes32 hash)
        external
        view
        returns (bool, address)
    {
        return SignatureUtils._tryRecoverContractSigner(signatures, offset, hash);
    }

    /// @param signatures Concatenated signature bytes
    /// @param offset Byte offset to start recovery at
    /// @param hash The hash that was signed
    /// @param v The recovery id byte (27 or 28)
    /// @return success True if EOA signer was recovered
    /// @return signer The recovered EOA address, or address(0) on failure
    function tryRecoverEOASigner(bytes memory signatures, uint256 offset, bytes32 hash, uint8 v)
        external
        pure
        returns (bool, address)
    {
        return SignatureUtils._tryRecoverEOASigner(signatures, offset, hash, v);
    }

    /// @param data The byte array to read from
    /// @param offset The byte offset to read v from
    /// @return The v byte at the given offset
    function getVByte(bytes memory data, uint256 offset) external pure returns (uint8) {
        return SignatureUtils._getVByte(data, offset);
    }

    /// @param data The byte array containing the contract signature header
    /// @param offset The byte offset to the start of the header
    /// @return The contract signer address extracted from the header
    function getContractSigner(bytes memory data, uint256 offset) external pure returns (address) {
        return SignatureUtils._getContractSigner(data, offset);
    }

    /// @param data The byte array containing the contract signature header
    /// @param offset The byte offset to the start of the header
    /// @return The inner signature length in bytes
    function getContractSignatureLength(bytes memory data, uint256 offset) external pure returns (uint16) {
        return SignatureUtils._getContractSignatureLength(data, offset);
    }

    /// @param data The byte array containing the contract signature
    /// @param offset The byte offset to the start of the inner signature
    /// @param sigLength The length of the inner signature to extract
    /// @return The extracted inner signature bytes
    function extractContractInnerSignature(bytes memory data, uint256 offset, uint16 sigLength)
        external
        pure
        returns (bytes memory)
    {
        return SignatureUtils._extractContractInnerSignature(data, offset, sigLength);
    }
}

/**
 * @dev SignatureUtilsTest
 *      Comprehensive tests for SignatureUtils library covering EOA (ECDSA)
 *         and ERC-1271 contract signature validation.
 *      Test coverage spans:
 *      - tryRecoverSigner (core implementation)
 *      - recoverSignerOrRevert (production-path verification)
 *      - tryRecoverSignerAtOffset (multi-sig offset recovery)
 *      - recoverSignerAtOffsetOrRevert (multi-sig revert cases)
 *      - helper functions tests (_getVByte, _getContractSigner, etc.)
 *      - Fuzz tests
 * @author Den Technologies Inc
 */
contract SignatureUtilsTest is SignatureTestHelpers {
    SignatureUtilsHarness public harness;

    /// @dev A well-known test private key (value = 1). Never use in production.
    uint256 constant TEST_PK_1 = 0x1;

    /// @dev A second test private key (value = 2).
    uint256 constant TEST_PK_2 = 0x2;

    /// @dev A third test private key (value = 3).
    uint256 constant TEST_PK_3 = 0x3;

    /// @dev A sample hash to sign in tests.
    bytes32 constant TEST_HASH = keccak256("test message");

    /// @dev A different hash to verify wrong-hash behavior.
    bytes32 constant WRONG_HASH = keccak256("wrong message");

    /// @dev Mock ERC-1271 contracts deployed once in setUp.
    MockERC1271ValidSigner public validSigner1271;
    MockERC1271WrongMagicSigner public wrongMagicSigner1271;
    MockERC1271RevertingSigner public revertingSigner1271;
    MockERC1271GasConsumer public gasConsumerSigner1271;
    MockERC1271ShortReturnSigner public shortReturnSigner1271;
    MockERC1271EmptyReturnSigner public emptyReturnSigner1271;
    MockERC1271ExtraBytesSigner public extraBytesSigner1271;
    MockERC1271LargeReturnSigner public largeReturnSigner1271;
    MockERC1271StateModifierSigner public stateModifierSigner1271;
    MockERC1271RightPaddedSigner public rightPaddedSigner1271;
    MockERC1271Return31BytesSigner public return31BytesSigner1271;

    function setUp() public {
        harness = new SignatureUtilsHarness();

        // Deploy all ERC-1271 mock contracts
        validSigner1271 = new MockERC1271ValidSigner();
        wrongMagicSigner1271 = new MockERC1271WrongMagicSigner();
        revertingSigner1271 = new MockERC1271RevertingSigner();
        gasConsumerSigner1271 = new MockERC1271GasConsumer();
        shortReturnSigner1271 = new MockERC1271ShortReturnSigner();
        emptyReturnSigner1271 = new MockERC1271EmptyReturnSigner();
        extraBytesSigner1271 = new MockERC1271ExtraBytesSigner();
        largeReturnSigner1271 = new MockERC1271LargeReturnSigner();
        stateModifierSigner1271 = new MockERC1271StateModifierSigner();
        rightPaddedSigner1271 = new MockERC1271RightPaddedSigner();
        return31BytesSigner1271 = new MockERC1271Return31BytesSigner();
    }

    /**
     * @dev Asserts that `tryRecoverSigner` fails for the given signature and hash.
     *      When `tryRecoverSigner` fails, it must return the canonical tuple:
     *      `(false, address(0))`.
     * @param signature The signature bytes that should fail recovery
     * @param hash The hash used for recovery
     * @param failureMessage Assertion message on failure
     */
    function _assertTryRecoverSignerFails(bytes memory signature, bytes32 hash, string memory failureMessage)
        internal
        view
    {
        (bool success, address signer) = harness.tryRecoverSigner(signature, hash);
        assertFalse(success, failureMessage);
        assertEq(signer, address(0), "Signer should be address(0)");
    }

    /// @dev Asserts that `recoverSignerOrRevert` reverts for the given signature and hash.
    /// @param signature The signature bytes that should cause revert
    /// @param hash The hash used for recovery
    function _assertRecoverSignerOrRevertReverts(bytes memory signature, bytes32 hash) internal {
        vm.expectRevert(SignatureUtils.SignatureRecoveryFailed.selector);
        harness.recoverSignerOrRevert(signature, hash);
    }

    /**
     * @dev Asserts that `tryRecoverSignerAtOffset` fails for the given signatures, offset, and hash.
     *      When `tryRecoverSignerAtOffset` fails, it must return the canonical tuple:
     *      `(false, address(0), 0)`.
     * @param signatures Concatenated signature bytes
     * @param offset Byte offset to start recovery at
     * @param hash The hash used for recovery
     * @param failureMessage Assertion message on failure
     */
    function _assertTryRecoverSignerAtOffsetFails(
        bytes memory signatures,
        uint256 offset,
        bytes32 hash,
        string memory failureMessage
    ) internal view {
        (bool success, address signer, uint256 nextOffset) = harness.tryRecoverSignerAtOffset(signatures, offset, hash);
        assertFalse(success, failureMessage);
        assertEq(signer, address(0), "Signer should be address(0)");
        assertEq(nextOffset, 0, "Next offset should be 0");
    }

    /// @dev Asserts that `recoverSignerAtOffsetOrRevert` reverts for the given signatures, offset, and hash.
    /// @param signatures Concatenated signature bytes
    /// @param offset Byte offset to start recovery at
    /// @param hash The hash used for recovery
    function _assertRecoverSignerAtOffsetOrRevertReverts(bytes memory signatures, uint256 offset, bytes32 hash)
        internal
    {
        vm.expectRevert(SignatureUtils.SignatureRecoveryFailed.selector);
        harness.recoverSignerAtOffsetOrRevert(signatures, offset, hash);
    }

    /**
     * @dev Asserts that `tryRecoverSigner` and `recoverSignerOrRevert` both succeed for the given signature and hash.
     *      When both succeed, they must produce identical signer.
     * @param signature The signature bytes that should succeed
     * @param hash The hash used for recovery
     * @param expectedSigner The address that should be recovered
     * @param failureMessage Assertion message on failure
     */
    function _assertRecoverSignerPairSucceeds(
        bytes memory signature,
        bytes32 hash,
        address expectedSigner,
        string memory failureMessage
    ) internal view {
        (bool successTry, address signerTry) = harness.tryRecoverSigner(signature, hash);
        assertTrue(successTry, failureMessage);
        assertEq(signerTry, expectedSigner, "tryRecoverSigner signer mismatch");

        address signerRevert = harness.recoverSignerOrRevert(signature, hash);
        assertEq(signerRevert, expectedSigner, "recoverSignerOrRevert signer mismatch");
    }

    /// @dev Asserts that `tryRecoverSigner` and `recoverSignerOrRevert` both fail for the given signature and hash.
    /// @param signature The signature bytes that should fail
    /// @param hash The hash used for recovery
    /// @param failureMessage Assertion message on failure
    function _assertRecoverSignerPairFails(bytes memory signature, bytes32 hash, string memory failureMessage)
        internal
    {
        _assertTryRecoverSignerFails(signature, hash, failureMessage);
        _assertRecoverSignerOrRevertReverts(signature, hash);
    }

    /**
     * @dev Asserts that `tryRecoverSignerAtOffset` and `recoverSignerAtOffsetOrRevert` both succeed for the given
     *      signatures, offset, and hash.
     *      When both succeed, they must produce the same signer and the same nextOffset.
     * @param signatures Concatenated signature bytes
     * @param offset Byte offset to start recovery at
     * @param hash The hash used for recovery
     * @param expectedSigner The address that should be recovered
     * @param expectedNextOffset The expected nextOffset after consuming the signature
     * @param failureMessage Assertion message on failure
     */
    function _assertRecoverSignerAtOffsetPairSucceeds(
        bytes memory signatures,
        uint256 offset,
        bytes32 hash,
        address expectedSigner,
        uint256 expectedNextOffset,
        string memory failureMessage
    ) internal view {
        (bool successTry, address signerTry, uint256 nextOffsetTry) =
            harness.tryRecoverSignerAtOffset(signatures, offset, hash);
        assertTrue(successTry, failureMessage);
        assertEq(signerTry, expectedSigner, "tryRecoverSignerAtOffset signer mismatch");
        assertEq(nextOffsetTry, expectedNextOffset, "tryRecoverSignerAtOffset nextOffset mismatch");

        (address signerRevert, uint256 nextOffsetRevert) =
            harness.recoverSignerAtOffsetOrRevert(signatures, offset, hash);
        assertEq(signerRevert, expectedSigner, "recoverSignerAtOffsetOrRevert signer mismatch");
        assertEq(nextOffsetRevert, expectedNextOffset, "recoverSignerAtOffsetOrRevert nextOffset mismatch");
    }

    /// @dev Asserts that `tryRecoverSignerAtOffset` and `recoverSignerAtOffsetOrRevert` both fail for the given
    ///      signatures, offset, and hash.
    ///      When both fail, they must produce the same signer (address(0)) and the same nextOffset (0).
    /// @param signatures Concatenated signature bytes
    /// @param offset Byte offset to start recovery at
    /// @param hash The hash used for recovery
    /// @param failureMessage Assertion message on failure
    function _assertRecoverSignerAtOffsetPairFails(
        bytes memory signatures,
        uint256 offset,
        bytes32 hash,
        string memory failureMessage
    ) internal {
        _assertTryRecoverSignerAtOffsetFails(signatures, offset, hash, failureMessage);
        _assertRecoverSignerAtOffsetOrRevertReverts(signatures, offset, hash);
    }

    /// @dev Test case: Recovering valid EOA signatures should succeed for both tryRecoverSigner and
    ///      recoverSignerOrRevert.
    function test_recoverSignerPair_validEOASignatures_succeed() public view {
        uint256[2] memory privateKeys = [TEST_PK_1, TEST_PK_2];
        for (uint256 i = 0; i < privateKeys.length; i++) {
            bytes memory sig = _signHash(privateKeys[i], TEST_HASH);
            _assertRecoverSignerPairSucceeds(
                sig,
                TEST_HASH,
                vm.addr(privateKeys[i]),
                string.concat("Valid EOA signature should succeed for case ", vm.toString(i))
            );
        }

        // Explicit v=27 case
        (bytes memory sigV27, bytes32 hashV27) = _findValidSignatureForV(TEST_PK_1, 27, TEST_HASH);
        _assertRecoverSignerPairSucceeds(sigV27, hashV27, vm.addr(TEST_PK_1), "Valid EOA signature with v=27");

        // Explicit v=28 case
        (bytes memory sigV28, bytes32 hashV28) = _findValidSignatureForV(TEST_PK_1, 28, TEST_HASH);
        _assertRecoverSignerPairSucceeds(sigV28, hashV28, vm.addr(TEST_PK_1), "Valid EOA signature with v=28");
    }

    /// @dev Test case: Recovering invalid EOA signatures should fail for both tryRecoverSigner and
    ///      recoverSignerOrRevert.
    function test_recoverSignerPair_invalidEOAInputs_fail() public {
        // Case 1: no signature bytes at all.
        bytes memory emptySig = new bytes(0);
        _assertRecoverSignerPairFails(emptySig, TEST_HASH, "Empty signature should fail");

        // Case 2: EOA signature is not exactly 65 bytes.
        uint16[2] memory invalidLengths = [uint16(64), uint16(66)];
        for (uint256 i = 0; i < invalidLengths.length; i++) {
            bytes memory sig = new bytes(invalidLengths[i]);
            sig[0] = bytes1(uint8(27));
            _assertRecoverSignerPairFails(
                sig, TEST_HASH, string.concat("Invalid EOA length should fail: ", vm.toString(invalidLengths[i]))
            );
        }

        // Case 3: EOA signature has an invalid v byte.
        bytes memory validSig = _signHash(TEST_PK_1, TEST_HASH);
        uint8[4] memory invalidVs = [uint8(1), uint8(26), uint8(29), uint8(255)];
        for (uint256 i = 0; i < invalidVs.length; i++) {
            validSig[0] = bytes1(invalidVs[i]);
            _assertRecoverSignerPairFails(
                validSig, TEST_HASH, string.concat("Invalid v should fail: ", vm.toString(invalidVs[i]))
            );
        }
    }

    /// @dev Test case: Recovering malleable and zero r/s signatures should fail for both tryRecoverSigner and
    ///      recoverSignerOrRevert.
    function test_recoverSignerPair_malleabilityAndZeroRS_edgeCases() public {
        // Case 1: Recovering malleable (high-s) signatures should fail.
        bytes memory malleableSig = _makeHighSSignature(TEST_PK_1, TEST_HASH);
        _assertRecoverSignerPairFails(malleableSig, TEST_HASH, "High-s malleable signature should fail");

        // Case 2: Recovering signatures with s > HALF_CURVE_ORDER (boundary+1) should fail.
        bytes memory aboveHalfOrderSig = _makeBoundaryPlusOneSSignature(TEST_PK_1, TEST_HASH);
        _assertRecoverSignerPairFails(aboveHalfOrderSig, TEST_HASH, "s > HALF_CURVE_ORDER should fail");

        // Case 3: Recovering signatures with zero r/s values should fail.
        bytes memory zeroRS = abi.encodePacked(uint8(27), bytes32(0), bytes32(0));
        _assertRecoverSignerPairFails(zeroRS, TEST_HASH, "Zeroed r/s should fail");

        // Case 4: Recovering signatures with zero r value and non-zero s value should fail.
        bytes memory sig = _signHash(TEST_PK_1, TEST_HASH);
        bytes32 validS;
        assembly {
            validS := mload(add(sig, 65))
        }
        bytes memory zeroR = abi.encodePacked(uint8(27), bytes32(0), validS);
        _assertRecoverSignerPairFails(zeroR, TEST_HASH, "Zeroed r value and non-zero s value should fail");
    }

    /// @dev Test case: Recovering a signature with s == HALF_CURVE_ORDER (the accepted boundary) should
    ///      succeed for both tryRecoverSigner and recoverSignerOrRevert.
    function test_recoverSignerPair_sAtHalfCurveOrder_succeeds() public {
        bytes memory sig = _makeBoundarySSignature(TEST_PK_1, TEST_HASH);
        (bool successTry, address signerTry) = harness.tryRecoverSigner(sig, TEST_HASH);

        assertTrue(successTry, "s == HALF_CURVE_ORDER should be accepted");
        assertTrue(signerTry != address(0), "Recovered signer should be non-zero at HALF_CURVE_ORDER");
        _assertRecoverSignerPairSucceeds(sig, TEST_HASH, signerTry, "s == HALF_CURVE_ORDER should succeed");
    }

    /// @dev Test case: Recovering a signature against the wrong hash should still succeed (wrong hash is not a format
    ///      failure), but both APIs should recover a signer different from the expected signer.
    function test_recoverSignerPair_wrongHash_recoversConsistently() public view {
        bytes memory sig = _signHash(TEST_PK_1, TEST_HASH);
        address expectedSigner = vm.addr(TEST_PK_1);

        (bool successTry, address signerTry) = harness.tryRecoverSigner(sig, WRONG_HASH);
        assertTrue(successTry, "tryRecoverSigner should still succeed for wrong hash");
        assertTrue(signerTry != expectedSigner, "Recovered signer should differ for wrong hash");
        assertTrue(signerTry != address(0), "Recovered signer should be non-zero");

        address signerRevert = harness.recoverSignerOrRevert(sig, WRONG_HASH);
        assertEq(signerRevert, signerTry, "Paired functions should recover the same signer");
    }

    /// @dev Test case: Recovering valid ERC-1271 contract signatures should succeed for both tryRecoverSigner and
    ///      recoverSignerOrRevert, including zero-length inner signature acceptance.
    function test_recoverSignerPair_validERC1271Signatures_succeed() public view {
        // Basic valid ERC-1271 payload.
        bytes memory sigA = _buildContractSignature(address(validSigner1271), hex"deadbeef");
        _assertRecoverSignerPairSucceeds(
            sigA, TEST_HASH, address(validSigner1271), "Valid ERC-1271 signature should succeed"
        );

        // Different inner payload to demonstrate data-agnostic contract validation behavior.
        bytes memory sigB = _buildContractSignature(address(validSigner1271), abi.encodePacked(keccak256("inner")));
        _assertRecoverSignerPairSucceeds(
            sigB, TEST_HASH, address(validSigner1271), "ERC-1271 magic-returning signer should succeed"
        );

        // Valid mock accepts empty signature data as well.
        bytes memory emptyInnerSig = _buildContractSignature(address(validSigner1271), new bytes(0));
        _assertRecoverSignerPairSucceeds(
            emptyInnerSig,
            TEST_HASH,
            address(validSigner1271),
            "Valid ERC-1271 signer should accept zero-length inner signature"
        );
    }

    /// @dev Test case: Recovering invalid ERC-1271 contract signatures should fail identically in both
    ///      tryRecoverSigner and recoverSignerOrRevert across all invalid-input cases.
    function test_recoverSignerPair_invalidERC1271Inputs_fail() public {
        bytes[] memory failingSigs = new bytes[](7);
        // Case 0: signer returns wrong magic value.
        failingSigs[0] = _buildContractSignature(address(wrongMagicSigner1271), hex"deadbeef");
        // Case 1: signer contract reverts.
        failingSigs[1] = _buildContractSignature(address(revertingSigner1271), hex"deadbeef");
        // Case 2: signer address is EOA (no code).
        failingSigs[2] = _buildContractSignature(vm.addr(0xBEEF), hex"deadbeef");
        // Case 3: signer is address(0).
        failingSigs[3] = _buildContractSignature(address(0), hex"deadbeef");
        // Case 4: empty inner signature to a signer that intentionally rejects.
        failingSigs[4] = _buildContractSignature(address(revertingSigner1271), new bytes(0));
        // Case 5: declared length exceeds available bytes.
        failingSigs[5] = abi.encodePacked(uint8(0), address(validSigner1271), uint16(100), bytes5(0xdeadbeefff));
        // Case 6: header truncated below minimum 23 bytes.
        bytes memory shortHeader = new bytes(22);
        shortHeader[0] = bytes1(uint8(0));
        failingSigs[6] = shortHeader;

        for (uint256 i = 0; i < failingSigs.length; i++) {
            _assertRecoverSignerPairFails(
                failingSigs[i],
                TEST_HASH,
                string.concat("Malformed/invalid ERC-1271 case should fail: ", vm.toString(i))
            );
        }
    }

    /// @dev Test case: Recovering single signatures (EOA and ERC-1271) at offset 0 should succeed for both
    ///      tryRecoverSignerAtOffset and recoverSignerAtOffsetOrRevert.
    function test_recoverSignerAtOffsetPair_validSingleSignatures_succeed() public view {
        bytes memory eoaSig = _signHash(TEST_PK_1, TEST_HASH);
        _assertRecoverSignerAtOffsetPairSucceeds(
            eoaSig, 0, TEST_HASH, vm.addr(TEST_PK_1), 65, "EOA at offset 0 should succeed"
        );

        bytes memory innerSig = hex"aabbccdd";
        bytes memory contractSig = _buildContractSignature(address(validSigner1271), innerSig);
        _assertRecoverSignerAtOffsetPairSucceeds(
            contractSig,
            0,
            TEST_HASH,
            address(validSigner1271),
            23 + innerSig.length,
            "ERC-1271 at offset 0 should succeed"
        );
    }

    /// @dev Test case: Iterating through concatenated multi-signature payloads (multiple EOAs, mixed EOA + ERC-1271,
    ///      and multiple ERC-1271 entries) should produce deterministic nextOffset progression.
    function test_recoverSignerAtOffsetPair_multiSignatureOffsets_succeed() public view {
        bytes memory sig1 = _signHash(TEST_PK_1, TEST_HASH);
        bytes memory sig2 = _signHash(TEST_PK_2, TEST_HASH);
        bytes memory sig3 = _signHash(TEST_PK_3, TEST_HASH);
        bytes memory innerSig = hex"aabbccdd";
        bytes memory contractSig = _buildContractSignature(address(validSigner1271), innerSig);

        bytes[] memory eoaPair = new bytes[](2);
        eoaPair[0] = sig1;
        eoaPair[1] = sig2;
        bytes memory combinedEOA = _concatSignatures(eoaPair);
        // Verify decoding at a non-zero starting offset.
        _assertRecoverSignerAtOffsetPairSucceeds(
            combinedEOA, 65, TEST_HASH, vm.addr(TEST_PK_2), 130, "Second EOA at offset 65 should succeed"
        );

        bytes[] memory mixedPair = new bytes[](2);
        mixedPair[0] = sig1;
        mixedPair[1] = contractSig;
        bytes memory combinedMixed = _concatSignatures(mixedPair);
        // First element in mixed payload.
        _assertRecoverSignerAtOffsetPairSucceeds(
            combinedMixed, 0, TEST_HASH, vm.addr(TEST_PK_1), 65, "First mixed signature should recover EOA"
        );
        // Chained decode into second element.
        _assertRecoverSignerAtOffsetPairSucceeds(
            combinedMixed,
            65,
            TEST_HASH,
            address(validSigner1271),
            65 + 23 + innerSig.length,
            "Second mixed signature should recover ERC-1271 signer"
        );

        bytes[] memory threeEOAs = new bytes[](3);
        threeEOAs[0] = sig1;
        threeEOAs[1] = sig2;
        threeEOAs[2] = sig3;
        bytes memory combinedThreeEOAs = _concatSignatures(threeEOAs);
        address[3] memory expectedEOASigners = [vm.addr(TEST_PK_1), vm.addr(TEST_PK_2), vm.addr(TEST_PK_3)];
        uint256 offset = 0;
        for (uint256 i = 0; i < 3; i++) {
            // For fixed-size EOA signatures, offset grows by +65 each step.
            uint256 nextOffset = (i + 1) * 65;
            _assertRecoverSignerAtOffsetPairSucceeds(
                combinedThreeEOAs,
                offset,
                TEST_HASH,
                expectedEOASigners[i],
                nextOffset,
                string.concat("Three-EOA iteration should recover signer ", vm.toString(i))
            );
            offset = nextOffset;
        }

        bytes memory inner1 = hex"aa";
        bytes memory inner2 = hex"bbcc";
        bytes memory inner3 = hex"ddeeff";
        bytes[] memory threeContracts = new bytes[](3);
        threeContracts[0] = _buildContractSignature(address(validSigner1271), inner1);
        threeContracts[1] = _buildContractSignature(address(validSigner1271), inner2);
        threeContracts[2] = _buildContractSignature(address(validSigner1271), inner3);
        bytes memory combinedThreeContracts = _concatSignatures(threeContracts);

        // For ERC-1271 signatures, each step adds header (23) + dynamic inner length.
        uint256[3] memory expectedContractOffsets;
        expectedContractOffsets[0] = 23 + inner1.length;
        expectedContractOffsets[1] = expectedContractOffsets[0] + 23 + inner2.length;
        expectedContractOffsets[2] = expectedContractOffsets[1] + 23 + inner3.length;

        offset = 0;
        for (uint256 i = 0; i < 3; i++) {
            _assertRecoverSignerAtOffsetPairSucceeds(
                combinedThreeContracts,
                offset,
                TEST_HASH,
                address(validSigner1271),
                expectedContractOffsets[i],
                string.concat("Three-ERC1271 iteration should recover signer ", vm.toString(i))
            );
            offset = expectedContractOffsets[i];
        }
    }

    /// @dev Test case: Invalid inputs to offset-based recovery (out-of-bounds offset, invalid v byte, malleable
    ///      signature, wrong ERC-1271 magic) should fail identically for both offset APIs.
    function test_recoverSignerAtOffsetPair_invalidInputs_fail() public {
        bytes memory sig = _signHash(TEST_PK_1, TEST_HASH);
        // Offset cannot be beyond or equal to total encoded length.
        _assertRecoverSignerAtOffsetPairFails(sig, 100, TEST_HASH, "Offset beyond length should fail");
        _assertRecoverSignerAtOffsetPairFails(sig, sig.length, TEST_HASH, "Offset at end should fail");

        // Invalid v dispatch byte for EOA mode.
        bytes memory invalidV = new bytes(65);
        invalidV[0] = bytes1(uint8(29));
        _assertRecoverSignerAtOffsetPairFails(invalidV, 0, TEST_HASH, "Invalid v at offset should fail");

        // High-s malleability should fail in offset mode as well.
        bytes memory malleableSig = _makeHighSSignature(TEST_PK_1, TEST_HASH);
        _assertRecoverSignerAtOffsetPairFails(malleableSig, 0, TEST_HASH, "Malleable signature at offset should fail");

        // ERC-1271 signer returns non-magic value.
        bytes memory wrongMagic = _buildContractSignature(address(wrongMagicSigner1271), hex"deadbeef");
        _assertRecoverSignerAtOffsetPairFails(wrongMagic, 0, TEST_HASH, "Wrong magic at offset should fail");
    }

    /// @dev Test case: Extracting the v byte at offset 0 should return the correct byte.
    function test_getVByte_offset0_returnsCorrectByte() public view {
        bytes memory data = hex"1b" // v=27
            hex"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
            hex"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";

        uint8 v = harness.getVByte(data, 0);
        assertEq(v, 27, "v byte at offset 0 should be 27");
    }

    /// @dev Test case: Extracting the v byte at a large offset (e.g., 200) should return the correct byte.
    function test_getVByte_largeOffset_returnsCorrectByte() public view {
        // Create a 250-byte array and set byte at position 200 to a known value
        bytes memory data = new bytes(250);
        data[200] = bytes1(uint8(42));

        uint8 v = harness.getVByte(data, 200);
        assertEq(v, 42, "v byte at offset 200 should be 42");
    }

    /// @dev Test case: Extracting the v byte when surrounding bytes are non-zero should return only the target byte.
    function test_getVByte_surroundingNonZero_onlyTargetByteReturned() public view {
        // Fill with 0xFF and set target byte to a specific value
        bytes memory data = new bytes(10);
        for (uint256 i = 0; i < data.length; i++) {
            data[i] = bytes1(uint8(0xff));
        }
        data[5] = bytes1(uint8(28)); // Set target to v=28

        uint8 v = harness.getVByte(data, 5);
        assertEq(v, 28, "Should extract only the target byte, not surrounding 0xFF bytes");
    }

    /// @dev Test case: Extracting the contract signer surrounded by non-zero bytes should return only the clean
    ///      20-byte address with no dirty upper bits.
    function test_getContractSigner_surroundedByNonZero_extractsCleanAddress() public view {
        // Build: v(1) = 0xFF | signer(20) = known address | rest = 0xFF
        address expectedAddr = address(0x1234567890AbcdEF1234567890aBcdef12345678);
        bytes memory data = new bytes(50);
        for (uint256 i = 0; i < data.length; i++) {
            data[i] = bytes1(uint8(0xff));
        }
        // Write signer at offset+1 (after v byte)
        bytes20 addrBytes = bytes20(expectedAddr);
        for (uint256 i = 0; i < 20; i++) {
            data[1 + i] = addrBytes[i];
        }

        address signer = harness.getContractSigner(data, 0);
        assertEq(signer, expectedAddr, "Should extract clean 20-byte address without dirty upper bits");
    }

    /// @dev Test case: Extracting a contract signer with leading zeros (e.g., 0x0000...0001) should correctly
    ///      recover the full address.
    function test_getContractSigner_leadingZeros_correctlyRecovered() public view {
        address expectedAddr = address(0x0000000000000000000000000000000000000001);
        bytes memory data = abi.encodePacked(uint8(0), expectedAddr, uint16(0));

        address signer = harness.getContractSigner(data, 0);
        assertEq(signer, expectedAddr, "Should correctly recover address with leading zeros");
    }

    /// @dev Test case: Extracting a contract signer with all 0xFF bytes should correctly recover the address
    ///      without truncation.
    function test_getContractSigner_allFfBytes_correctlyRecovered() public view {
        address expectedAddr = address(0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF);
        bytes memory data = abi.encodePacked(uint8(0), expectedAddr, uint16(0));

        address signer = harness.getContractSigner(data, 0);
        assertEq(signer, expectedAddr, "Should correctly recover all-0xFF address");
    }

    /// @dev Test case: Parsing a contract signature length of 1 (0x0001) should return 1.
    function test_getContractSignatureLength_one_parsedCorrectly() public view {
        // Build: v(1) | signer(20) | length(2) = 0x0001
        bytes memory data = abi.encodePacked(uint8(0), address(0x1), uint16(1));

        uint16 sigLength = harness.getContractSignatureLength(data, 0);
        assertEq(sigLength, 1, "Length should be parsed as 1");
    }

    /// @dev Test case: Parsing a contract signature length of 256 (0x0100) should return 256, verifying big-endian
    ///      parsing (not little-endian 1).
    function test_getContractSignatureLength_256_bigEndianParsedCorrectly() public view {
        // Build: v(1) | signer(20) | length(2) = 256 = 0x0100 big-endian
        bytes memory data = abi.encodePacked(uint8(0), address(0x1), uint16(256));

        uint16 sigLength = harness.getContractSignatureLength(data, 0);
        assertEq(sigLength, 256, "Length should be 256 (big-endian), not 1 (little-endian)");
    }

    /// @dev Test case: Parsing a contract signature length of 65535 (0xFFFF, max uint16) should be correctly parsed.
    function test_getContractSignatureLength_maxUint16_parsedCorrectly() public view {
        bytes memory data = abi.encodePacked(uint8(0), address(0x1), uint16(65_535));

        uint16 sigLength = harness.getContractSignatureLength(data, 0);
        assertEq(sigLength, 65_535, "Length should be max uint16 (65535)");
    }

    /// @dev Test case: Parsing a contract signature length of 0 (0x0000) should return 0.
    function test_getContractSignatureLength_zero_returnsZero() public view {
        bytes memory data = abi.encodePacked(uint8(0), address(0x1), uint16(0));

        uint16 sigLength = harness.getContractSignatureLength(data, 0);
        assertEq(sigLength, 0, "Length should be 0");
    }

    /// @dev Test case: Extracting a 1-byte inner signature should return a byte that matches the source exactly.
    function test_extractContractInnerSignature_length1_matchesSource() public view {
        bytes memory innerSig = hex"ab";
        bytes memory data = abi.encodePacked(uint8(0), address(0x1), uint16(1), innerSig);

        bytes memory extracted = harness.extractContractInnerSignature(data, 0, 1);

        assertEq(extracted.length, 1, "Extracted length should be 1");
        assertEq(extracted[0], innerSig[0], "Extracted byte should match source");
    }

    /// @dev Test case: Extracting a 31-byte inner signature (non-word-aligned) should not over-copy into the
    ///      returned bytes.
    function test_extractContractInnerSignature_length31_noOverCopy() public view {
        bytes memory innerSig = new bytes(31);
        for (uint256 i = 0; i < 31; i++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            innerSig[i] = bytes1(uint8(i + 1)); // Safe: i+1 is bounded to 1-31
        }
        bytes memory data = abi.encodePacked(uint8(0), address(0x1), uint16(31), innerSig);

        bytes memory extracted = harness.extractContractInnerSignature(data, 0, 31);

        assertEq(extracted.length, 31, "Extracted length should be 31");
        for (uint256 i = 0; i < 31; i++) {
            assertEq(extracted[i], innerSig[i], string.concat("Byte mismatch at index ", vm.toString(i)));
        }
    }

    /// @dev Test case: Extracting a 32-byte inner signature should produce an exact one-chunk copy with full data
    ///      integrity.
    function test_extractContractInnerSignature_length32_exactChunkCopy() public view {
        bytes memory innerSig = new bytes(32);
        for (uint256 i = 0; i < 32; i++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            innerSig[i] = bytes1(uint8(i)); // Safe: i is bounded to 0-31
        }
        bytes memory data = abi.encodePacked(uint8(0), address(0x1), uint16(32), innerSig);

        bytes memory extracted = harness.extractContractInnerSignature(data, 0, 32);

        assertEq(extracted.length, 32, "Extracted length should be 32");
        assertEq(keccak256(extracted), keccak256(innerSig), "Data should match exactly");
    }

    /// @dev Test case: Extracting a 33-byte inner signature should produce a two-chunk copy that returns only
    ///      33 bytes (not 64).
    function test_extractContractInnerSignature_length33_twoChunkOnly33Bytes() public view {
        bytes memory innerSig = new bytes(33);
        for (uint256 i = 0; i < 33; i++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            innerSig[i] = bytes1(uint8(i)); // Safe: i is bounded to 0-32
        }
        bytes memory data = abi.encodePacked(uint8(0), address(0x1), uint16(33), innerSig);

        bytes memory extracted = harness.extractContractInnerSignature(data, 0, 33);

        assertEq(extracted.length, 33, "Extracted length should be 33, not 64");
        for (uint256 i = 0; i < 33; i++) {
            assertEq(extracted[i], innerSig[i], string.concat("Byte mismatch at index ", vm.toString(i)));
        }
    }

    /// @dev Test case: Extracting a 65-byte inner signature (EOA sig size) should maintain full data integrity
    ///      byte-for-byte.
    function test_extractContractInnerSignature_length65_fullDataIntegrity() public view {
        bytes memory innerSig = new bytes(65);
        for (uint256 i = 0; i < 65; i++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            innerSig[i] = bytes1(uint8(i % 256)); // Safe: modulo 256 ensures value fits in uint8
        }
        bytes memory data = abi.encodePacked(uint8(0), address(0x1), uint16(65), innerSig);

        bytes memory extracted = harness.extractContractInnerSignature(data, 0, 65);

        assertEq(extracted.length, 65, "Extracted length should be 65");
        assertEq(keccak256(extracted), keccak256(innerSig), "Full 65-byte data should match exactly");
    }

    /// @dev Test case: Extracting an inner signature consisting of all 0xFF bytes should produce no corruption
    ///      during chunk copy.
    function test_extractContractInnerSignature_allFfBytes_noCorruption() public view {
        bytes memory innerSig = new bytes(65);
        for (uint256 i = 0; i < 65; i++) {
            innerSig[i] = bytes1(uint8(0xff));
        }
        bytes memory data = abi.encodePacked(uint8(0), address(0x1), uint16(65), innerSig);

        bytes memory extracted = harness.extractContractInnerSignature(data, 0, 65);

        assertEq(extracted.length, 65, "Extracted length should be 65");
        for (uint256 i = 0; i < 65; i++) {
            assertEq(uint8(extracted[i]), 0xff, string.concat("Byte at ", vm.toString(i), " should be 0xFF"));
        }
    }

    /// @dev Test case: Extracting a 96-byte inner signature should produce an exact 3-chunk copy with data
    ///      integrity byte-for-byte.
    function test_extractContractInnerSignature_length96_threeChunkIntegrity() public view {
        bytes memory innerSig = new bytes(96);
        for (uint256 i = 0; i < 96; i++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            innerSig[i] = bytes1(uint8(i % 256)); // Safe: modulo 256 ensures value fits in uint8
        }
        bytes memory data = abi.encodePacked(uint8(0), address(0x1), uint16(96), innerSig);

        bytes memory extracted = harness.extractContractInnerSignature(data, 0, 96);

        assertEq(extracted.length, 96, "Extracted length should be 96");
        assertEq(keccak256(extracted), keccak256(innerSig), "96-byte data should match exactly");
    }

    /// @dev Test case: Extracting a 97-byte inner signature should produce a 4-chunk copy that returns only
    ///      97 bytes (not 128).
    function test_extractContractInnerSignature_length97_fourChunkOnly97Bytes() public view {
        bytes memory innerSig = new bytes(97);
        for (uint256 i = 0; i < 97; i++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            innerSig[i] = bytes1(uint8(i % 256)); // Safe: modulo 256 ensures value fits in uint8
        }
        bytes memory data = abi.encodePacked(uint8(0), address(0x1), uint16(97), innerSig);

        bytes memory extracted = harness.extractContractInnerSignature(data, 0, 97);

        assertEq(extracted.length, 97, "Extracted length should be 97, not 128");
        assertEq(keccak256(extracted), keccak256(innerSig), "97-byte data should match exactly");
    }

    /// @dev Test case: Extracting a 160-byte inner signature should produce an exact 5-chunk copy with data
    ///      integrity byte-for-byte.
    function test_extractContractInnerSignature_length160_fiveChunkIntegrity() public view {
        bytes memory innerSig = new bytes(160);
        for (uint256 i = 0; i < 160; i++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            innerSig[i] = bytes1(uint8(i % 256)); // Safe: modulo 256 ensures value fits in uint8
        }
        bytes memory data = abi.encodePacked(uint8(0), address(0x1), uint16(160), innerSig);

        bytes memory extracted = harness.extractContractInnerSignature(data, 0, 160);

        assertEq(extracted.length, 160, "Extracted length should be 160");
        assertEq(keccak256(extracted), keccak256(innerSig), "160-byte data should match exactly");
    }

    /// @dev Test case: Extracting a 161-byte inner signature should produce a 6-chunk copy that returns only
    ///      161 bytes (not 192).
    function test_extractContractInnerSignature_length161_sixChunkOnly161Bytes() public view {
        bytes memory innerSig = new bytes(161);
        for (uint256 i = 0; i < 161; i++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            innerSig[i] = bytes1(uint8(i % 256)); // Safe: modulo 256 ensures value fits in uint8
        }
        bytes memory data = abi.encodePacked(uint8(0), address(0x1), uint16(161), innerSig);

        bytes memory extracted = harness.extractContractInnerSignature(data, 0, 161);

        assertEq(extracted.length, 161, "Extracted length should be 161, not 192");
        assertEq(keccak256(extracted), keccak256(innerSig), "161-byte data should match exactly");
    }

    /// @dev Test case: Extracting a 1600-byte inner signature should produce an exact 50-chunk copy with data
    ///      integrity byte-for-byte.
    function test_extractContractInnerSignature_length1600_fiftyChunkIntegrity() public view {
        bytes memory innerSig = new bytes(1600);
        for (uint256 i = 0; i < 1600; i++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            innerSig[i] = bytes1(uint8(i % 256)); // Safe: modulo 256 ensures value fits in uint8
        }
        bytes memory data = abi.encodePacked(uint8(0), address(0x1), uint16(1600), innerSig);

        bytes memory extracted = harness.extractContractInnerSignature(data, 0, 1600);

        assertEq(extracted.length, 1600, "Extracted length should be 1600");
        assertEq(keccak256(extracted), keccak256(innerSig), "1600-byte data should match exactly");
    }

    /// @dev Test case: Extracting a 1601-byte inner signature should produce a 51-chunk copy that returns only
    ///      1601 bytes (not 1632).
    function test_extractContractInnerSignature_length1601_fiftyOneChunkOnly1601Bytes() public view {
        bytes memory innerSig = new bytes(1601);
        for (uint256 i = 0; i < 1601; i++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            innerSig[i] = bytes1(uint8(i % 256)); // Safe: modulo 256 ensures value fits in uint8
        }
        bytes memory data = abi.encodePacked(uint8(0), address(0x1), uint16(1601), innerSig);

        bytes memory extracted = harness.extractContractInnerSignature(data, 0, 1601);

        assertEq(extracted.length, 1601, "Extracted length should be 1601, not 1632");
        assertEq(keccak256(extracted), keccak256(innerSig), "1601-byte data should match exactly");
    }

    /// @dev Test case: Extracting an inner signature of any random length in [1, 2000] should always produce
    ///      extracted bytes that match the source exactly.
    function testFuzz_extractContractInnerSignature_randomLength_matchesSource(uint16 sigLength) public view {
        sigLength = uint16(bound(sigLength, 1, 2000));

        bytes memory innerSig = new bytes(sigLength);
        for (uint256 i = 0; i < sigLength; i++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            innerSig[i] = bytes1(uint8(i % 256)); // Safe: modulo 256 ensures value fits in uint8
        }
        bytes memory data = abi.encodePacked(uint8(0), address(0x1), sigLength, innerSig);

        bytes memory extracted = harness.extractContractInnerSignature(data, 0, sigLength);

        assertEq(extracted.length, sigLength, "Extracted length should equal sigLength");
        assertEq(keccak256(extracted), keccak256(innerSig), "Extracted data should match source exactly");
    }

    /// @dev Test case: Recovering an EOA signer at a non-zero offset (second signature in a concatenated array)
    ///      should extract r and s correctly.
    function test_tryRecoverEOASigner_nonZeroOffset_extractsCorrectly() public view {
        bytes memory sig1 = _signHash(TEST_PK_1, TEST_HASH);
        bytes memory sig2 = _signHash(TEST_PK_2, TEST_HASH);
        bytes[] memory sigs = new bytes[](2);
        sigs[0] = sig1;
        sigs[1] = sig2;
        bytes memory combined = _concatSignatures(sigs);
        address expectedSigner2 = vm.addr(TEST_PK_2);
        uint8 v2 = uint8(sig2[0]);

        (bool success, address signer) = harness.tryRecoverEOASigner(combined, 65, TEST_HASH, v2);

        assertTrue(success, "Should recover second signer at offset 65");
        assertEq(signer, expectedSigner2, "Signer should match PK_2");
    }

    /// @dev Test case: Recovering an EOA signer when preceding bytes are all non-zero (0xFF) should not bleed
    ///      into the r or s values.
    function test_tryRecoverEOASigner_precedingNonZero_noBleed() public view {
        // Fill prefix with 0xFF, then append a valid signature
        bytes memory prefix = new bytes(65);
        for (uint256 i = 0; i < 65; i++) {
            prefix[i] = bytes1(uint8(0xff));
        }
        bytes memory sig = _signHash(TEST_PK_1, TEST_HASH);
        bytes memory combined = abi.encodePacked(prefix, sig);
        address expectedSigner = vm.addr(TEST_PK_1);
        uint8 v = uint8(sig[0]);

        (bool success, address signer) = harness.tryRecoverEOASigner(combined, 65, TEST_HASH, v);

        assertTrue(success, "Should recover signer despite 0xFF prefix");
        assertEq(signer, expectedSigner, "Non-zero preceding bytes should not bleed into r or s");
    }

    /// @dev Test case: Recovering an EOA signer with s == HALF_CURVE_ORDER at a non-zero offset should be
    ///      accepted (boundary value).
    function test_tryRecoverEOASigner_sAtHalfCurveOrderNonZeroOffset_accepted() public view {
        bytes memory prefix = new bytes(10);
        bytes memory sig = _makeBoundarySSignature(TEST_PK_1, TEST_HASH);
        bytes memory combined = abi.encodePacked(prefix, sig);
        uint8 v = uint8(sig[0]);

        (bool success, address signer) = harness.tryRecoverEOASigner(combined, 10, TEST_HASH, v);

        assertTrue(success, "Should accept s == HALF_CURVE_ORDER");
        assertTrue(signer != address(0), "Recovered signer should be non-zero at HALF_CURVE_ORDER");
    }

    /// @dev Test case: Recovering an EOA signer with s == HALF_CURVE_ORDER + 1 at a non-zero offset should be
    ///      rejected by the malleability check.
    function test_tryRecoverEOASigner_sAboveHalfCurveOrderNonZeroOffset_rejected() public view {
        bytes memory prefix = new bytes(10);
        bytes memory sig = _makeBoundaryPlusOneSSignature(TEST_PK_1, TEST_HASH);
        bytes memory combined = abi.encodePacked(prefix, sig);
        uint8 v = uint8(sig[0]);

        (bool success, address signer) = harness.tryRecoverEOASigner(combined, 10, TEST_HASH, v);

        assertFalse(success, "Should reject s > HALF_CURVE_ORDER");
        assertEq(signer, address(0), "Signer should be address(0)");
    }

    /// @dev Test case: Recovering an EOA signer at offset 0 with a valid signature should extract r and s
    ///      correctly from the start.
    function test_tryRecoverEOASigner_offset0_extractsCorrectly() public view {
        bytes memory sig = _signHash(TEST_PK_1, TEST_HASH);
        address expectedSigner = vm.addr(TEST_PK_1);
        uint8 v = uint8(sig[0]);

        (bool success, address signer) = harness.tryRecoverEOASigner(sig, 0, TEST_HASH, v);

        assertTrue(success, "Should recover signer at offset 0");
        assertEq(signer, expectedSigner, "Signer should match");
    }

    /// @dev Test case: Recovering an EOA signer when offset + 65 > signatures.length should return
    ///      (false, address(0)).
    function test_tryRecoverEOASigner_insufficientBytes_returnsFalse() public view {
        bytes memory shortData = new bytes(60); // Less than 65 bytes
        shortData[0] = bytes1(uint8(27));

        (bool success, address signer) = harness.tryRecoverEOASigner(shortData, 0, TEST_HASH, 27);

        assertFalse(success, "Should fail when not enough bytes");
        assertEq(signer, address(0), "Signer should be address(0)");
    }

    /// @dev Test case: Recovering an EOA signer when offset + 65 == signatures.length (exactly fits) should
    ///      succeed.
    function test_tryRecoverEOASigner_exactFit_succeeds() public view {
        bytes memory sig = _signHash(TEST_PK_1, TEST_HASH);
        address expectedSigner = vm.addr(TEST_PK_1);
        uint8 v = uint8(sig[0]);

        // sig.length should be exactly 65, so offset=0 + 65 == length
        assertEq(sig.length, 65, "Signature should be exactly 65 bytes");

        (bool success, address signer) = harness.tryRecoverEOASigner(sig, 0, TEST_HASH, v);

        assertTrue(success, "Should succeed when signature exactly fits");
        assertEq(signer, expectedSigner, "Signer should match");
    }

    /// @dev Test case: Recovering an EOA signer with r = bytes32(0) should return (false, address(0)) because
    ///      ecrecover returns address(0).
    function test_tryRecoverEOASigner_zeroR_returnsFalse() public view {
        bytes memory sig = abi.encodePacked(uint8(27), bytes32(0), bytes32(uint256(1)));

        (bool success, address signer) = harness.tryRecoverEOASigner(sig, 0, TEST_HASH, 27);

        assertFalse(success, "Should fail with zeroed r");
        assertEq(signer, address(0), "Signer should be address(0)");
    }

    /// @dev Test case: Recovering an EOA signer with s = bytes32(0) should return (false, address(0)) because
    ///      ecrecover returns address(0).
    function test_tryRecoverEOASigner_zeroS_returnsFalse() public view {
        bytes memory sig = abi.encodePacked(uint8(27), bytes32(uint256(1)), bytes32(0));

        (bool success, address signer) = harness.tryRecoverEOASigner(sig, 0, TEST_HASH, 27);

        assertFalse(success, "Should fail with zeroed s");
        assertEq(signer, address(0), "Signer should be address(0)");
    }

    /// @dev Test case: Recovering an EOA signer with v = 27 should recover the expected signer.
    function test_tryRecoverEOASigner_v27_recoversCorrectly() public view {
        (bytes memory sig, bytes32 hash) = _findValidSignatureForV(TEST_PK_1, 27, TEST_HASH);
        address expectedSigner = vm.addr(TEST_PK_1);

        (bool success, address signer) = harness.tryRecoverEOASigner(sig, 0, hash, 27);

        assertTrue(success, "Should recover with v=27");
        assertEq(signer, expectedSigner, "Signer should match");
    }

    /// @dev Test case: Recovering an EOA signer with v = 28 should recover the expected signer.
    function test_tryRecoverEOASigner_v28_recoversCorrectly() public view {
        (bytes memory sig, bytes32 hash) = _findValidSignatureForV(TEST_PK_1, 28, TEST_HASH);
        address expectedSigner = vm.addr(TEST_PK_1);

        (bool success, address signer) = harness.tryRecoverEOASigner(sig, 0, hash, 28);

        assertTrue(success, "Should recover with v=28");
        assertEq(signer, expectedSigner, "Signer should match");
    }

    /// @dev Test case: Recovering three consecutive EOA signatures should extract each correctly at offsets
    ///      0, 65, and 130.
    function test_tryRecoverEOASigner_threeConsecutive_allExtractedCorrectly() public view {
        bytes memory sig1 = _signHash(TEST_PK_1, TEST_HASH);
        bytes memory sig2 = _signHash(TEST_PK_2, TEST_HASH);
        bytes memory sig3 = _signHash(TEST_PK_3, TEST_HASH);
        bytes[] memory sigs = new bytes[](3);
        sigs[0] = sig1;
        sigs[1] = sig2;
        sigs[2] = sig3;
        bytes memory combined = _concatSignatures(sigs);

        address[3] memory expected = [vm.addr(TEST_PK_1), vm.addr(TEST_PK_2), vm.addr(TEST_PK_3)];
        bytes[3] memory rawSigs = [sig1, sig2, sig3];

        for (uint256 i = 0; i < 3; i++) {
            uint8 v = uint8(rawSigs[i][0]);
            (bool success, address signer) = harness.tryRecoverEOASigner(combined, i * 65, TEST_HASH, v);
            assertTrue(success, string.concat("Should recover signer at offset ", vm.toString(i * 65)));
            assertEq(signer, expected[i], string.concat("Signer mismatch at index ", vm.toString(i)));
        }
    }

    /// @dev Test case: Trailing garbage bytes after a valid 65-byte signature should not affect recovery.
    function test_tryRecoverEOASigner_trailingGarbage_doesNotAffectRecovery() public view {
        bytes memory sig = _signHash(TEST_PK_1, TEST_HASH);
        address expectedSigner = vm.addr(TEST_PK_1);
        uint8 v = uint8(sig[0]);

        // Append 100 bytes of garbage
        bytes memory garbage = new bytes(100);
        for (uint256 i = 0; i < 100; i++) {
            garbage[i] = bytes1(uint8(0xab));
        }
        bytes memory combined = abi.encodePacked(sig, garbage);

        (bool success, address signer) = harness.tryRecoverEOASigner(combined, 0, TEST_HASH, v);

        assertTrue(success, "Trailing garbage should not affect recovery");
        assertEq(signer, expectedSigner, "Signer should match despite trailing garbage");
    }

    /// @dev Test case: Recovering an EOA signer with any random valid private key at any random offset should
    ///      always recover the correct signer.
    function testFuzz_tryRecoverEOASigner_randomKeyAndOffset_recoversCorrectly(uint256 privateKey, uint8 prefixLength)
        public
        view
    {
        // Bound private key to valid secp256k1 range
        privateKey = bound(privateKey, 1, SECP256K1_CURVE_ORDER - 1);
        // Bound prefix length to something reasonable
        prefixLength = uint8(bound(prefixLength, 0, 200));

        bytes memory prefix = new bytes(prefixLength);
        bytes memory sig = _signHash(privateKey, TEST_HASH);
        address expectedSigner = vm.addr(privateKey);
        uint8 v = uint8(sig[0]);

        bytes memory combined = abi.encodePacked(prefix, sig);

        (bool success, address signer) = harness.tryRecoverEOASigner(combined, prefixLength, TEST_HASH, v);

        assertTrue(success, "Should always recover valid signature");
        assertEq(signer, expectedSigner, "Should always recover correct signer");
    }

    /// @dev Test case: When the header is exactly at the boundary (offset + 23 == length) with sigLength=0, the
    ///      contract should be called with empty bytes and succeed for a valid signer.
    function test_tryRecoverContractSigner_headerAtBoundary_handlesCorrectly() public view {
        // Build exactly 23 bytes: header only, sigLength=0
        bytes memory data = abi.encodePacked(uint8(0), address(validSigner1271), uint16(0));
        assertEq(data.length, 23, "Data should be exactly 23 bytes");

        // Since sigLength=0, offset + 23 + 0 == length, so it should proceed to ERC-1271 check
        (bool success, address signer) = harness.tryRecoverContractSigner(data, 0, TEST_HASH);

        // Mock valid signer accepts any sig including empty, so this should succeed
        assertTrue(success, "Should succeed with sigLength=0 when header exactly fits");
        assertEq(signer, address(validSigner1271), "Signer should be the contract");
    }

    /// @dev Test case: When the full signature is exactly at the boundary (offset + 23 + sigLength == length),
    ///      recovery should succeed.
    function test_tryRecoverContractSigner_fullSigAtBoundary_succeeds() public view {
        bytes memory innerSig = hex"aabb";
        bytes memory data = abi.encodePacked(uint8(0), address(validSigner1271), uint16(2), innerSig);

        // offset(0) + 23 + 2 == 25 == data.length
        assertEq(data.length, 25, "Data should be exactly 25 bytes");

        (bool success, address signer) = harness.tryRecoverContractSigner(data, 0, TEST_HASH);

        assertTrue(success, "Should succeed when full signature exactly fits");
        assertEq(signer, address(validSigner1271), "Signer should be the contract");
    }

    /// @dev Test case: Recovering a contract signer when the signer is address(0) should return false gracefully
    ///      (staticcall to 0x0 fails).
    function test_tryRecoverContractSigner_signerAddressZero_returnsFalse() public view {
        bytes memory innerSig = hex"aabb";
        bytes memory data = abi.encodePacked(uint8(0), address(0), uint16(2), innerSig);

        (bool success, address signer) = harness.tryRecoverContractSigner(data, 0, TEST_HASH);

        assertFalse(success, "Should fail gracefully with signer=address(0)");
        assertEq(signer, address(0), "Signer should be address(0)");
    }

    /// @dev Test case: Recovering a contract signer when offset + 23 > signatures.length should return
    ///      (false, address(0)) because there are not enough bytes for the header.
    function test_tryRecoverContractSigner_notEnoughBytesForHeader_returnsFalse() public view {
        // Only 22 bytes available, need 23 for header
        bytes memory data = new bytes(22);
        data[0] = bytes1(uint8(0));

        (bool success, address signer) = harness.tryRecoverContractSigner(data, 0, TEST_HASH);

        assertFalse(success, "Should fail when not enough bytes for header");
        assertEq(signer, address(0), "Signer should be address(0)");
    }

    /// @dev Test case: Recovering a contract signer when the header fits but the inner signature bytes don't
    ///      should return (false, address(0)).
    function test_tryRecoverContractSigner_headerFitsButInnerSigDoesnt_returnsFalse() public view {
        // Header says sigLength=10 but only 5 bytes of inner sig available
        bytes memory data = abi.encodePacked(uint8(0), address(validSigner1271), uint16(10), bytes5(0xdeadbeefff));

        (bool success, address signer) = harness.tryRecoverContractSigner(data, 0, TEST_HASH);

        assertFalse(success, "Should fail when inner sig doesn't fit");
        assertEq(signer, address(0), "Signer should be address(0)");
    }

    /// @dev Test case: Recovering a contract signer with a valid signer and a valid ERC-1271 response should
    ///      return (true, signer).
    function test_tryRecoverContractSigner_validSignerValidResponse_returnsTrue() public view {
        bytes memory innerSig = hex"deadbeef";
        bytes memory data = abi.encodePacked(uint8(0), address(validSigner1271), uint16(4), innerSig);

        (bool success, address signer) = harness.tryRecoverContractSigner(data, 0, TEST_HASH);

        assertTrue(success, "Should succeed with valid signer and response");
        assertEq(signer, address(validSigner1271), "Signer should be the contract");
    }

    /// @dev Test case: Recovering a contract signer when the ERC-1271 contract returns the wrong magic value
    ///      should return (false, address(0)).
    function test_tryRecoverContractSigner_wrongMagic_returnsFalse() public view {
        bytes memory innerSig = hex"deadbeef";
        bytes memory data = abi.encodePacked(uint8(0), address(wrongMagicSigner1271), uint16(4), innerSig);

        (bool success, address signer) = harness.tryRecoverContractSigner(data, 0, TEST_HASH);

        assertFalse(success, "Should fail when contract returns wrong magic");
        assertEq(signer, address(0), "Signer should be address(0)");
    }

    /// @dev Test case: Recovering a contract signer when the ERC-1271 contract reverts should return
    ///      (false, address(0)).
    function test_tryRecoverContractSigner_contractReverts_returnsFalse() public view {
        bytes memory innerSig = hex"deadbeef";
        bytes memory data = abi.encodePacked(uint8(0), address(revertingSigner1271), uint16(4), innerSig);

        (bool success, address signer) = harness.tryRecoverContractSigner(data, 0, TEST_HASH);

        assertFalse(success, "Should fail when contract reverts");
        assertEq(signer, address(0), "Signer should be address(0)");
    }

    /// @dev Test case: Recovering a contract signer with sigLength = 0 should delegate to ERC-1271 with empty
    ///      bytes.
    function test_tryRecoverContractSigner_sigLengthZero_delegatesWithEmptyBytes() public view {
        bytes memory data = abi.encodePacked(uint8(0), address(validSigner1271), uint16(0));

        (bool success, address signer) = harness.tryRecoverContractSigner(data, 0, TEST_HASH);

        // validSigner1271 accepts any signature including empty
        assertTrue(success, "Should delegate empty bytes to ERC-1271 contract");
        assertEq(signer, address(validSigner1271), "Signer should be the contract");
    }

    /// @dev Test case: Recovering a contract signer when the signer is an EOA (no code) should return
    ///      (false, address(0)).
    function test_tryRecoverContractSigner_signerIsEOA_returnsFalse() public view {
        address eoa = vm.addr(0xBEEF);
        bytes memory innerSig = hex"deadbeef";
        bytes memory data = abi.encodePacked(uint8(0), eoa, uint16(4), innerSig);

        (bool success, address signer) = harness.tryRecoverContractSigner(data, 0, TEST_HASH);

        assertFalse(success, "Should fail when signer is an EOA");
        assertEq(signer, address(0), "Signer should be address(0)");
    }

    /// @dev Test case: Recovering a contract signer at a non-zero offset preceded by an EOA signature should
    ///      correctly recover the contract signer.
    function test_tryRecoverContractSigner_atNonZeroOffsetAfterEOA_recoversCorrectly() public view {
        bytes memory eoaSig = _signHash(TEST_PK_1, TEST_HASH);
        bytes memory innerSig = hex"aabb";
        bytes memory contractSig = abi.encodePacked(uint8(0), address(validSigner1271), uint16(2), innerSig);
        bytes memory combined = abi.encodePacked(eoaSig, contractSig);

        (bool success, address signer) = harness.tryRecoverContractSigner(combined, 65, TEST_HASH);

        assertTrue(success, "Should recover contract signer at non-zero offset");
        assertEq(signer, address(validSigner1271), "Signer should be the contract");
    }

    /// @dev Test case: Recovering two consecutive contract signatures should recover each one correctly at the
    ///      appropriate offset.
    function test_tryRecoverContractSigner_twoConsecutive_bothRecoverCorrectly() public view {
        bytes memory inner1 = hex"aa";
        bytes memory inner2 = hex"bbcc";
        bytes memory sig1 = abi.encodePacked(uint8(0), address(validSigner1271), uint16(1), inner1);
        bytes memory sig2 = abi.encodePacked(uint8(0), address(validSigner1271), uint16(2), inner2);
        bytes memory combined = abi.encodePacked(sig1, sig2);

        // First at offset 0
        (bool success1, address signer1) = harness.tryRecoverContractSigner(combined, 0, TEST_HASH);
        assertTrue(success1, "First contract sig should recover");
        assertEq(signer1, address(validSigner1271), "First signer should be the contract");

        // Second at offset 24 (23 header + 1 inner)
        uint256 secondOffset = 23 + inner1.length; // 24
        (bool success2, address signer2) = harness.tryRecoverContractSigner(combined, secondOffset, TEST_HASH);
        assertTrue(success2, "Second contract sig should recover");
        assertEq(signer2, address(validSigner1271), "Second signer should be the contract");
    }

    /// @dev Test case: Recovering a contract signer with a very large inner signature (1000 bytes) should
    ///      extract and validate correctly.
    function test_tryRecoverContractSigner_largeSigLength_succeeds() public view {
        bytes memory innerSig = new bytes(1000);
        for (uint256 i = 0; i < 1000; i++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            innerSig[i] = bytes1(uint8(i % 256)); // Safe: modulo 256 ensures value fits in uint8
        }
        bytes memory data = abi.encodePacked(uint8(0), address(validSigner1271), uint16(1000), innerSig);

        (bool success, address signer) = harness.tryRecoverContractSigner(data, 0, TEST_HASH);

        assertTrue(success, "Should handle very large inner signature");
        assertEq(signer, address(validSigner1271), "Signer should be the contract");
    }

    /// @dev Test case: Recovering a contract signer with any random valid ERC-1271 signature at any random offset
    ///      should always recover correctly.
    function testFuzz_tryRecoverContractSigner_randomOffsetAndLength_recoversCorrectly(
        uint8 prefixLength,
        uint16 innerSigLength
    ) public view {
        prefixLength = uint8(bound(prefixLength, 0, 100));
        innerSigLength = uint16(bound(innerSigLength, 0, 500));

        bytes memory prefix = new bytes(prefixLength);
        bytes memory innerSig = new bytes(innerSigLength);
        for (uint256 i = 0; i < innerSigLength; i++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            innerSig[i] = bytes1(uint8(i % 256)); // Safe: modulo 256 ensures value fits in uint8
        }
        bytes memory contractSig =
            abi.encodePacked(uint8(0), address(validSigner1271), uint16(innerSigLength), innerSig);
        bytes memory combined = abi.encodePacked(prefix, contractSig);

        (bool success, address signer) = harness.tryRecoverContractSigner(combined, prefixLength, TEST_HASH);

        assertTrue(success, "Should always recover valid contract signer");
        assertEq(signer, address(validSigner1271), "Signer should be the contract");
    }

    /// @dev Test case: A contract that returns magic with extra trailing bytes (result.length > 32) should be
    ///      considered valid.
    function test_isValidERC1271SignatureNow_extraTrailingBytes_valid() public view {
        bool result = harness.isValidERC1271SignatureNow(address(extraBytesSigner1271), TEST_HASH, hex"");

        assertTrue(result, "Should be valid when result has extra bytes starting with magic");
    }

    /// @dev Test case: A contract that returns exactly 32 bytes but with the wrong magic value should be
    ///      considered invalid.
    function test_isValidERC1271SignatureNow_wrongMagic32Bytes_invalid() public view {
        bool result = harness.isValidERC1271SignatureNow(address(wrongMagicSigner1271), TEST_HASH, hex"");

        assertFalse(result, "Should be invalid when magic value is wrong");
    }

    /// @dev Test case: A contract that returns fewer than 32 bytes should be considered invalid.
    function test_isValidERC1271SignatureNow_fewerThan32Bytes_invalid() public view {
        bool result = harness.isValidERC1271SignatureNow(address(shortReturnSigner1271), TEST_HASH, hex"");

        assertFalse(result, "Should be invalid when result is fewer than 32 bytes");
    }

    /// @dev Test case: A contract that consumes all gas (out-of-gas in staticcall) should return false without
    ///      reverting.
    function test_isValidERC1271SignatureNow_gasConsumer_returnsFalse() public view {
        // The gas consumer enters an infinite loop; staticcall should fail without propagating revert
        bool result = harness.isValidERC1271SignatureNow(address(gasConsumerSigner1271), TEST_HASH, hex"");

        assertFalse(result, "Should return false when contract consumes all gas");
    }

    /// @dev Test case: A contract that returns empty bytes (length 0) should be considered invalid.
    function test_isValidERC1271SignatureNow_emptyReturn_invalid() public view {
        bool result = harness.isValidERC1271SignatureNow(address(emptyReturnSigner1271), TEST_HASH, hex"");

        assertFalse(result, "Should be invalid when result is empty");
    }

    /// @dev Test case: A contract that returns exactly 32 bytes with the correct magic value should be considered
    ///      valid (happy path).
    function test_isValidERC1271SignatureNow_correctMagic32Bytes_valid() public view {
        bool result = harness.isValidERC1271SignatureNow(address(validSigner1271), TEST_HASH, hex"");

        assertTrue(result, "Should be valid for correct magic value in 32 bytes");
    }

    /// @dev Test case: When the signer has no code (EOA), the staticcall should return an empty result and the
    ///      function should return false.
    function test_isValidERC1271SignatureNow_signerIsEOA_returnsFalse() public view {
        address eoa = vm.addr(0xBEEF);

        bool result = harness.isValidERC1271SignatureNow(eoa, TEST_HASH, hex"");

        assertFalse(result, "Should return false when signer has no code");
    }

    /// @dev Test case: When the contract reverts (staticcall success=false), the function should return false.
    function test_isValidERC1271SignatureNow_contractReverts_returnsFalse() public view {
        bool result = harness.isValidERC1271SignatureNow(address(revertingSigner1271), TEST_HASH, hex"");

        assertFalse(result, "Should return false when contract reverts");
    }

    /// @dev Test case: A contract that returns a very large result (>1000 bytes) starting with magic should be
    ///      considered valid.
    function test_isValidERC1271SignatureNow_largeReturnStartingWithMagic_valid() public view {
        bool result = harness.isValidERC1271SignatureNow(address(largeReturnSigner1271), TEST_HASH, hex"");

        assertTrue(result, "Should be valid when large result starts with magic");
    }

    /// @dev Test case: A contract that returns 31 bytes (one short of the 32-byte minimum) should be considered
    ///      invalid.
    function test_isValidERC1271SignatureNow_31Bytes_invalid() public view {
        bool result = harness.isValidERC1271SignatureNow(address(return31BytesSigner1271), TEST_HASH, hex"");

        assertFalse(result, "Should be invalid when result is 31 bytes (one short)");
    }

    /// @dev Test case: A contract that returns magic right-padded with a non-zero byte (e.g., 0x1626ba7e00...01)
    ///      should be treated as invalid (false), not as a revert.
    function test_isValidERC1271SignatureNow_rightPaddedDifferently_invalid() public view {
        bool result = harness.isValidERC1271SignatureNow(address(rightPaddedSigner1271), TEST_HASH, hex"");

        assertFalse(result, "Dirty right-padding should be treated as invalid");
    }

    /// @dev Test case: A contract that attempts state modification during a staticcall should cause the staticcall
    ///      to fail and the function should return false.
    function test_isValidERC1271SignatureNow_stateModification_returnsFalse() public view {
        bool result = harness.isValidERC1271SignatureNow(address(stateModifierSigner1271), TEST_HASH, hex"");

        assertFalse(result, "Should return false when contract attempts state modification in staticcall");
    }

    /// @dev Test case: Only the exact ERC-1271 magic value (0x1626ba7e) should produce a true result; any other
    ///      random bytes4 return value should produce false.
    function testFuzz_isValidERC1271SignatureNow_randomMagicValue_onlyCorrectMagicIsValid(bytes4 randomMagic) public {
        // Deploy a mock that returns the random magic value
        MockERC1271CustomReturn mock = new MockERC1271CustomReturn(randomMagic);

        bool result = harness.isValidERC1271SignatureNow(address(mock), TEST_HASH, hex"");

        if (randomMagic == IERC1271.isValidSignature.selector) {
            assertTrue(result, "Should be valid when magic matches ERC-1271");
        } else {
            assertFalse(result, "Should be invalid for any non-magic bytes4 value");
        }
    }

    /// @dev Test case: Any valid private key should produce a recoverable signature via tryRecoverSigner.
    function testFuzz_tryRecoverSigner_anyValidPrivateKey_recoversCorrectly(uint256 privateKey) public view {
        privateKey = bound(privateKey, 1, SECP256K1_CURVE_ORDER - 1);

        bytes memory sig = _signHash(privateKey, TEST_HASH);
        address expectedSigner = vm.addr(privateKey);

        (bool success, address signer) = harness.tryRecoverSigner(sig, TEST_HASH);

        assertTrue(success, "Should always recover valid signature");
        assertEq(signer, expectedSigner, "Should always recover correct signer");
    }

    /// @dev Test case: Random bytes should never successfully recover a signer.
    function testFuzz_tryRecoverSigner_randomBytes_neverRecovers(bytes memory randomSig) public view {
        (bool success, address signer) = harness.tryRecoverSigner(randomSig, TEST_HASH);

        assertFalse(success, "Random bytes should not recover a signer");
        assertEq(signer, address(0), "Failed recovery should return address(0)");
    }

    /// @dev Test case: Flipping the s value to the upper half of the curve (signature malleability) should always
    ///      be rejected by tryRecoverSigner.
    function testFuzz_tryRecoverSigner_malleability_alwaysRejected(uint256 privateKey) public view {
        privateKey = bound(privateKey, 1, SECP256K1_CURVE_ORDER - 1);

        bytes memory malleableSig = _makeHighSSignature(privateKey, TEST_HASH);

        (bool success,) = harness.tryRecoverSigner(malleableSig, TEST_HASH);

        assertFalse(success, "Malleable (high-s) signature should always be rejected");
    }

    /// @dev Test case: Random ERC-1271 inner signature lengths should always produce the correct nextOffset
    ///      calculation (23 + innerLength).
    function testFuzz_tryRecoverSignerAtOffset_randomERC1271InnerLength_offsetCorrect(uint16 innerLength) public view {
        innerLength = uint16(bound(innerLength, 0, 1000));

        bytes memory innerSig = new bytes(innerLength);
        bytes memory sig = _buildContractSignature(address(validSigner1271), innerSig);

        (bool success,, uint256 nextOffset) = harness.tryRecoverSignerAtOffset(sig, 0, TEST_HASH);

        assertTrue(success, "Should succeed with valid contract signer");
        assertEq(nextOffset, 23 + innerLength, "nextOffset should be 23 + innerLength");
    }

    /// @dev Test case: Random multi-signature arrays (N EOA + M ERC-1271) should always have correct offset
    ///      chaining, with the final offset equaling the total combined length.
    function testFuzz_tryRecoverSignerAtOffset_mixedMultiSig_offsetChainingWorks(uint8 numEOA, uint8 numContract)
        public
        view
    {
        numEOA = uint8(bound(numEOA, 0, 5));
        numContract = uint8(bound(numContract, 0, 5));

        // Need at least 1 signature
        if (numEOA == 0 && numContract == 0) {
            numEOA = 1;
        }

        uint256 totalSigs = uint256(numEOA) + uint256(numContract);
        bytes[] memory sigs = new bytes[](totalSigs);

        // Build EOA signatures first
        for (uint256 i = 0; i < numEOA; i++) {
            uint256 pk = i + 1; // Private keys 1, 2, 3, ...
            sigs[i] = _signHash(pk, TEST_HASH);
        }

        // Then build contract signatures
        for (uint256 i = 0; i < numContract; i++) {
            bytes memory innerSig = new bytes(i + 1); // Varying inner sig lengths
            sigs[numEOA + i] = _buildContractSignature(address(validSigner1271), innerSig);
        }

        bytes memory combined = _concatSignatures(sigs);

        // Iterate through all signatures using offset chaining
        uint256 offset = 0;
        for (uint256 i = 0; i < totalSigs; i++) {
            (bool success,, uint256 nextOffset) = harness.tryRecoverSignerAtOffset(combined, offset, TEST_HASH);
            assertTrue(success, string.concat("Should recover sig at index ", vm.toString(i)));
            assertTrue(nextOffset > offset, "nextOffset should advance");
            offset = nextOffset;
        }

        // After all signatures, offset should equal the total length
        assertEq(offset, combined.length, "Final offset should equal total combined length");
    }

    /// @dev Test case: A signature created for hash A should never validate as the same signer when verified
    ///      against a different hash B.
    function testFuzz_tryRecoverSigner_differentHash_differentSigner(uint256 privateKey, bytes32 hashB) public view {
        privateKey = bound(privateKey, 1, SECP256K1_CURVE_ORDER - 1);
        // Ensure hashB != TEST_HASH
        vm.assume(hashB != TEST_HASH);

        bytes memory sig = _signHash(privateKey, TEST_HASH);
        address expectedSigner = vm.addr(privateKey);

        // Verify against a different hash
        (bool success, address signer) = harness.tryRecoverSigner(sig, hashB);

        if (success) {
            // If recovery succeeds with a different hash, the signer must be different
            assertTrue(signer != expectedSigner, "Signature for hash A should not validate as same signer for hash B");
        }
    }

    /// @dev Test case: Any EOA signature length except 65 should be rejected by tryRecoverSigner.
    function testFuzz_tryRecoverSigner_invalidEOALength_returnsFalse(uint16 sigLength) public view {
        sigLength = uint16(bound(sigLength, 0, 1000));
        vm.assume(sigLength != 65);

        bytes memory sig = new bytes(sigLength);
        if (sigLength > 0) {
            // Use an EOA marker so the parser takes the ECDSA path.
            sig[0] = bytes1(uint8(27));
        }

        (bool success, address signer) = harness.tryRecoverSigner(sig, TEST_HASH);

        assertFalse(success, "Recovery should fail for any non-65-byte EOA signature");
        assertEq(signer, address(0), "Signer should be address(0)");
    }

    /// @dev Test case: Any v byte except {0, 27, 28} should be rejected by tryRecoverSigner.
    function testFuzz_tryRecoverSigner_invalidVByte_returnsFalse(uint8 invalidV) public view {
        vm.assume(invalidV != 0 && invalidV != 27 && invalidV != 28);

        bytes memory sig = _signHash(TEST_PK_1, TEST_HASH);
        sig[0] = bytes1(invalidV);

        (bool success, address signer) = harness.tryRecoverSigner(sig, TEST_HASH);

        assertFalse(success, "Recovery should fail for invalid v bytes");
        assertEq(signer, address(0), "Signer should be address(0)");
    }
}
