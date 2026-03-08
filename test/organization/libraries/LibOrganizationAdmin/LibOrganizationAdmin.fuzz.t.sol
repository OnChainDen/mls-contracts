// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationAdmin} from "interfaces/organization/IOrganizationAdmin.sol";
import {MockERC1271ValidSigner} from "test/helpers/MockERC1271Signers.sol";
import {
    LibOrganizationAdminSuiteBase
} from "test/organization/libraries/LibOrganizationAdmin/LibOrganizationAdminSuiteBase.sol";
import {
    OrganizationImplementationHarness,
    OrganizationImplementationV2Harness
} from "test/organization/shared/OrganizationUpgradeHarnesses.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";
import {OperationType} from "types/CommonTypes.sol";

/**
 * @dev Fuzz tests for cross-file admin behaviors.
 */
contract LibOrganizationAdminFuzzTest is LibOrganizationAdminSuiteBase {
    /**
     * @dev Verifies that successful auth requires at least threshold valid admin signatures.
     */
    function testFuzz_successRequiresAtLeastThresholdSignatures(uint8 rawThreshold, uint8 rawSignatureCount) public {
        // Arrange: derive bounded values and seed a 3-admin setup.
        uint256 threshold = bound(uint256(rawThreshold), 1, 3);
        uint256 signatureCount = bound(uint256(rawSignatureCount), 0, 3);

        // Setup: configure the initial organization state for this scenario.

        _setMembersAndAdmins({
            members: buildArray(admin1, admin2, admin3),
            admins: buildArray(admin1, admin2, admin3),
            threshold: threshold
        });

        bytes memory operationData = abi.encode("fuzz-f1", threshold, signatureCount);
        uint256 salt = 4001;
        uint256 expiration = block.timestamp + 1 hours;
        bytes32 operationHash = harness.getAdminOperationHash({
            operationType: OperationType.ModifyAdmins,
            operationData: operationData,
            salt: salt,
            expirationTimestamp: expiration,
            isApproval: true
        });

        uint256[] memory privateKeys = new uint256[](signatureCount);
        if (signatureCount > 0) privateKeys[0] = ADMIN_PK_1;
        if (signatureCount > 1) privateKeys[1] = ADMIN_PK_2;
        if (signatureCount > 2) privateKeys[2] = ADMIN_PK_3;

        bytes memory signatures = _buildSortedEOASignatures(operationHash, privateKeys);
        AdminAuthParams memory auth =
            AdminAuthParams({salt: salt, expirationTimestamp: expiration, signatures: signatures});

        // Assert: success iff the number of valid signatures reaches threshold.
        if (signatureCount >= threshold) {
            // Call: invoke admin-auth validation and nonce-consumption logic.
            harness.validateAdminAuthAndConsumeNonceOrRevert({
                operationType: OperationType.ModifyAdmins,
                operationData: operationData,
                isApproval: true,
                authParams: auth
            });
        } else {
            // Verify: this scenario should revert with the expected failure mode.
            vm.expectRevert(IOrganizationAdmin.InsufficientAdminAuthorization.selector);
            // Call: invoke admin-auth validation and nonce-consumption logic.
            harness.validateAdminAuthAndConsumeNonceOrRevert({
                operationType: OperationType.ModifyAdmins,
                operationData: operationData,
                isApproval: true,
                authParams: auth
            });
        }
    }

    /**
     * @dev Verifies that invalid threshold updates (`0` or `> finalAdminCount`) always revert.
     */
    function testFuzz_invalidThresholdUpdatesAlwaysRevert(uint256 tooHighThresholdRaw, bool useZeroThreshold) public {
        // Arrange: start from a valid single-admin state.
        // Setup: configure the initial organization state for this scenario.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        uint256 expectFinalAdminCount = harness.adminCount();
        uint256 actualInvalidThreshold =
            useZeroThreshold ? 0 : bound(tooHighThresholdRaw, expectFinalAdminCount + 1, type(uint32).max);

        // Act/Assert: both invalid classes (`0` and `> count`) must revert.
        // Verify: this scenario should revert with the expected failure mode.
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationAdmin.InvalidAdminVotingThreshold.selector, actualInvalidThreshold, expectFinalAdminCount
            )
        );
        // Call: invoke `modifyAdminsViaLibrary` with the prepared inputs.
        harness.modifyAdminsViaLibrary({
            adminsToAdd: buildEmptyAddressArray(),
            adminsToRemove: buildEmptyAddressArray(),
            newVotingThreshold: actualInvalidThreshold
        });
    }

    /**
     * @dev Verifies that different salts for the same payload produce unique nonces.
     */
    function testFuzz_NMFZ_2_differentSaltsProduceDifferentNonces(uint256 saltA, uint256 saltB) public view {
        // Setup: constrain fuzz inputs to valid preconditions for this scenario.
        vm.assume(saltA != saltB);

        // Nonce derivation includes salt, so unequal salts should produce unequal nonces.
        bytes memory operationData = abi.encode("fuzz-f3");

        // Call: compute both nonce variants for the same payload and different salts.
        uint256 nonceA = harness.computeNonce({
            operationType: OperationType.ModifyAdmins, operationData: operationData, salt: saltA
        });
        uint256 nonceB = harness.computeNonce({
            operationType: OperationType.ModifyAdmins, operationData: operationData, salt: saltB
        });

        // Verify: assert the postconditions for this scenario.

        assertTrue(nonceA != nonceB, "nonces must differ for different salts");
    }

    /**
     * @dev Verifies that random `(operationType, operationData, salt)` tuples produce distinct nonces whenever any
     * input differs.
     */
    function testFuzz_NMFZ_1_randomNonceTuplesRemainDistinctWhenInputsDiffer(
        uint8 rawOperationTypeA,
        bytes calldata operationDataA,
        uint256 saltA,
        uint8 rawOperationTypeB,
        bytes calldata operationDataB,
        uint256 saltB
    ) public view {
        // Setup: bound enum inputs to valid operation types and skip the identical-tuple control case.
        OperationType operationTypeA =
            OperationType(bound(uint256(rawOperationTypeA), 0, uint256(OperationType.AccountTransactionRejection)));
        OperationType operationTypeB =
            OperationType(bound(uint256(rawOperationTypeB), 0, uint256(OperationType.AccountTransactionRejection)));
        vm.assume(
            operationTypeA != operationTypeB || keccak256(operationDataA) != keccak256(operationDataB) || saltA != saltB
        );

        // Call: compute both nonce variants for the fuzzed tuples.
        uint256 nonceA = harness.computeNonce({
            operationType: operationTypeA, operationData: operationDataA, salt: saltA
        });
        uint256 nonceB = harness.computeNonce({
            operationType: operationTypeB, operationData: operationDataB, salt: saltB
        });

        // Verify: any difference in the bound nonce tuple should change the nonce output in practice.
        assertTrue(nonceA != nonceB, "distinct nonce tuples should not collide");
    }

    /**
     * @dev Verifies that including a signer who is neither admin nor member causes `SignerIsNotAdmin`.
     */
    function testFuzz_nonAdminNonMemberSignerInclusion_revertsSignerIsNotAdmin(uint256 nonAdminPk) public {
        // Arrange: threshold=2 ensures both signatures are evaluated.
        // Setup: configure the initial organization state for this scenario.
        _setMembersAndAdmins({members: buildArray(admin1, admin2), admins: buildArray(admin1, admin2), threshold: 2});

        nonAdminPk = bound(nonAdminPk, 1, SECP256K1_CURVE_ORDER - 1);
        address nonAdmin = vm.addr(nonAdminPk);
        // Setup: constrain fuzz inputs to valid preconditions for this scenario.
        vm.assume(nonAdmin != admin1 && nonAdmin != admin2);

        bytes memory operationData = abi.encode("fuzz-f4", nonAdmin);
        uint256 salt = 4002;
        uint256 expiration = block.timestamp + 1 hours;
        bytes32 operationHash = harness.getAdminOperationHash({
            operationType: OperationType.ModifyAdmins,
            operationData: operationData,
            salt: salt,
            expirationTimestamp: expiration,
            isApproval: true
        });

        address[] memory signers = buildArray(admin1, nonAdmin);
        bytes[] memory signatures = new bytes[](2);
        signatures[0] = _signHash(ADMIN_PK_1, operationHash);
        signatures[1] = _signHash(nonAdminPk, operationHash);

        AdminAuthParams memory auth = AdminAuthParams({
            salt: salt, expirationTimestamp: expiration, signatures: _sortAndConcatSignatures(signers, signatures)
        });

        // Assert: non-admin signatures are rejected even when cryptographically valid.
        // Verify: this scenario should revert with the expected failure mode.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationAdmin.SignerIsNotAdmin.selector, nonAdmin));
        // Call: invoke admin-auth validation and nonce-consumption logic.
        harness.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins, operationData: operationData, isApproval: true, authParams: auth
        });
    }

    /**
     * @dev Verifies that including a signer who is a member but not an admin causes `SignerIsNotAdmin`.
     */
    function testFuzz_nonAdminMemberSignerInclusion_revertsSignerIsNotAdmin(uint256 memberNonAdminPk) public {
        memberNonAdminPk = bound(memberNonAdminPk, 1, SECP256K1_CURVE_ORDER - 1);
        address memberNonAdmin = vm.addr(memberNonAdminPk);
        // Setup: constrain fuzz inputs to valid preconditions for this scenario.
        vm.assume(memberNonAdmin != admin1 && memberNonAdmin != admin2);

        // Arrange: threshold=2 ensures both signatures are evaluated.
        // Setup: configure the initial organization state for this scenario.
        _setMembersAndAdmins({
            members: buildArray(admin1, admin2, memberNonAdmin), admins: buildArray(admin1, admin2), threshold: 2
        });

        bytes memory operationData = abi.encode("fuzz-f4-member", memberNonAdmin);
        uint256 salt = 4004;
        uint256 expiration = block.timestamp + 1 hours;
        bytes32 operationHash = harness.getAdminOperationHash({
            operationType: OperationType.ModifyAdmins,
            operationData: operationData,
            salt: salt,
            expirationTimestamp: expiration,
            isApproval: true
        });

        address[] memory signers = buildArray(admin1, memberNonAdmin);
        bytes[] memory signatures = new bytes[](2);
        signatures[0] = _signHash(ADMIN_PK_1, operationHash);
        signatures[1] = _signHash(memberNonAdminPk, operationHash);

        AdminAuthParams memory auth = AdminAuthParams({
            salt: salt, expirationTimestamp: expiration, signatures: _sortAndConcatSignatures(signers, signatures)
        });

        // Assert: member-only (non-admin) signatures are rejected.
        // Verify: this scenario should revert with the expected failure mode.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationAdmin.SignerIsNotAdmin.selector, memberNonAdmin));
        // Call: invoke admin-auth validation and nonce-consumption logic.
        harness.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins, operationData: operationData, isApproval: true, authParams: auth
        });
    }

    /**
     * @dev Verifies that any payload mutation after signing invalidates authorization.
     */
    function testFuzz_payloadMutationAfterSigning_invalidatesAuthorization(bytes32 signedSeed, bytes32 mutatedSeed)
        public
    {
        // Setup: constrain fuzz inputs to valid preconditions for this scenario.
        vm.assume(signedSeed != mutatedSeed);
        // Arrange: sign one payload but execute using a different payload.
        // Setup: configure the initial organization state for this scenario.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        bytes memory signedOperationData = abi.encode(signedSeed);
        bytes memory mutatedOperationData = abi.encode(mutatedSeed);

        uint256 salt = 4003;
        uint256 expiration = block.timestamp + 1 hours;

        AdminAuthParams memory signedAuth = _buildAdminAuthParamsForEOA({
            operationType: OperationType.ModifyAdmins,
            operationData: signedOperationData,
            isApproval: true,
            salt: salt,
            expirationTimestamp: expiration,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Verify: this scenario should revert with the expected failure mode.

        vm.expectPartialRevert(IOrganizationAdmin.SignerIsNotAdmin.selector);
        // Call: invoke admin-auth validation and nonce-consumption logic.
        harness.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins,
            operationData: mutatedOperationData,
            isApproval: true,
            authParams: signedAuth
        });

        // Failed authorization should not leave nonce state partially mutated.
        uint256 mutatedNonce = harness.computeNonce({
            operationType: OperationType.ModifyAdmins, operationData: mutatedOperationData, salt: salt
        });
        uint256 signedNonce = harness.computeNonce({
            operationType: OperationType.ModifyAdmins, operationData: signedOperationData, salt: salt
        });
        // Verify: assert the postconditions for this scenario.
        assertFalse(harness.getUsedNonce(mutatedNonce), "failed auth must not leave mutated nonce consumed");
        assertFalse(harness.getUsedNonce(signedNonce), "failed auth must not leave signed nonce consumed");
    }

    /**
     * @dev Verifies that expired or otherwise invalid admin-auth attempts never leave nonce state consumed.
     */
    function testFuzz_NMFZ_4_invalidOrExpiredAdminAuthNeverConsumesNonce(
        bytes32 signedSeed,
        bytes32 executedSeed,
        uint256 salt,
        uint64 offsetSeconds,
        uint8 rawMode
    ) public {
        // Setup: configure a valid single-admin state, then choose one invalid-auth mode to exercise.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        uint8 mode = uint8(rawMode % 4);
        uint256 offset = bound(uint256(offsetSeconds), 1, 10 days);
        bytes memory signedOperationData = abi.encode(signedSeed);
        bytes memory executedOperationData = abi.encode(executedSeed);
        uint256 expiration = mode == 0 ? (block.timestamp > offset ? block.timestamp - offset : uint256(0)) : block.timestamp + offset;

        AdminAuthParams memory auth;
        if (mode == 0) {
            auth = _buildAdminAuthParamsForEOA({
                operationType: OperationType.ModifyAdmins,
                operationData: signedOperationData,
                isApproval: true,
                salt: salt,
                expirationTimestamp: expiration,
                privateKeys: buildUint256Array(ADMIN_PK_1)
            });

            // Verify: expired auth is rejected before nonce state changes.
            vm.expectPartialRevert(IOrganizationAdmin.AdminOperationExpired.selector);
            // Call: validate the expired authorization payload.
            harness.validateAdminAuthAndConsumeNonceOrRevert({
                operationType: OperationType.ModifyAdmins,
                operationData: signedOperationData,
                isApproval: true,
                authParams: auth
            });
        } else if (mode == 1) {
            vm.assume(signedSeed != executedSeed);
            auth = _buildAdminAuthParamsForEOA({
                operationType: OperationType.ModifyAdmins,
                operationData: signedOperationData,
                isApproval: true,
                salt: salt,
                expirationTimestamp: expiration,
                privateKeys: buildUint256Array(ADMIN_PK_1)
            });

            // Verify: mutating operation data after signing invalidates auth without consuming nonce.
            vm.expectPartialRevert(IOrganizationAdmin.SignerIsNotAdmin.selector);
            // Call: validate using the mutated payload.
            harness.validateAdminAuthAndConsumeNonceOrRevert({
                operationType: OperationType.ModifyAdmins,
                operationData: executedOperationData,
                isApproval: true,
                authParams: auth
            });
        } else if (mode == 2) {
            auth = _buildAdminAuthParamsForEOA({
                operationType: OperationType.ModifyMembers,
                operationData: signedOperationData,
                isApproval: true,
                salt: salt,
                expirationTimestamp: expiration,
                privateKeys: buildUint256Array(ADMIN_PK_1)
            });

            // Verify: signatures for the wrong operation type cannot consume the target nonce.
            vm.expectPartialRevert(IOrganizationAdmin.SignerIsNotAdmin.selector);
            // Call: validate using a mismatched operation type.
            harness.validateAdminAuthAndConsumeNonceOrRevert({
                operationType: OperationType.ModifyAdmins,
                operationData: signedOperationData,
                isApproval: true,
                authParams: auth
            });
        } else {
            auth = _buildAdminAuthParamsForEOA({
                operationType: OperationType.ModifyAdmins,
                operationData: signedOperationData,
                isApproval: false,
                salt: salt,
                expirationTimestamp: expiration,
                privateKeys: buildUint256Array(ADMIN_PK_1)
            });

            // Verify: rejection-intent signatures cannot be replayed as approval auth.
            vm.expectPartialRevert(IOrganizationAdmin.SignerIsNotAdmin.selector);
            // Call: validate execution auth using rejection-intent signatures.
            harness.validateAdminAuthAndConsumeNonceOrRevert({
                operationType: OperationType.ModifyAdmins,
                operationData: signedOperationData,
                isApproval: true,
                authParams: auth
            });
        }

        // Verify: none of the failed auth paths should leave signed or executed nonces consumed.
        uint256 signedNonce = harness.computeNonce({
            operationType: OperationType.ModifyAdmins, operationData: signedOperationData, salt: salt
        });
        uint256 executedNonce = harness.computeNonce({
            operationType: OperationType.ModifyAdmins, operationData: executedOperationData, salt: salt
        });
        assertFalse(harness.getUsedNonce(signedNonce), "failed auth must not consume signed nonce");
        assertFalse(harness.getUsedNonce(executedNonce), "failed auth must not consume executed nonce");
    }

    /**
     * @dev Verifies that mixed EOA/ERC-1271 signature streams accept sorted admin signers and reject ordering/admin
     * violations while parsing variable inner-signature lengths.
     */
    function testFuzz_NMFZ_5_mixedEOAAndERC1271Streams_enforceOrderingAndAdminChecks(
        bytes calldata innerSig,
        bool reverseOrder,
        bool useNonAdminContract
    ) public {
        // Setup: choose a contract signer, configure admin membership, and build a mixed signature stream over one
        // operation hash.
        address contractSigner = useNonAdminContract ? address(new MockERC1271ValidSigner()) : address(validSigner1271);
        _setMembersAndAdmins({
            members: buildArray(admin1, admin2, contractSigner),
            admins: useNonAdminContract ? buildArray(admin1, admin2) : buildArray(admin1, contractSigner),
            threshold: 2
        });

        uint256 salt = 4010;
        uint256 expiration = block.timestamp + 1 hours;
        bytes32 operationHash = harness.getAdminOperationHash({
            operationType: OperationType.ModifyAdmins,
            operationData: abi.encode("fuzz-f5", keccak256(innerSig)),
            salt: salt,
            expirationTimestamp: expiration,
            isApproval: true
        });

        address[] memory signers = buildArray(admin1, contractSigner);
        bytes[] memory signatures = new bytes[](2);
        signatures[0] = _signHash(ADMIN_PK_1, operationHash);
        bytes memory contractInnerSig = innerSig.length == 0 ? bytes(hex"01") : bytes(innerSig);
        signatures[1] = _buildContractSignature(contractSigner, contractInnerSig);

        // Sort once, then optionally reverse the packed stream to exercise offset-order enforcement.
        if (uint160(signers[1]) < uint160(signers[0])) {
            (signers[0], signers[1]) = (signers[1], signers[0]);
            (signatures[0], signatures[1]) = (signatures[1], signatures[0]);
        }
        bytes[] memory packedOrder = signatures;
        if (reverseOrder) {
            packedOrder = new bytes[](2);
            packedOrder[0] = signatures[1];
            packedOrder[1] = signatures[0];
        }
        bytes memory packedSignatures = _concatSignatures(packedOrder);
        AdminAuthParams memory auth =
            AdminAuthParams({salt: salt, expirationTimestamp: expiration, signatures: packedSignatures});

        if (reverseOrder) {
            // Verify: descending signer order must be rejected even when individual signatures are valid.
            vm.expectPartialRevert(IOrganizationAdmin.DuplicateOrOutOfOrderAdminSigner.selector);
            // Call: validate the reversed mixed signature stream.
            harness.validateAdminAuthAndConsumeNonceOrRevert({
                operationType: OperationType.ModifyAdmins,
                operationData: abi.encode("fuzz-f5", keccak256(innerSig)),
                isApproval: true,
                authParams: auth
            });
        } else if (useNonAdminContract) {
            // Verify: valid ERC-1271 signatures still fail if the contract signer is not an admin.
            vm.expectRevert(abi.encodeWithSelector(IOrganizationAdmin.SignerIsNotAdmin.selector, contractSigner));
            // Call: validate the mixed stream with a non-admin contract signer.
            harness.validateAdminAuthAndConsumeNonceOrRevert({
                operationType: OperationType.ModifyAdmins,
                operationData: abi.encode("fuzz-f5", keccak256(innerSig)),
                isApproval: true,
                authParams: auth
            });
        } else {
            // Call: validate the sorted mixed stream with both signer classes authorized.
            harness.validateAdminAuthAndConsumeNonceOrRevert({
                operationType: OperationType.ModifyAdmins,
                operationData: abi.encode("fuzz-f5", keccak256(innerSig)),
                isApproval: true,
                authParams: auth
            });
        }
    }

    /**
     * @dev Verifies a nonce consumed successfully by `rejectAdminOperation` cannot be replayed through
     * `upgradeToAndCallWithAuthorization`.
     */
    function testFuzz_NMFZ_3_rejectThenUpgradeReplaySameNonceAlwaysReverts(uint256 saltRaw) public {
        // Setup: deploy a fresh organization harness and bind both approval and rejection auth to the same upgrade
        // tuple.
        uint256 salt = bound(saltRaw, 1, type(uint256).max);
        OrganizationImplementationHarness org = new OrganizationImplementationHarness();
        OrganizationImplementationV2Harness target = new OrganizationImplementationV2Harness();
        org.setGuardian(GUARDIAN);
        org.setMemberStatus(admin1, true);
        org.setAdminStatus(admin1, true);
        org.setAdminCount(1);
        org.setVotingThreshold(1);

        bytes memory operationData = abi.encode(address(target), keccak256(bytes("")));
        uint256 expiration = block.timestamp + 1 hours;
        bytes32 rejectionHash = org.getAdminOperationHash({
            operationType: OperationType.Upgrade,
            operationData: operationData,
            salt: salt,
            expirationTimestamp: expiration,
            isApproval: false
        });
        bytes32 approvalHash = org.getAdminOperationHash({
            operationType: OperationType.Upgrade,
            operationData: operationData,
            salt: salt,
            expirationTimestamp: expiration,
            isApproval: true
        });
        AdminAuthParams memory rejectionAuth = AdminAuthParams({
            salt: salt,
            expirationTimestamp: expiration,
            signatures: _buildSortedEOASignatures(rejectionHash, buildUint256Array(ADMIN_PK_1))
        });
        AdminAuthParams memory approvalAuth = AdminAuthParams({
            salt: salt,
            expirationTimestamp: expiration,
            signatures: _buildSortedEOASignatures(approvalHash, buildUint256Array(ADMIN_PK_1))
        });
        uint256 nonce = org.computeNonce(OperationType.Upgrade, operationData, salt);

        // Call: consume the upgrade nonce through rejection, then replay it through the execution entry point.
        vm.prank(GUARDIAN);
        org.rejectAdminOperation(OperationType.Upgrade, operationData, rejectionAuth);

        // Verify: replay through a different nonce-consuming entry point must still revert on the shared nonce.
        assertTrue(org.getUsedNonce(nonce), "rejection should consume the upgrade nonce");
        _expectNonceAlreadyUsed(nonce);
        vm.prank(GUARDIAN);
        org.upgradeToAndCallWithAuthorization(address(target), bytes(""), approvalAuth);
    }

    /**
     * @dev Verifies unauthorized callers cannot burn nonces on either rejection or upgrade entry points.
     */
    function testFuzz_NMFZ_6_unauthorizedCallerAttemptsNeverBurnNonce(uint256 saltRaw, bool useUpgradePath) public {
        // Setup: deploy a fresh organization harness and build valid auth for the selected nonce-consuming path.
        uint256 salt = bound(saltRaw, 1, type(uint256).max);
        OrganizationImplementationHarness org = new OrganizationImplementationHarness();
        OrganizationImplementationV2Harness target = new OrganizationImplementationV2Harness();
        org.setGuardian(GUARDIAN);
        org.setMemberStatus(admin1, true);
        org.setAdminStatus(admin1, true);
        org.setAdminCount(1);
        org.setVotingThreshold(1);

        bytes memory operationData = abi.encode(address(target), keccak256(bytes("")));
        uint256 expiration = block.timestamp + 1 hours;
        bytes32 operationHash = org.getAdminOperationHash({
            operationType: OperationType.Upgrade,
            operationData: operationData,
            salt: salt,
            expirationTimestamp: expiration,
            isApproval: useUpgradePath
        });
        AdminAuthParams memory auth = AdminAuthParams({
            salt: salt,
            expirationTimestamp: expiration,
            signatures: _buildSortedEOASignatures(operationHash, buildUint256Array(ADMIN_PK_1))
        });
        uint256 nonce = org.computeNonce(OperationType.Upgrade, operationData, salt);

        // Call: attempt the selected entry point from a non-guardian caller.
        _expectOnlyGuardianRevert(NON_GUARDIAN);
        vm.prank(NON_GUARDIAN);
        if (useUpgradePath) {
            org.upgradeToAndCallWithAuthorization(address(target), bytes(""), auth);
        } else {
            org.rejectAdminOperation(OperationType.Upgrade, operationData, auth);
        }

        // Verify: caller-gate failures must not consume the underlying nonce.
        assertFalse(org.getUsedNonce(nonce), "unauthorized caller should not burn nonce");
    }

    /**
     * @dev Verifies that successful mixed add/remove calls preserve admin invariants.
     */
    function testFuzz_successfulMixedAddRemove_keepsAdminInvariants(
        bool addCandidate,
        bool removeAdmin2,
        bool removeAdmin3,
        uint8 thresholdSeed
    ) public {
        // Arrange: start from three admins and one extra member candidate.
        address candidate = address(0xF601);
        // Setup: configure the initial organization state for this scenario.
        _setMembersAndAdmins({
            members: buildArray(admin1, admin2, admin3, candidate),
            admins: buildArray(admin1, admin2, admin3),
            threshold: 2
        });

        uint256 addLength = addCandidate ? 1 : 0;
        uint256 removeLength = (removeAdmin2 ? 1 : 0) + (removeAdmin3 ? 1 : 0);

        address[] memory adminsToAdd = new address[](addLength);
        if (addCandidate) {
            adminsToAdd[0] = candidate;
        }

        address[] memory adminsToRemove = new address[](removeLength);
        uint256 index = 0;
        if (removeAdmin2) {
            adminsToRemove[index] = admin2;
            index++;
        }
        if (removeAdmin3) {
            adminsToRemove[index] = admin3;
        }

        uint256 proposedThreshold = bound(uint256(thresholdSeed), 0, 5);

        // Call: use a low-level invocation so fuzzing explores both success and revert paths.
        (bool success,) = address(harness)
            .call(abi.encodeCall(harness.modifyAdminsViaLibrary, (adminsToAdd, adminsToRemove, proposedThreshold)));

        // Verify: only successful calls must satisfy postconditions.
        if (success) {
            // Assert postconditions required by successful admin mutations.
            uint256 adminCount = harness.adminCount();
            uint256 threshold = harness.votingThreshold();

            // Verify: assert the postconditions for this scenario.

            assertGe(adminCount, 1, "successful calls must never leave zero admins");
            // Verify: assert the postconditions for this scenario.
            assertGe(threshold, 1, "successful calls must keep threshold >= 1");
            // Verify: assert the postconditions for this scenario.
            assertLe(threshold, adminCount, "successful calls must keep threshold <= adminCount");
        }
    }
}
