// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {Script} from "forge-std/Script.sol";

import {DeploymentConfig} from "script/config/DeploymentConfig.sol";
import {Create2Utils} from "script/libraries/Create2Utils.sol";
import {Logger} from "script/libraries/Logger.sol";
import {ScriptUtils} from "script/libraries/ScriptUtils.sol";
import {StringUtils} from "script/libraries/StringUtils.sol";

/**
 * @title DeployDenSingletonFactory
 * @notice Script to deploy the Den Singleton Factory on chains where it doesn't exist
 * @dev CRITICAL: This script uses a special deployer key that MUST maintain nonce = 0.
 *      If the nonce is burned, the factory cannot be deployed at the expected address.
 *
 *      SAFETY CHECKS:
 *      1. Verifies deployer nonce is exactly 0
 *      2. Verifies deployer has sufficient ETH balance
 *      3. Warns and requires confirmation when the deployer is the production deployer
 *      2. Verifies arachnid and Den singleton factories are not already deployed
 *      3. Requires interactive confirmation when broadcasting
 *
 * @author Den Technologies Inc
 */
contract DeployDenSingletonFactory is Script {
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
        ScriptUtils.confirmBroadcastOrDryRun(vm, "DeployDenSingletonFactory");

        // Log the deployment header
        Logger.logBoxHeader("Den Singleton Factory - Factory Deployment");

        // Validate that the Arachnid factory is not already deployed
        // We should not be deploying the Den Singleton Factory if the Arachnid factory is already deployed.
        Create2Utils.validateFactoryNotDeployedOrRevert(
            DeploymentConfig.ARACHNID_CREATE2_FACTORY_ADDRESS, "Arachnid factory"
        );

        // Validate that the Den Singleton Factory is not already deployed
        Create2Utils.validateFactoryNotDeployedOrRevert(
            DeploymentConfig.PROD_DEN_SINGLETON_FACTORY_ADDRESS, "Den Singleton Factory"
        );

        // Warn and require confirmation for production and non-production deployers
        bool isProductionDeployer = _warnAndConfirmDeployerAddress();

        // Validate that the deployer nonce is exactly 0
        _warnAndConfirmIfDeployerNonceNotZero();

        // Validate that the deployer has sufficient ETH balance
        Create2Utils.validateDeployerHasSufficientEthOrRevert(
            msg.sender, _REQUIRED_ETH_BALANCE, "DeployDenSingletonFactory"
        );

        // Log section header
        Logger.logSection("DEPLOYING DEN SINGLETON FACTORY");

        // Deploy the factory
        vm.startBroadcast();
        address deployedAtAddress = _deployFactory();
        vm.stopBroadcast();

        // Case: Production deployer
        // Check that the factory was deployed at the expected production address
        if (isProductionDeployer) {
            if (!Create2Utils.isContractDeployedAtAddress(DeploymentConfig.PROD_DEN_SINGLETON_FACTORY_ADDRESS)) {
                Logger.logFail("ERROR: Factory was not deployed at the expected production address!");
                Logger.logKeyValue("Expected", DeploymentConfig.PROD_DEN_SINGLETON_FACTORY_ADDRESS);
                Logger.logKeyValue("Got", deployedAtAddress);
                revert("Factory deployment failed");
            }
        } else if (!Create2Utils.isContractDeployedAtAddress(DeploymentConfig.NON_PROD_DEN_SINGLETON_FACTORY_ADDRESS)) {
            // Case: Non-production deployer
            // Check that the factory was deployed at the expected non-production address
            Logger.logFail("ERROR: Factory was not deployed at the expected non-production address!");
            Logger.logKeyValue("Expected", DeploymentConfig.NON_PROD_DEN_SINGLETON_FACTORY_ADDRESS);
            Logger.logKeyValue("Got", deployedAtAddress);
            revert("Factory deployment failed");
        }

        // Log success
        Logger.logDeploymentSuccess("Den Singleton Factory", deployedAtAddress, "CREATE2_FACTORY_ADDRESS");
    }

    /// @notice Funds the Den Singleton Factory deployer address with ETH
    /// @dev Can be called separately to fund the deployer before running the main script.
    /// @param targetDeployerAddress The deployer address to fund
    function fundDeployer(address targetDeployerAddress) external {
        // Prevent using the production Den Factory deployer for funding
        Create2Utils.validateNotProductionDenFactoryDeployerOrRevert();

        require(targetDeployerAddress != address(0), "Target deployer address cannot be zero");

        // Log the funding details
        Logger.logEmptyLine();
        Logger.logIndented("Funding Den Singleton Factory deployer...");
        Logger.logKeyValue("Target", targetDeployerAddress);
        Logger.logKeyValue("Amount (wei)", _REQUIRED_ETH_BALANCE);
        Logger.logEmptyLine();

        // Fund the deployer
        vm.startBroadcast();
        payable(targetDeployerAddress).transfer(_REQUIRED_ETH_BALANCE);
        vm.stopBroadcast();

        // Log the success
        Logger.logPass("Deployer funded successfully");
    }

    /// @dev Deploys the Den Singleton Factory using inline assembly
    ///      Uses CREATE opcode from nonce 0 to achieve deterministic address
    function _deployFactory() internal returns (address deployedAtAddress) {
        // Den Singleton Factory bytecode (minimal CREATE2 factory)
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
    function _warnAndConfirmIfDeployerNonceNotZero() internal {
        // Get the deployer's nonce
        uint256 nonce = vm.getNonce(msg.sender);

        // Case: Deployer nonce is 0 - no confirmation needed
        if (nonce == 0) {
            Logger.logCheckPass("Deployer nonce is 0");
            return;
        }

        // Case: Deployer nonce is not 0 - require confirmation with context in prompt
        // NOTE: Context is embedded in prompt because console.log output is buffered
        // solhint-disable-next-line func-named-parameters
        string memory context = string(
            abi.encodePacked(
                "\n  !! WARNING: Deployer nonce is not 0 (expected 0) !!\n",
                "  CRITICAL: Nonce has been burned! Factory address will change.\n",
                "  Continuing will deploy to an unexpected address.\n",
                "  Current nonce: ",
                StringUtils.toString(nonce)
            )
        );

        ScriptUtils.promptForConfirmationOrRevert(vm, context);
    }

    /// @dev Warns and prompts for confirmation of the deployer address
    /// @return isProductionDeployer True if the deployer is the production deployer
    function _warnAndConfirmDeployerAddress() internal returns (bool isProductionDeployer) {
        // Case: Deployer address matches production address
        if (msg.sender == DeploymentConfig.PROD_DEN_FACTORY_DEPLOYER_ADDRESS) {
            // Build context for prompt - embedded because console.log output is buffered
            // solhint-disable-next-line func-named-parameters
            string memory context = string(
                abi.encodePacked(
                    "\n  !! Using PRODUCTION Den Factory deployer !!\n",
                    "  This EOA must keep nonce 0 for deterministic deployment.\n",
                    "  Deployer: ",
                    StringUtils.toHexString(msg.sender),
                    "\n  Expected factory: ",
                    StringUtils.toHexString(DeploymentConfig.PROD_DEN_SINGLETON_FACTORY_ADDRESS)
                )
            );

            ScriptUtils.promptForConfirmationOrRevert(vm, context);
            Logger.logCheckPass("Production deployer confirmed");
            return true;
        }

        // Case: Deployer address is NOT the production deployer
        // Build context for prompt - embedded because console.log output is buffered
        // solhint-disable-next-line func-named-parameters
        string memory nonProdContext = string(
            abi.encodePacked(
                "\n  !! Using NON-PRODUCTION Den Factory deployer !!\n",
                "  Factory address will differ from production.\n",
                "  Deployer: ",
                StringUtils.toHexString(msg.sender),
                "\n  Production deployer: ",
                StringUtils.toHexString(DeploymentConfig.PROD_DEN_FACTORY_DEPLOYER_ADDRESS)
            )
        );

        ScriptUtils.promptForConfirmationOrRevert(vm, nonProdContext);
        Logger.logCheckPass("Non-production deployer confirmed");
        return false;
    }
}
