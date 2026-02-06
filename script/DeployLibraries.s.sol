// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {LibOrganizationAccountSignature} from "organization/libraries/LibOrganizationAccountSignature.sol";
import {LibOrganizationAdmin} from "organization/libraries/LibOrganizationAdmin.sol";
import {LibOrganizationGuardianRecovery} from "organization/libraries/LibOrganizationGuardianRecovery.sol";
import {LibOrganizationInitialization} from "organization/libraries/LibOrganizationInitialization.sol";
import {LibOrganizationPolicy} from "organization/libraries/LibOrganizationPolicy.sol";
import {LibOrganizationTxRecovery} from "organization/libraries/LibOrganizationTxRecovery.sol";
import {BaseDeployScript} from "script/base/BaseDeployScript.sol";
import {Create2Utils} from "script/libraries/Create2Utils.sol";
import {LinkedLibrariesUtils} from "script/libraries/LinkedLibrariesUtils.sol";
import {Logger} from "script/libraries/Logger.sol";
import {
    DependentLibraries,
    IndependentLibraries,
    LinkedLibraryInfo,
    PlatformLibraries
} from "script/libraries/Types.sol";

/**
 * @title DeployLibraries
 * @notice Deploys platform libraries that will need to be linked to contracts via CREATE2
 *         for deterministic addresses.
 * @dev This script must be run BEFORE DeployContracts.s.sol.
 *      Library deployment is split into two stages due to inter-library dependencies:
 *
 *      Stage 1 (runDeployIndependentLibs): Deploys Policy and Admin (no library deps)
 *      Stage 2 (runDeployDependentLibs): Deploys Init and AccountSig (requires Policy/Admin linked)
 *
 *      Usage for Stage 1:
 *        forge script script/DeployLibraries.s.sol:DeployLibraries \
 *          --sig "runDeployIndependentLibs(address)" <CREATE2_FACTORY_ADDRESS> \
 *          --rpc-url $RPC_URL --broadcast -vvvv
 *
 *      Usage for Stage 2 (after Stage 1 is deployed):
 *        forge script script/DeployLibraries.s.sol:DeployLibraries \
 *          --sig "runDeployDependentLibs(address)" <CREATE2_FACTORY_ADDRESS> \
 *          --libraries <POLICY_PATH>:<POLICY_ADDR> \
 *          --libraries <ADMIN_PATH>:<ADMIN_ADDR> \
 *          --rpc-url $RPC_URL --broadcast -vvvv
 *
 *      SAFETY CHECKS:
 *      1. Verifies the provided CREATE2 factory is a known factory from deployment.toml
 *      2. Verifies the provided CREATE2 factory is deployed
 *      3. Verifies that the deployer is not the production Den Factory deployer
 *      4. For Stage 2: Validates independent libraries are deployed and correctly linked
 *      5. Requires interactive confirmation when broadcasting
 *
 * @author Den Technologies Inc
 */
contract DeployLibraries is BaseDeployScript {
    /**
     * @notice Stage 1: Deploy independent libraries (Policy and Admin)
     * @dev These libraries have no dependencies on other platform libraries.
     *      Run this BEFORE runDeployDependentLibs.
     * @param factoryAddress Address of the CREATE2 factory to use for deployments
     */
    function runDeployIndependentLibs(address factoryAddress) external {
        // Common deployment initialization (factory validation, confirmations, header logging)
        validateAndInitializeDeploymentOrRevert(
            factoryAddress, "DeployLibraries - Stage 1: Independent (Policy, Admin)"
        );

        // Start broadcasting transactions
        vm.startBroadcast();

        // Deploy independent libraries (Policy and Admin)
        IndependentLibraries memory libs = _deployIndependentLibraries();

        // Stop broadcasting transactions
        vm.stopBroadcast();

        // Log deployed addresses
        _logIndependentLibraryAddresses(libs);
    }

    /**
     * @notice Stage 2: Deploy dependent libraries (Init and AccountSig)
     * @dev These libraries depend on Policy and Admin being deployed and linked via --libraries.
     *      IMPORTANT: Run this AFTER runDeployIndependentLibs and with --libraries flags for Policy/Admin.
     * @param factoryAddress Address of the CREATE2 factory to use for deployments
     */
    function runDeployDependentLibs(address factoryAddress) external {
        // Common deployment initialization (factory validation, confirmations, header logging)
        validateAndInitializeDeploymentOrRevert(
            factoryAddress, "DeployLibraries - Stage 2: Dependent (Init, AccountSig)"
        );

        // Get expected addresses from deployment.toml
        PlatformLibraries memory expected = getExpectedLibraryAddresses();

        // Validate Admin is linked in LibOrganizationInitialization and deployed
        Logger.logSection("Verify LibOrganizationAdmin Linked and Deployed");
        bytes memory initInitCode = type(LibOrganizationInitialization).creationCode;
        LinkedLibraryInfo[] memory adminLib = new LinkedLibraryInfo[](1);
        adminLib[0] = LinkedLibraryInfo(expected.adminAddress, "LibOrganizationAdmin");
        LinkedLibrariesUtils.validateLinkedLibrariesOrRevert(initInitCode, adminLib);

        // Validate Policy is linked in LibOrganizationAccountSignature and deployed
        Logger.logSection("Verify LibOrganizationPolicy Linked and Deployed");
        bytes memory accountSigInitCode = type(LibOrganizationAccountSignature).creationCode;
        LinkedLibraryInfo[] memory policyLib = new LinkedLibraryInfo[](1);
        policyLib[0] = LinkedLibraryInfo(expected.policyAddress, "LibOrganizationPolicy");
        LinkedLibrariesUtils.validateLinkedLibrariesOrRevert(accountSigInitCode, policyLib);

        // Start broadcasting transactions
        vm.startBroadcast();

        // Deploy dependent libraries (Init and AccountSig)
        DependentLibraries memory libs = _deployDependentLibraries();

        // Stop broadcasting transactions
        vm.stopBroadcast();

        // Log deployed addresses
        _logDependentLibraryAddresses(libs);
    }

    /**
     * @notice Compute and print independent library addresses without deploying
     * @dev Use this to preview addresses before deployment. Does not require RPC connection.
     * @param factoryAddress Address of the CREATE2 factory to use for address computation
     */
    function computeIndependentAddresses(address factoryAddress) external pure {
        // Validate the provided CREATE2 factory address
        require(factoryAddress != address(0), "Factory address cannot be zero");

        // Log the header
        Logger.logBoxHeader("Computed Independent Library Addresses");
        Logger.logKeyValue("CREATE2 Factory", factoryAddress);
        Logger.logEmptyLine();

        // Compute and log the expected independent library addresses
        Logger.logKeyValue(
            "LibOrganizationPolicy",
            Create2Utils.computeAddress(factoryAddress, LIB_ORG_POLICY_SALT, type(LibOrganizationPolicy).creationCode)
        );
        Logger.logKeyValue(
            "LibOrganizationAdmin",
            Create2Utils.computeAddress(factoryAddress, LIB_ORG_ADMIN_SALT, type(LibOrganizationAdmin).creationCode)
        );
        Logger.logKeyValue(
            "LibOrganizationTxRecovery",
            Create2Utils.computeAddress(
                factoryAddress, LIB_ORG_TX_RECOVERY_SALT, type(LibOrganizationTxRecovery).creationCode
            )
        );
        Logger.logKeyValue(
            "LibOrganizationGuardianRecovery",
            Create2Utils.computeAddress(
                factoryAddress, LIB_ORG_GUARDIAN_RECOVERY_SALT, type(LibOrganizationGuardianRecovery).creationCode
            )
        );
        Logger.logEmptyLine();
    }

    /**
     * @notice Compute and print dependent library addresses without deploying
     * @dev Use this to preview addresses before deployment. Does not require RPC connection.
     *      IMPORTANT: This function must be called with --libraries flags for Policy and Admin
     *      to ensure the correct addresses are embedded in the bytecode.
     * @param factoryAddress Address of the CREATE2 factory to use for address computation
     */
    function computeDependentAddresses(address factoryAddress) external pure {
        // Validate the provided CREATE2 factory address
        require(factoryAddress != address(0), "Factory address cannot be zero");

        // Log the header
        Logger.logBoxHeader("Computed Dependent Library Addresses");
        Logger.logKeyValue("CREATE2 Factory", factoryAddress);
        Logger.logEmptyLine();

        // Compute and log the expected dependent library addresses
        Logger.logKeyValue(
            "LibOrganizationInitialization",
            Create2Utils.computeAddress(
                factoryAddress, LIB_ORG_INIT_SALT, type(LibOrganizationInitialization).creationCode
            )
        );
        Logger.logKeyValue(
            "LibOrganizationAccountSignature",
            Create2Utils.computeAddress(
                factoryAddress, LIB_ORG_ACCOUNT_SIG_SALT, type(LibOrganizationAccountSignature).creationCode
            )
        );
        Logger.logEmptyLine();
    }

    /// @dev Deploys independent platform libraries (Policy and Admin) via CREATE2
    /// @return libs Struct containing deployed independent library addresses
    function _deployIndependentLibraries() internal returns (IndependentLibraries memory libs) {
        Logger.logSection("Independent Libraries (CREATE2)");

        // Deploy LibOrganizationPolicy
        (libs.policyAddress,) = Create2Utils.deployIfNotExists(
            _factoryAddress, LIB_ORG_POLICY_SALT, type(LibOrganizationPolicy).creationCode, "LibOrganizationPolicy"
        );

        // Deploy LibOrganizationAdmin
        (libs.adminAddress,) = Create2Utils.deployIfNotExists(
            _factoryAddress, LIB_ORG_ADMIN_SALT, type(LibOrganizationAdmin).creationCode, "LibOrganizationAdmin"
        );

        // Deploy LibOrganizationTxRecovery
        (libs.txRecoveryAddress,) = Create2Utils.deployIfNotExists(
            _factoryAddress,
            LIB_ORG_TX_RECOVERY_SALT,
            type(LibOrganizationTxRecovery).creationCode,
            "LibOrganizationTxRecovery"
        );

        // Deploy LibOrganizationGuardianRecovery
        (libs.guardianRecoveryAddress,) = Create2Utils.deployIfNotExists(
            _factoryAddress,
            LIB_ORG_GUARDIAN_RECOVERY_SALT,
            type(LibOrganizationGuardianRecovery).creationCode,
            "LibOrganizationGuardianRecovery"
        );
    }

    /// @dev Deploys dependent platform libraries (Init and AccountSig) via CREATE2
    /// @return libs Struct containing deployed dependent library addresses
    function _deployDependentLibraries() internal returns (DependentLibraries memory libs) {
        Logger.logSection("Dependent Libraries (CREATE2)");

        // Deploy LibOrganizationInitialization (depends on Admin being linked)
        (libs.initializationAddress,) = Create2Utils.deployIfNotExists(
            _factoryAddress,
            LIB_ORG_INIT_SALT,
            type(LibOrganizationInitialization).creationCode,
            "LibOrganizationInitialization"
        );

        // Deploy LibOrganizationAccountSignature (depends on Policy being linked)
        (libs.accountSignatureAddress,) = Create2Utils.deployIfNotExists(
            _factoryAddress,
            LIB_ORG_ACCOUNT_SIG_SALT,
            type(LibOrganizationAccountSignature).creationCode,
            "LibOrganizationAccountSignature"
        );
    }

    /// @dev Logs independent library addresses in a formatted summary
    /// @param libs Struct containing deployed independent library addresses
    function _logIndependentLibraryAddresses(IndependentLibraries memory libs) internal pure {
        Logger.logBoxHeader(unicode"✅ Deployed Independent Library Addresses");
        Logger.logKeyValue("LibOrganizationPolicy", libs.policyAddress);
        Logger.logKeyValue("LibOrganizationAdmin", libs.adminAddress);
        Logger.logKeyValue("LibOrganizationTxRecovery", libs.txRecoveryAddress);
        Logger.logKeyValue("LibOrganizationGuardianRecovery", libs.guardianRecoveryAddress);
        Logger.logBoxFooter();
    }

    /// @dev Logs dependent library addresses in a formatted summary
    /// @param libs Struct containing deployed dependent library addresses
    function _logDependentLibraryAddresses(DependentLibraries memory libs) internal pure {
        Logger.logBoxHeader(unicode"✅ Deployed Dependent Library Addresses");
        Logger.logKeyValue("LibOrganizationInitialization", libs.initializationAddress);
        Logger.logKeyValue("LibOrganizationAccountSignature", libs.accountSignatureAddress);
        Logger.logBoxFooter();
    }
}
