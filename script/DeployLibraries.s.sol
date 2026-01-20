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
    /// @notice Address of the deployed LibOrganizationPolicy library
    address public libOrganizationPolicy;

    /// @notice Address of the deployed LibOrganizationAdmin library
    address public libOrganizationAdmin;

    /// @notice Address of the deployed LibOrganizationInitialization library
    address public libOrganizationInitialization;

    /// @notice Address of the deployed LibOrganizationAccountSignature library
    address public libOrganizationAccountSignature;

    /// @notice Address of the CREATE2 factory being used for deployments
    address public create2Factory;

    /**
     * @notice Main entry point - deploys all platform libraries via CREATE2
     */
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        create2Factory = _getCreate2Factory();

        Create2Deployer.logDeploymentHeader(create2Factory, block.chainid);
        console.log("  Deployer EOA: %s", deployerAddress);
        console.log("  Mode: Library Deployment Only");
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        _deployPlatformLibraries();

        vm.stopBroadcast();

        Create2Deployer.logDeploymentComplete();
        _logDeployedAddresses();
        _printLibrariesCommand();
    }

    /**
     * @notice Compute and print library addresses without deploying
     * @dev Use this to preview the --libraries flags before any deployment
     */
    function computeAddresses() external view {
        address factory = _getCreate2Factory();

        console.log("");
        console.log("================================================================================");
        console.log("  Computed Deterministic Library Addresses");
        console.log("================================================================================");
        console.log("  CREATE2 Factory: %s", factory);
        console.log("  Chain ID: %s", block.chainid);
        console.log("");

        address libPolicy = Create2Deployer.computeAddress(
            factory, DeploymentConfig.LIB_ORG_POLICY_SALT, type(LibOrganizationPolicy).creationCode
        );
        address libAdmin = Create2Deployer.computeAddress(
            factory, DeploymentConfig.LIB_ORG_ADMIN_SALT, type(LibOrganizationAdmin).creationCode
        );
        address libInit = Create2Deployer.computeAddress(
            factory, DeploymentConfig.LIB_ORG_INIT_SALT, type(LibOrganizationInitialization).creationCode
        );
        address libAccSig = Create2Deployer.computeAddress(
            factory, DeploymentConfig.LIB_ORG_ACCOUNT_SIG_SALT, type(LibOrganizationAccountSignature).creationCode
        );

        console.log("  LibOrganizationPolicy:           %s", libPolicy);
        console.log("  LibOrganizationAdmin:            %s", libAdmin);
        console.log("  LibOrganizationInitialization:   %s", libInit);
        console.log("  LibOrganizationAccountSignature: %s", libAccSig);
        console.log("");

        _printLibrariesCommandWithAddresses(libPolicy, libAdmin, libInit, libAccSig);
    }

    /// @dev Deploys all platform libraries via CREATE2 for deterministic addresses
    ///      Libraries deployed: LibOrganizationPolicy, LibOrganizationAdmin,
    ///      LibOrganizationInitialization, LibOrganizationAccountSignature
    function _deployPlatformLibraries() internal {
        Create2Deployer.logSection("Platform Libraries (CREATE2)");

        // Deploy LibOrganizationPolicy
        (libOrganizationPolicy,) = Create2Deployer.deployIfNotExists(
            create2Factory,
            DeploymentConfig.LIB_ORG_POLICY_SALT,
            type(LibOrganizationPolicy).creationCode,
            "LibOrganizationPolicy"
        );

        // Deploy LibOrganizationAdmin
        (libOrganizationAdmin,) = Create2Deployer.deployIfNotExists(
            create2Factory,
            DeploymentConfig.LIB_ORG_ADMIN_SALT,
            type(LibOrganizationAdmin).creationCode,
            "LibOrganizationAdmin"
        );

        // Deploy LibOrganizationInitialization
        (libOrganizationInitialization,) = Create2Deployer.deployIfNotExists(
            create2Factory,
            DeploymentConfig.LIB_ORG_INIT_SALT,
            type(LibOrganizationInitialization).creationCode,
            "LibOrganizationInitialization"
        );

        // Deploy LibOrganizationAccountSignature
        (libOrganizationAccountSignature,) = Create2Deployer.deployIfNotExists(
            create2Factory,
            DeploymentConfig.LIB_ORG_ACCOUNT_SIG_SALT,
            type(LibOrganizationAccountSignature).creationCode,
            "LibOrganizationAccountSignature"
        );
    }

    /// @dev Retrieves the CREATE2 factory address from environment or auto-detects one
    /// @return factory Address of the available CREATE2 factory
    function _getCreate2Factory() internal view returns (address factory) {
        // First, check if explicitly provided
        try vm.envAddress("CREATE2_FACTORY_ADDRESS") returns (address provided) {
            if (provided != address(0) && Create2Deployer.isContractDeployedAtAddress(provided)) {
                return provided;
            }
        } catch {}

        // Auto-detect available factory
        (factory,) = Create2Deployer.getAvailableFactory();

        if (factory == address(0)) {
            revert("No CREATE2 factory available");
        }
    }

    /// @dev Logs all deployed library addresses in a formatted summary
    function _logDeployedAddresses() internal view {
        console.log("");
        console.log("================================================================================");
        console.log("  Deployed Library Addresses");
        console.log("================================================================================");
        console.log("");
        console.log("  LibOrganizationPolicy:           %s", libOrganizationPolicy);
        console.log("  LibOrganizationAdmin:            %s", libOrganizationAdmin);
        console.log("  LibOrganizationInitialization:   %s", libOrganizationInitialization);
        console.log("  LibOrganizationAccountSignature: %s", libOrganizationAccountSignature);
        console.log("");
        console.log("================================================================================");
    }

    /// @dev Prints the forge --libraries command using deployed addresses
    function _printLibrariesCommand() internal view {
        _printLibrariesCommandWithAddresses(
            libOrganizationPolicy, libOrganizationAdmin, libOrganizationInitialization, libOrganizationAccountSignature
        );
    }

    /// @dev Prints the forge --libraries command with specified addresses
    /// @param libPolicy Address of the LibOrganizationPolicy library
    /// @param libAdmin Address of the LibOrganizationAdmin library
    /// @param libInit Address of the LibOrganizationInitialization library
    /// @param libAccSig Address of the LibOrganizationAccountSignature library
    function _printLibrariesCommandWithAddresses(
        address libPolicy,
        address libAdmin,
        address libInit,
        address libAccSig
    ) internal pure {
        console.log("");
        console.log("================================================================================");
        console.log("  NEXT STEP: Run DeployContracts with the following --libraries flags:");
        console.log("================================================================================");
        console.log("");
        console.log("  forge script script/DeployContracts.s.sol:DeployContracts \\");
        console.log("    --rpc-url $RPC_URL \\");
        console.log("    --broadcast \\");
        console.log("    --libraries %s:%s \\", DeploymentConfig.LIB_ORG_POLICY_PATH, libPolicy);
        console.log("    --libraries %s:%s \\", DeploymentConfig.LIB_ORG_ADMIN_PATH, libAdmin);
        console.log("    --libraries %s:%s \\", DeploymentConfig.LIB_ORG_INIT_PATH, libInit);
        console.log("    --libraries %s:%s \\", DeploymentConfig.LIB_ORG_ACCOUNT_SIG_PATH, libAccSig);
        console.log("    -vvvv");
        console.log("");
        console.log("================================================================================");
    }
}
