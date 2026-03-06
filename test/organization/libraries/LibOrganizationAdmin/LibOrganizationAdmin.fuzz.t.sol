// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationAdmin} from "interfaces/organization/IOrganizationAdmin.sol";
import {
    LibOrganizationAdminSuiteBase
} from "test/organization/libraries/LibOrganizationAdmin/LibOrganizationAdminSuiteBase.sol";
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
    function testFuzz_differentSaltsProduceDifferentNonces(uint256 saltA, uint256 saltB) public view {
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
