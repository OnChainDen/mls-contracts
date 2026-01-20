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
 * @notice Deploys platform libraries via CREATE2 for deterministic addresses
 * @dev This script must be run BEFORE DeployContracts.s.sol.
 *      After running this script, use the outputted --libraries flags when running DeployContracts.
 *
 *      Usage:
 *        forge script script/DeployLibraries.s.sol:DeployLibraries \
 *          --rpc-url $RPC_URL \
 *          --broadcast \
 *          -vvvv
 *
 * @author Den Technologies Inc
 */
contract DeployLibraries is Script {
    /**
     * @notice Main entry point - deploys all platform libraries via CREATE2
     */
    function run() external {
        // Prompt for confirmation when running with --broadcast
        ScriptUtils.confirmBroadcastOrDryRun(vm, "DeployLibraries");

        // Get the deployer private key/address from the environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        // Get the CREATE2 factory that will be used for deployments
        // The address of the factory is explicitly provided in the environment
        address factoryAddress = Create2Utils.getCreate2Factory(vm);

        // Log the deployment header
        // This includes the factory type, chain ID, and deployer EOA address
        Create2Utils.logDeploymentHeader(factoryAddress, block.chainid);
        Logger.logKeyAddress("Deployer EOA", deployerAddress);
        Logger.logKeyValue("Mode", "Library Deployment Only");
        Logger.logEmptyLine();

        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        // Deploy platform libraries
        PlatformLibraries memory libs = _deployPlatformLibraries(factoryAddress);

        // Stop broadcasting transactions
        vm.stopBroadcast();

        Logger.logDeploymentComplete();
        _logDeployedAddresses(libs);
        _printLibrariesCommand(libs);
    }

    /**
     * @notice Compute and print library addresses without deploying
     * @dev Use this to preview the --libraries flags before any deployment
     */
    function computeAddresses() external view {
        // Get the CREATE2 factory that will be used for deployments
        // The address of the factory is explicitly provided in the environment
        address factoryAddress = Create2Utils.getCreate2Factory(vm);

        // Log the header
        // This includes the factory type, chain ID, and deployed library addresses
        Logger.logBoxHeader("Computed Deterministic Library Addresses");
        Logger.logKeyAddress("CREATE2 Factory", factoryAddress);
        Logger.logKeyUint("Chain ID", block.chainid);
        Logger.logEmptyLine();

        // Compute the expected library addresses
        PlatformLibraries memory expectedLibAddresses =
            LinkedLibrariesUtils.computePlatformLibraryAddresses(factoryAddress);

        // Log the computed library addresses
        Logger.logKeyAddress("LibOrganizationPolicy", expectedLibAddresses.policyAddress);
        Logger.logKeyAddress("LibOrganizationAdmin", expectedLibAddresses.adminAddress);
        Logger.logKeyAddress("LibOrganizationInitialization", expectedLibAddresses.initializationAddress);
        Logger.logKeyAddress("LibOrganizationAccountSignature", expectedLibAddresses.accountSignatureAddress);
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
        Logger.logEmptyLine();
        Logger.logKeyAddress("LibOrganizationPolicy", libs.policyAddress);
        Logger.logKeyAddress("LibOrganizationAdmin", libs.adminAddress);
        Logger.logKeyAddress("LibOrganizationInitialization", libs.initializationAddress);
        Logger.logKeyAddress("LibOrganizationAccountSignature", libs.accountSignatureAddress);
        Logger.logEmptyLine();
        Logger.logBoxFooter();
    }

    /// @dev Prints the forge --libraries command with library addresses
    /// @param libs Struct containing library addresses
    function _printLibrariesCommand(PlatformLibraries memory libs) internal pure {
        Logger.logBoxHeader("NEXT STEP: Run DeployContracts with the following --libraries flags:");
        Logger.logEmptyLine();
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
