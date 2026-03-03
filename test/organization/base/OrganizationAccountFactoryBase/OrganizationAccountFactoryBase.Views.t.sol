// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

import {IOrganization} from "interfaces/IOrganization.sol";
import {
    OrganizationAccountFactoryBaseSuiteBase
} from "test/organization/base/OrganizationAccountFactoryBase/OrganizationAccountFactoryBaseSuiteBase.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";

/**
 * @dev Unit tests for `OrganizationAccountFactoryBase` view behavior.
 */
contract OrganizationAccountFactoryBaseViewsTest is OrganizationAccountFactoryBaseSuiteBase {
    /// @dev Verifies `computeAccountAddress` returns the same value as direct library-wrapper computation.
    function test_OAFB_CAA_1_computeAccountAddress_delegatesToLibraryAndReturnsSameResult() public view {
        bytes32 create2Salt = bytes32(uint256(7017));

        // Setup: choose deterministic CREATE2 salt for both view paths.
        // Call: compute address via base external view and direct library wrapper.
        address viaBase = harness.computeAccountAddress(create2Salt);
        address viaLibrary = harness.computeAccountAddressViaLibraryWrapper(create2Salt);

        // Verify: both code paths should resolve to the same deterministic address.
        assertEq(viaBase, viaLibrary, "base view should mirror library compute result");
    }

    /// @dev Verifies `computeAccountAddress` is callable by arbitrary non-guardian callers.
    function test_OAFB_CAA_2_computeAccountAddress_callableByAnyone() public {
        bytes32 create2Salt = bytes32(uint256(7018));

        // Setup: choose deterministic CREATE2 salt and non-guardian caller fixture.
        vm.prank(NON_GUARDIAN);
        // Call: read computed address from a non-guardian account.
        address computed = harness.computeAccountAddress(create2Salt);

        // Verify: call succeeds and returns deterministic non-zero destination.
        assertTrue(computed != address(0), "computed address should be non-zero");
    }

    /// @dev Verifies compute output remains stable across account implementation upgrades.
    function test_OAFB_CAA_3_computeAccountAddress_sameSalt_stableAcrossImplementationUpgrades() public {
        bytes32 create2Salt = bytes32(uint256(7066));

        // Setup: configure one-admin auth and whitelist both implementation versions.
        _setSingleAdminThresholdOne();
        _setAccountImplementationWhitelisted(accountImplementationV1, true);
        _setAccountImplementationWhitelisted(accountImplementationV2, true);

        (AdminAuthParams memory authV1,) = _buildSetAccountImplementationAuth({
            newImplementation: accountImplementationV1,
            salt: 7166,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        vm.prank(GUARDIAN);
        // Call: apply first implementation update.
        harness.setAccountImplementation(accountImplementationV1, authV1);

        address beforeUpgrade = harness.computeAccountAddress(create2Salt);

        (AdminAuthParams memory authV2,) = _buildSetAccountImplementationAuth({
            newImplementation: accountImplementationV2,
            salt: 7167,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        vm.prank(GUARDIAN);
        // Call: apply second implementation update.
        harness.setAccountImplementation(accountImplementationV2, authV2);

        address afterUpgrade = harness.computeAccountAddress(create2Salt);

        // Verify: CREATE2 account address derivation is independent of implementation version.
        assertEq(beforeUpgrade, afterUpgrade, "computed account address should not change across upgrades");
    }

    /// @dev Verifies `implementation()` returns the current account implementation from storage.
    function test_OAFB_I_1_implementation_returnsCurrentImplementationAddressFromStorage() public {
        // Setup: seed account implementation storage directly.
        harness.setAccountImplementationStorage(accountImplementationV1);

        // Call: read beacon implementation through base view.
        address implementationAddress = harness.implementation();

        // Verify: returned value should match storage.
        assertEq(implementationAddress, accountImplementationV1, "implementation view should mirror storage");
    }

    /// @dev Verifies `implementation()` reverts `AccountImplementationNotSet` when unset.
    function test_OAFB_I_2_implementation_whenUnset_revertsAccountImplementationNotSet() public {
        // Setup: leave account implementation storage as zero.

        // Verify: unset implementation should revert with canonical organization error.
        vm.expectRevert(IOrganization.AccountImplementationNotSet.selector);
        // Call: read beacon implementation before initialization.
        harness.implementation();
    }

    /// @dev Verifies `implementation()` returns updated address after successful set-account-implementation call.
    function test_OAFB_I_3_implementation_afterSetAccountImplementation_returnsUpdatedAddress() public {
        // Setup: configure one-admin auth and whitelist target implementation.
        _setSingleAdminThresholdOne();
        _setAccountImplementationWhitelisted(accountImplementationV2, true);

        (AdminAuthParams memory auth,) = _buildSetAccountImplementationAuth({
            newImplementation: accountImplementationV2,
            salt: 7121,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });

        vm.prank(GUARDIAN);
        // Call: update implementation through base admin-gated path.
        harness.setAccountImplementation(accountImplementationV2, auth);

        // Verify: beacon implementation getter should return updated value.
        assertEq(harness.implementation(), accountImplementationV2, "implementation should update after set call");
    }

    /// @dev Verifies `implementation()` is callable by arbitrary non-guardian callers.
    function test_OAFB_I_4_implementation_callableByAnyone() public {
        // Setup: seed account implementation so view call succeeds.
        harness.setAccountImplementationStorage(accountImplementationV1);

        vm.prank(NON_GUARDIAN);
        // Call: read beacon implementation from non-guardian account.
        address implementationAddress = harness.implementation();

        // Verify: non-guardian callers can read implementation.
        assertEq(implementationAddress, accountImplementationV1, "implementation should be publicly readable");
    }

    /// @dev Verifies successive implementation updates are reflected by `implementation()` getter.
    function test_OAFB_I_5_implementation_afterSuccessiveSetCalls_returnsLatest() public {
        // Setup: configure one-admin baseline and whitelist both implementation versions.
        _setSingleAdminThresholdOne();
        _setAccountImplementationWhitelisted(accountImplementationV1, true);
        _setAccountImplementationWhitelisted(accountImplementationV2, true);

        (AdminAuthParams memory setV1Auth,) = _buildSetAccountImplementationAuth({
            newImplementation: accountImplementationV1,
            salt: 7122,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        vm.prank(GUARDIAN);
        harness.setAccountImplementation(accountImplementationV1, setV1Auth);
        assertEq(harness.implementation(), accountImplementationV1, "getter should return first configured implementation");

        (AdminAuthParams memory setV2Auth,) = _buildSetAccountImplementationAuth({
            newImplementation: accountImplementationV2,
            salt: 7123,
            expiration: block.timestamp + 1 hours,
            isApproval: true,
            privateKeys: buildUint256Array(ADMIN_PK_1)
        });
        vm.prank(GUARDIAN);
        // Call: execute second implementation update.
        harness.setAccountImplementation(accountImplementationV2, setV2Auth);

        // Verify: getter now returns most recently configured implementation.
        assertEq(harness.implementation(), accountImplementationV2, "getter should return latest configured implementation");
    }

    /// @dev Verifies desired behavior that no-code stored implementation addresses are rejected.
    function test_OAFB_I_6_implementation_noCodeStoredImplementation_reverts() public {
        address noCodeImplementation = address(0xCA67);

        // Setup: seed a non-zero implementation address with no runtime code.
        harness.setAccountImplementationStorage(noCodeImplementation);

        // Verify: no-code implementation addresses should fail closed.
        vm.expectRevert(
            abi.encodeWithSelector(ERC1967Utils.ERC1967InvalidImplementation.selector, noCodeImplementation)
        );
        // Call: read beacon implementation with no-code target in storage.
        harness.implementation();
    }
}
