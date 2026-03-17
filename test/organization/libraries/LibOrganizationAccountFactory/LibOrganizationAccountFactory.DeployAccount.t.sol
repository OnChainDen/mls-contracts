// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {Errors} from "@openzeppelin/contracts/utils/Errors.sol";
import {Vm} from "forge-std/Vm.sol";

import {AccountProxy} from "account/AccountProxy.sol";
import {IAccount} from "interfaces/IAccount.sol";
import {IOrganizationAccountFactory} from "interfaces/organization/IOrganizationAccountFactory.sol";
import {
    LibOrganizationAccountFactorySuiteBase
} from "test/organization/libraries/LibOrganizationAccountFactory/LibOrganizationAccountFactorySuiteBase.sol";

/**
 * @dev Unit tests for `LibOrganizationAccountFactory.deployAccount` behavior.
 */
contract LibOrganizationAccountFactoryDeployAccountTest is LibOrganizationAccountFactorySuiteBase {
    /// @dev Verifies deployment uses deterministic CREATE2 address derivation for a fixed salt.
    function test_deployAccount_deterministicCreate2Address_matchesManualDerivation() public {
        bytes32 create2Salt = bytes32(uint256(8023));

        // Setup: set a valid beacon implementation with runtime code.
        harness.setAccountImplementationStorage(accountImplementationV1);

        bytes memory bytecode = harness.getAccountProxyBytecodeViaLibrary();
        address expected = Create2.computeAddress(create2Salt, keccak256(bytecode), address(harness));

        // Call: deploy through library wrapper.
        address deployed = harness.deployAccountViaLibrary(create2Salt);

        // Verify: deployed address matches manual CREATE2 derivation.
        assertEq(deployed, expected, "deployed address should match CREATE2 derivation");
    }

    /// @dev Verifies deployed address matches `computeAccountAddress(create2Salt)`.
    function test_deployAccount_deployedAddress_matchesComputeAccountAddress() public {
        bytes32 create2Salt = bytes32(uint256(8024));

        // Setup: set a valid beacon implementation with runtime code.
        harness.setAccountImplementationStorage(accountImplementationV1);

        address expected = harness.computeAccountAddressViaLibrary(create2Salt);

        // Call: deploy through library wrapper.
        address deployed = harness.deployAccountViaLibrary(create2Salt);

        // Verify: deployment result equals computed address.
        assertEq(deployed, expected, "deployed address should match computeAccountAddress");
    }

    /// @dev Verifies boundary salts deploy to addresses matching `computeAccountAddress`.
    function test_deployAccount_boundarySalts_matchComputedAddresses() public {
        // Setup: set a valid beacon implementation with runtime code.
        harness.setAccountImplementationStorage(accountImplementationV1);

        bytes32 zeroSalt = bytes32(0);
        bytes32 maxSalt = bytes32(type(uint256).max);

        // Call: compute and deploy for both boundary salts.
        address expectedZero = harness.computeAccountAddressViaLibrary(zeroSalt);
        address deployedZero = harness.deployAccountViaLibrary(zeroSalt);

        address expectedMax = harness.computeAccountAddressViaLibrary(maxSalt);
        address deployedMax = harness.deployAccountViaLibrary(maxSalt);

        // Verify: both boundary deployments match computed addresses.
        assertEq(deployedZero, expectedZero, "zero-salt deployment should match computeAccountAddress");
        assertEq(deployedMax, expectedMax, "max-salt deployment should match computeAccountAddress");
    }

    /// @dev Verifies successful deployment marks `deployedAccounts[account] = true`.
    function test_deployAccount_success_setsDeployedAccountsMappingTrue() public {
        bytes32 create2Salt = bytes32(uint256(8025));

        // Setup: set a valid beacon implementation with runtime code.
        harness.setAccountImplementationStorage(accountImplementationV1);

        // Call: deploy account through library wrapper.
        address deployed = harness.deployAccountViaLibrary(create2Salt);

        // Verify: deployment-tracking mapping is set for deployed account.
        assertTrue(harness.isDeployedAccount(deployed), "deployed account should be tracked");
    }

    /// @dev Verifies successful deployment emits `AccountDeployed` with expected parameters.
    function test_deployAccount_success_emitsAccountDeployedWithExpectedParameters() public {
        bytes32 create2Salt = bytes32(uint256(8026));

        // Setup: set a valid beacon implementation and precompute expected address.
        harness.setAccountImplementationStorage(accountImplementationV1);
        address expected = harness.computeAccountAddressViaLibrary(create2Salt);

        // Verify: deployment emits event with `(accountAddress, organizationAddress, salt)`.
        vm.expectEmit(true, true, true, true, address(harness));
        emit IOrganizationAccountFactory.AccountDeployed(expected, address(harness), create2Salt);

        // Call: deploy account through library wrapper.
        harness.deployAccountViaLibrary(create2Salt);
    }

    /// @dev Verifies deploying the same salt twice reverts due CREATE2 collision.
    function test_deployAccount_sameSaltTwice_revertsCreate2Collision() public {
        bytes32 create2Salt = bytes32(uint256(8027));

        // Setup: set valid beacon implementation and perform first successful deployment.
        harness.setAccountImplementationStorage(accountImplementationV1);
        harness.deployAccountViaLibrary(create2Salt);

        // Verify: second deployment with same salt should revert.
        vm.expectRevert(Errors.FailedDeployment.selector);
        // Call: redeploy using identical CREATE2 salt.
        harness.deployAccountViaLibrary(create2Salt);
    }

    /// @dev Verifies deployed proxy is bound to this organization as its beacon.
    function test_deployAccount_deployedProxyBeaconIsOrganization() public {
        bytes32 create2Salt = bytes32(uint256(8028));

        // Setup: set a valid account implementation with `getOrganizationAddress` view.
        harness.setAccountImplementationStorage(accountImplementationV1);

        // Call: deploy account and read organization address through proxy.
        address deployed = harness.deployAccountViaLibrary(create2Salt);
        address organization = IAccount(payable(deployed)).getOrganizationAddress();

        // Verify: account beacon resolves to deploying organization (the harness).
        assertEq(organization, address(harness), "account beacon should be organization address");
    }

    /// @dev Verifies defensive mismatch branch reverts `AccountDeploymentAddressMismatch` under fault injection.
    function test_deployAccount_faultInjectedAddressMismatch_revertsAccountDeploymentAddressMismatch() public {
        bytes32 create2Salt = bytes32(uint256(8029));

        // Setup: set a valid beacon implementation with runtime code.
        harness.setAccountImplementationStorage(accountImplementationV1);

        // Verify: fault-injected mismatch path reverts with library defensive error.
        vm.expectRevert(IOrganizationAccountFactory.AccountDeploymentAddressMismatch.selector);
        // Call: execute fault-injected deploy wrapper with mismatched post-check.
        harness.deployAccountViaInjectedAddressMismatch(create2Salt);
    }

    /// @dev Verifies no-code implementation reverts and leaves mapping/events unchanged on failed deployment.
    function test_deployAccount_noCodeImplementation_revertsAndDoesNotSetMappingOrEmitEvent() public {
        bytes32 create2Salt = bytes32(uint256(8068));
        address noCodeImplementation = address(0xBEEF);

        // Setup: store a non-zero implementation address without runtime code.
        harness.setAccountImplementationStorage(noCodeImplementation);
        address expected = harness.computeAccountAddressViaLibrary(create2Salt);

        vm.recordLogs();

        // Verify: BeaconProxy constructor should reject no-code implementation.
        vm.expectRevert(
            abi.encodeWithSelector(ERC1967Utils.ERC1967InvalidImplementation.selector, noCodeImplementation)
        );
        // Call: attempt deployment via library wrapper.
        harness.deployAccountViaLibrary(create2Salt);

        // Verify: failed deployment should not set mapping and should not emit AccountDeployed.
        assertFalse(harness.isDeployedAccount(expected), "failed deployment must not mark account as deployed");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(_countAccountDeployedEvents(logs), 0, "failed deployment must not emit AccountDeployed");
    }

    /// @dev Verifies zero implementation reverts and leaves mapping/events unchanged on failed deployment.
    function test_deployAccount_zeroImplementation_revertsAndDoesNotSetMappingOrEmitEvent() public {
        bytes32 create2Salt = bytes32(uint256(8081));
        address zeroImplementation = address(0);

        // Setup: ensure account implementation is explicitly zero.
        harness.setAccountImplementationStorage(zeroImplementation);
        address expected = harness.computeAccountAddressViaLibrary(create2Salt);

        vm.recordLogs();

        // Verify: BeaconProxy constructor should reject zero implementation.
        vm.expectRevert(abi.encodeWithSelector(ERC1967Utils.ERC1967InvalidImplementation.selector, zeroImplementation));
        // Call: attempt deployment via library wrapper.
        harness.deployAccountViaLibrary(create2Salt);

        // Verify: failed deployment should not set mapping and should not emit AccountDeployed.
        assertFalse(harness.isDeployedAccount(expected), "failed deployment must not mark account as deployed");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(_countAccountDeployedEvents(logs), 0, "failed deployment must not emit AccountDeployed");
    }

    /// @dev Verifies deployed proxy runtime code matches reference `AccountProxy` runtime code.
    function test_deployAccount_runtimeCode_matchesReferenceAccountProxyRuntimeCode() public {
        bytes32 create2Salt = bytes32(uint256(8079));

        // Setup: set valid beacon implementation and deploy account via library.
        harness.setAccountImplementationStorage(accountImplementationV1);
        address deployed = harness.deployAccountViaLibrary(create2Salt);

        // Call: deploy reference proxy with same beacon/init params.
        address referenceProxy = address(new AccountProxy(address(harness), bytes("")));

        // Verify: runtime bytecode should match reference proxy runtime code.
        assertEq(keccak256(deployed.code), keccak256(referenceProxy.code), "deployed proxy runtime code mismatch");
    }

    /**
     * @dev Counts `AccountDeployed` events in a recorded log array.
     */
    function _countAccountDeployedEvents(Vm.Log[] memory logs) internal pure returns (uint256 count) {
        bytes32 topic = keccak256("AccountDeployed(address,address,bytes32)");
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == topic) {
                ++count;
            }
        }
    }
}
