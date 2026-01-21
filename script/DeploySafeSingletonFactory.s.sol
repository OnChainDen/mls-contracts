// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Script} from "forge-std/Script.sol";

import {DeploymentConfig} from "script/config/DeploymentConfig.sol";
import {Create2Utils} from "script/libraries/Create2Utils.sol";
import {Logger} from "script/libraries/Logger.sol";
import {ScriptUtils} from "script/libraries/ScriptUtils.sol";

/**
 * @title DeploySafeSingletonFactory
 * @notice Script to deploy the Safe Singleton Factory on chains where it doesn't exist
 * @dev CRITICAL: This script uses a special deployer key that MUST maintain nonce = 0.
 *      If the nonce is burned, the factory cannot be deployed at the expected address.
 *
 *      The Safe Singleton Factory is normally deployed via pre-signed raw transactions
 *      (see https://github.com/safe-global/safe-singleton-factory). This script instead
 *      deploys the bytecode directly for Foundry compatibility and multi-chain support,
 *      since pre-signed transactions are chain-specific (signature includes chainId).
 *
 *      SAFETY CHECKS:
 *      1. Verifies deployer nonce is exactly 0
 *      2. Verifies factory is not already deployed
 *      3. Requires interactive confirmation when broadcasting
 *      4. Logs dry-run mode when not broadcasting
 *
 * @author Den Technologies Inc
 */
contract DeploySafeSingletonFactory is Script {
    /// @dev Gas price for the deployment transaction (125 gwei - works on most chains)
    uint256 internal constant _DEPLOYMENT_GAS_PRICE = 125_000_000_000;

    /// @dev Gas limit for the deployment transaction
    uint256 internal constant _DEPLOYMENT_GAS_LIMIT = 101_616;

    /// @dev Required ETH balance for the deployer (gas price * gas limit * 2 for buffer)
    uint256 internal constant _REQUIRED_ETH_BALANCE = _DEPLOYMENT_GAS_PRICE * _DEPLOYMENT_GAS_LIMIT * 2;

    /**
     * @notice Main entry point for the deployment script
     * @dev Runs comprehensive safety checks before allowing deployment
     */
    function run() external {
        // Prompt for confirmation when running with --broadcast
        ScriptUtils.confirmBroadcastOrDryRun(vm, "DeploySafeSingletonFactory");

        // Log the deployment header
        Logger.logBoxHeader("Safe Singleton Factory - Factory Deployment");

        // Validate that the Arachnid factory is not already deployed
        // We should not be deploying the Safe Singleton Factory if the Arachnid factory is already deployed.
        Create2Utils.validateFactoryNotDeployedOrRevert(
            DeploymentConfig.ARACHNID_CREATE2_FACTORY_ADDRESS, "Arachnid factory"
        );

        // Validate that the Safe Singleton Factory is not already deployed
        Create2Utils.validateFactoryNotDeployedOrRevert(
            DeploymentConfig.SAFE_SINGLETON_FACTORY_ADDRESS, "Safe Singleton Factory"
        );

        // Get the deployer address
        address deployerAddress = msg.sender;

        // Warn and require confirmation for production and non-production deployers
        bool isProductionDeployer = _warnAndConfirmDeployerAddress(deployerAddress);

        // Validate that the deployer nonce is exactly 0
        _warnAndConfirmIfDeployerNonceNotZero(deployerAddress);

        // Validate that the deployer has sufficient ETH balance
        Create2Utils.validateDeployerHasSufficientEthOrRevert(
            deployerAddress, _REQUIRED_ETH_BALANCE, "DeploySafeSingletonFactory"
        );

        // Log section header
        Logger.logSection("DEPLOYING SAFE SINGLETON FACTORY");

        // Deploy the factory
        vm.startBroadcast();
        address deployedAtAddress = _deployFactory();
        vm.stopBroadcast();

        // Case: Production deployer should yield the known deterministic address
        if (isProductionDeployer) {
            if (!Create2Utils.isContractDeployedAtAddress(DeploymentConfig.PROD_EXPECTED_SAFE_FACTORY_ADDRESS)) {
                Logger.logFail("ERROR: Factory was not deployed at the expected production address!");
                Logger.logKeyAddress("Expected", DeploymentConfig.PROD_EXPECTED_SAFE_FACTORY_ADDRESS);
                Logger.logKeyAddress("Got", deployedAtAddress);
                revert("Factory deployment failed");
            }
        } else if (!Create2Utils.isContractDeployedAtAddress(deployedAtAddress)) {
            // Case: Non-production deployer should still deploy successfully
            Logger.logFail("ERROR: Factory deployment failed for non-production deployer!");
            Logger.logKeyAddress("Got", deployedAtAddress);
            revert("Factory deployment failed");
        }

        // Log success
        Logger.logDeploymentSuccess("Safe Singleton Factory", deployedAtAddress, "CREATE2_FACTORY_ADDRESS");
    }

    /// @notice Funds the Safe Singleton Factory deployer address with ETH
    /// @dev Can be called separately to fund the deployer before running the main script.
    /// @param targetDeployerAddress The deployer address to fund
    function fundDeployer(address targetDeployerAddress) external {
        // Prevent using the production Safe Factory deployer for funding
        Create2Utils.validateNotProductionSafeFactoryDeployerOrRevert();

        require(targetDeployerAddress != address(0), "Target deployer address cannot be zero");

        // Log the funding details
        Logger.logEmptyLine();
        Logger.logIndented("Funding Safe Singleton Factory deployer...");
        Logger.logKeyAddress("Target", targetDeployerAddress);
        Logger.logKeyUint("Amount (wei)", _REQUIRED_ETH_BALANCE);
        Logger.logEmptyLine();

        // Fund the deployer
        vm.startBroadcast();
        payable(targetDeployerAddress).transfer(_REQUIRED_ETH_BALANCE);
        vm.stopBroadcast();

        // Log the success
        Logger.logPass("Deployer funded successfully");
    }

    /// @dev Deploys the Safe Singleton Factory using inline assembly
    ///      Uses CREATE opcode from nonce 0 to achieve deterministic address
    function _deployFactory() internal returns (address deployedAtAddress) {
        // Safe Singleton Factory bytecode (minimal CREATE2 factory)
        // This is the init code that produces a contract at the expected address
        // forgefmt: disable-next-item
        bytes memory factoryBytecode =
            // solhint-disable-next-line max-line-length
            hex"604580600e600039806000f350fe7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578082fd5b8082525050506014600cf3";

        // slither-disable-next-line assembly
        assembly {
            deployedAtAddress := create(0, add(factoryBytecode, 0x20), mload(factoryBytecode))
        }

        // Check that the factory was deployed
        require(deployedAtAddress != address(0), "Factory deployment failed");

        return deployedAtAddress;
    }

    /// @dev Warns and prompts for confirmation if the deployer nonce is not 0
    /// @param deployerAddress The deployer address to check
    function _warnAndConfirmIfDeployerNonceNotZero(address deployerAddress) internal {
        // Log the check start
        Logger.logCheckStart("Checking deployer nonce...");

        // Get the deployer's nonce
        uint256 nonce = vm.getNonce(deployerAddress);

        // Case: Deployer nonce is 0
        if (nonce == 0) {
            Logger.logCheckPass("Deployer nonce is 0");
            return;
        }

        // Case: Deployer nonce is not 0
        Logger.logCheckWarn("Deployer nonce is not 0 (expected 0)");
        Logger.logCheckDetail("CRITICAL: Nonce has been burned! Factory address will change.");
        Logger.logCheckDetail("Continuing may deploy to an unexpected address.");
        Logger.logKeyUint("Current nonce", nonce);

        ScriptUtils.promptForConfirmationOrRevert(vm);
    }

    /// @dev Warns and prompts for confirmation of the deployer address
    /// @param deployerAddress The deployer address to confirm
    /// @return isProductionDeployer True if the deployer is the production deployer
    function _warnAndConfirmDeployerAddress(address deployerAddress) internal returns (bool isProductionDeployer) {
        // Log the check start
        Logger.logCheckStart("Confirming deployer address...");

        // Case: Deployer address matches production address
        if (deployerAddress == DeploymentConfig.PROD_SAFE_FACTORY_DEPLOYER_ADDRESS) {
            Logger.logCheckWarn("Using PRODUCTION Safe Factory deployer");
            Logger.logCheckDetail("This EOA must keep nonce 0 for deterministic deployment.");
            Logger.logKeyAddress("Deployer", deployerAddress);
            Logger.logKeyAddress("Expected factory", DeploymentConfig.PROD_EXPECTED_SAFE_FACTORY_ADDRESS);
            ScriptUtils.promptForConfirmationOrRevert(vm);
            Logger.logCheckPass("Production deployer confirmed");
            return true;
        }

        // Case: Deployer address is NOT the production deployer
        Logger.logCheckWarn("Using NON-PRODUCTION Safe Factory deployer");
        Logger.logCheckDetail("Factory address will differ from production.");
        Logger.logKeyAddress("Deployer", deployerAddress);
        Logger.logKeyAddress("Production deployer", DeploymentConfig.PROD_SAFE_FACTORY_DEPLOYER_ADDRESS);
        ScriptUtils.promptForConfirmationOrRevert(vm);
        Logger.logCheckPass("Non-production deployer confirmed");
        return false;
    }
}
