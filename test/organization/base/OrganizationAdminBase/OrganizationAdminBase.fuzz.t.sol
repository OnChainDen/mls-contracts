// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationAdmin} from "interfaces/organization/IOrganizationAdmin.sol";
import {
    OrganizationAdminBaseSuiteBase
} from "test/organization/base/OrganizationAdminBase/OrganizationAdminBaseSuiteBase.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";
import {OperationType} from "types/CommonTypes.sol";

/**
 * @dev Fuzz tests for `OrganizationAdminBase`.
 */
contract OrganizationAdminBaseFuzzTest is OrganizationAdminBaseSuiteBase {
    function _invokeModifyAdminsPath(
        bool useRejectPath,
        bytes memory operationData,
        address[] memory adminsToAdd,
        address[] memory adminsToRemove,
        uint256 newVotingThreshold,
        AdminAuthParams memory auth
    ) internal {
        if (useRejectPath) {
            harness.rejectAdminOperation(OperationType.ModifyAdmins, operationData, auth);
        } else {
            harness.modifyAdmins({
                adminsToAdd: adminsToAdd,
                adminsToRemove: adminsToRemove,
                newVotingThreshold: newVotingThreshold,
                authParams: auth
            });
        }
    }

    function _buildMutatedModifyAdminsPayload(
        uint8 mode,
        address[] memory signedAdds,
        address[] memory signedRemoves,
        uint256 signedThreshold,
        address mutatedAdmin
    )
        internal
        view
        returns (
            address[] memory mutatedAdds,
            address[] memory mutatedRemoves,
            uint256 mutatedThreshold,
            bytes memory mutatedOperationData
        )
    {
        mutatedAdds = signedAdds;
        mutatedRemoves = signedRemoves;
        mutatedThreshold = signedThreshold;

        if (mode == 0) {
            mutatedAdds = buildArray(mutatedAdmin);
        } else if (mode == 1) {
            mutatedRemoves = buildArray(admin1);
        } else {
            mutatedThreshold = 2;
        }

        mutatedOperationData = _encodeOperationDataForModifyAdmins(mutatedAdds, mutatedRemoves, mutatedThreshold);
    }

    /**
     * @dev Verifies `OrganizationAdminBase.modifyAdmins` and `OrganizationAdminBase.rejectAdminOperation` remain
     *      guardian-only entry points.
     * @param useRejectPath Whether to exercise the rejection entry point instead of the execution entry point
     * @param saltRaw Raw salt used to derive a bounded nonce salt
     */
    function testFuzz_FOAB_ADMOP_45_modifyAdminsAndRejectAdminOperationAreGuardianOnly(
        bool useRejectPath,
        uint256 saltRaw
    ) public {
        address candidate = address(0x5101);

        // Setup: configure one valid admin/member signer and build the matching auth payload for the chosen entry
        // point.
        _setMembersAndAdmins({members: buildArray(admin1, candidate), admins: buildArray(admin1), threshold: 1});

        uint256 salt = bound(saltRaw, 1, type(uint256).max);
        uint256 expiration = block.timestamp + 1 hours;
        (AdminAuthParams memory auth, bytes memory operationData) = _buildModifyAdminsAuth({
            adminsToAdd: buildArray(candidate),
            adminsToRemove: buildEmptyAddressArray(),
            newVotingThreshold: 1,
            salt: salt,
            expiration: expiration,
            isApproval: !useRejectPath,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        uint256 nonce =
            harness.computeNonce({operationType: OperationType.ModifyAdmins, operationData: operationData, salt: salt});

        // Call: invoke the selected base entry point from a non-guardian caller.
        _expectOnlyGuardianRevert(NON_GUARDIAN);
        vm.prank(NON_GUARDIAN);
        _invokeModifyAdminsPath(useRejectPath, operationData, buildArray(candidate), buildEmptyAddressArray(), 1, auth);

        // Verify: the caller gate should reject the call before consuming the bound nonce or mutating admin state.
        assertFalse(harness.getUsedNonce(nonce), "guardian gate should leave nonce unused");
        assertFalse(harness.isAdmin(candidate), "guardian gate should block admin mutation");
    }

    /**
     * @dev Verifies `OrganizationAdminBase.modifyAdmins` and `OrganizationAdminBase.rejectAdminOperation` bind
     *      signatures to the exact hashed add/remove/threshold payload.
     * @param mutationSelector Chooses which payload component to mutate after signing
     * @param useRejectPath Whether to exercise the rejection entry point instead of the execution entry point
     * @param saltRaw Raw salt used to derive a bounded nonce salt
     */
    function testFuzz_FOAB_ADMOP_45_modifyAdminsAndRejectAdminOperationBindSignaturesToExactPayload(
        uint8 mutationSelector,
        bool useRejectPath,
        uint256 saltRaw
    ) public {
        address signedAdmin = address(0x5102);
        address mutatedAdmin = address(0x5103);

        // Setup: configure one valid admin signer plus two member candidates and sign one exact modify-admins payload.
        _setMembersAndAdmins({
            members: buildArray(admin1, signedAdmin, mutatedAdmin), admins: buildArray(admin1), threshold: 1
        });

        uint256 salt = bound(saltRaw, 1, type(uint256).max);
        uint256 expiration = block.timestamp + 1 hours;
        address[] memory signedAdds = buildArray(signedAdmin);
        address[] memory signedRemoves = buildEmptyAddressArray();
        uint256 signedThreshold = 1;

        (AdminAuthParams memory auth, bytes memory signedOperationData) = _buildModifyAdminsAuth({
            adminsToAdd: signedAdds,
            adminsToRemove: signedRemoves,
            newVotingThreshold: signedThreshold,
            salt: salt,
            expiration: expiration,
            isApproval: !useRejectPath,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        uint8 mode = uint8(mutationSelector % 3);
        (
            address[] memory mutatedAdds,
            address[] memory mutatedRemoves,
            uint256 mutatedThreshold,
            bytes memory mutatedOperationData
        ) = _buildMutatedModifyAdminsPayload(mode, signedAdds, signedRemoves, signedThreshold, mutatedAdmin);
        uint256 signedNonce = harness.computeNonce({
            operationType: OperationType.ModifyAdmins, operationData: signedOperationData, salt: salt
        });
        uint256 mutatedNonce = harness.computeNonce({
            operationType: OperationType.ModifyAdmins, operationData: mutatedOperationData, salt: salt
        });

        // Call: replay the signed auth against an altered base-contract payload.
        vm.expectPartialRevert(IOrganizationAdmin.SignerIsNotAdmin.selector);
        vm.prank(GUARDIAN);
        _invokeModifyAdminsPath(
            useRejectPath, mutatedOperationData, mutatedAdds, mutatedRemoves, mutatedThreshold, auth
        );

        // Verify: altered payloads should not consume either the replay nonce or the originally signed nonce.
        assertFalse(harness.getUsedNonce(mutatedNonce), "altered payload should not consume its nonce");
        assertFalse(harness.getUsedNonce(signedNonce), "failed replay should preserve the signed nonce");

        // Call: execute the original signed payload through the same entry point.
        vm.prank(GUARDIAN);
        _invokeModifyAdminsPath(useRejectPath, signedOperationData, signedAdds, signedRemoves, signedThreshold, auth);

        // Verify: only the exact signed payload should authorize successfully.
        assertTrue(harness.getUsedNonce(signedNonce), "exact payload should consume the signed nonce");
        if (useRejectPath) {
            assertFalse(harness.isAdmin(signedAdmin), "rejection path should not execute admin mutations");
        } else {
            assertTrue(harness.isAdmin(signedAdmin), "exact execution payload should add the signed admin");
        }
    }
}
