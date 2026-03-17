// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationAdmin} from "interfaces/organization/IOrganizationAdmin.sol";
import {
    OrganizationMembersBaseSuiteBase
} from "test/organization/base/OrganizationMembersBase/OrganizationMembersBaseSuiteBase.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";
import {OperationType} from "types/CommonTypes.sol";

/**
 * @dev Fuzz tests for `OrganizationMembersBase`.
 */
contract OrganizationMembersBaseFuzzTest is OrganizationMembersBaseSuiteBase {
    /**
     * @dev Verifies `OrganizationMembersBase.modifyMembers` remains guardian-only.
     * @param saltRaw Raw salt used to derive a bounded nonce salt
     */
    function testFuzz_modifyMembersIsGuardianOnly(uint256 saltRaw) public {
        address candidate = address(0x5201);

        // Setup: configure one valid admin signer and build the matching member-modification auth payload.
        _setMembersAndAdmins({members: buildArray(admin1), admins: buildArray(admin1), threshold: 1});

        uint256 salt = bound(saltRaw, 1, type(uint256).max);
        uint256 expiration = block.timestamp + 1 hours;
        (AdminAuthParams memory auth, bytes memory operationData) = _buildModifyMembersAuth({
            membersToAdd: buildArray(candidate),
            membersToRemove: buildEmptyAddressArray(),
            salt: salt,
            expiration: expiration,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        uint256 nonce = harness.computeNonce({
            operationType: OperationType.ModifyMembers, operationData: operationData, salt: salt
        });

        // Call: invoke `modifyMembers` from a non-guardian caller.
        _expectOnlyGuardianRevert(NON_GUARDIAN);
        vm.prank(NON_GUARDIAN);
        harness.modifyMembers({
            membersToAdd: buildArray(candidate), membersToRemove: buildEmptyAddressArray(), authParams: auth
        });

        // Verify: the caller gate should reject the call before nonce or membership state changes.
        assertFalse(harness.getUsedNonce(nonce), "guardian gate should leave nonce unused");
        assertFalse(harness.isMember(candidate), "guardian gate should block member mutation");
    }

    /**
     * @dev Verifies `OrganizationMembersBase.modifyMembers` binds signatures to the exact add/remove batch hashes.
     * @param mutationSelector Chooses which member batch component to mutate after signing
     * @param saltRaw Raw salt used to derive a bounded nonce salt
     */
    function testFuzz_modifyMembersBindsSignaturesToExactMemberBatches(uint8 mutationSelector, uint256 saltRaw) public {
        address signedAddA = address(0x5202);
        address signedAddB = address(0x5203);
        address removeA = address(0x5204);
        address removeB = address(0x5205);

        // Setup: configure one valid admin signer, two candidate additions, and two removable members.
        _setMembersAndAdmins({members: buildArray(admin1, removeA, removeB), admins: buildArray(admin1), threshold: 1});

        uint256 salt = bound(saltRaw, 1, type(uint256).max);
        uint256 expiration = block.timestamp + 1 hours;
        address[] memory signedAdds = buildArray(signedAddA, signedAddB);
        address[] memory signedRemoves = buildArray(removeA);

        (AdminAuthParams memory auth, bytes memory signedOperationData) = _buildModifyMembersAuth({
            membersToAdd: signedAdds,
            membersToRemove: signedRemoves,
            salt: salt,
            expiration: expiration,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        uint8 mode = uint8(mutationSelector % 3);
        address[] memory mutatedAdds = signedAdds;
        address[] memory mutatedRemoves = signedRemoves;
        if (mode == 0) {
            mutatedAdds = buildArray(signedAddB, signedAddA);
        } else if (mode == 1) {
            mutatedAdds = buildArray(signedAddA, removeB);
        } else {
            mutatedRemoves = buildArray(removeB);
        }

        bytes memory mutatedOperationData = _encodeOperationDataForModifyMembers(mutatedAdds, mutatedRemoves);
        uint256 signedNonce = harness.computeNonce({
            operationType: OperationType.ModifyMembers, operationData: signedOperationData, salt: salt
        });
        uint256 mutatedNonce = harness.computeNonce({
            operationType: OperationType.ModifyMembers, operationData: mutatedOperationData, salt: salt
        });

        // Call: replay the signed auth against an altered add/remove member batch.
        vm.expectPartialRevert(IOrganizationAdmin.SignerIsNotAdmin.selector);
        vm.prank(GUARDIAN);
        harness.modifyMembers({membersToAdd: mutatedAdds, membersToRemove: mutatedRemoves, authParams: auth});

        // Verify: altered member batches should not consume either nonce domain.
        assertFalse(harness.getUsedNonce(mutatedNonce), "altered member batch should not consume its nonce");
        assertFalse(harness.getUsedNonce(signedNonce), "failed replay should preserve the signed nonce");

        // Call: execute the original signed member batch.
        vm.prank(GUARDIAN);
        harness.modifyMembers({membersToAdd: signedAdds, membersToRemove: signedRemoves, authParams: auth});

        // Verify: only the exact signed batch should authorize and mutate membership state.
        assertTrue(harness.getUsedNonce(signedNonce), "exact member batch should consume the signed nonce");
        assertTrue(harness.isMember(signedAddA), "exact member batch should add the first candidate");
        assertTrue(harness.isMember(signedAddB), "exact member batch should add the second candidate");
        assertFalse(harness.isMember(removeA), "exact member batch should remove the signed removal target");
    }
}
