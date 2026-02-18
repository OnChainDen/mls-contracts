// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationAdmin} from "interfaces/organization/IOrganizationAdmin.sol";
import {LibOrganizationAdminHarness} from "test/organization/harness/LibOrganizationAdminHarness.sol";
import {OrganizationAdminStateHarness} from "test/organization/harness/OrganizationAdminStateHarness.sol";
import {OrganizationAdminTestBase} from "test/organization/helpers/OrganizationAdminTestBase.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";
import {OperationType} from "types/CommonTypes.sol";

/**
 * @dev Fuzz tests for cross-file admin behaviors.
 */
contract OrganizationAdminFuzzTest is OrganizationAdminTestBase {
    /// @dev Concrete harness used by fuzz tests for library-level admin behavior.
    LibOrganizationAdminHarness internal harness;

    /**
     * @dev Deploys the library-focused harness for this suite.
     */
    function _deployHarness() internal override returns (OrganizationAdminStateHarness) {
        harness = new LibOrganizationAdminHarness();
        return OrganizationAdminStateHarness(address(harness));
    }

    /**
     * @dev Successful auth requires at least threshold valid admin signatures.
     */
    function testFuzz_successRequiresAtLeastThresholdSignatures(uint8 rawThreshold, uint8 rawSignatureCount) public {
        // Arrange: derive bounded values and seed a 3-admin setup.
        uint256 threshold = bound(uint256(rawThreshold), 1, 3);
        uint256 signatureCount = bound(uint256(rawSignatureCount), 0, 3);

        _setMembersAndAdmins({
            members: buildArray(admin1, admin2, admin3),
            admins: buildArray(admin1, admin2, admin3),
            threshold: threshold
        });

        bytes memory operationData = abi.encode("fuzz-f1", threshold, signatureCount);
        uint256 salt = 4001;
        uint256 expiration = block.timestamp + 1 hours;
        bytes32 operationHash = _computeOperationHash({
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
            harness.validateAdminAuthAndConsumeNonceOrRevert({
                operationType: OperationType.ModifyAdmins,
                operationData: operationData,
                isApproval: true,
                authParams: auth
            });
        } else {
            vm.expectRevert(IOrganizationAdmin.InsufficientAdminAuthorization.selector);
            harness.validateAdminAuthAndConsumeNonceOrRevert({
                operationType: OperationType.ModifyAdmins,
                operationData: operationData,
                isApproval: true,
                authParams: auth
            });
        }
    }

    /**
     * @dev Invalid threshold updates (`0` or `> finalAdminCount`) always revert.
     */
    function testFuzz_invalidThresholdUpdatesAlwaysRevert(uint256 tooHighThresholdRaw, bool useZeroThreshold) public {
        // Arrange: start from a valid single-admin state.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        uint256 finalAdminCount = harness.adminCount();
        uint256 invalidThreshold =
            useZeroThreshold ? 0 : bound(tooHighThresholdRaw, finalAdminCount + 1, type(uint32).max);

        // Act/Assert: both invalid classes (`0` and `> count`) must revert.
        vm.expectRevert(
            abi.encodeWithSelector(
                IOrganizationAdmin.InvalidAdminVotingThreshold.selector, invalidThreshold, finalAdminCount
            )
        );
        harness.modifyAdminsViaLibrary({
            adminsToAdd: buildEmptyAddressArray(),
            adminsToRemove: buildEmptyAddressArray(),
            newVotingThreshold: invalidThreshold
        });
    }

    /**
     * @dev Different salts for the same payload produce unique nonces.
     */
    function testFuzz_differentSaltsProduceDifferentNonces(uint256 saltA, uint256 saltB) public view {
        vm.assume(saltA != saltB);

        // Nonce derivation includes salt, so unequal salts should produce unequal nonces.
        bytes memory operationData = abi.encode("fuzz-f3");

        uint256 nonceA = _computeNonce(OperationType.ModifyAdmins, operationData, saltA);
        uint256 nonceB = _computeNonce(OperationType.ModifyAdmins, operationData, saltB);

        assertTrue(nonceA != nonceB, "nonces must differ for different salts");
    }

    /**
     * @dev Including a non-admin signer causes strict `SignerIsNotAdmin` revert.
     */
    function testFuzz_nonAdminSignerInclusion_revertsSignerIsNotAdmin(uint256 nonAdminPk) public {
        // Arrange: threshold=2 ensures both signatures are evaluated.
        _setMembersAndAdmins({members: buildArray(admin1, admin2), admins: buildArray(admin1, admin2), threshold: 2});

        nonAdminPk = bound(nonAdminPk, 1, SECP256K1_CURVE_ORDER - 1);
        address nonAdmin = vm.addr(nonAdminPk);
        vm.assume(nonAdmin != admin1 && nonAdmin != admin2);

        bytes memory operationData = abi.encode("fuzz-f4", nonAdmin);
        uint256 salt = 4002;
        uint256 expiration = block.timestamp + 1 hours;
        bytes32 operationHash = _computeOperationHash({
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
        vm.expectRevert(abi.encodeWithSelector(IOrganizationAdmin.SignerIsNotAdmin.selector, nonAdmin));
        harness.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins, operationData: operationData, isApproval: true, authParams: auth
        });
    }

    /**
     * @dev Any payload mutation after signing invalidates authorization.
     */
    function testFuzz_payloadMutationAfterSigning_invalidatesAuthorization(bytes32 signedSeed, bytes32 mutatedSeed)
        public
    {
        vm.assume(signedSeed != mutatedSeed);
        // Arrange: sign one payload but execute using a different payload.
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

        vm.expectRevert();
        harness.validateAdminAuthAndConsumeNonceOrRevert({
            operationType: OperationType.ModifyAdmins,
            operationData: mutatedOperationData,
            isApproval: true,
            authParams: signedAuth
        });

        // Failed authorization should not leave nonce state partially mutated.
        uint256 nonce = _computeNonce(OperationType.ModifyAdmins, mutatedOperationData, salt);
        assertFalse(_isNonceUsed(nonce), "failed auth must not leave nonce consumed");
    }

    /**
     * @dev Successful mixed add/remove calls preserve admin invariants.
     */
    function testFuzz_successfulMixedAddRemove_keepsAdminInvariants(
        bool addCandidate,
        bool removeAdmin2,
        bool removeAdmin3,
        uint8 thresholdSeed
    ) public {
        // Arrange: start from three admins and one extra member candidate.
        address candidate = address(0xF601);
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

        // Use low-level call so fuzzing explores both success and revert paths.
        (bool success,) = address(harness)
            .call(abi.encodeCall(harness.modifyAdminsViaLibrary, (adminsToAdd, adminsToRemove, proposedThreshold)));

        if (success) {
            // Assert postconditions required by successful admin mutations.
            uint256 adminCount = harness.adminCount();
            uint256 threshold = harness.votingThreshold();

            assertGe(adminCount, 1, "successful calls must never leave zero admins");
            assertGe(threshold, 1, "successful calls must keep threshold >= 1");
            assertLe(threshold, adminCount, "successful calls must keep threshold <= adminCount");
        }
    }
}
