// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {OwnableUpgradeable} from "@openzeppelin-upgradeable/access/OwnableUpgradeable.sol";

import {AccountImplementation} from "account/AccountImplementation.sol";
import {ImplementationWhitelistProxy} from "implementation-whitelist/ImplementationWhitelistProxy.sol";
import {IImplementationWhitelist} from "interfaces/IImplementationWhitelist.sol";
import {SignatureTestHelpers} from "test/helpers/SignatureTestHelpers.sol";
import {
    ImplementationWhitelistHarness,
    ImplementationWhitelistV2Harness
} from "test/implementation-whitelist/ImplementationWhitelistImplementation/ImplementationWhitelistHarnesses.sol";
import {
    InitializationSuiteBase
} from "test/organization/base/OrganizationInitializationBase/OrganizationInitializationBaseSuiteBase.sol";
import {
    OrganizationImplementationHarness,
    OrganizationImplementationV2Harness,
    OrganizationImplementationV3Harness
} from "test/organization/shared/OrganizationUpgradeHarnesses.sol";
import {AdminAuthParams} from "types/AdminTypes.sol";
import {ContractType, GroupModification, InitializationParams, OperationType} from "types/CommonTypes.sol";

/**
 * @dev Cross-file integration tests for system-wide implementation whitelist enforcement.
 */
contract ImplementationWhitelistControlsCrossFileTest is InitializationSuiteBase, SignatureTestHelpers {
    address internal constant WHITELIST_OWNER = address(0xA11CE);
    address internal constant NEW_WHITELIST_OWNER = address(0xCAFE01);
    uint256 internal constant ADMIN_PK_1 = 0xA11CE;

    OrganizationImplementationHarness internal baseOrganizationImplementation;
    OrganizationImplementationV2Harness internal upgradeOrganizationImplementation;
    OrganizationImplementationV3Harness internal otherOrganizationImplementation;

    AccountImplementation internal baseAccountImplementation;
    AccountImplementation internal upgradeAccountImplementation;
    AccountImplementation internal otherAccountImplementation;

    ImplementationWhitelistHarness internal whitelistImplementation;
    ImplementationWhitelistHarness internal whitelistProxy;
    ImplementationWhitelistV2Harness internal whitelistImplementationV2;

    address internal admin1;
    address internal constant MEMBER_4 = address(0xA104);

    /// @dev Deploys a real whitelist proxy plus real organization/account implementation fixtures for cross-file tests.
    function setUp() public override {
        super.setUp();

        admin1 = vm.addr(ADMIN_PK_1);

        baseOrganizationImplementation = new OrganizationImplementationHarness();
        upgradeOrganizationImplementation = new OrganizationImplementationV2Harness();
        otherOrganizationImplementation = new OrganizationImplementationV3Harness();

        baseAccountImplementation = new AccountImplementation();
        upgradeAccountImplementation = new AccountImplementation();
        otherAccountImplementation = new AccountImplementation();

        whitelistImplementation = new ImplementationWhitelistHarness();
        whitelistImplementationV2 = new ImplementationWhitelistV2Harness();

        bytes memory initData = abi.encodeWithSelector(
            whitelistImplementation.initialize.selector,
            WHITELIST_OWNER,
            _singleAddressArray(address(baseOrganizationImplementation)),
            _singleAddressArray(address(baseAccountImplementation))
        );

        whitelistProxy = ImplementationWhitelistHarness(
            payable(address(new ImplementationWhitelistProxy(address(whitelistImplementation), initData)))
        );
    }

    /// @dev Verifies all three system entrypoints reject unwhitelisted implementations. [IWC-INT-1]
    function test_IWC_INT_1_unwhitelistedTargets_revertAcrossDeployOrganizationUpgradeAndAccountUpgrade() public {
        // Setup: deploy a baseline organization while leaving the candidate org/account upgrade targets unwhitelisted.
        InitializationParams memory params = _buildInitializationParams(address(baseAccountImplementation));
        OrganizationImplementationHarness organization = _deployOrganizationProxy({
            salt: bytes32(uint256(15_100)),
            implementationAddress: address(baseOrganizationImplementation),
            params: params
        });
        AdminAuthParams memory orgUpgradeAuth = _buildUpgradeAuth({
            organization: organization,
            newImplementation: address(upgradeOrganizationImplementation),
            data: bytes(""),
            salt: 15_101
        });
        AdminAuthParams memory accountUpgradeAuth = _buildAccountImplementationAuth({
            organization: organization, newImplementation: address(upgradeAccountImplementation), salt: 15_102
        });

        // Verify: factory deployment rejects an unwhitelisted Organization implementation.
        vm.expectRevert(
            abi.encodeWithSelector(
                IImplementationWhitelist.ImplementationNotWhitelisted.selector,
                address(upgradeOrganizationImplementation)
            )
        );
        // Call: attempt to deploy a new organization from an unwhitelisted Organization implementation target.
        vm.prank(AUTHORIZED_DEPLOYER);
        factory.deployOrganization(
            bytes32(uint256(15_103)), address(upgradeOrganizationImplementation), address(whitelistProxy), params
        );

        // Verify: organization UUPS upgrade rejects an unwhitelisted target and preserves the active implementation.
        vm.expectRevert(
            abi.encodeWithSelector(
                IImplementationWhitelist.ImplementationNotWhitelisted.selector,
                address(upgradeOrganizationImplementation)
            )
        );
        // Call: attempt to upgrade the deployed organization to an unwhitelisted implementation.
        vm.prank(GUARDIAN);
        organization.upgradeToAndCallWithAuthorization(
            address(upgradeOrganizationImplementation), bytes(""), orgUpgradeAuth
        );
        assertEq(
            _readProxyImplementation(address(organization)),
            address(baseOrganizationImplementation),
            "unwhitelisted org upgrade should not change the active implementation"
        );

        // Verify: account implementation upgrade rejects an unwhitelisted Account target and preserves the beacon
        // pointer.
        vm.expectRevert(
            abi.encodeWithSelector(
                IImplementationWhitelist.ImplementationNotWhitelisted.selector, address(upgradeAccountImplementation)
            )
        );
        // Call: attempt to update the organization's shared account implementation to an unwhitelisted target.
        vm.prank(GUARDIAN);
        organization.setAccountImplementation(address(upgradeAccountImplementation), accountUpgradeAuth);
        assertEq(
            organization.getAccountImplementationStorage(),
            address(baseAccountImplementation),
            "unwhitelisted account upgrade should not change the beacon implementation pointer"
        );
    }

    /// @dev Verifies Account and Organization whitelist namespaces stay isolated across all system entrypoints.
    ///      [IWC-INT-2]
    function test_UPG_CTRL_6__IWC_INT_2_accountAndOrganizationNamespaces_remainSeparatedAcrossDeployUpgradeAndAccountFlows()
        public
    {
        // Setup: whitelist the organization candidate under Account only, and the account candidate under
        // Organization only, then deploy a baseline organization.
        _setWhitelistStatus(ContractType.Account, address(upgradeOrganizationImplementation), true);
        _setWhitelistStatus(ContractType.Organization, address(upgradeAccountImplementation), true);

        InitializationParams memory params = _buildInitializationParams(address(baseAccountImplementation));
        OrganizationImplementationHarness organization = _deployOrganizationProxy({
            salt: bytes32(uint256(15_200)),
            implementationAddress: address(baseOrganizationImplementation),
            params: params
        });
        AdminAuthParams memory orgUpgradeAuth = _buildUpgradeAuth({
            organization: organization,
            newImplementation: address(upgradeOrganizationImplementation),
            data: bytes(""),
            salt: 15_201
        });
        AdminAuthParams memory accountUpgradeAuth = _buildAccountImplementationAuth({
            organization: organization, newImplementation: address(upgradeAccountImplementation), salt: 15_202
        });

        // Verify: Account-only whitelist entries never unlock Organization deployment.
        vm.expectRevert(
            abi.encodeWithSelector(
                IImplementationWhitelist.ImplementationNotWhitelisted.selector,
                address(upgradeOrganizationImplementation)
            )
        );
        // Call: attempt to deploy with an Organization target whitelisted only for Account contracts.
        vm.prank(AUTHORIZED_DEPLOYER);
        factory.deployOrganization(
            bytes32(uint256(15_203)), address(upgradeOrganizationImplementation), address(whitelistProxy), params
        );

        // Verify: Account-only whitelist entries never unlock Organization UUPS upgrades.
        vm.expectRevert(
            abi.encodeWithSelector(
                IImplementationWhitelist.ImplementationNotWhitelisted.selector,
                address(upgradeOrganizationImplementation)
            )
        );
        // Call: attempt to upgrade the baseline organization using an Account-only whitelist entry.
        vm.prank(GUARDIAN);
        organization.upgradeToAndCallWithAuthorization(
            address(upgradeOrganizationImplementation), bytes(""), orgUpgradeAuth
        );

        // Verify: Organization-only whitelist entries never unlock Account implementation updates.
        vm.expectRevert(
            abi.encodeWithSelector(
                IImplementationWhitelist.ImplementationNotWhitelisted.selector, address(upgradeAccountImplementation)
            )
        );
        // Call: attempt to point the account beacon at a target whitelisted only for Organization contracts.
        vm.prank(GUARDIAN);
        organization.setAccountImplementation(address(upgradeAccountImplementation), accountUpgradeAuth);
    }

    /// @dev Verifies unwhitelisting active implementations blocks future deployments and upgrades without mutating the
    ///      already-active organization or account implementation pointers. [IWI-CTRL-5]
    function test_IWI_CTRL_5_unwhitelistingActiveImplementations_blocksFutureDeploysAndPreservesPointers() public {
        // Setup: deploy a baseline organization while both active implementations remain whitelisted.
        InitializationParams memory params = _buildInitializationParams(address(baseAccountImplementation));
        OrganizationImplementationHarness organization = _deployOrganizationProxy({
            salt: bytes32(uint256(15_250)),
            implementationAddress: address(baseOrganizationImplementation),
            params: params
        });
        address orgPointerBefore = _readProxyImplementation(address(organization));
        address accountPointerBefore = organization.getAccountImplementationStorage();

        // Setup: unwhitelist the implementations that are already active for the baseline organization.
        _setWhitelistStatus(ContractType.Organization, address(baseOrganizationImplementation), false);
        _setWhitelistStatus(ContractType.Account, address(baseAccountImplementation), false);

        // Verify: new deployments using the now-unwhitelisted active Organization implementation are blocked.
        vm.expectRevert(
            abi.encodeWithSelector(
                IImplementationWhitelist.ImplementationNotWhitelisted.selector,
                address(baseOrganizationImplementation)
            )
        );
        // Call: attempt to deploy a fresh organization against the unwhitelisted active implementation target.
        vm.prank(AUTHORIZED_DEPLOYER);
        factory.deployOrganization(
            bytes32(uint256(15_251)), address(baseOrganizationImplementation), address(whitelistProxy), params
        );

        // Verify: trying to "upgrade" to the same now-unwhitelisted active Organization implementation also fails.
        AdminAuthParams memory orgUpgradeAuth = _buildUpgradeAuth({
            organization: organization,
            newImplementation: address(baseOrganizationImplementation),
            data: bytes(""),
            salt: 15_252
        });
        vm.expectRevert(
            abi.encodeWithSelector(
                IImplementationWhitelist.ImplementationNotWhitelisted.selector,
                address(baseOrganizationImplementation)
            )
        );
        // Call: attempt an organization upgrade targeting the already-active but now-unwhitelisted implementation.
        vm.prank(GUARDIAN);
        organization.upgradeToAndCallWithAuthorization(address(baseOrganizationImplementation), bytes(""), orgUpgradeAuth);

        // Verify: trying to re-set the already-active account implementation also fails once it is unwhitelisted.
        AdminAuthParams memory accountUpgradeAuth = _buildAccountImplementationAuth({
            organization: organization, newImplementation: address(baseAccountImplementation), salt: 15_253
        });
        vm.expectRevert(
            abi.encodeWithSelector(
                IImplementationWhitelist.ImplementationNotWhitelisted.selector, address(baseAccountImplementation)
            )
        );
        // Call: attempt to re-apply the active account implementation after unwhitelisting it.
        vm.prank(GUARDIAN);
        organization.setAccountImplementation(address(baseAccountImplementation), accountUpgradeAuth);

        // Verify: the blocked deploy/upgrade attempts never mutate the active implementation pointers.
        assertEq(_readProxyImplementation(address(organization)), orgPointerBefore, "active org pointer should remain unchanged");
        assertEq(
            organization.getAccountImplementationStorage(),
            accountPointerBefore,
            "active account pointer should remain unchanged"
        );
    }

    /// @dev Verifies whitelist UUPS upgrades preserve state and enforcement in factory, org-upgrade, and
    /// account-upgrade flows. [IWC-INT-5]
    function test_IWC_INT_5_whitelistUpgrade_preservesFactoryOrgAndAccountEnforcement() public {
        // Setup: whitelist alternate org/account implementations, then deploy a baseline organization before the
        // whitelist proxy upgrade.
        _setWhitelistStatus(ContractType.Organization, address(upgradeOrganizationImplementation), true);
        _setWhitelistStatus(ContractType.Account, address(upgradeAccountImplementation), true);

        InitializationParams memory params = _buildInitializationParams(address(baseAccountImplementation));
        OrganizationImplementationHarness organization = _deployOrganizationProxy({
            salt: bytes32(uint256(15_500)),
            implementationAddress: address(baseOrganizationImplementation),
            params: params
        });

        // Call: upgrade the shared whitelist proxy in place to the V2 implementation.
        vm.prank(WHITELIST_OWNER);
        ImplementationWhitelistV2Harness(address(whitelistProxy))
            .upgradeToAndCall(address(whitelistImplementationV2), bytes(""));

        // Verify: whitelist upgrade switched logic while preserving previously allowed implementations.
        assertEq(ImplementationWhitelistV2Harness(address(whitelistProxy)).version(), 2, "whitelist upgrade failed");

        // Call: deploy a new organization with a pre-whitelisted post-upgrade implementation.
        OrganizationImplementationHarness deployedAfterWhitelistUpgrade = _deployOrganizationProxy({
            salt: bytes32(uint256(15_501)),
            implementationAddress: address(upgradeOrganizationImplementation),
            params: params
        });

        // Verify: factory deployment still respects preserved whitelist state after the whitelist upgrade.
        assertTrue(
            deployedAfterWhitelistUpgrade.isInitialized(), "factory deployment should still succeed post-upgrade"
        );

        // Verify: non-whitelisted factory deploy targets still fail after the whitelist upgrade.
        vm.expectRevert(
            abi.encodeWithSelector(
                IImplementationWhitelist.ImplementationNotWhitelisted.selector, address(otherOrganizationImplementation)
            )
        );
        // Call: attempt a factory deployment with an Organization implementation that remained unwhitelisted.
        vm.prank(AUTHORIZED_DEPLOYER);
        factory.deployOrganization(
            bytes32(uint256(15_502)), address(otherOrganizationImplementation), address(whitelistProxy), params
        );

        // Call: execute a whitelisted Organization implementation upgrade after the whitelist upgrade.
        AdminAuthParams memory orgUpgradeAuth = _buildUpgradeAuth({
            organization: organization,
            newImplementation: address(upgradeOrganizationImplementation),
            data: bytes(""),
            salt: 15_503
        });
        vm.prank(GUARDIAN);
        organization.upgradeToAndCallWithAuthorization(
            address(upgradeOrganizationImplementation), bytes(""), orgUpgradeAuth
        );

        // Verify: the organization upgrade path still honors preserved whitelist state post-upgrade.
        assertEq(
            _readProxyImplementation(address(organization)),
            address(upgradeOrganizationImplementation),
            "organization upgrade should keep working after whitelist UUPS upgrade"
        );

        // Verify: non-whitelisted Organization upgrade targets still fail post-upgrade.
        AdminAuthParams memory blockedOrgUpgradeAuth = _buildUpgradeAuth({
            organization: organization,
            newImplementation: address(otherOrganizationImplementation),
            data: bytes(""),
            salt: 15_504
        });
        vm.expectRevert(
            abi.encodeWithSelector(
                IImplementationWhitelist.ImplementationNotWhitelisted.selector, address(otherOrganizationImplementation)
            )
        );
        // Call: attempt to upgrade the organization to an implementation that was never whitelisted.
        vm.prank(GUARDIAN);
        organization.upgradeToAndCallWithAuthorization(
            address(otherOrganizationImplementation), bytes(""), blockedOrgUpgradeAuth
        );

        // Call: execute a whitelisted account implementation update after the whitelist upgrade.
        AdminAuthParams memory accountUpgradeAuth = _buildAccountImplementationAuth({
            organization: organization, newImplementation: address(upgradeAccountImplementation), salt: 15_505
        });
        vm.prank(GUARDIAN);
        organization.setAccountImplementation(address(upgradeAccountImplementation), accountUpgradeAuth);

        // Verify: the account upgrade path still honors preserved whitelist state post-upgrade.
        assertEq(
            organization.getAccountImplementationStorage(),
            address(upgradeAccountImplementation),
            "account implementation update should keep working after whitelist UUPS upgrade"
        );

        // Verify: non-whitelisted account implementation targets still fail post-upgrade.
        AdminAuthParams memory blockedAccountUpgradeAuth = _buildAccountImplementationAuth({
            organization: organization, newImplementation: address(otherAccountImplementation), salt: 15_506
        });
        vm.expectRevert(
            abi.encodeWithSelector(
                IImplementationWhitelist.ImplementationNotWhitelisted.selector, address(otherAccountImplementation)
            )
        );
        // Call: attempt to move the account beacon to an implementation that remained unwhitelisted.
        vm.prank(GUARDIAN);
        organization.setAccountImplementation(address(otherAccountImplementation), blockedAccountUpgradeAuth);
    }

    /// @dev Verifies whitelist ownership transfer immediately changes who can unlock factory, org-upgrade, and
    ///      account-upgrade flows. [IWC-INT-6]
    function test_UPG_CTRL_5__IWC_INT_6_whitelistOwnershipTransfer_changesSystemWideMutationAuthority() public {
        // Setup: deploy a baseline organization, then transfer whitelist ownership to a new owner while leaving the
        // candidate org/account targets unwhitelisted.
        InitializationParams memory params = _buildInitializationParams(address(baseAccountImplementation));
        OrganizationImplementationHarness organization = _deployOrganizationProxy({
            salt: bytes32(uint256(15_600)),
            implementationAddress: address(baseOrganizationImplementation),
            params: params
        });

        vm.prank(WHITELIST_OWNER);
        whitelistProxy.transferOwnership(NEW_WHITELIST_OWNER);
        vm.prank(NEW_WHITELIST_OWNER);
        whitelistProxy.acceptOwnership();

        // Verify: the previous whitelist owner can no longer alter whitelist state.
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, WHITELIST_OWNER));
        // Call: old owner attempts to whitelist a new Organization implementation.
        vm.prank(WHITELIST_OWNER);
        whitelistProxy.whitelistImplementations(
            ContractType.Organization, _singleAddressArray(address(upgradeOrganizationImplementation)), new address[](0)
        );

        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, WHITELIST_OWNER));
        // Call: old owner attempts to whitelist a new Account implementation.
        vm.prank(WHITELIST_OWNER);
        whitelistProxy.whitelistImplementations(
            ContractType.Account, _singleAddressArray(address(upgradeAccountImplementation)), new address[](0)
        );

        // Verify: system entrypoints remain blocked while the new owner has not whitelisted the targets yet.
        vm.expectRevert(
            abi.encodeWithSelector(
                IImplementationWhitelist.ImplementationNotWhitelisted.selector,
                address(upgradeOrganizationImplementation)
            )
        );
        // Call: attempt to deploy an organization using the still-unwhitelisted Organization target.
        vm.prank(AUTHORIZED_DEPLOYER);
        factory.deployOrganization(
            bytes32(uint256(15_601)), address(upgradeOrganizationImplementation), address(whitelistProxy), params
        );

        AdminAuthParams memory blockedOrgUpgradeAuth = _buildUpgradeAuth({
            organization: organization,
            newImplementation: address(upgradeOrganizationImplementation),
            data: bytes(""),
            salt: 15_602
        });
        vm.expectRevert(
            abi.encodeWithSelector(
                IImplementationWhitelist.ImplementationNotWhitelisted.selector,
                address(upgradeOrganizationImplementation)
            )
        );
        // Call: attempt to upgrade the deployed organization before the new owner whitelists the target.
        vm.prank(GUARDIAN);
        organization.upgradeToAndCallWithAuthorization(
            address(upgradeOrganizationImplementation), bytes(""), blockedOrgUpgradeAuth
        );

        AdminAuthParams memory blockedAccountUpgradeAuth = _buildAccountImplementationAuth({
            organization: organization, newImplementation: address(upgradeAccountImplementation), salt: 15_603
        });
        vm.expectRevert(
            abi.encodeWithSelector(
                IImplementationWhitelist.ImplementationNotWhitelisted.selector, address(upgradeAccountImplementation)
            )
        );
        // Call: attempt to update the account beacon before the new owner whitelists the target.
        vm.prank(GUARDIAN);
        organization.setAccountImplementation(address(upgradeAccountImplementation), blockedAccountUpgradeAuth);

        // Call: the new owner whitelists the Organization and Account targets system-wide.
        vm.prank(NEW_WHITELIST_OWNER);
        whitelistProxy.whitelistImplementations(
            ContractType.Organization, _singleAddressArray(address(upgradeOrganizationImplementation)), new address[](0)
        );
        vm.prank(NEW_WHITELIST_OWNER);
        whitelistProxy.whitelistImplementations(
            ContractType.Account, _singleAddressArray(address(upgradeAccountImplementation)), new address[](0)
        );

        // Verify: factory deployment is now unlocked by the new whitelist owner.
        OrganizationImplementationHarness deployedAfterOwnershipTransfer = _deployOrganizationProxy({
            salt: bytes32(uint256(15_604)),
            implementationAddress: address(upgradeOrganizationImplementation),
            params: params
        });
        assertTrue(
            deployedAfterOwnershipTransfer.isInitialized(),
            "new whitelist owner should be able to unlock factory deployments"
        );

        // Verify: organization upgrade is now unlocked by the new whitelist owner.
        AdminAuthParams memory orgUpgradeAuth = _buildUpgradeAuth({
            organization: organization,
            newImplementation: address(upgradeOrganizationImplementation),
            data: bytes(""),
            salt: 15_605
        });
        vm.prank(GUARDIAN);
        organization.upgradeToAndCallWithAuthorization(
            address(upgradeOrganizationImplementation), bytes(""), orgUpgradeAuth
        );
        assertEq(
            _readProxyImplementation(address(organization)),
            address(upgradeOrganizationImplementation),
            "new whitelist owner should be able to unlock organization upgrades"
        );

        // Verify: account implementation updates are now unlocked by the new whitelist owner.
        AdminAuthParams memory accountUpgradeAuth = _buildAccountImplementationAuth({
            organization: organization, newImplementation: address(upgradeAccountImplementation), salt: 15_606
        });
        vm.prank(GUARDIAN);
        organization.setAccountImplementation(address(upgradeAccountImplementation), accountUpgradeAuth);
        assertEq(
            organization.getAccountImplementationStorage(),
            address(upgradeAccountImplementation),
            "new whitelist owner should be able to unlock account implementation updates"
        );
    }

    /// @dev Builds initialization params whose admin signer matches the deterministic EOA test key.
    /// @param accountImplementationAddress Account implementation configured during organization initialization.
    /// @return params Valid initialization params for factory deployment and later admin-auth execution.
    function _buildInitializationParams(address accountImplementationAddress)
        internal
        view
        returns (InitializationParams memory params)
    {
        params.members = buildArray(MEMBER_1, MEMBER_4, admin1);
        params.admins = buildArray(admin1);
        params.votingThreshold = 1;
        params.groups = new GroupModification[](0);
        params.guardian = GUARDIAN;
        params.accountImplementation = accountImplementationAddress;
        params.adminOperationTimelockDurationSeconds = 2 days;
        params.transactionAndERC1271RecoveryAddress = TX_RECOVERY;
        params.txRecoveryTimelockDurationSeconds = 2 days;
        params.guardianRecoveryAddress = GUARDIAN_RECOVERY;
        params.guardianRecoveryTimelockDurationSeconds = 2 days;
    }

    /// @dev Deploys an organization proxy through the real factory using the supplied implementation and whitelist.
    /// @param salt CREATE2 salt used for deterministic organization deployment.
    /// @param implementationAddress Organization implementation used for the proxy deployment.
    /// @param params Initialization payload forwarded into the organization initializer.
    /// @return organization Deployed organization proxy cast to the upgrade harness surface.
    function _deployOrganizationProxy(bytes32 salt, address implementationAddress, InitializationParams memory params)
        internal
        returns (OrganizationImplementationHarness organization)
    {
        vm.prank(AUTHORIZED_DEPLOYER);
        organization = OrganizationImplementationHarness(
            payable(factory.deployOrganization(salt, implementationAddress, address(whitelistProxy), params))
        );
    }

    /// @dev Builds admin auth for an Organization UUPS upgrade operation.
    /// @param organization Organization proxy used to compute the signed operation hash.
    /// @param newImplementation Organization implementation authorized by the signed payload.
    /// @param data Migration calldata hashed into the signed operation payload.
    /// @param salt Nonce salt included in the signed payload.
    /// @return auth Signed admin authorization for `upgradeToAndCallWithAuthorization`.
    function _buildUpgradeAuth(
        OrganizationImplementationHarness organization,
        address newImplementation,
        bytes memory data,
        uint256 salt
    ) internal view returns (AdminAuthParams memory auth) {
        auth = _buildOperationAuth({
            organization: organization,
            operationType: OperationType.Upgrade,
            operationData: abi.encode(newImplementation, keccak256(data)),
            salt: salt
        });
    }

    /// @dev Builds admin auth for an account-implementation update operation.
    /// @param organization Organization proxy used to compute the signed operation hash.
    /// @param newImplementation Account implementation authorized by the signed payload.
    /// @param salt Nonce salt included in the signed payload.
    /// @return auth Signed admin authorization for `setAccountImplementation`.
    function _buildAccountImplementationAuth(
        OrganizationImplementationHarness organization,
        address newImplementation,
        uint256 salt
    ) internal view returns (AdminAuthParams memory auth) {
        auth = _buildOperationAuth({
            organization: organization,
            operationType: OperationType.UpgradeAccount,
            operationData: abi.encode(newImplementation),
            salt: salt
        });
    }

    /// @dev Builds EOA admin authorization for the provided operation tuple.
    /// @param organization Organization proxy used to compute the signed operation hash.
    /// @param operationType Operation domain being authorized.
    /// @param operationData ABI-encoded operation payload bound into the authorization.
    /// @param salt Nonce salt included in the signed payload.
    /// @return auth Signed admin authorization with a one-hour expiration window.
    function _buildOperationAuth(
        OrganizationImplementationHarness organization,
        OperationType operationType,
        bytes memory operationData,
        uint256 salt
    ) internal view returns (AdminAuthParams memory auth) {
        uint256 expirationTimestamp = block.timestamp + 1 hours;
        bytes32 operationHash =
            organization.getAdminOperationHash(operationType, operationData, salt, expirationTimestamp, true);
        bytes memory signatures = _buildSortedEOASignatures(operationHash, buildUint256Array(ADMIN_PK_1));
        auth = AdminAuthParams({salt: salt, expirationTimestamp: expirationTimestamp, signatures: signatures});
    }

    /// @dev Sets whitelist status for one implementation under the current whitelist owner.
    /// @param contractType Whitelist namespace being mutated.
    /// @param implementationAddress Implementation whose status is being changed.
    /// @param isWhitelisted Whether the implementation should end the call whitelisted or unwhitelisted.
    function _setWhitelistStatus(ContractType contractType, address implementationAddress, bool isWhitelisted)
        internal
    {
        vm.prank(whitelistProxy.owner());
        whitelistProxy.whitelistImplementations(
            contractType,
            isWhitelisted ? _singleAddressArray(implementationAddress) : new address[](0),
            isWhitelisted ? new address[](0) : _singleAddressArray(implementationAddress)
        );
    }

    /// @dev Builds a one-element address array.
    /// @param value Address stored at index zero.
    /// @return values One-element address array.
    function _singleAddressArray(address value) internal pure returns (address[] memory values) {
        values = new address[](1);
        values[0] = value;
    }

    /// @dev Sorts signer/signature pairs and concatenates the signatures in canonical signer order.
    /// @param operationHash Operation hash signed by each test admin key.
    /// @param privateKeys Private keys used to produce EOA signatures.
    /// @return signatures Concatenated signatures sorted by signer address.
    function _buildSortedEOASignatures(bytes32 operationHash, uint256[] memory privateKeys)
        internal
        view
        returns (bytes memory signatures)
    {
        address[] memory signers = new address[](privateKeys.length);
        bytes[] memory builtSignatures = new bytes[](privateKeys.length);

        for (uint256 i = 0; i < privateKeys.length; ++i) {
            signers[i] = vm.addr(privateKeys[i]);
            builtSignatures[i] = _signHash(privateKeys[i], operationHash);
        }

        for (uint256 i = 0; i < signers.length; ++i) {
            for (uint256 j = i + 1; j < signers.length; ++j) {
                if (uint160(signers[j]) < uint160(signers[i])) {
                    (signers[i], signers[j]) = (signers[j], signers[i]);
                    (builtSignatures[i], builtSignatures[j]) = (builtSignatures[j], builtSignatures[i]);
                }
            }
        }

        signatures = _concatSignatures(builtSignatures);
    }

    /// @dev Reads the active ERC-1967 implementation pointer from a proxy.
    /// @param proxy Proxy address whose implementation slot should be read.
    /// @return implementationAddress Implementation address stored in the ERC-1967 implementation slot.
    function _readProxyImplementation(address proxy) internal view returns (address implementationAddress) {
        implementationAddress = address(uint160(uint256(vm.load(proxy, ERC1967_IMPLEMENTATION_SLOT))));
    }
}
