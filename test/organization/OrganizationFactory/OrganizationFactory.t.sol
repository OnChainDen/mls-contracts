// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {Errors} from "@openzeppelin/contracts/utils/Errors.sol";
import {Vm} from "forge-std/Vm.sol";

import {IImplementationWhitelist} from "interfaces/IImplementationWhitelist.sol";
import {IOrganization} from "interfaces/IOrganization.sol";
import {IOrganizationFactory} from "interfaces/IOrganizationFactory.sol";
import {IOrganizationAdmin} from "interfaces/organization/IOrganizationAdmin.sol";
import {IOrganizationInitialization} from "interfaces/organization/IOrganizationInitialization.sol";
import {OrganizationProxy} from "organization/OrganizationProxy.sol";
import {
    IncompatibleOrganizationImplementation,
    InitializationWhitelistMock,
    OrganizationFactoryHarness,
    OrganizationImplementationHarness
} from "test/organization/OrganizationFactory/OrganizationFactoryHarnesses.sol";
import {
    InitializationSuiteBase
} from "test/organization/base/OrganizationInitializationBase/OrganizationInitializationBaseSuiteBase.sol";
import {ContractType, InitializationParams} from "types/CommonTypes.sol";

/**
 * @dev Factory-level tests for initialization and deployment flows.
 */
contract OrganizationFactoryTest is InitializationSuiteBase {
    /// @dev Verifies `OrganizationFactory.constructor` reverts with `ZeroAddress` when the deployer is zero.
    function test_OF_CTOR_1_constructor_zeroDeployer_revertsZeroAddress() public {
        // Setup: Prepare a zero deployer address for constructor input.
        address zeroDeployer = address(0);

        // Call: Deploy the factory harness with the zero deployer and expect a revert.
        vm.expectRevert(IOrganizationFactory.ZeroAddress.selector);
        new OrganizationFactoryHarness(zeroDeployer);

        // Verify: The constructor guard is enforced by the expected `ZeroAddress` revert.
    }

    /// @dev Verifies `OrganizationFactory.constructor` stores a non-zero deployer in `DEPLOYER_ADDRESS` and keeps it
    /// immutable.
    function test_OF_CTOR_2__OF_CTOR_3_constructor_nonZeroStoresAndRemainsImmutable() public {
        // Setup: Deploy a local factory with a custom deployer and valid initialization params.
        address deployer = address(0xDEAD01);
        OrganizationFactoryHarness localFactory = new OrganizationFactoryHarness(deployer);
        InitializationParams memory params = _defaultInitializationParams();

        // Call: Deploy one organization through the local factory as the configured deployer.
        vm.prank(deployer);
        localFactory.deployOrganization(bytes32(uint256(1)), address(implementation), address(whitelist), params);

        // Verify: The immutable deployer address remains equal to the constructor value.
        assertEq(localFactory.DEPLOYER_ADDRESS(), deployer, "immutable deployer should remain unchanged");
    }

    /// @dev Verifies `OrganizationFactory.deployOrganization` returns the precomputed proxy address, initializes it
    /// atomically, and emits deployment events in order.
    function test_OF_DO_1__OF_DO_2__OF_DO_3__OF_DO_18__OF_DO_19__OF_DO_20__OF_DO_21__CFI_FLOW_1_deployAuthorizedValidParams_succeedsAndMatchesPrecompute()
        public
    {
        // Setup: Build valid initialization params, precompute the CREATE2 address, and start log recording.
        bytes32 salt = bytes32(uint256(1001));
        InitializationParams memory params = _defaultInitializationParams();
        address expected = _computeOrganizationAddress(salt);

        vm.recordLogs();

        // Call: Deploy an organization from the authorized deployer through the factory.
        vm.prank(AUTHORIZED_DEPLOYER);
        address deployed = factory.deployOrganization(salt, address(implementation), address(whitelist), params);

        // Verify: The deployment address, initialized state, runtime code, and event counts/order all match
        // expectations.
        assertEq(deployed, expected, "returned address should match precomputed address");

        IOrganization organization = IOrganization(deployed);
        assertTrue(organization.isInitialized(), "organization should be initialized atomically");
        assertEq(organization.getDeployerAddress(), address(factory), "deployer should be factory address");

        _assertInitializedState(organization, params);
        _assertProxyRuntimeCode(deployed);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(_countTopic(logs, ORG_DEPLOYED_TOPIC), 1, "OrganizationDeployed should emit once");
        assertEq(_countTopic(logs, ORG_INITIALIZED_TOPIC), 1, "OrganizationInitialized should emit once");
        assertTrue(
            _firstTopicIndex(logs, ORG_DEPLOYED_TOPIC) < _firstTopicIndex(logs, ORG_INITIALIZED_TOPIC),
            "OrganizationDeployed should be emitted before OrganizationInitialized"
        );
    }

    /// @dev Verifies `OrganizationFactory.deployOrganization` reverts with `UnauthorizedDeployer` for non-authorized
    /// callers.
    function test_OF_DO_4_deployOrganization_unauthorizedCaller_revertsUnauthorizedDeployer() public {
        // Setup: Prepare valid initialization params for an unauthorized caller attempt.
        InitializationParams memory params = _defaultInitializationParams();

        // Call: Attempt deployment from an unauthorized caller and expect `UnauthorizedDeployer`.
        vm.expectRevert(IOrganizationInitialization.UnauthorizedDeployer.selector);
        vm.prank(UNAUTHORIZED_CALLER);
        factory.deployOrganization(bytes32(uint256(2001)), address(implementation), address(whitelist), params);

        // Verify: Access control is enforced by the expected revert.
    }

    /// @dev Verifies `OrganizationFactory.deployOrganization` reverts when the organization implementation is not
    /// whitelisted.
    function test_OF_DO_5_deployOrganization_nonWhitelistedImplementation_revertsImplementationNotWhitelisted() public {
        // Setup: Mark the organization implementation as not whitelisted and keep valid init params.
        InitializationParams memory params = _defaultInitializationParams();
        whitelist.setImplementationWhitelisted(ContractType.Organization, address(implementation), false);

        // Call: Attempt deployment from the authorized deployer and expect `ImplementationNotWhitelisted`.
        vm.expectRevert(
            abi.encodeWithSelector(
                IImplementationWhitelist.ImplementationNotWhitelisted.selector, address(implementation)
            )
        );
        vm.prank(AUTHORIZED_DEPLOYER);
        factory.deployOrganization(bytes32(uint256(2002)), address(implementation), address(whitelist), params);

        // Verify: Whitelist enforcement is confirmed by the expected revert.
    }

    /// @dev Verifies `OrganizationFactory.deployOrganization` validates whitelist inputs using
    /// `ContractType.Organization` and the exact implementation address.
    function test_OF_DO_6__OF_DO_7_deployOrganization_whitelistValidation_usesOrganizationTypeAndExactImplementation()
        public
    {
        // Setup: Configure the whitelist mock to expect one exact validation tuple and then reject it.
        bytes32 salt = bytes32(uint256(2003));
        InitializationParams memory params = _defaultInitializationParams();

        whitelist.setImplementationWhitelisted(ContractType.Organization, address(implementation), false);
        whitelist.setExpectedValidationInput(ContractType.Organization, address(implementation), true);

        // Call: Attempt deployment and expect the whitelist-not-whitelisted revert for the exact tuple.
        vm.expectRevert(
            abi.encodeWithSelector(
                IImplementationWhitelist.ImplementationNotWhitelisted.selector, address(implementation)
            )
        );
        vm.prank(AUTHORIZED_DEPLOYER);
        factory.deployOrganization(salt, address(implementation), address(whitelist), params);

        // Verify: Reaching the expected revert confirms the factory passed the intended whitelist validation inputs.
    }

    /// @dev Verifies `OrganizationFactory.deployOrganization` rejects `implementationAddress == address(0)`.
    function test_OF_DO_8_deployOrganization_zeroImplementation_reverts() public {
        // Setup: Prepare deployment inputs with a zero implementation while keeping whitelist checks enabled.
        bytes32 salt = bytes32(uint256(2004));
        InitializationParams memory params = _defaultInitializationParams();

        whitelist.setImplementationWhitelisted(ContractType.Organization, address(0), true);

        // Call: Attempt deployment with zero implementation and expect `ERC1967InvalidImplementation`.
        vm.expectRevert(abi.encodeWithSelector(ERC1967Utils.ERC1967InvalidImplementation.selector, address(0)));
        vm.prank(AUTHORIZED_DEPLOYER);
        factory.deployOrganization(salt, address(0), address(whitelist), params);

        // Verify: Invalid implementation inputs are rejected by the expected revert.
    }

    /// @dev Verifies `OrganizationFactory.deployOrganization` rejects an EOA implementation address.
    function test_OF_DO_9_deployOrganization_eoaImplementation_revertsInvalidImplementation() public {
        // Setup: Use an EOA as the implementation address and whitelist it to isolate proxy safety validation.
        bytes32 salt = bytes32(uint256(2005));
        InitializationParams memory params = _defaultInitializationParams();
        address eoaImplementation = address(0xE091);

        whitelist.setImplementationWhitelisted(ContractType.Organization, eoaImplementation, true);

        // Call: Attempt deployment and expect `ERC1967InvalidImplementation` for the EOA address.
        vm.expectRevert(abi.encodeWithSelector(ERC1967Utils.ERC1967InvalidImplementation.selector, eoaImplementation));
        vm.prank(AUTHORIZED_DEPLOYER);
        factory.deployOrganization(salt, eoaImplementation, address(whitelist), params);

        // Verify: Non-contract implementation addresses are rejected by the expected revert.
    }

    /// @dev Verifies `OrganizationFactory.deployOrganization` rejects `whitelistAddress == address(0)`.
    function test_OF_DO_10_deployOrganization_zeroWhitelist_reverts() public {
        // Setup: Prepare valid deployment inputs except for a zero whitelist address.
        bytes32 salt = bytes32(uint256(2006));
        InitializationParams memory params = _defaultInitializationParams();

        // Call: Attempt deployment with zero whitelist and expect a bare EVM revert (Solidity extcodesize check
        // fails when calling a function on address(0) which has no code).
        vm.expectRevert(bytes(""));
        vm.prank(AUTHORIZED_DEPLOYER);
        factory.deployOrganization(salt, address(implementation), address(0), params);

        // Verify: Zero whitelist input is rejected by the deployment path.
    }

    /// @dev Verifies `OrganizationFactory.deployOrganization` rejects an EOA whitelist address as a safety requirement.
    function test_OF_DO_11_deployOrganization_eoaWhitelist_revertsDesiredBehavior() public {
        // Setup: Prepare valid deployment params with an EOA used as whitelist address.
        bytes32 salt = bytes32(uint256(2007));
        InitializationParams memory params = _defaultInitializationParams();
        address eoaWhitelist = address(0xEE01);

        // Call: Attempt deployment against the EOA whitelist and expect a bare EVM revert (Solidity extcodesize
        // check fails when calling a function on an EOA which has no code).
        vm.expectRevert(bytes(""));
        vm.prank(AUTHORIZED_DEPLOYER);
        factory.deployOrganization(salt, address(implementation), eoaWhitelist, params);

        // Verify: The revert captures the requirement that whitelist must be a valid contract endpoint.
    }

    /// @dev Verifies `OrganizationFactory.deployOrganization` reverts on a second deployment of the same CREATE2 tuple.
    function test_OF_DO_12_deployOrganization_sameTupleTwice_secondDeployRevertsCreate2Collision() public {
        // Setup: Deploy once with a fixed tuple to consume the CREATE2 address.
        bytes32 salt = bytes32(uint256(2008));
        InitializationParams memory params = _defaultInitializationParams();

        vm.prank(AUTHORIZED_DEPLOYER);
        factory.deployOrganization(salt, address(implementation), address(whitelist), params);

        // Call: Re-deploy the same tuple and expect CREATE2 deployment failure.
        vm.expectRevert(Errors.FailedDeployment.selector);
        vm.prank(AUTHORIZED_DEPLOYER);
        factory.deployOrganization(salt, address(implementation), address(whitelist), params);

        // Verify: CREATE2 collision protection is enforced by the expected failed deployment revert.
    }

    /// @dev Verifies `OrganizationFactory.deployOrganization` derives different addresses for the same salt when
    /// implementation changes.
    function test_OF_DO_13_deployOrganization_sameSaltDifferentImplementation_producesDifferentAddresses() public {
        // Setup: Prepare a second valid organization implementation and whitelist it.
        bytes32 salt = bytes32(uint256(2009));
        InitializationParams memory params = _defaultInitializationParams();

        OrganizationImplementationHarness implementationV2 = new OrganizationImplementationHarness();
        whitelist.setImplementationWhitelisted(ContractType.Organization, address(implementationV2), true);

        vm.prank(AUTHORIZED_DEPLOYER);
        address deployedA = factory.deployOrganization(salt, address(implementation), address(whitelist), params);

        // Call: Deploy twice with the same salt and whitelist but different implementations.
        vm.prank(AUTHORIZED_DEPLOYER);
        address deployedB = factory.deployOrganization(salt, address(implementationV2), address(whitelist), params);

        // Verify: Both deployments succeed and resolve to distinct CREATE2 addresses.
        assertTrue(deployedA != deployedB, "different implementation should produce different CREATE2 address");
        assertGt(deployedA.code.length, 0, "first deployment should have code");
        assertGt(deployedB.code.length, 0, "second deployment should have code");
    }

    /// @dev Verifies `OrganizationFactory.deployOrganization` derives different addresses for the same salt when
    /// whitelist changes.
    function test_OF_DO_14_deployOrganization_sameSaltDifferentWhitelist_producesDifferentAddresses() public {
        // Setup: Prepare a second whitelist contract that approves the same implementation tuple.
        bytes32 salt = bytes32(uint256(2010));
        InitializationParams memory params = _defaultInitializationParams();

        InitializationWhitelistMock whitelistV2 = new InitializationWhitelistMock();
        whitelistV2.setImplementationWhitelisted(ContractType.Organization, address(implementation), true);
        whitelistV2.setImplementationWhitelisted(ContractType.Account, address(accountImplementation), true);

        vm.prank(AUTHORIZED_DEPLOYER);
        address deployedA = factory.deployOrganization(salt, address(implementation), address(whitelist), params);

        // Call: Deploy twice with the same salt and implementation but different whitelist contracts.
        vm.prank(AUTHORIZED_DEPLOYER);
        address deployedB = factory.deployOrganization(salt, address(implementation), address(whitelistV2), params);

        // Verify: Both deployments succeed and produce distinct CREATE2 addresses.
        assertTrue(deployedA != deployedB, "different whitelist should produce different CREATE2 address");
        assertGt(deployedA.code.length, 0, "first deployment should have code");
        assertGt(deployedB.code.length, 0, "second deployment should have code");
    }

    /// @dev Verifies `OrganizationFactory.deployOrganization` rolls back atomically when initialization parameters are
    /// invalid.
    function test_OF_DO_15__CFI_FLOW_2_deployOrganization_invalidInitParams_revertAndLeaveNoCode() public {
        // Setup: Build three invalid initialization variants and precompute each target deployment address.
        InitializationParams memory noMembers = _defaultInitializationParams();
        noMembers.members = buildEmptyAddressArray();

        InitializationParams memory noAdmins = _defaultInitializationParams();
        noAdmins.admins = buildEmptyAddressArray();

        InitializationParams memory invalidThreshold = _defaultInitializationParams();
        invalidThreshold.votingThreshold = 3;

        bytes32 saltA = bytes32(uint256(2011));
        bytes32 saltB = bytes32(uint256(2012));
        bytes32 saltC = bytes32(uint256(2013));

        address computedA = factory.computeOrganizationAddress(saltA, address(implementation), address(whitelist));
        address computedB = factory.computeOrganizationAddress(saltB, address(implementation), address(whitelist));
        address computedC = factory.computeOrganizationAddress(saltC, address(implementation), address(whitelist));

        // Call: Attempt deployment for each invalid variant and expect the row-specific revert.
        vm.expectRevert(IOrganizationInitialization.NoMembersProvided.selector);
        vm.prank(AUTHORIZED_DEPLOYER);
        factory.deployOrganization(saltA, address(implementation), address(whitelist), noMembers);

        vm.expectRevert(IOrganizationAdmin.InvalidAdminConfig.selector);
        vm.prank(AUTHORIZED_DEPLOYER);
        factory.deployOrganization(saltB, address(implementation), address(whitelist), noAdmins);

        vm.expectRevert(abi.encodeWithSelector(IOrganizationAdmin.InvalidAdminVotingThreshold.selector, 3, 2));
        vm.prank(AUTHORIZED_DEPLOYER);
        factory.deployOrganization(saltC, address(implementation), address(whitelist), invalidThreshold);

        // Verify: Every failed deployment leaves zero runtime code at its computed CREATE2 address.
        assertEq(computedA.code.length, 0, "no-members revert should leave no deployed code");
        assertEq(computedB.code.length, 0, "no-admins revert should leave no deployed code");
        assertEq(computedC.code.length, 0, "invalid-threshold revert should leave no deployed code");
    }

    /// @dev Verifies `OrganizationFactory.deployOrganization` does not persist deployment effects when initialization
    /// reverts.
    function test_OF_DO_16_deployOrganization_revertedInitialization_doesNotPersistOrganizationDeployedEvent() public {
        // Setup: Prepare invalid initialization input and precompute the deployment address.
        bytes32 salt = bytes32(uint256(2014));
        InitializationParams memory params = _defaultInitializationParams();
        params.members = buildEmptyAddressArray();
        address computed = _computeOrganizationAddress(salt);

        // Call: Attempt deployment with invalid params and expect `NoMembersProvided`.
        vm.expectRevert(IOrganizationInitialization.NoMembersProvided.selector);
        vm.prank(AUTHORIZED_DEPLOYER);
        factory.deployOrganization(salt, address(implementation), address(whitelist), params);

        // Verify: Reverted deployment leaves no code at the target address, proving no persisted deployment effect.
        assertEq(computed.code.length, 0, "reverted deploy should not persist deployed code");
    }

    /// @dev Verifies `OrganizationFactory.deployOrganization` allows retrying the same tuple after a failed
    /// initialization attempt.
    function test_OF_DO_17__CFI_FLOW_3_deployOrganization_failedThenRetryWithSameTuple_succeeds() public {
        // Setup: Prepare invalid and valid initialization params for the same deployment tuple.
        bytes32 salt = bytes32(uint256(2015));
        InitializationParams memory invalidParams = _defaultInitializationParams();
        invalidParams.members = buildEmptyAddressArray();

        InitializationParams memory validParams = _defaultInitializationParams();

        // Call: Fail once with invalid params, then retry the same tuple with valid params.
        vm.expectRevert(IOrganizationInitialization.NoMembersProvided.selector);
        vm.prank(AUTHORIZED_DEPLOYER);
        factory.deployOrganization(salt, address(implementation), address(whitelist), invalidParams);

        vm.prank(AUTHORIZED_DEPLOYER);
        address deployed = factory.deployOrganization(salt, address(implementation), address(whitelist), validParams);

        // Verify: The retry succeeds at the deterministic precomputed address and initializes the organization.
        assertEq(
            deployed, _computeOrganizationAddress(salt), "retry should deploy at deterministic precomputed address"
        );
        assertTrue(IOrganization(deployed).isInitialized(), "retry deployment should initialize organization");
    }

    /// @dev Verifies `OrganizationFactory.deployOrganization` reverts atomically for a whitelisted implementation with
    /// incompatible `initialize` behavior.
    function test_OF_DO_22_deployOrganization_incompatibleWhitelistedImplementation_revertsAtomically() public {
        // Setup: Deploy an incompatible implementation, whitelist it, and precompute its CREATE2 address.
        bytes32 salt = bytes32(uint256(2016));
        InitializationParams memory params = _defaultInitializationParams();

        IncompatibleOrganizationImplementation badImplementation = new IncompatibleOrganizationImplementation();
        whitelist.setImplementationWhitelisted(ContractType.Organization, address(badImplementation), true);

        address expected = factory.computeOrganizationAddress(salt, address(badImplementation), address(whitelist));

        // Call: Attempt deployment with the incompatible implementation and expect a bare EVM revert
        // (delegatecall to an implementation without `initialize` function or fallback).
        vm.expectRevert(bytes(""));
        vm.prank(AUTHORIZED_DEPLOYER);
        factory.deployOrganization(salt, address(badImplementation), address(whitelist), params);

        // Verify: Atomic rollback leaves no code at the computed address.
        assertEq(expected.code.length, 0, "failed incompatible deployment must leave no code");
    }

    /// @dev Verifies `OrganizationFactory.computeOrganizationAddress` is deterministic and independent of caller
    /// context.
    function test_OF_COA_1__OF_COA_6_computeOrganizationAddress_deterministicAndCallerIndependent() public {
        // Setup: Select a fixed tuple for repeated address computation.
        bytes32 salt = bytes32(uint256(3001));

        // Call: Compute the organization address from two different callers with identical inputs.
        vm.prank(AUTHORIZED_DEPLOYER);
        address computedA = factory.computeOrganizationAddress(salt, address(implementation), address(whitelist));

        vm.prank(UNAUTHORIZED_CALLER);
        address computedB = factory.computeOrganizationAddress(salt, address(implementation), address(whitelist));

        // Verify: Identical inputs produce the same deterministic CREATE2 address.
        assertEq(computedA, computedB, "same inputs should return deterministic address");
    }

    /// @dev Verifies `OrganizationFactory.computeOrganizationAddress` changes when salt, implementation, whitelist, or
    /// factory address changes.
    function test_OF_COA_2__OF_COA_3__OF_COA_4__OF_COA_5_computeOrganizationAddress_changesAcrossTupleDimensions()
        public
    {
        // Setup: Build alternate salt, implementation, whitelist, and factory inputs for tuple dimension checks.
        bytes32 saltA = bytes32(uint256(3002));
        bytes32 saltB = bytes32(uint256(3003));

        OrganizationImplementationHarness implementationV2 = new OrganizationImplementationHarness();
        whitelist.setImplementationWhitelisted(ContractType.Organization, address(implementationV2), true);

        InitializationWhitelistMock whitelistV2 = new InitializationWhitelistMock();
        whitelistV2.setImplementationWhitelisted(ContractType.Organization, address(implementation), true);

        OrganizationFactoryHarness factoryV2 = new OrganizationFactoryHarness(AUTHORIZED_DEPLOYER);

        // Call: Compute addresses across the base tuple and each modified tuple dimension.
        address base = factory.computeOrganizationAddress(saltA, address(implementation), address(whitelist));
        address differentSalt = factory.computeOrganizationAddress(saltB, address(implementation), address(whitelist));
        address differentImpl = factory.computeOrganizationAddress(saltA, address(implementationV2), address(whitelist));
        address differentWhitelist =
            factory.computeOrganizationAddress(saltA, address(implementation), address(whitelistV2));
        address differentFactory =
            factoryV2.computeOrganizationAddress(saltA, address(implementation), address(whitelist));

        // Verify: Each tuple variation produces a distinct computed address.
        assertTrue(base != differentSalt, "different salt should produce different computed address");
        assertTrue(base != differentImpl, "different implementation should produce different computed address");
        assertTrue(base != differentWhitelist, "different whitelist should produce different computed address");
        assertTrue(base != differentFactory, "different factory address should produce different computed address");
    }

    /// @dev Verifies `OrganizationFactory.computeOrganizationAddress` matches manual CREATE2 derivation and remains
    /// stable before and after deployment.
    function test_OF_COA_7__OF_COA_8__OF_COA_9_computeOrganizationAddress_matchesManualFormulaAndDeployment() public {
        // Setup: Build proxy init code hash and manual CREATE2 expectation for a fixed deployment tuple.
        bytes32 salt = bytes32(uint256(3004));
        InitializationParams memory params = _defaultInitializationParams();

        bytes memory bytecode = factory.getOrganizationProxyBytecode(address(implementation), address(whitelist));
        bytes32 initCodeHash = keccak256(bytecode);

        address manual =
            address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(factory), salt, initCodeHash)))));

        address computedBefore = factory.computeOrganizationAddress(salt, address(implementation), address(whitelist));

        // Call: Deploy once and recompute the address after deployment.
        vm.prank(AUTHORIZED_DEPLOYER);
        address deployed = factory.deployOrganization(salt, address(implementation), address(whitelist), params);

        address computedAfter = factory.computeOrganizationAddress(salt, address(implementation), address(whitelist));

        // Verify: Manual formula, precompute, deployed address, and post-deploy compute value are all equal.
        assertEq(computedBefore, manual, "compute should match manual CREATE2 formula");
        assertEq(deployed, computedBefore, "deployed address should match precomputed address");
        assertEq(computedAfter, computedBefore, "compute should remain unchanged after deployment");
    }

    /// @dev Verifies `OrganizationFactory.getOrganizationProxyBytecode` returns deterministic constructor-encoded
    /// bytecode and stable init-code hashes.
    function test_OF_GOPB_1__OF_GOPB_2__OF_GOPB_3__OF_GOPB_4__OF_GOPB_5_getOrganizationProxyBytecode_matchesExpectedEncodingAndHashBehavior()
        public
    {
        // Setup: Prepare baseline and variant implementation/whitelist addresses for bytecode comparisons.
        address implA = address(implementation);
        address implB = address(new OrganizationImplementationHarness());
        address whitelistA = address(whitelist);
        address whitelistB = address(new InitializationWhitelistMock());

        // Call: Build bytecode across baseline and variant inputs and compute associated hashes.
        bytes memory bytecodeA1 = factory.getOrganizationProxyBytecode(implA, whitelistA);
        bytes memory bytecodeA2 = factory.getOrganizationProxyBytecode(implA, whitelistA);
        bytes memory bytecodeB = factory.getOrganizationProxyBytecode(implB, whitelistA);
        bytes memory bytecodeC = factory.getOrganizationProxyBytecode(implA, whitelistB);

        bytes memory expected = abi.encodePacked(type(OrganizationProxy).creationCode, abi.encode(implA, whitelistA));

        bytes32 salt = bytes32(uint256(1));
        bytes32 initCodeHash = keccak256(bytecodeA1);
        address manualAddr = Create2.computeAddress(salt, initCodeHash, address(factory));
        address factoryAddr = factory.computeOrganizationAddress(salt, implA, whitelistA);

        // Verify: Bytecode encoding, determinism, input sensitivity, and hash stability all match expected behavior.
        assertEq(bytecodeA1, expected, "proxy bytecode should match expected constructor encoding");
        assertEq(bytecodeA1, bytecodeA2, "bytecode should be deterministic for same inputs");
        assertTrue(keccak256(bytecodeA1) != keccak256(bytecodeB), "bytecode hash should differ by implementation");
        assertTrue(keccak256(bytecodeA1) != keccak256(bytecodeC), "bytecode hash should differ by whitelist");
        assertEq(
            manualAddr,
            factoryAddr,
            "keccak256 of public bytecode should match init code hash in computeOrganizationAddress"
        );
    }
}
