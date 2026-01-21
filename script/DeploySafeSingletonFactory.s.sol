// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
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
    /// @dev Expected factory address after deployment (deterministic via nonce-0 CREATE)
    address internal constant _EXPECTED_FACTORY_ADDRESS = 0x914d7Fec6aaC8cd542e72Bca78B30650d45643d7;

    /// @dev Deployer address that must have nonce 0 for deterministic deployment
    address internal constant _EXPECTED_DEPLOYER_ADDRESS = 0xE1CB04A0fA36DdD16a06ea828007E35e1a3cBC37;

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

        // Get the deployer private key from the environment variable
        uint256 deployerPrivateKey = vm.envUint("SAFE_FACTORY_DEPLOYER_PRIVATE_KEY");

        // Validate that the deployer private key matches the expected address
        _validateDeployerPrivateKeyOrRevert(deployerPrivateKey);

        // Validate that the deployer nonce is exactly 0
        _warnAndConfirmIfDeployerNonceNotZero();

        // Validate that the deployer has sufficient ETH balance
        Create2Utils.validateDeployerHasSufficientEthOrRevert(
            _EXPECTED_DEPLOYER_ADDRESS, _REQUIRED_ETH_BALANCE, "DeploySafeSingletonFactory"
        );

        // Log section header
        Logger.logSection("DEPLOYING SAFE SINGLETON FACTORY");

        // Deploy the factory
        vm.startBroadcast(deployerPrivateKey);
        _deployFactory();
        vm.stopBroadcast();

        // Case: Factory was not deployed at the expected address
        if (!Create2Utils.isContractDeployedAtAddress(_EXPECTED_FACTORY_ADDRESS)) {
            Logger.logFail("ERROR: Factory was not deployed at the expected address!");

            revert("Factory deployment failed");
        }

        // Log success
        Logger.logDeploymentSuccess("Safe Singleton Factory", _EXPECTED_FACTORY_ADDRESS, "CREATE2_FACTORY_ADDRESS");
    }

    /// @notice Funds the Safe Singleton Factory deployer address with ETH
    /// @dev Can be called separately to fund the deployer before running the main script.
    ///      Requires PRIVATE_KEY environment variable to be set for the funding account.
    function fundDeployer() external {
        // Get the private key for the account that will fund the deployer
        uint256 fundingPrivateKey = vm.envUint("PRIVATE_KEY");

        // Log the funding details
        Logger.logEmptyLine();
        Logger.logIndented("Funding Safe Singleton Factory deployer...");
        Logger.logKeyAddress("Target", _EXPECTED_DEPLOYER_ADDRESS);
        Logger.logKeyUint("Amount (wei)", _REQUIRED_ETH_BALANCE);
        Logger.logEmptyLine();

        // Fund the deployer
        vm.startBroadcast(fundingPrivateKey);
        payable(_EXPECTED_DEPLOYER_ADDRESS).transfer(_REQUIRED_ETH_BALANCE);
        vm.stopBroadcast();

        // Log the success
        Logger.logPass("Deployer funded successfully");
    }

    /// @dev Deploys the Safe Singleton Factory using inline assembly
    ///      Uses CREATE opcode from nonce 0 to achieve deterministic address
    function _deployFactory() internal {
        // Safe Singleton Factory bytecode (minimal CREATE2 factory)
        // This is the init code that produces a contract at the expected address
        // forgefmt: disable-next-item
        bytes memory factoryBytecode =
            // solhint-disable-next-line max-line-length
            hex"604580600e600039806000f350fe7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578082fd5b8082525050506014600cf3";

        address deployedAtAddress;

        // slither-disable-next-line assembly
        assembly {
            deployedAtAddress := create(0, add(factoryBytecode, 0x20), mload(factoryBytecode))
        }

        // Check that the factory was deployed
        require(deployedAtAddress != address(0), "Factory deployment failed");
    }

    /// @dev Warns and prompts for confirmation if the deployer nonce is not 0
    function _warnAndConfirmIfDeployerNonceNotZero() internal {
        // Log the check start
        Logger.logCheckStart("Checking deployer nonce...");

        // Get the deployer's nonce
        uint256 nonce = vm.getNonce(_EXPECTED_DEPLOYER_ADDRESS);

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

        string memory response = vm.prompt("Type 'yes' to continue anyway: ");
        string memory trimmedResponse = vm.trim(response);

        require(Strings.equal(trimmedResponse, "yes"), "Deployment cancelled");
    }

    /// @dev Validates that the deployer private key matches the expected address
    /// @param deployerPrivateKey The private key to validate
    function _validateDeployerPrivateKeyOrRevert(uint256 deployerPrivateKey) internal view {
        // Log the check start
        Logger.logCheckStart("Checking deployer private key...");

        // Get the deployer's address
        address deployerAddress = vm.addr(deployerPrivateKey);

        // Case: Deployer address matches expected address
        if (deployerAddress == _EXPECTED_DEPLOYER_ADDRESS) {
            Logger.logCheckPass("Deployer key matches expected address");
            return;
        }

        // Case: Deployer address does not match expected address
        Logger.logCheckFail("Deployer address mismatch");
        Logger.logCheckDetail("Expected: see _EXPECTED_DEPLOYER_ADDRESS constant");
        Logger.logCheckDetail("Got: different address from provided key");

        revert("Deployer address mismatch");
    }
}
