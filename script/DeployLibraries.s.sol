// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Script} from "forge-std/Script.sol";

import {LibOrganizationAccountSignature} from "organization/libraries/LibOrganizationAccountSignature.sol";
import {LibOrganizationAdmin} from "organization/libraries/LibOrganizationAdmin.sol";
import {LibOrganizationInitialization} from "organization/libraries/LibOrganizationInitialization.sol";
import {LibOrganizationPolicy} from "organization/libraries/LibOrganizationPolicy.sol";
import {DeploymentConfig} from "script/config/DeploymentConfig.sol";
import {Create2Utils} from "script/libraries/Create2Utils.sol";
import {LinkedLibrariesUtils} from "script/libraries/LinkedLibrariesUtils.sol";
import {Logger} from "script/libraries/Logger.sol";
import {ScriptUtils} from "script/libraries/ScriptUtils.sol";
import {PlatformLibraries} from "script/libraries/Types.sol";

/**
 * @title DeployLibraries
 * @notice Deploys platform libraries that will need to be linked to contracts via CREATE2
 *         for deterministic addresses.
 * @dev This script must be run BEFORE DeployContracts.s.sol.
 *      After running this script, use the outputted --libraries flags when running DeployContracts.
 *
 *      Usage:
 *        forge script script/DeployLibraries.s.sol:DeployLibraries \
 *          --sig "run(address)" <CREATE2_FACTORY_ADDRESS> \
 *          --rpc-url $RPC_URL \
 *          --broadcast \
 *          -vvvv
 *
 *      SAFETY CHECKS:
 *      1. Verifies the provided CREATE2 factory address is not zero
 *      2. Verifies the provided CREATE2 factory address is deployed at the provided address
 *      3. Verifies that the deployer is not the production Den Factory deployer
 *      4. Requires interactive confirmation when broadcasting
 *
 * @author Den Technologies Inc
 */
contract DeployLibraries is Script {
    /**
     * @notice Main entry point - deploys all platform libraries via CREATE2
     * @param factoryAddress Address of the CREATE2 factory to use for deployments
     */
    function run(address factoryAddress) external {
        // Validate the provided CREATE2 factory address
        require(factoryAddress != address(0), "Factory address cannot be zero");
        require(
            Create2Utils.isContractDeployedAtAddress(factoryAddress), "CREATE2 factory not deployed at provided address"
        );

        // Prompt for confirmation when running with --broadcast
        ScriptUtils.confirmBroadcastOrDryRun(vm, "DeployLibraries");

        // Prevent using the production Den Factory deployer for this script
        Create2Utils.validateNotProductionDenFactoryDeployerOrRevert();

        // Log the deployment header
        // This includes the factory type, chain ID, and deployer EOA address
        Create2Utils.logDeploymentHeader(factoryAddress, block.chainid);
        Logger.logKeyValue("Deployer EOA", msg.sender);
        Logger.logKeyValue("Mode", "Library Deployment Only");
        Logger.logEmptyLine();

        // Start broadcasting transactions
        vm.startBroadcast();

        // Deploy platform libraries
        PlatformLibraries memory libs = _deployPlatformLibraries(factoryAddress);

        // Stop broadcasting transactions
        vm.stopBroadcast();

        // Log that the deployment is complete and print the deployed library addresses and
        // the forge --libraries command to run DeployContracts.s.sol with the correct library addresses.
        Logger.logDeploymentComplete();
        _logDeployedAddresses(libs);
        _printLibrariesCommand(libs);
    }

    /**
     * @notice Compute and print library addresses without deploying
     * @dev Use this to preview the --libraries flags before any deployment
     * @param factoryAddress Address of the CREATE2 factory to use for address computation
     */
    function computeAddresses(address factoryAddress) external view {
        // Validate the provided CREATE2 factory address
        require(factoryAddress != address(0), "Factory address cannot be zero");
        require(
            Create2Utils.isContractDeployedAtAddress(factoryAddress), "CREATE2 factory not deployed at provided address"
        );

        // Log the header
        // This includes the factory type, chain ID, and deployed library addresses
        Logger.logBoxHeader("Computed Deterministic Library Addresses");
        Logger.logKeyValue("CREATE2 Factory", factoryAddress);
        Logger.logKeyValue("Chain ID", block.chainid);
        Logger.logEmptyLine();

        // Compute the expected library addresses
        PlatformLibraries memory expectedLibAddresses =
            LinkedLibrariesUtils.computePlatformLibraryAddresses(factoryAddress);

        // Log the computed library addresses
        Logger.logKeyValue("LibOrganizationPolicy", expectedLibAddresses.policyAddress);
        Logger.logKeyValue("LibOrganizationAdmin", expectedLibAddresses.adminAddress);
        Logger.logKeyValue("LibOrganizationInitialization", expectedLibAddresses.initializationAddress);
        Logger.logKeyValue("LibOrganizationAccountSignature", expectedLibAddresses.accountSignatureAddress);
        Logger.logEmptyLine();

        // Print the forge --libraries command with library addresses
        _printLibrariesCommand(expectedLibAddresses);
    }

    /// @dev Deploys all platform libraries via CREATE2 for deterministic addresses
    /// @param factoryAddress Address of the CREATE2 factory to use for deployments
    /// @return libs Struct containing all deployed library addresses
    function _deployPlatformLibraries(address factoryAddress) internal returns (PlatformLibraries memory libs) {
        Logger.logSection("Platform Libraries (CREATE2)");

        // Deploy LibOrganizationPolicy
        (libs.policyAddress,) = Create2Utils.deployIfNotExists(
            factoryAddress,
            DeploymentConfig.LIB_ORG_POLICY_SALT,
            type(LibOrganizationPolicy).creationCode,
            "LibOrganizationPolicy"
        );

        // Deploy LibOrganizationAdmin
        (libs.adminAddress,) = Create2Utils.deployIfNotExists(
            factoryAddress,
            DeploymentConfig.LIB_ORG_ADMIN_SALT,
            type(LibOrganizationAdmin).creationCode,
            "LibOrganizationAdmin"
        );

        // Deploy LibOrganizationInitialization
        (libs.initializationAddress,) = Create2Utils.deployIfNotExists(
            factoryAddress,
            DeploymentConfig.LIB_ORG_INIT_SALT,
            type(LibOrganizationInitialization).creationCode,
            "LibOrganizationInitialization"
        );

        // Deploy LibOrganizationAccountSignature
        (libs.accountSignatureAddress,) = Create2Utils.deployIfNotExists(
            factoryAddress,
            DeploymentConfig.LIB_ORG_ACCOUNT_SIG_SALT,
            type(LibOrganizationAccountSignature).creationCode,
            "LibOrganizationAccountSignature"
        );
    }

    /// @dev Logs all deployed library addresses in a formatted summary
    /// @param libs Struct containing deployed library addresses
    function _logDeployedAddresses(PlatformLibraries memory libs) internal pure {
        Logger.logBoxHeader("Deployed Library Addresses");
        Logger.logKeyValue("LibOrganizationPolicy", libs.policyAddress);
        Logger.logKeyValue("LibOrganizationAdmin", libs.adminAddress);
        Logger.logKeyValue("LibOrganizationInitialization", libs.initializationAddress);
        Logger.logKeyValue("LibOrganizationAccountSignature", libs.accountSignatureAddress);
        Logger.logEmptyLine();
        Logger.logBoxFooter();
    }

    /// @dev Prints the forge --libraries command with library addresses
    /// @param libs Struct containing library addresses
    function _printLibrariesCommand(PlatformLibraries memory libs) internal pure {
        Logger.logBoxHeader("NEXT STEP: Run DeployContracts with the following --libraries flags:");
        Logger.logIndented("forge script script/DeployContracts.s.sol:DeployContracts \\");
        Logger.logIndented("  --rpc-url $RPC_URL \\");
        Logger.logIndented("  --broadcast \\");
        Logger.logIndented(
            // solhint-disable-next-line func-named-parameters
            string.concat(
                "  --libraries ",
                DeploymentConfig.LIB_ORG_POLICY_PATH,
                ":",
                Strings.toHexString(libs.policyAddress),
                " \\"
            )
        );
        Logger.logIndented(
            // solhint-disable-next-line func-named-parameters
            string.concat(
                "  --libraries ",
                DeploymentConfig.LIB_ORG_ADMIN_PATH,
                ":",
                Strings.toHexString(libs.adminAddress),
                " \\"
            )
        );
        Logger.logIndented(
            // solhint-disable-next-line func-named-parameters
            string.concat(
                "  --libraries ",
                DeploymentConfig.LIB_ORG_INIT_PATH,
                ":",
                Strings.toHexString(libs.initializationAddress),
                " \\"
            )
        );
        Logger.logIndented(
            // solhint-disable-next-line func-named-parameters
            string.concat(
                "  --libraries ",
                DeploymentConfig.LIB_ORG_ACCOUNT_SIG_PATH,
                ":",
                Strings.toHexString(libs.accountSignatureAddress),
                " \\"
            )
        );
        Logger.logIndented("  -vvvv");
        Logger.logEmptyLine();
        Logger.logBoxFooter();
    }
}
