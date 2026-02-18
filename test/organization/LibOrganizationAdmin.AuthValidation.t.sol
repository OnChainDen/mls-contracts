// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationAdmin} from "interfaces/organization/IOrganizationAdmin.sol";
import {LibOrganizationAdminHarness} from "test/organization/harness/LibOrganizationAdminHarness.sol";
import {LibOrganizationAdminSuiteBase} from "test/organization/helpers/LibOrganizationAdminSuiteBase.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";
import {OperationType} from "types/CommonTypes.sol";

/**
 * @dev Unit tests for `LibOrganizationAdmin.validateAdminAuthAndConsumeNonceOrRevert`.
 */
contract LibOrganizationAdminAuthValidationTest is LibOrganizationAdminSuiteBase {
    /// @dev Future expiration succeeds.
    function test_validateAdminAuth_futureExpiration_succeeds() public {
        // Arrange: one admin, threshold one, and a future expiration.
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
        harness.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            authParams: auth
        });

        // Assert: successful auth must leave nonce marked as used.
        uint256 nonce = _computeNonce(OperationType.ModifyAdmins, baseOperationData, salt);
        assertTrue(_isNonceUsed(nonce), "nonce should be consumed on success");
    }

    /// @dev expirationTimestamp equal to current block timestamp succeeds.
    function test_validateAdminAuth_expirationEqualsBlockTimestamp_succeeds() public {
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

        harness.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            authParams: auth
        });

        uint256 nonce = _computeNonce(OperationType.ModifyAdmins, baseOperationData, salt);
        assertTrue(_isNonceUsed(nonce), "nonce should be consumed on boundary expiration success");
    }

    /// @dev Past expiration reverts AdminOperationExpired.
    function test_validateAdminAuth_pastExpiration_revertsAdminOperationExpired() public {
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

        vm.expectRevert(
            abi.encodeWithSelector(IOrganizationAdmin.AdminOperationExpired.selector, expiration, block.timestamp)
        );
        harness.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            authParams: auth
        });
    }

    /// @dev Empty signatures revert InsufficientAdminAuthorization.
    function test_validateAdminAuth_emptySignatures_revertsInsufficientAuthorization() public {
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        uint256 salt = 14;
        uint256 expiration = block.timestamp + 1 hours;
        AdminAuthParams memory auth =
            AdminAuthParams({salt: salt, expirationTimestamp: expiration, signatures: bytes("")});

        vm.expectRevert(IOrganizationAdmin.InsufficientAdminAuthorization.selector);
        harness.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            authParams: auth
        });

        uint256 nonce = _computeNonce(OperationType.ModifyAdmins, baseOperationData, salt);
        assertFalse(_isNonceUsed(nonce), "nonce should not stay consumed after revert");
    }

    /// @dev Threshold=1 with one valid admin signature succeeds.
    function test_validateAdminAuth_thresholdOne_singleValidSignature_succeeds() public {
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

        harness.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            authParams: auth
        });
    }

    /// @dev Exactly-threshold signatures succeed.
    function test_validateAdminAuth_exactlyThresholdSignatures_succeeds() public {
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

        harness.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            authParams: auth
        });
    }

    /// @dev Fewer valid signatures than threshold reverts InsufficientAdminAuthorization.
    function test_validateAdminAuth_belowThreshold_revertsInsufficientAuthorization() public {
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

        vm.expectRevert(IOrganizationAdmin.InsufficientAdminAuthorization.selector);
        harness.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            authParams: auth
        });
    }

    /// @dev Duplicate signer reverts DuplicateOrOutOfOrderAdminSigner.
    function test_validateAdminAuth_duplicateSigner_revertsDuplicateOrOutOfOrder() public {
        _setMembersAndAdmins({members: buildArray(admin1, admin2), admins: buildArray(admin1, admin2), threshold: 2});

        uint256 salt = 18;
        uint256 expiration = block.timestamp + 1 hours;
        bytes32 operationHash = _computeOperationHash({
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

        vm.expectRevert(
            abi.encodeWithSelector(IOrganizationAdmin.DuplicateOrOutOfOrderAdminSigner.selector, admin1, admin1)
        );
        harness.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            authParams: auth
        });
    }

    /// @dev Out-of-order signers reverts DuplicateOrOutOfOrderAdminSigner.
    function test_validateAdminAuth_outOfOrderSigners_revertsDuplicateOrOutOfOrder() public {
        _setMembersAndAdmins({members: buildArray(admin1, admin2), admins: buildArray(admin1, admin2), threshold: 2});

        uint256 salt = 19;
        uint256 expiration = block.timestamp + 1 hours;
        bytes32 operationHash = _computeOperationHash({
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
            vm.expectRevert(
                abi.encodeWithSelector(IOrganizationAdmin.DuplicateOrOutOfOrderAdminSigner.selector, signer1, signer2)
            );
        } else {
            outOfOrder = abi.encodePacked(sig1, sig2);
            vm.expectRevert(
                abi.encodeWithSelector(IOrganizationAdmin.DuplicateOrOutOfOrderAdminSigner.selector, signer2, signer1)
            );
        }

        AdminAuthParams memory auth =
            AdminAuthParams({salt: salt, expirationTimestamp: expiration, signatures: outOfOrder});
        harness.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            authParams: auth
        });
    }

    /// @dev Valid signature from non-admin signer reverts SignerIsNotAdmin.
    function test_validateAdminAuth_nonAdminSigner_revertsSignerIsNotAdmin() public {
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        uint256 salt = 20;
        uint256 expiration = block.timestamp + 1 hours;
        address nonAdminSigner = vm.addr(0xDEAD);

        bytes32 operationHash = _computeOperationHash({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            salt: salt,
            expirationTimestamp: expiration,
            isApproval: true
        });
        bytes memory sig = _signHash(0xDEAD, operationHash);
        AdminAuthParams memory auth = AdminAuthParams({salt: salt, expirationTimestamp: expiration, signatures: sig});

        vm.expectRevert(abi.encodeWithSelector(IOrganizationAdmin.SignerIsNotAdmin.selector, nonAdminSigner));
        harness.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            authParams: auth
        });
    }

    /// @dev Malformed packed signatures revert SignatureRecoveryFailed.
    function test_validateAdminAuth_malformedPackedSignatures_revertsSignatureRecoveryFailed() public {
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        uint256 salt = 21;
        uint256 expiration = block.timestamp + 1 hours;
        bytes memory malformed = hex"1b";
        AdminAuthParams memory auth =
            AdminAuthParams({salt: salt, expirationTimestamp: expiration, signatures: malformed});

        _expectSignatureRecoveryFailure();
        harness.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            authParams: auth
        });
    }

    /// @dev ERC-1271 wrong magic signer reverts SignatureRecoveryFailed.
    function test_validateAdminAuth_erc1271WrongMagic_revertsSignatureRecoveryFailed() public {
        address contractAdmin = address(wrongMagicSigner1271);
        _setMembersAndAdmins({members: buildArray(contractAdmin), admins: buildArray(contractAdmin), threshold: 1});

        uint256 salt = 22;
        uint256 expiration = block.timestamp + 1 hours;
        bytes memory contractSig = _buildContractSignature({signer: contractAdmin, innerSig: hex"abcd"});
        AdminAuthParams memory auth =
            AdminAuthParams({salt: salt, expirationTimestamp: expiration, signatures: contractSig});

        _expectSignatureRecoveryFailure();
        harness.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            authParams: auth
        });
    }

    /// @dev Reverting ERC-1271 signer reverts SignatureRecoveryFailed.
    function test_validateAdminAuth_erc1271RevertingSigner_revertsSignatureRecoveryFailed() public {
        address contractAdmin = address(revertingSigner1271);
        _setMembersAndAdmins({members: buildArray(contractAdmin), admins: buildArray(contractAdmin), threshold: 1});

        uint256 salt = 23;
        uint256 expiration = block.timestamp + 1 hours;
        bytes memory contractSig = _buildContractSignature({signer: contractAdmin, innerSig: hex"abcd"});
        AdminAuthParams memory auth =
            AdminAuthParams({salt: salt, expirationTimestamp: expiration, signatures: contractSig});

        _expectSignatureRecoveryFailure();
        harness.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            authParams: auth
        });
    }

    /// @dev Mixed EOA + ERC-1271 signatures in ascending order succeed.
    function test_validateAdminAuth_mixedEOAAndERC1271_sorted_succeeds() public {
        address contractAdmin = address(validSigner1271);
        _setMembersAndAdmins({
            members: buildArray(admin1, contractAdmin), admins: buildArray(admin1, contractAdmin), threshold: 2
        });

        uint256 salt = 24;
        uint256 expiration = block.timestamp + 1 hours;
        bytes32 operationHash = _computeOperationHash({
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
        harness.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            authParams: auth
        });
    }

    /// @dev First use of nonce succeeds; second use reverts NonceAlreadyUsed.
    function test_validateAdminAuth_nonceReplay_revertsNonceAlreadyUsed() public {
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

        harness.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            authParams: auth
        });

        uint256 nonce = _computeNonce(OperationType.ModifyAdmins, baseOperationData, salt);
        _expectNonceAlreadyUsed(nonce);
        harness.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            authParams: auth
        });
    }

    /// @dev Same operation with different salts produces different nonces.
    function test_validateAdminAuth_differentSalts_produceDifferentNonces() public view {
        uint256 nonceA = _computeNonce(OperationType.ModifyAdmins, baseOperationData, 111);
        uint256 nonceB = _computeNonce(OperationType.ModifyAdmins, baseOperationData, 222);

        assertTrue(nonceA != nonceB, "nonces must differ for different salts");
    }

    /// @dev Same data+salt with different operationType produces different nonces.
    function test_validateAdminAuth_differentOperationTypes_produceDifferentNonces() public view {
        uint256 salt = 333;
        uint256 nonceA = _computeNonce(OperationType.ModifyAdmins, baseOperationData, salt);
        uint256 nonceB = _computeNonce(OperationType.ModifyMembers, baseOperationData, salt);

        assertTrue(nonceA != nonceB, "nonces must differ across operation types");
    }

    /// @dev Same operation and salt across different organization addresses produces different nonces.
    function test_validateAdminAuth_differentOrganizationAddresses_produceDifferentNonces() public {
        LibOrganizationAdminHarness secondHarness = new LibOrganizationAdminHarness();

        uint256 salt = 444;
        uint256 nonceA = harness.computeNonce(OperationType.ModifyAdmins, baseOperationData, salt);
        uint256 nonceB = secondHarness.computeNonce(OperationType.ModifyAdmins, baseOperationData, salt);

        assertTrue(nonceA != nonceB, "nonce must bind to organization address");
    }

    /// @dev Approval signatures cannot authorize rejection.
    function test_validateAdminAuth_approvalSignatureCannotAuthorizeRejection() public {
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
        vm.expectRevert();
        harness.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: false,
            authParams: approvalAuth
        });

        uint256 nonce = _computeNonce(OperationType.ModifyAdmins, baseOperationData, salt);
        assertFalse(_isNonceUsed(nonce), "nonce should rollback on failed auth");
    }

    /// @dev Rejection signatures cannot authorize approval.
    function test_validateAdminAuth_rejectionSignatureCannotAuthorizeApproval() public {
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

        vm.expectRevert();
        harness.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            authParams: rejectionAuth
        });

        uint256 nonce = _computeNonce(OperationType.ModifyAdmins, baseOperationData, salt);
        assertFalse(_isNonceUsed(nonce), "nonce should rollback on failed auth");
    }

    /// @dev Trailing bytes after threshold is met are ignored (early exit).
    function test_validateAdminAuth_trailingBytesIgnoredAfterThresholdMet() public {
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        uint256 salt = 28;
        uint256 expiration = block.timestamp + 1 hours;
        bytes32 operationHash = _computeOperationHash({
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

        harness.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            authParams: auth
        });
    }

    /// @dev Failed auth after nonce write attempt rolls back nonce usage.
    function test_validateAdminAuth_failedAuth_rollsBackNonceUsage() public {
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        uint256 salt = 29;
        uint256 expiration = block.timestamp + 1 hours;
        bytes memory malformed = hex"1b";
        AdminAuthParams memory auth =
            AdminAuthParams({salt: salt, expirationTimestamp: expiration, signatures: malformed});

        uint256 nonce = _computeNonce(OperationType.ModifyAdmins, baseOperationData, salt);

        _expectSignatureRecoveryFailure();
        harness.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            authParams: auth
        });

        assertFalse(_isNonceUsed(nonce), "nonce must not remain used after revert");
    }

    /// @dev Admin removed after signing but before execution causes SignerIsNotAdmin.
    function test_validateAdminAuth_adminRemovedAfterSigning_revertsSignerIsNotAdmin() public {
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

        vm.expectRevert(abi.encodeWithSelector(IOrganizationAdmin.SignerIsNotAdmin.selector, admin1));
        harness.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            authParams: auth
        });
    }

    /// @dev Threshold raised after signing causes old signature set to fail.
    function test_validateAdminAuth_thresholdRaisedAfterSigning_revertsInsufficientAuthorization() public {
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

        vm.expectRevert(IOrganizationAdmin.InsufficientAdminAuthorization.selector);
        harness.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            authParams: auth
        });
    }

    /// @dev Chain ID changes invalidate old signatures.
    function test_validateAdminAuth_chainIdChange_invalidatesOldSignatures() public {
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

        vm.expectRevert();
        harness.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins,
            operationData: baseOperationData,
            isApproval: true,
            authParams: auth
        });
    }
}
