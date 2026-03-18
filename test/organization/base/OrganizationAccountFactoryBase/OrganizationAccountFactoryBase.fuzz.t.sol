// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IImplementationWhitelist} from "interfaces/IImplementationWhitelist.sol";
import {IOrganizationAdmin} from "interfaces/organization/IOrganizationAdmin.sol";
import {
    OrganizationAccountFactoryBaseSuiteBase
} from "test/organization/base/OrganizationAccountFactoryBase/OrganizationAccountFactoryBaseSuiteBase.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";
import {OperationType} from "types/CommonTypes.sol";

/**
 * @dev Fuzz tests for `OrganizationAccountFactoryBase`.
 */
contract OrganizationAccountFactoryBaseFuzzTest is OrganizationAccountFactoryBaseSuiteBase {
    /// @dev Verifies `deployAccount` stays guardian-gated and binds admin auth to the exact CREATE2 salt.
    /// @param caller Fuzzed caller used for the unauthorized branch.
    /// @param create2Salt Fuzzed CREATE2 salt authorized for deployment.
    /// @param adminSaltRaw Fuzzed admin-auth salt seed.
    function testFuzz_deployAccount_enforcesGuardianAndExactCreate2Salt(
        address caller,
        bytes32 create2Salt,
        uint256 adminSaltRaw
    ) public {
        // Setup: seed a valid implementation, require one admin signature, and build auth for the exact salt.
        vm.assume(caller != GUARDIAN);
        _setSingleAdminThresholdOne();
        harness.setAccountImplementationStorage(accountImplementationV1);

        uint256 adminSalt = bound(adminSaltRaw, 1, type(uint96).max);
        (AdminAuthParams memory auth, bytes memory operationData) = _buildDeployAccountAuth({
            create2Salt: create2Salt,
            salt: adminSalt,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        bytes32 mutatedCreate2Salt =
            create2Salt == bytes32(type(uint256).max) ? bytes32(0) : bytes32(uint256(create2Salt) + 1);

        // Call: invoke `deployAccount` first from a non-guardian caller, then from the guardian with mismatched
        // operation data, and finally with the exact authorized tuple.
        _expectOnlyGuardianRevert(caller);
        vm.prank(caller);
        harness.deployAccount(create2Salt, auth);

        vm.expectPartialRevert(IOrganizationAdmin.SignerIsNotAdmin.selector);
        vm.prank(GUARDIAN);
        harness.deployAccount(mutatedCreate2Salt, auth);

        vm.prank(GUARDIAN);
        address deployed = harness.deployAccount(create2Salt, auth);

        // Verify: unauthorized and mismatched calls fail closed, while the exact guardian-authorized tuple deploys and
        // consumes its nonce.
        uint256 nonce = _computeDeployAccountNonce(operationData, adminSalt);
        assertEq(deployed, harness.computeAccountAddress(create2Salt), "deployed account should match precompute");
        assertGt(deployed.code.length, 0, "successful guardian path should deploy runtime code");
        assertTrue(harness.getUsedNonce(nonce), "successful deployment should consume the deploy nonce");
    }

    /// @dev Verifies `setAccountImplementation` stays guardian-gated, rejects unwhitelisted targets, and binds admin
    /// auth to the exact implementation address.
    /// @param caller Fuzzed caller used for the unauthorized branch.
    /// @param useFirstImplementation Selects which runtime-code implementation is authorized.
    /// @param adminSaltRaw Fuzzed admin-auth salt seed.
    function testFuzz_setAccountImplementation_enforcesGuardianWhitelistAndExactImplementation(
        address caller,
        bool useFirstImplementation,
        uint256 adminSaltRaw
    ) public {
        // Setup: require one admin signature, whitelist only the intended implementation, and derive two auth salts.
        vm.assume(caller != GUARDIAN);
        _setSingleAdminThresholdOne();

        address approvedImplementation = useFirstImplementation ? accountImplementationV1 : accountImplementationV2;
        address mutatedImplementation = useFirstImplementation ? accountImplementationV2 : accountImplementationV1;
        _setAccountImplementationWhitelisted(approvedImplementation, true);

        uint256 adminSalt = bound(adminSaltRaw, 1, type(uint96).max - 1);
        (AdminAuthParams memory approvedAuth,) = _buildSetAccountImplementationAuth({
            newImplementation: approvedImplementation,
            salt: adminSalt,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        (AdminAuthParams memory unwhitelistedAuth, bytes memory unwhitelistedOperationData) = _buildSetAccountImplementationAuth({
            newImplementation: mutatedImplementation,
            salt: adminSalt + 1,
            expiration: block.timestamp + 1 days,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        // Call: invoke the setter from a non-guardian caller, then with mismatched operation data, then through the
        // correct guardian-authorized path, and finally against an unwhitelisted target.
        _expectOnlyGuardianRevert(caller);
        vm.prank(caller);
        harness.setAccountImplementation(approvedImplementation, approvedAuth);

        vm.expectPartialRevert(IOrganizationAdmin.SignerIsNotAdmin.selector);
        vm.prank(GUARDIAN);
        harness.setAccountImplementation(mutatedImplementation, approvedAuth);

        vm.prank(GUARDIAN);
        harness.setAccountImplementation(approvedImplementation, approvedAuth);

        uint256 unwhitelistedNonce = _computeSetAccountImplementationNonce(unwhitelistedOperationData, adminSalt + 1);

        // Partial revert: outer call succeeds, nonce consumed, unwhitelisted target rejected internally.
        vm.expectEmit(true, true, false, true);
        emit IOrganizationAdmin.AdminOperationExecutionReverted(
            OperationType.UpgradeAccount,
            unwhitelistedNonce,
            abi.encodeWithSelector(
                IImplementationWhitelist.ImplementationNotWhitelisted.selector, mutatedImplementation
            )
        );
        vm.prank(GUARDIAN);
        harness.setAccountImplementation(mutatedImplementation, unwhitelistedAuth);

        // Verify: only the guardian can apply the exact authorized payload, and whitelist enforcement preserves the
        // previously configured implementation pointer.
        assertEq(
            harness.getAccountImplementationStorage(),
            approvedImplementation,
            "only the whitelisted authorized implementation should persist"
        );
    }
}
