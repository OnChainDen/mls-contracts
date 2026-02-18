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
        AdminAuthParams memory auth = _buildAdminAuthParamsForEOA({
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
        AdminAuthParams memory auth = _buildAdminAuthParamsForEOA({
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

    /// @dev Verifies that a past expiration timestamp reverts with `AdminOperationExpired`.
    function test_validateAdminAuth_pastExpiration_revertsAdminOperationExpired() public {
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        uint256 salt = 13;
        uint256 expiration = block.timestamp - 1;
        AdminAuthParams memory auth = _buildAdminAuthParamsForEOA({
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

    /// @dev Verifies that a single valid admin signature passes authorization when threshold is one.
    function test_validateAdminAuth_thresholdOne_singleValidSignature_succeeds() public {
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        uint256 salt = 15;
        uint256 expiration = block.timestamp + 1 hours;
        AdminAuthParams memory auth = _buildAdminAuthParamsForEOA({
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
        AdminAuthParams memory auth = _buildAdminAuthParamsForEOA({
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
        AdminAuthParams memory auth = _buildAdminAuthParamsForEOA({
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

    /// @dev Verifies that a valid signature from a non-admin signer reverts with `SignerIsNotAdmin`.
    function test_validateAdminAuth_nonAdminSigner_revertsSignerIsNotAdmin() public {
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

    /// @dev Verifies that replaying a consumed nonce reverts with `NonceAlreadyUsed`.
    function test_validateAdminAuth_nonceReplay_revertsNonceAlreadyUsed() public {
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        uint256 salt = 25;
        uint256 expiration = block.timestamp + 1 hours;
        AdminAuthParams memory auth = _buildAdminAuthParamsForEOA({
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
        AdminAuthParams memory approvalAuth = _buildAdminAuthParamsForEOA({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            salt: salt,
            expirationTimestamp: expiration,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // `isApproval` is part of the typed-data domain, so this must fail.
        // Verify: confirm this branch reverts for the intended failure condition.
        vm.expectRevert();
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
        AdminAuthParams memory rejectionAuth = _buildAdminAuthParamsForEOA({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: false,
            salt: salt,
            expirationTimestamp: expiration,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Verify: confirm this branch reverts for the intended failure condition.

        vm.expectRevert();
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
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        uint256 salt = 30;
        uint256 expiration = block.timestamp + 1 hours;
        AdminAuthParams memory auth = _buildAdminAuthParamsForEOA({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            salt: salt,
            expirationTimestamp: expiration,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        harness.setAdminStatus(admin1, false);

        // Verify: confirm this branch reverts for the intended failure condition.

        vm.expectRevert(abi.encodeWithSelector(IOrganizationAdmin.SignerIsNotAdmin.selector, admin1));
        // Call: run `validateAdminAuthAndConsumeNonceOrRevert` for the prepared operation payload and auth params.
        harness.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            authParams: auth
        });
    }

    /// @dev Verifies that raising the threshold after signing causes the old signature set to revert.
    function test_validateAdminAuth_thresholdRaisedAfterSigning_revertsInsufficientAuthorization() public {
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1, admin2), admins: buildArray(admin1, admin2), threshold: 1});

        uint256 salt = 31;
        uint256 expiration = block.timestamp + 1 hours;
        AdminAuthParams memory auth = _buildAdminAuthParamsForEOA({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            salt: salt,
            expirationTimestamp: expiration,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        harness.setVotingThreshold(2);

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

    /// @dev Verifies that a chain ID change invalidates previously signed signatures.
    function test_validateAdminAuth_chainIdChange_invalidatesOldSignatures() public {
        // Setup: configure members, admins, and voting threshold for the branch being exercised.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        uint256 salt = 32;
        uint256 expiration = block.timestamp + 1 hours;
        AdminAuthParams memory auth = _buildAdminAuthParamsForEOA({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            salt: salt,
            expirationTimestamp: expiration,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Chain ID is embedded into the typed-data payload.
        vm.chainId(block.chainid + 1);

        // Verify: confirm this branch reverts for the intended failure condition.

        vm.expectRevert();
        // Call: run `validateAdminAuthAndConsumeNonceOrRevert` for the prepared operation payload and auth params.
        harness.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            authParams: auth
        });
    }
}
