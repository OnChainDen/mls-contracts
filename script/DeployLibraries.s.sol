// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Script, console} from "forge-std/Script.sol";

import {LibOrganizationAccountSignature} from "organization/libraries/LibOrganizationAccountSignature.sol";
import {LibOrganizationAdmin} from "organization/libraries/LibOrganizationAdmin.sol";
import {LibOrganizationInitialization} from "organization/libraries/LibOrganizationInitialization.sol";
import {LibOrganizationPolicy} from "organization/libraries/LibOrganizationPolicy.sol";
import {DeploymentConfig} from "script/config/DeploymentConfig.sol";
import {Create2Deployer} from "script/libraries/Create2Deployer.sol";

/**
 * @title DeployLibraries
 * @notice Deploys platform libraries via CREATE2 for deterministic addresses
 * @dev This script must be run BEFORE DeployContracts.s.sol.
 *      After running this script, use the output --libraries flags when running DeployContracts.
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
    /// @dev Grouped addresses for deployed platform libraries
    struct PlatformLibraries {
        address policy;
        address admin;
        address initialization;
        address accountSignature;
    }

    /**
     * @notice Main entry point - deploys all platform libraries via CREATE2
     */
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);
        address factory = Create2Deployer.getCreate2Factory(vm);

        Create2Deployer.logDeploymentHeader(factory, block.chainid);
        console.log("  Deployer EOA: %s", deployerAddress);
        console.log("  Mode: Library Deployment Only");
        console.log("");

        vm.startBroadcast(deployerPrivateKey);
        PlatformLibraries memory libs = _deployPlatformLibraries(factory);
        vm.stopBroadcast();

        Create2Deployer.logDeploymentComplete();
        _logDeployedAddresses(libs);
        _printLibrariesCommand(libs);
    }

    /**
     * @notice Compute and print library addresses without deploying
     * @dev Use this to preview the --libraries flags before any deployment
     */
    function computeAddresses() external view {
        address factory = Create2Deployer.getCreate2Factory(vm);

        console.log("");
        console.log("================================================================================");
        console.log("  Computed Deterministic Library Addresses");
        console.log("================================================================================");
        console.log("  CREATE2 Factory: %s", factory);
        console.log("  Chain ID: %s", block.chainid);
        console.log("");

        PlatformLibraries memory libs = _computeLibraryAddresses(factory);

        console.log("  LibOrganizationPolicy:           %s", libs.policy);
        console.log("  LibOrganizationAdmin:            %s", libs.admin);
        console.log("  LibOrganizationInitialization:   %s", libs.initialization);
        console.log("  LibOrganizationAccountSignature: %s", libs.accountSignature);
        console.log("");

        _printLibrariesCommand(libs);
    }

    /// @dev Deploys all platform libraries via CREATE2 for deterministic addresses
    /// @param factory Address of the CREATE2 factory to use for deployments
    /// @return libs Struct containing all deployed library addresses
    function _deployPlatformLibraries(address factory) internal returns (PlatformLibraries memory libs) {
        Create2Deployer.logSection("Platform Libraries (CREATE2)");

        // Deploy LibOrganizationPolicy
        (libs.policy,) = Create2Deployer.deployIfNotExists(
            factory,
            DeploymentConfig.LIB_ORG_POLICY_SALT,
            type(LibOrganizationPolicy).creationCode,
            "LibOrganizationPolicy"
        );

        // Deploy LibOrganizationAdmin
        (libs.admin,) = Create2Deployer.deployIfNotExists(
            factory,
            DeploymentConfig.LIB_ORG_ADMIN_SALT,
            type(LibOrganizationAdmin).creationCode,
            "LibOrganizationAdmin"
        );

        // Deploy LibOrganizationInitialization
        (libs.initialization,) = Create2Deployer.deployIfNotExists(
            factory,
            DeploymentConfig.LIB_ORG_INIT_SALT,
            type(LibOrganizationInitialization).creationCode,
            "LibOrganizationInitialization"
        );

        // Deploy LibOrganizationAccountSignature
        (libs.accountSignature,) = Create2Deployer.deployIfNotExists(
            factory,
            DeploymentConfig.LIB_ORG_ACCOUNT_SIG_SALT,
            type(LibOrganizationAccountSignature).creationCode,
            "LibOrganizationAccountSignature"
        );
    }

    /// @dev Computes deterministic library addresses without deploying
    /// @param factory Address of the CREATE2 factory to use for address computation
    /// @return libs Struct containing computed library addresses
    function _computeLibraryAddresses(address factory) internal pure returns (PlatformLibraries memory libs) {
        libs.policy = Create2Deployer.computeAddress(
            factory, DeploymentConfig.LIB_ORG_POLICY_SALT, type(LibOrganizationPolicy).creationCode
        );
        libs.admin = Create2Deployer.computeAddress(
            factory, DeploymentConfig.LIB_ORG_ADMIN_SALT, type(LibOrganizationAdmin).creationCode
        );
        libs.initialization = Create2Deployer.computeAddress(
            factory, DeploymentConfig.LIB_ORG_INIT_SALT, type(LibOrganizationInitialization).creationCode
        );
        libs.accountSignature = Create2Deployer.computeAddress(
            factory, DeploymentConfig.LIB_ORG_ACCOUNT_SIG_SALT, type(LibOrganizationAccountSignature).creationCode
        );
    }

    /// @dev Logs all deployed library addresses in a formatted summary
    /// @param libs Struct containing deployed library addresses
    function _logDeployedAddresses(PlatformLibraries memory libs) internal pure {
        console.log("");
        console.log("================================================================================");
        console.log("  Deployed Library Addresses");
        console.log("================================================================================");
        console.log("");
        console.log("  LibOrganizationPolicy:           %s", libs.policy);
        console.log("  LibOrganizationAdmin:            %s", libs.admin);
        console.log("  LibOrganizationInitialization:   %s", libs.initialization);
        console.log("  LibOrganizationAccountSignature: %s", libs.accountSignature);
        console.log("");
        console.log("================================================================================");
    }

    /// @dev Prints the forge --libraries command with library addresses
    /// @param libs Struct containing library addresses
    function _printLibrariesCommand(PlatformLibraries memory libs) internal pure {
        console.log("");
        console.log("================================================================================");
        console.log("  NEXT STEP: Run DeployContracts with the following --libraries flags:");
        console.log("================================================================================");
        console.log("");
        console.log("  forge script script/DeployContracts.s.sol:DeployContracts \\");
        console.log("    --rpc-url $RPC_URL \\");
        console.log("    --broadcast \\");
        console.log("    --libraries %s:%s \\", DeploymentConfig.LIB_ORG_POLICY_PATH, libs.policy);
        console.log("    --libraries %s:%s \\", DeploymentConfig.LIB_ORG_ADMIN_PATH, libs.admin);
        console.log("    --libraries %s:%s \\", DeploymentConfig.LIB_ORG_INIT_PATH, libs.initialization);
        console.log("    --libraries %s:%s \\", DeploymentConfig.LIB_ORG_ACCOUNT_SIG_PATH, libs.accountSignature);
        console.log("    -vvvv");
        console.log("");
        console.log("================================================================================");
    }
}
