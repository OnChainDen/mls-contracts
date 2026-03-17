// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationAdmin} from "interfaces/organization/IOrganizationAdmin.sol";
import {
    LibOrganizationAdminHarness
} from "test/organization/libraries/LibOrganizationAdmin/LibOrganizationAdminHarness.sol";
import {
    LibOrganizationAdminSuiteBase
} from "test/organization/libraries/LibOrganizationAdmin/LibOrganizationAdminSuiteBase.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";
import {OperationType} from "types/CommonTypes.sol";

/**
 * @dev Unit tests for `LibOrganizationAdmin.validateAdminAuthAndConsumeNonceOrRevert`.
 */
contract LibOrganizationAdminAuthValidationTest is LibOrganizationAdminSuiteBase {
    /// @dev Verifies that a future expiration timestamp passes authorization.
    function test_validateAdminAuth_futureExpiration_succeeds() public {
        // Arrange: one admin, threshold one, and a future expiration.
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        uint256 salt = 11;
        uint256 expiration = block.timestamp + 1 hours;
        AdminAuthParams memory auth = _buildAdminAuthParamsForEoa({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            salt: salt,
            expirationTimestamp: expiration,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Act: validate authorization and consume nonce.
        // Call: run `validateAdminAuthAndConsumeNonceOrRevert` for the prepared operation payload and auth params.
        harness.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            authParams: auth
        });

        // Verify: successful auth must leave nonce marked as used.
        uint256 nonce = harness.computeNonce({
            operationType: OperationType.ModifyAdmins, operationData: baseOperationData, salt: salt
        });
        // Verify: assert that the nonce is marked used after successful authorization/execution.
        assertTrue(harness.getUsedNonce(nonce), "nonce should be consumed on success");
    }

    /// @dev Verifies that an expiration timestamp equal to the current block timestamp passes authorization.
    function test_validateAdminAuth_expirationEqualsBlockTimestamp_succeeds() public {
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        uint256 salt = 12;
        uint256 expiration = block.timestamp;
        AdminAuthParams memory auth = _buildAdminAuthParamsForEoa({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            salt: salt,
            expirationTimestamp: expiration,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call: run `validateAdminAuthAndConsumeNonceOrRevert` for the prepared operation payload and auth params.

        harness.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            authParams: auth
        });

        // Verify: successful auth must leave nonce marked as used.
        uint256 nonce = harness.computeNonce({
            operationType: OperationType.ModifyAdmins, operationData: baseOperationData, salt: salt
        });
        // Verify: assert that the nonce is marked used after successful authorization/execution.
        assertTrue(harness.getUsedNonce(nonce), "nonce should be consumed on boundary expiration success");
    }

    /// @dev Verifies signatures are bound to the exact expiration timestamp encoded into the operation hash.
    function test_validateAdminAuth_signedExpirationMismatch_revertsAndDoesNotConsumeNonce() public {
        // Setup: configure one admin and sign the payload with a different expiration than the call uses.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        uint256 salt = 12_001;
        uint256 signedExpiration = block.timestamp + 1 hours;
        uint256 providedExpiration = signedExpiration + 1;
        bytes32 signedHash = harness.getAdminOperationHash({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            salt: salt,
            expirationTimestamp: signedExpiration,
            isApproval: true
        });
        AdminAuthParams memory auth = AdminAuthParams({
            salt: salt, expirationTimestamp: providedExpiration, signatures: _signHash(ADMIN_PK_1, signedHash)
        });
        uint256 nonce = harness.computeNonce({
            operationType: OperationType.ModifyAdmins, operationData: baseOperationData, salt: salt
        });

        // Verify: changing the signed expiration invalidates auth and rolls back nonce consumption.
        vm.expectPartialRevert(IOrganizationAdmin.SignerIsNotAdmin.selector);
        // Call: validate the payload using the mismatched expiration timestamp.
        harness.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            authParams: auth
        });

        // Verify: failed auth does not consume the nonce.
        assertFalse(harness.getUsedNonce(nonce), "expiration mismatch should not consume nonce");
    }

    /// @dev Verifies that a past expiration timestamp reverts with `AdminOperationExpired`.
    function test_validateAdminAuth_pastExpiration_revertsAdminOperationExpired() public {
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        uint256 salt = 13;
        uint256 expiration = block.timestamp - 1;
        AdminAuthParams memory auth = _buildAdminAuthParamsForEoa({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            salt: salt,
            expirationTimestamp: expiration,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Verify: confirm this branch reverts for the intended failure condition.

        vm.expectRevert(
            abi.encodeWithSelector(IOrganizationAdmin.AdminOperationExpired.selector, expiration, block.timestamp)
        );
        // Call: run `validateAdminAuthAndConsumeNonceOrRevert` for the prepared operation payload and auth params.
        harness.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            authParams: auth
        });
    }

    /// @dev Verifies that empty signatures revert with `InsufficientAdminAuthorization`.
    function test_validateAdminAuth_emptySignatures_revertsInsufficientAuthorization() public {
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        uint256 salt = 14;
        uint256 expiration = block.timestamp + 1 hours;
        AdminAuthParams memory auth =
            AdminAuthParams({salt: salt, expirationTimestamp: expiration, signatures: bytes("")});

        // Verify: confirm this branch reverts for the intended failure condition.

        vm.expectRevert(IOrganizationAdmin.InsufficientAdminAuthorization.selector);
        // Call: run `validateAdminAuthAndConsumeNonceOrRevert` for the prepared operation payload and auth params.
        harness.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            authParams: auth
        });

        uint256 nonce = harness.computeNonce({
            operationType: OperationType.ModifyAdmins, operationData: baseOperationData, salt: salt
        });
        // Verify: assert that nonce usage was rolled back (or never consumed) on failure.
        assertFalse(harness.getUsedNonce(nonce), "nonce should not stay consumed after revert");
    }

    /// @dev Verifies `LibOrganizationAdmin.validateAdminAuthAndConsumeNonceOrRevert` succeeds with valid admin auth
    /// and consumes the derived nonce.
    function test_L_5_validateAdminAuth_thresholdOneSingleValidSignature_succeedsAndConsumesNonce() public {
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        uint256 salt = 15;
        uint256 expiration = block.timestamp + 1 hours;
        AdminAuthParams memory auth = _buildAdminAuthParamsForEoa({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            salt: salt,
            expirationTimestamp: expiration,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call: run `validateAdminAuthAndConsumeNonceOrRevert` for the prepared operation payload and auth params.

        harness.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            authParams: auth
        });

        // Verify: successful validation must consume the computed nonce.
        uint256 nonce = harness.computeNonce({
            operationType: OperationType.ModifyAdmins, operationData: baseOperationData, salt: salt
        });
        assertTrue(harness.getUsedNonce(nonce), "nonce should be consumed on threshold-one success");
    }

    /// @dev Verifies that exactly-threshold valid signatures pass authorization.
    function test_validateAdminAuth_exactlyThresholdSignatures_succeeds() public {
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1, admin2), admins: buildArray(admin1, admin2), threshold: 2});

        uint256 salt = 16;
        uint256 expiration = block.timestamp + 1 hours;
        AdminAuthParams memory auth = _buildAdminAuthParamsForEoa({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            salt: salt,
            expirationTimestamp: expiration,
            privateKeys: buildUint256Array(ADMIN_PK_1, ADMIN_PK_2)
        });

        // Call: run `validateAdminAuthAndConsumeNonceOrRevert` for the prepared operation payload and auth params.

        harness.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            authParams: auth
        });

        // Verify: successful validation must consume the computed nonce.
        uint256 nonce = harness.computeNonce({
            operationType: OperationType.ModifyAdmins, operationData: baseOperationData, salt: salt
        });
        assertTrue(harness.getUsedNonce(nonce), "nonce should be consumed on exact-threshold success");
    }

    /// @dev Verifies that fewer valid signatures than the threshold reverts with `InsufficientAdminAuthorization`.
    function test_validateAdminAuth_belowThreshold_revertsInsufficientAuthorization() public {
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1, admin2), admins: buildArray(admin1, admin2), threshold: 2});

        uint256 salt = 17;
        uint256 expiration = block.timestamp + 1 hours;
        AdminAuthParams memory auth = _buildAdminAuthParamsForEoa({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            salt: salt,
            expirationTimestamp: expiration,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Verify: confirm this branch reverts for the intended failure condition.

        vm.expectRevert(IOrganizationAdmin.InsufficientAdminAuthorization.selector);
        // Call: run `validateAdminAuthAndConsumeNonceOrRevert` for the prepared operation payload and auth params.
        harness.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            authParams: auth
        });
    }

    /// @dev Verifies that a duplicate signer reverts with `DuplicateOrOutOfOrderAdminSigner`.
    function test_validateAdminAuth_duplicateSigner_revertsDuplicateOrOutOfOrder() public {
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1, admin2), admins: buildArray(admin1, admin2), threshold: 2});

        uint256 salt = 18;
        uint256 expiration = block.timestamp + 1 hours;
        bytes32 operationHash = harness.getAdminOperationHash({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            salt: salt,
            expirationTimestamp: expiration,
            isApproval: true
        });

        bytes memory sig = _signHash(ADMIN_PK_1, operationHash);
        // Duplicate signer violates strict monotonic ordering.
        bytes memory duplicate = abi.encodePacked(sig, sig);
        AdminAuthParams memory auth =
            AdminAuthParams({salt: salt, expirationTimestamp: expiration, signatures: duplicate});

        // Verify: confirm this branch reverts for the intended failure condition.

        vm.expectRevert(
            abi.encodeWithSelector(IOrganizationAdmin.DuplicateOrOutOfOrderAdminSigner.selector, admin1, admin1)
        );
        // Call: run `validateAdminAuthAndConsumeNonceOrRevert` for the prepared operation payload and auth params.
        harness.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            authParams: auth
        });
    }

    /// @dev Verifies that out-of-order signers revert with `DuplicateOrOutOfOrderAdminSigner`.
    function test_validateAdminAuth_outOfOrderSigners_revertsDuplicateOrOutOfOrder() public {
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1, admin2), admins: buildArray(admin1, admin2), threshold: 2});

        uint256 salt = 19;
        uint256 expiration = block.timestamp + 1 hours;
        bytes32 operationHash = harness.getAdminOperationHash({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            salt: salt,
            expirationTimestamp: expiration,
            isApproval: true
        });

        bytes memory sig1 = _signHash(ADMIN_PK_1, operationHash);
        bytes memory sig2 = _signHash(ADMIN_PK_2, operationHash);

        address signer1 = vm.addr(ADMIN_PK_1);
        address signer2 = vm.addr(ADMIN_PK_2);

        bytes memory outOfOrder;
        if (signer1 < signer2) {
            outOfOrder = abi.encodePacked(sig2, sig1);
            // Verify: confirm this branch reverts for the intended failure condition.
            vm.expectRevert(
                abi.encodeWithSelector(IOrganizationAdmin.DuplicateOrOutOfOrderAdminSigner.selector, signer1, signer2)
            );
        } else {
            outOfOrder = abi.encodePacked(sig1, sig2);
            // Verify: confirm this branch reverts for the intended failure condition.
            vm.expectRevert(
                abi.encodeWithSelector(IOrganizationAdmin.DuplicateOrOutOfOrderAdminSigner.selector, signer2, signer1)
            );
        }

        AdminAuthParams memory auth =
            AdminAuthParams({salt: salt, expirationTimestamp: expiration, signatures: outOfOrder});
        // Call: run `validateAdminAuthAndConsumeNonceOrRevert` for the prepared operation payload and auth params.
        harness.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            authParams: auth
        });
    }

    /// @dev Verifies that a valid signature from a signer who is neither admin nor member reverts with
    /// `SignerIsNotAdmin`.
    function test_validateAdminAuth_nonAdminNonMemberSigner_revertsSignerIsNotAdmin() public {
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        uint256 salt = 20;
        uint256 expiration = block.timestamp + 1 hours;
        address nonAdminSigner = vm.addr(0xDEAD);

        bytes32 operationHash = harness.getAdminOperationHash({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            salt: salt,
            expirationTimestamp: expiration,
            isApproval: true
        });
        bytes memory sig = _signHash(0xDEAD, operationHash);
        AdminAuthParams memory auth = AdminAuthParams({salt: salt, expirationTimestamp: expiration, signatures: sig});

        // Verify: confirm this branch reverts for the intended failure condition.

        vm.expectRevert(abi.encodeWithSelector(IOrganizationAdmin.SignerIsNotAdmin.selector, nonAdminSigner));
        // Call: run `validateAdminAuthAndConsumeNonceOrRevert` for the prepared operation payload and auth params.
        harness.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            authParams: auth
        });
    }

    /// @dev Verifies that a valid signature from a member who is not an admin reverts with `SignerIsNotAdmin`.
    function test_validateAdminAuth_nonAdminMemberSigner_revertsSignerIsNotAdmin() public {
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1, admin2), admins: buildArray(admin1), threshold: 1});

        uint256 salt = 20;
        uint256 expiration = block.timestamp + 1 hours;

        bytes32 operationHash = harness.getAdminOperationHash({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            salt: salt,
            expirationTimestamp: expiration,
            isApproval: true
        });
        bytes memory sig = _signHash(ADMIN_PK_2, operationHash);
        AdminAuthParams memory auth = AdminAuthParams({salt: salt, expirationTimestamp: expiration, signatures: sig});

        // Verify: confirm this branch reverts for the intended failure condition.

        vm.expectRevert(abi.encodeWithSelector(IOrganizationAdmin.SignerIsNotAdmin.selector, admin2));
        // Call: run `validateAdminAuthAndConsumeNonceOrRevert` for the prepared operation payload and auth params.
        harness.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            authParams: auth
        });
    }

    /// @dev Verifies that malformed packed signatures revert with `SignatureRecoveryFailed`.
    function test_validateAdminAuth_malformedPackedSignatures_revertsSignatureRecoveryFailed() public {
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        uint256 salt = 21;
        uint256 expiration = block.timestamp + 1 hours;
        bytes memory malformed = hex"1b";
        AdminAuthParams memory auth =
            AdminAuthParams({salt: salt, expirationTimestamp: expiration, signatures: malformed});

        // Verify: malformed signature encoding must fail signature recovery.
        _expectSignatureRecoveryFailure();
        // Call: run `validateAdminAuthAndConsumeNonceOrRevert` for the prepared operation payload and auth params.
        harness.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            authParams: auth
        });
    }

    /// @dev Verifies that an ERC-1271 signer returning the wrong magic value reverts with `SignatureRecoveryFailed`.
    function test_validateAdminAuth_erc1271WrongMagic_revertsSignatureRecoveryFailed() public {
        address contractAdmin = address(wrongMagicSigner1271);
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(contractAdmin), admins: buildArray(contractAdmin), threshold: 1});

        uint256 salt = 22;
        uint256 expiration = block.timestamp + 1 hours;
        bytes memory contractSig = _buildContractSignature({signer: contractAdmin, innerSig: hex"abcd"});
        AdminAuthParams memory auth =
            AdminAuthParams({salt: salt, expirationTimestamp: expiration, signatures: contractSig});

        // Verify: wrong ERC-1271 magic value must fail signature recovery.
        _expectSignatureRecoveryFailure();
        // Call: run `validateAdminAuthAndConsumeNonceOrRevert` for the prepared operation payload and auth params.
        harness.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            authParams: auth
        });
    }

    /// @dev Verifies that a reverting ERC-1271 signer causes a `SignatureRecoveryFailed` revert.
    function test_validateAdminAuth_erc1271RevertingSigner_revertsSignatureRecoveryFailed() public {
        address contractAdmin = address(revertingSigner1271);
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(contractAdmin), admins: buildArray(contractAdmin), threshold: 1});

        uint256 salt = 23;
        uint256 expiration = block.timestamp + 1 hours;
        bytes memory contractSig = _buildContractSignature({signer: contractAdmin, innerSig: hex"abcd"});
        AdminAuthParams memory auth =
            AdminAuthParams({salt: salt, expirationTimestamp: expiration, signatures: contractSig});

        // Verify: ERC-1271 signer reverts must bubble up as signature-recovery failure.
        _expectSignatureRecoveryFailure();
        // Call: run `validateAdminAuthAndConsumeNonceOrRevert` for the prepared operation payload and auth params.
        harness.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            authParams: auth
        });
    }

    /// @dev Verifies that mixed EOA and ERC-1271 signatures in ascending order pass authorization.
    function test_validateAdminAuth_mixedEOAAndERC1271_sorted_succeeds() public {
        address contractAdmin = address(validSigner1271);
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({
            members: buildArray(admin1, contractAdmin), admins: buildArray(admin1, contractAdmin), threshold: 2
        });

        uint256 salt = 24;
        uint256 expiration = block.timestamp + 1 hours;
        bytes32 operationHash = harness.getAdminOperationHash({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            salt: salt,
            expirationTimestamp: expiration,
            isApproval: true
        });

        address[] memory signers = buildArray(admin1, contractAdmin);
        bytes[] memory signatures = new bytes[](2);
        signatures[0] = _signHash(ADMIN_PK_1, operationHash);
        signatures[1] = _buildContractSignature({signer: contractAdmin, innerSig: hex"beef"});

        AdminAuthParams memory auth = AdminAuthParams({
            salt: salt, expirationTimestamp: expiration, signatures: _sortAndConcatSignatures(signers, signatures)
        });
        // Call: run `validateAdminAuthAndConsumeNonceOrRevert` for the prepared operation payload and auth params.
        harness.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            authParams: auth
        });

        // Verify: this test passes if mixed-signer validation succeeds without reverting.
    }

    /// @dev Verifies `LibOrganizationAdmin.validateAdminAuthAndConsumeNonceOrRevert` succeeds once and then rejects a
    /// replay of the same nonce.
    function test_L_15_validateAdminAuth_nonceReplay_revertsNonceAlreadyUsed() public {
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        uint256 salt = 25;
        uint256 expiration = block.timestamp + 1 hours;
        AdminAuthParams memory auth = _buildAdminAuthParamsForEoa({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            salt: salt,
            expirationTimestamp: expiration,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call: run `validateAdminAuthAndConsumeNonceOrRevert` for the prepared operation payload and auth params.

        harness.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            authParams: auth
        });

        uint256 nonce = harness.computeNonce({
            operationType: OperationType.ModifyAdmins, operationData: baseOperationData, salt: salt
        });
        // Verify: replay protection should reject nonce reuse.
        _expectNonceAlreadyUsed(nonce);
        // Call: run `validateAdminAuthAndConsumeNonceOrRevert` for the prepared operation payload and auth params.
        harness.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            authParams: auth
        });
    }

    /// @dev Verifies that the same operation with different salts produces different nonces.
    function test_validateAdminAuth_differentSalts_produceDifferentNonces() public view {
        // Setup: define one operation payload and two salt variants.

        // Call: compute nonces for each salt variant.
        uint256 nonceA = harness.computeNonce({
            operationType: OperationType.ModifyAdmins, operationData: baseOperationData, salt: 111
        });
        uint256 nonceB = harness.computeNonce({
            operationType: OperationType.ModifyAdmins, operationData: baseOperationData, salt: 222
        });

        // Verify: assert that nonce derivation changes when the input dimension changes.

        assertTrue(nonceA != nonceB, "nonces must differ for different salts");
    }

    /// @dev Verifies that the same data and salt with different operation types produce different nonces.
    function test_validateAdminAuth_differentOperationTypes_produceDifferentNonces() public view {
        uint256 salt = 333;

        // Setup: keep payload and salt fixed while varying the operation type.

        // Call: compute nonces for both operation types.
        uint256 nonceA = harness.computeNonce({
            operationType: OperationType.ModifyAdmins, operationData: baseOperationData, salt: salt
        });
        uint256 nonceB = harness.computeNonce({
            operationType: OperationType.ModifyMembers, operationData: baseOperationData, salt: salt
        });

        // Verify: assert that nonce derivation changes when the input dimension changes.

        assertTrue(nonceA != nonceB, "nonces must differ across operation types");
    }

    /// @dev Verifies that the same operation and salt produce different nonces across different organization addresses.
    function test_validateAdminAuth_differentOrganizationAddresses_produceDifferentNonces() public {
        // Setup: deploy a second harness to change the organization address component.
        LibOrganizationAdminHarness secondHarness = new LibOrganizationAdminHarness();

        uint256 salt = 444;

        // Call: compute nonces from both harness addresses for the same payload tuple.
        uint256 nonceA = harness.computeNonce(OperationType.ModifyAdmins, baseOperationData, salt);
        uint256 nonceB = secondHarness.computeNonce(OperationType.ModifyAdmins, baseOperationData, salt);

        // Verify: assert that nonce derivation changes when the input dimension changes.

        assertTrue(nonceA != nonceB, "nonce must bind to organization address");
    }

    /// @dev Verifies that approval signatures cannot authorize a rejection operation.
    function test_validateAdminAuth_approvalSignatureCannotAuthorizeRejection() public {
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        uint256 salt = 26;
        uint256 expiration = block.timestamp + 1 hours;
        AdminAuthParams memory approvalAuth = _buildAdminAuthParamsForEoa({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            salt: salt,
            expirationTimestamp: expiration,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // `isApproval` is part of the typed-data domain, so this must fail.
        // Verify: confirm this branch reverts for the intended failure condition.
        vm.expectPartialRevert(IOrganizationAdmin.SignerIsNotAdmin.selector);
        // Call: run `validateAdminAuthAndConsumeNonceOrRevert` for the prepared operation payload and auth params.
        harness.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: false,
            authParams: approvalAuth
        });

        uint256 nonce = harness.computeNonce({
            operationType: OperationType.ModifyAdmins, operationData: baseOperationData, salt: salt
        });
        // Verify: assert that nonce usage was rolled back (or never consumed) on failure.
        assertFalse(harness.getUsedNonce(nonce), "nonce should rollback on failed auth");
    }

    /// @dev Verifies that rejection signatures cannot authorize an approval operation.
    function test_validateAdminAuth_rejectionSignatureCannotAuthorizeApproval() public {
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        uint256 salt = 27;
        uint256 expiration = block.timestamp + 1 hours;
        AdminAuthParams memory rejectionAuth = _buildAdminAuthParamsForEoa({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: false,
            salt: salt,
            expirationTimestamp: expiration,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Verify: the approval-path hash mismatch recovers a non-admin signer and fails the admin check.
        vm.expectPartialRevert(IOrganizationAdmin.SignerIsNotAdmin.selector);
        // Call: run `validateAdminAuthAndConsumeNonceOrRevert` for the prepared operation payload and auth params.
        harness.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            authParams: rejectionAuth
        });

        uint256 nonce = harness.computeNonce({
            operationType: OperationType.ModifyAdmins, operationData: baseOperationData, salt: salt
        });
        // Verify: assert that nonce usage was rolled back (or never consumed) on failure.
        assertFalse(harness.getUsedNonce(nonce), "nonce should rollback on failed auth");
    }

    /// @dev Verifies that trailing bytes after the threshold is met are ignored via early exit.
    function test_validateAdminAuth_trailingBytesIgnoredAfterThresholdMet() public {
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        uint256 salt = 28;
        uint256 expiration = block.timestamp + 1 hours;
        bytes32 operationHash = harness.getAdminOperationHash({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            salt: salt,
            expirationTimestamp: expiration,
            isApproval: true
        });

        bytes memory validSig = _signHash(ADMIN_PK_1, operationHash);
        // Early exit at threshold means trailing bytes are never parsed.
        bytes memory signatures = abi.encodePacked(validSig, hex"deadbeefcafebabe");
        AdminAuthParams memory auth =
            AdminAuthParams({salt: salt, expirationTimestamp: expiration, signatures: signatures});

        // Call: run `validateAdminAuthAndConsumeNonceOrRevert` for the prepared operation payload and auth params.

        harness.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            authParams: auth
        });

        // Verify: this test passes if threshold short-circuit succeeds without reverting.
    }

    /// @dev Verifies that a failed authorization rolls back nonce consumption.
    function test_validateAdminAuth_failedAuth_rollsBackNonceUsage() public {
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        uint256 salt = 29;
        uint256 expiration = block.timestamp + 1 hours;
        bytes memory malformed = hex"1b";
        AdminAuthParams memory auth =
            AdminAuthParams({salt: salt, expirationTimestamp: expiration, signatures: malformed});

        uint256 nonce = harness.computeNonce({
            operationType: OperationType.ModifyAdmins, operationData: baseOperationData, salt: salt
        });

        _expectSignatureRecoveryFailure();
        // Call: run `validateAdminAuthAndConsumeNonceOrRevert` for the prepared operation payload and auth params.
        harness.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            authParams: auth
        });

        // Verify: assert that nonce usage was rolled back (or never consumed) on failure.

        assertFalse(harness.getUsedNonce(nonce), "nonce must not remain used after revert");
    }

    /// @dev Verifies that removing an admin after signing but before execution reverts with `SignerIsNotAdmin`.
    function test_validateAdminAuth_adminRemovedAfterSigning_revertsSignerIsNotAdmin() public {
        // Setup: configure a two-admin quorum, sign with `admin1`, then remove `admin1` before execution so the
        // signed admin set is stale at validation time.
        _setMembersAndAdmins({members: buildArray(admin1, admin2), admins: buildArray(admin1, admin2), threshold: 1});

        uint256 salt = 30;
        uint256 expiration = block.timestamp + 1 hours;
        AdminAuthParams memory auth = _buildAdminAuthParamsForEoa({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            salt: salt,
            expirationTimestamp: expiration,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        uint256 nonce = harness.computeNonce({
            operationType: OperationType.ModifyAdmins, operationData: baseOperationData, salt: salt
        });

        // Call: remove the only signer in the bundle from the current admin set, then execute the stale auth bundle.
        harness.setAdminStatus(admin1, false);

        vm.expectRevert(abi.encodeWithSelector(IOrganizationAdmin.SignerIsNotAdmin.selector, admin1));
        harness.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            authParams: auth
        });

        // Verify: stale admin-set changes fail closed and leave the signed nonce unused.
        assertFalse(harness.getUsedNonce(nonce), "removing the signed admin should leave nonce unused");
    }

    /// @dev Verifies that raising the threshold after signing causes the old signature set to revert.
    function test_validateAdminAuth_thresholdRaisedAfterSigning_revertsInsufficientAuthorization() public {
        // Setup: configure a one-of-two admin quorum, sign with one admin, then raise the threshold so the signed
        // bundle no longer satisfies current execution-time state.
        _setMembersAndAdmins({members: buildArray(admin1, admin2), admins: buildArray(admin1, admin2), threshold: 1});

        uint256 salt = 31;
        uint256 expiration = block.timestamp + 1 hours;
        AdminAuthParams memory auth = _buildAdminAuthParamsForEoa({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            salt: salt,
            expirationTimestamp: expiration,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        uint256 nonce = harness.computeNonce({
            operationType: OperationType.ModifyAdmins, operationData: baseOperationData, salt: salt
        });

        // Call: increase the required threshold after signatures are collected, then execute the stale bundle.
        harness.setVotingThreshold(2);

        vm.expectRevert(IOrganizationAdmin.InsufficientAdminAuthorization.selector);
        harness.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            authParams: auth
        });

        // Verify: threshold drift invalidates stale signatures without burning the nonce.
        assertFalse(harness.getUsedNonce(nonce), "raising threshold should leave stale-signature nonce unused");
    }

    /// @dev Verifies that a chain ID change invalidates previously signed signatures.
    function test_validateAdminAuth_chainIdChange_invalidatesOldSignatures() public {
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        uint256 salt = 32;
        uint256 expiration = block.timestamp + 1 hours;
        AdminAuthParams memory auth = _buildAdminAuthParamsForEoa({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            salt: salt,
            expirationTimestamp: expiration,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        uint256 nonce = harness.computeNonce({
            operationType: OperationType.ModifyAdmins, operationData: baseOperationData, salt: salt
        });

        // Chain ID is embedded into the typed-data payload.
        vm.chainId(block.chainid + 1);

        // Verify: the changed EIP-712 domain recovers a non-admin signer and leaves the nonce unused.
        vm.expectPartialRevert(IOrganizationAdmin.SignerIsNotAdmin.selector);
        // Call: run `validateAdminAuthAndConsumeNonceOrRevert` for the prepared operation payload and auth params.
        harness.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            authParams: auth
        });

        // Verify: failed cross-chain replay does not consume the nonce.
        assertFalse(harness.getUsedNonce(nonce), "cross-chain replay should not consume nonce");
    }

    /// @dev Verifies admin signatures valid on one organization fail on another organization.
    function test_validateAdminAuth_crossOrganizationReplay_revertsSignerIsNotAdmin() public {
        // Setup: deploy a second organization harness and mirror the same admin/member configuration on both.
        LibOrganizationAdminHarness otherHarness = new LibOrganizationAdminHarness();
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
        otherHarness.setGuardian(GUARDIAN);
        otherHarness.setMemberStatus(admin1, true);
        otherHarness.setAdminStatus(admin1, true);
        otherHarness.setAdminCount(1);
        otherHarness.setVotingThreshold(1);

        uint256 salt = 32_001;
        uint256 expiration = block.timestamp + 1 hours;
        AdminAuthParams memory auth = _buildAdminAuthParamsForEoa({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            salt: salt,
            expirationTimestamp: expiration,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Verify: replaying the signed payload on another organization changes the EIP-712 domain and fails auth.
        vm.expectPartialRevert(IOrganizationAdmin.SignerIsNotAdmin.selector);
        // Call: validate the original signature bundle through the second organization harness.
        otherHarness.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            authParams: auth
        });
    }

    /// @dev Verifies `LibOrganizationAdmin.validateAdminAuthAndConsumeNonceOrRevert` leaves expired nonces unused.
    function test_validateAdminAuth_expiredAuth_revertsAndDoesNotConsumeNonce() public {
        uint256 salt = 33;
        uint256 expiration = block.timestamp - 1;

        // Setup: configure one-admin auth and precompute the nonce tied to an already-expired payload.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
        AdminAuthParams memory auth = _buildAdminAuthParamsForEoa({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            salt: salt,
            expirationTimestamp: expiration,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        uint256 nonce = harness.computeNonce({
            operationType: OperationType.ModifyAdmins, operationData: baseOperationData, salt: salt
        });

        // Call: validate expired admin auth, expecting the expiration guard to revert before nonce consumption.
        vm.expectRevert(
            abi.encodeWithSelector(IOrganizationAdmin.AdminOperationExpired.selector, expiration, block.timestamp)
        );
        harness.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            authParams: auth
        });

        // Verify: the expired branch leaves the derived nonce unused.
        assertFalse(harness.getUsedNonce(nonce), "expired auth should not consume nonce");
    }

    /// @dev Verifies `LibOrganizationAdmin.validateAdminAuthAndConsumeNonceOrRevert` keeps below-threshold nonces
    /// unused.
    function test_validateAdminAuth_belowThreshold_revertsAndDoesNotConsumeNonce() public {
        uint256 salt = 34;

        // Setup: require two admin signatures while signing the payload with only one admin key.
        _setMembersAndAdmins({members: buildArray(admin1, admin2), admins: buildArray(admin1, admin2), threshold: 2});
        AdminAuthParams memory auth = _buildAdminAuthParamsForEoa({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            salt: salt,
            expirationTimestamp: block.timestamp + 1 hours,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        uint256 nonce = harness.computeNonce({
            operationType: OperationType.ModifyAdmins, operationData: baseOperationData, salt: salt
        });

        // Call: validate the undersigned payload, expecting threshold enforcement to revert.
        vm.expectRevert(IOrganizationAdmin.InsufficientAdminAuthorization.selector);
        harness.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            authParams: auth
        });

        // Verify: the failed threshold check does not leave the nonce consumed.
        assertFalse(harness.getUsedNonce(nonce), "below-threshold auth should not consume nonce");
    }

    /// @dev Verifies `LibOrganizationAdmin.validateAdminAuthAndConsumeNonceOrRevert` keeps malformed-signature nonces
    /// unused.
    function test_validateAdminAuth_malformedSignatures_revertAndDoNotConsumeNonce() public {
        uint256 salt = 35;

        // Setup: configure one-admin auth and bind the nonce to a malformed packed-signature payload.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
        AdminAuthParams memory auth =
            AdminAuthParams({salt: salt, expirationTimestamp: block.timestamp + 1 hours, signatures: hex"1b"});
        uint256 nonce = harness.computeNonce({
            operationType: OperationType.ModifyAdmins, operationData: baseOperationData, salt: salt
        });

        // Call: validate malformed signatures, expecting signature recovery to revert after nonce rollback.
        _expectSignatureRecoveryFailure();
        harness.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            authParams: auth
        });

        // Verify: malformed signatures do not leave the nonce consumed.
        assertFalse(harness.getUsedNonce(nonce), "malformed signatures should not consume nonce");
    }

    /// @dev Verifies `LibOrganizationAdmin.validateAdminAuthAndConsumeNonceOrRevert` rejects changed operation data
    /// without burning nonce.
    function test_validateAdminAuth_signedOperationDataMismatch_revertsAndDoesNotConsumeNonce() public {
        bytes memory signedOperationData = baseOperationData;
        // casting string literal to bytes32 is safe because "mutated-operation" fits within 32 bytes
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes memory mutatedOperationData = abi.encode(bytes32("mutated-operation"), uint256(456));
        uint256 salt = 36;

        // Setup: sign the baseline payload, then call validation with different operation data under the same salt.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
        AdminAuthParams memory auth = _buildAdminAuthParamsForEoa({
            operationType: OperationType.ModifyAdmins,
            operationData: signedOperationData,
            isApproval: true,
            salt: salt,
            expirationTimestamp: block.timestamp + 1 hours,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call: validate with mutated operation data, expecting signer recovery against the wrong hash to fail admin
        // checks.
        vm.expectPartialRevert(IOrganizationAdmin.SignerIsNotAdmin.selector);
        harness.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins,
            operationData: mutatedOperationData,
            isApproval: true,
            authParams: auth
        });

        uint256 signedNonce = harness.computeNonce({
            operationType: OperationType.ModifyAdmins, operationData: signedOperationData, salt: salt
        });
        uint256 mutatedNonce = harness.computeNonce({
            operationType: OperationType.ModifyAdmins, operationData: mutatedOperationData, salt: salt
        });

        // Verify: neither the signed nonce nor the mutated nonce is consumed on the failed authorization path.
        assertFalse(harness.getUsedNonce(signedNonce), "signed payload nonce should remain unused");
        assertFalse(harness.getUsedNonce(mutatedNonce), "mutated payload nonce should remain unused");
    }

    /// @dev Verifies `LibOrganizationAdmin.validateAdminAuthAndConsumeNonceOrRevert` rejects changed operation types
    /// without burning nonce.
    function test_validateAdminAuth_signedOperationTypeMismatch_revertsAndDoesNotConsumeNonce() public {
        uint256 salt = 37;

        // Setup: sign the payload for `ModifyAdmins`, then call validation under `ModifyMembers` with the same bytes
        // and salt.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
        AdminAuthParams memory auth = _buildAdminAuthParamsForEoa({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            salt: salt,
            expirationTimestamp: block.timestamp + 1 hours,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call: validate with the wrong operation type, expecting signer recovery against the wrong hash to fail admin
        // checks.
        vm.expectPartialRevert(IOrganizationAdmin.SignerIsNotAdmin.selector);
        harness.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyMembers,
            operationData: baseOperationData,
            isApproval: true,
            authParams: auth
        });

        uint256 adminsNonce = harness.computeNonce({
            operationType: OperationType.ModifyAdmins, operationData: baseOperationData, salt: salt
        });
        uint256 membersNonce = harness.computeNonce({
            operationType: OperationType.ModifyMembers, operationData: baseOperationData, salt: salt
        });

        // Verify: neither nonce domain is consumed by the wrong-operation-type attempt.
        assertFalse(harness.getUsedNonce(adminsNonce), "signed operation-type nonce should remain unused");
        assertFalse(harness.getUsedNonce(membersNonce), "mutated operation-type nonce should remain unused");
    }

    /// @dev Verifies signatures are bound to the exact salt encoded into the operation hash.
    function test_validateAdminAuth_signedSaltMismatch_revertsAndDoesNotConsumeEitherNonce() public {
        // Setup: configure one admin and sign the payload with a different salt than the call uses.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        uint256 signedSalt = 12_101;
        uint256 providedSalt = signedSalt + 1;
        uint256 expiration = block.timestamp + 1 hours;
        bytes32 signedHash = harness.getAdminOperationHash({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            salt: signedSalt,
            expirationTimestamp: expiration,
            isApproval: true
        });
        AdminAuthParams memory auth = AdminAuthParams({
            salt: providedSalt, expirationTimestamp: expiration, signatures: _signHash(ADMIN_PK_1, signedHash)
        });
        uint256 signedNonce = harness.computeNonce({
            operationType: OperationType.ModifyAdmins, operationData: baseOperationData, salt: signedSalt
        });
        uint256 providedNonce = harness.computeNonce({
            operationType: OperationType.ModifyAdmins, operationData: baseOperationData, salt: providedSalt
        });

        // Verify: changing the signed salt invalidates auth and leaves both nonce domains unused.
        vm.expectPartialRevert(IOrganizationAdmin.SignerIsNotAdmin.selector);
        // Call: validate the payload using the mismatched salt.
        harness.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            authParams: auth
        });

        // Verify: neither the originally signed nonce nor the provided nonce is consumed.
        assertFalse(harness.getUsedNonce(signedNonce), "signed salt nonce should remain unused");
        assertFalse(harness.getUsedNonce(providedNonce), "provided salt nonce should remain unused");
    }

    /// @dev Verifies `LibOrganizationAdmin.validateAdminAuthAndConsumeNonceOrRevert` keeps non-admin signer nonces
    /// unused.
    function test_validateAdminAuth_nonAdminSigner_revertsAndDoesNotConsumeNonce() public {
        uint256 nonAdminPk = 0xDEAE;
        uint256 salt = 38;
        address nonAdminSigner = vm.addr(nonAdminPk);

        // Setup: configure one-admin auth, then sign the payload with an address that is not an admin.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
        bytes32 operationHash = harness.getAdminOperationHash({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            salt: salt,
            expirationTimestamp: block.timestamp + 1 hours,
            isApproval: true
        });
        AdminAuthParams memory auth = AdminAuthParams({
            salt: salt, expirationTimestamp: block.timestamp + 1 hours, signatures: _signHash(nonAdminPk, operationHash)
        });
        uint256 nonce = harness.computeNonce({
            operationType: OperationType.ModifyAdmins, operationData: baseOperationData, salt: salt
        });

        // Call: validate the non-admin signer payload, expecting `SignerIsNotAdmin`.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationAdmin.SignerIsNotAdmin.selector, nonAdminSigner));
        harness.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            authParams: auth
        });

        // Verify: the failed non-admin authorization keeps the nonce unused.
        assertFalse(harness.getUsedNonce(nonce), "non-admin signer should not consume nonce");
    }

    /// @dev Verifies `LibOrganizationAdmin.validateAdminAuthAndConsumeNonceOrRevert` keeps out-of-order signer nonces
    /// unused.
    function test_validateAdminAuth_outOfOrderSigners_revertAndDoNotConsumeNonce() public {
        uint256 salt = 39;

        // Setup: configure threshold-two auth, then intentionally pack the signer set in descending address order.
        _setMembersAndAdmins({members: buildArray(admin1, admin2), admins: buildArray(admin1, admin2), threshold: 2});
        bytes32 operationHash = harness.getAdminOperationHash({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            salt: salt,
            expirationTimestamp: block.timestamp + 1 hours,
            isApproval: true
        });
        bytes memory sig1 = _signHash(ADMIN_PK_1, operationHash);
        bytes memory sig2 = _signHash(ADMIN_PK_2, operationHash);
        bytes memory outOfOrder = admin1 < admin2 ? abi.encodePacked(sig2, sig1) : abi.encodePacked(sig1, sig2);
        AdminAuthParams memory auth =
            AdminAuthParams({salt: salt, expirationTimestamp: block.timestamp + 1 hours, signatures: outOfOrder});
        uint256 nonce = harness.computeNonce({
            operationType: OperationType.ModifyAdmins, operationData: baseOperationData, salt: salt
        });

        // Call: validate the out-of-order signer set, expecting strict signer ordering to revert.
        vm.expectPartialRevert(IOrganizationAdmin.DuplicateOrOutOfOrderAdminSigner.selector);
        harness.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            authParams: auth
        });

        // Verify: the failed signer-ordering branch keeps the nonce unused.
        assertFalse(harness.getUsedNonce(nonce), "out-of-order signers should not consume nonce");
    }

    /// @dev Verifies `LibOrganizationAdmin.validateAdminAuthAndConsumeNonceOrRevert` shares nonce space across approval
    /// and rejection.
    function test_validateAdminAuth_approvalThenRejection_reusesSharedNonceAndRevertsNonceAlreadyUsed() public {
        uint256 salt = 40;
        uint256 expiration = block.timestamp + 1 hours;

        // Setup: configure one-admin auth and build distinct approval/rejection signatures for the same operation
        // tuple.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
        AdminAuthParams memory approvalAuth = _buildAdminAuthParamsForEoa({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            salt: salt,
            expirationTimestamp: expiration,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        AdminAuthParams memory rejectionAuth = _buildAdminAuthParamsForEoa({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: false,
            salt: salt,
            expirationTimestamp: expiration,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        uint256 nonce = harness.computeNonce({
            operationType: OperationType.ModifyAdmins, operationData: baseOperationData, salt: salt
        });

        // Call: consume the nonce through approval, then replay the same tuple through the rejection path.
        harness.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            authParams: approvalAuth
        });

        _expectNonceAlreadyUsed(nonce);
        harness.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: false,
            authParams: rejectionAuth
        });

        // Verify: approval burned the shared nonce before the rejection-path replay.
        assertTrue(harness.getUsedNonce(nonce), "shared nonce should remain consumed after approval");
    }

    /// @dev Verifies `LibOrganizationAdmin.validateAdminAuthAndConsumeNonceOrRevert` isolates nonce space by operation
    /// type.
    function test_validateAdminAuth_differentOperationTypes_canBothSucceed() public {
        uint256 salt = 41;
        uint256 expiration = block.timestamp + 1 hours;

        // Setup: configure one-admin auth and sign the same payload bytes for two different admin operation domains.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
        AdminAuthParams memory modifyAdminsAuth = _buildAdminAuthParamsForEoa({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            salt: salt,
            expirationTimestamp: expiration,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        AdminAuthParams memory modifyMembersAuth = _buildAdminAuthParamsForEoa({
            operationType: OperationType.ModifyMembers,
            operationData: baseOperationData,
            isApproval: true,
            salt: salt,
            expirationTimestamp: expiration,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        uint256 modifyAdminsNonce = harness.computeNonce({
            operationType: OperationType.ModifyAdmins, operationData: baseOperationData, salt: salt
        });
        uint256 modifyMembersNonce = harness.computeNonce({
            operationType: OperationType.ModifyMembers, operationData: baseOperationData, salt: salt
        });

        // Call: validate both operation types with the same payload bytes and salt.
        harness.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            authParams: modifyAdminsAuth
        });
        harness.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyMembers,
            operationData: baseOperationData,
            isApproval: true,
            authParams: modifyMembersAuth
        });

        // Verify: both operation domains consume their own nonce successfully.
        assertTrue(harness.getUsedNonce(modifyAdminsNonce), "modify-admins nonce should be consumed");
        assertTrue(harness.getUsedNonce(modifyMembersNonce), "modify-members nonce should be consumed");
    }

    /// @dev Verifies `LibOrganizationAdmin.validateAdminAuthAndConsumeNonceOrRevert` isolates nonce space by salt.
    function test_validateAdminAuth_differentSalts_canBothSucceed() public {
        uint256 expiration = block.timestamp + 1 hours;

        // Setup: configure one-admin auth and sign the same operation tuple twice with different salts.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});
        AdminAuthParams memory authA = _buildAdminAuthParamsForEoa({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            salt: 42,
            expirationTimestamp: expiration,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        AdminAuthParams memory authB = _buildAdminAuthParamsForEoa({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            salt: 43,
            expirationTimestamp: expiration,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        uint256 nonceA = harness.computeNonce({
            operationType: OperationType.ModifyAdmins, operationData: baseOperationData, salt: 42
        });
        uint256 nonceB = harness.computeNonce({
            operationType: OperationType.ModifyAdmins, operationData: baseOperationData, salt: 43
        });

        // Call: validate both salts against the same operation tuple.
        harness.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            authParams: authA
        });
        harness.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            authParams: authB
        });

        // Verify: both salts consume independent nonces successfully.
        assertTrue(harness.getUsedNonce(nonceA), "first salt nonce should be consumed");
        assertTrue(harness.getUsedNonce(nonceB), "second salt nonce should be consumed");
    }

    /// @dev Verifies `LibOrganizationAdmin.validateAdminAuthAndConsumeNonceOrRevert` enforces shared replay protection
    /// for mixed EOA/ERC-1271 auth.
    function test_validateAdminAuth_mixedEOAAndERC1271_successThenReplay_revertsSharedNonce() public {
        address contractAdmin = address(validSigner1271);
        uint256 salt = 44;
        uint256 expiration = block.timestamp + 1 hours;

        // Setup: configure threshold-two auth with one EOA signer and one ERC-1271 signer over a shared nonce tuple.
        _setMembersAndAdmins({
            members: buildArray(admin1, contractAdmin), admins: buildArray(admin1, contractAdmin), threshold: 2
        });
        bytes32 operationHash = harness.getAdminOperationHash({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            salt: salt,
            expirationTimestamp: expiration,
            isApproval: true
        });
        address[] memory signers = buildArray(admin1, contractAdmin);
        bytes[] memory signatures = new bytes[](2);
        signatures[0] = _signHash(ADMIN_PK_1, operationHash);
        signatures[1] = _buildContractSignature({signer: contractAdmin, innerSig: hex"beef"});
        AdminAuthParams memory auth = AdminAuthParams({
            salt: salt, expirationTimestamp: expiration, signatures: _sortAndConcatSignatures(signers, signatures)
        });
        uint256 nonce = harness.computeNonce({
            operationType: OperationType.ModifyAdmins, operationData: baseOperationData, salt: salt
        });

        // Call: validate the mixed signer set once successfully, then replay the same nonce tuple.
        harness.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            authParams: auth
        });

        _expectNonceAlreadyUsed(nonce);
        harness.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            authParams: auth
        });

        // Verify: the mixed-signer success path still enforces one-time nonce consumption.
        assertTrue(harness.getUsedNonce(nonce), "mixed signer nonce should remain consumed after replay attempt");
    }
}
