// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IOrganizationGuardian} from "interfaces/organization/IOrganizationGuardian.sol";
import {
    OrganizationGuardianBaseSuiteBase
} from "test/organization/base/OrganizationGuardianBase/OrganizationGuardianBaseSuiteBase.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";

/**
 * @dev Fuzz tests for `OrganizationGuardianBase`.
 */
contract OrganizationGuardianBaseFuzzTest is OrganizationGuardianBaseSuiteBase {
    /// @dev Verifies guardian entry points enforce `onlyGuardian` and `onlyPendingGuardian` under random caller fuzz.
    /// @param caller The unauthorized caller used against the guardian entry points.
    /// @param saltSeed Entropy used to derive distinct auth salts.
    function testFuzz_FOGUB_ENTRY_119_guardianEntryPoints_enforceOnlyGuardianAndOnlyPendingGuardian(
        address caller,
        uint256 saltSeed
    ) public {
        vm.assume(caller != GUARDIAN);
        vm.assume(caller != NEW_GUARDIAN_A);

        // Setup: configure a valid single-admin signer set so the caller gates are the only failing condition.
        _setMembersAndAdmins(buildArray(admin1), buildArray(admin1), 1);

        // Setup: build valid auth payloads for the guardian entry points.
        (AdminAuthParams memory initiateAuth,) = _buildInitiateGuardianUpdateAuth({
            newGuardian: NEW_GUARDIAN_A,
            salt: uint256(keccak256(abi.encode(saltSeed, "initiate"))),
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call: attempt initiate as a non-guardian caller, expecting the guardian-only gate revert.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationGuardian.UnauthorizedGuardian.selector, caller, GUARDIAN));
        vm.prank(caller);
        harness.initiateGuardianUpdate(NEW_GUARDIAN_A, initiateAuth);

        _initiatePendingGuardianUpdate(NEW_GUARDIAN_A, uint256(keccak256(abi.encode(saltSeed, "seed-pending"))));

        (AdminAuthParams memory finalizeAuth,) = _buildFinalizeGuardianUpdateAuth({
            pendingGuardian: NEW_GUARDIAN_A,
            salt: uint256(keccak256(abi.encode(saltSeed, "finalize"))),
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        (AdminAuthParams memory cancelAuth,) = _buildCancelGuardianUpdateAuth({
            pendingGuardian: NEW_GUARDIAN_A,
            salt: uint256(keccak256(abi.encode(saltSeed, "cancel"))),
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call: attempt finalize and cancel as a non-guardian caller, then attempt accept as a non-pending guardian.
        vm.expectRevert(abi.encodeWithSelector(IOrganizationGuardian.UnauthorizedGuardian.selector, caller, GUARDIAN));
        vm.prank(caller);
        harness.finalizeGuardianUpdate(finalizeAuth);

        vm.expectRevert(abi.encodeWithSelector(IOrganizationGuardian.UnauthorizedGuardian.selector, caller, GUARDIAN));
        vm.prank(caller);
        harness.cancelGuardianUpdate(cancelAuth);

        _expectOnlyPendingGuardianRevert(caller, NEW_GUARDIAN_A);
        vm.prank(caller);
        harness.acceptGuardian();

        // Verify: the unauthorized calls leave the pending guardian state untouched.
        assertEq(harness.getPendingGuardianStorage(), NEW_GUARDIAN_A, "pending guardian should remain unchanged");
        assertEq(
            harness.getPendingGuardianUpdateTimestampStorage(),
            block.timestamp + ADMIN_OPERATION_TIMELOCK,
            "pending finalize timestamp should remain unchanged"
        );
    }
}
