// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Script} from "forge-std/Script.sol";

import {DeploymentConfig} from "script/config/DeploymentConfig.sol";
import {Create2Deployer} from "script/libraries/Create2Deployer.sol";
import {Logger} from "script/libraries/Logger.sol";

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
 *      3. Requires explicit CONFIRM_DEPLOYMENT=true environment variable
 *      4. Runs in dry-run mode by default
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
        Create2Deployer.logFactoryDeploymentHeader("Safe Singleton Factory");

        // Check if deployment is confirmed
        bool confirmDeployment = vm.envOr("CONFIRM_DEPLOYMENT", false);

        // Run all safety checks
        bool allChecksPassed = _runSafetyChecks();

        if (!allChecksPassed) {
            Create2Deployer.logSafetyChecksFailed();
            revert("Safety checks failed");
        }

        if (!confirmDeployment) {
            // forgefmt: disable-next-item
            Create2Deployer.logDryRunMode(
                "DeploySafeSingletonFactory",
                "WARNING: This will use nonce 0 of the deployer account. Make sure this is the correct chain."
            );
            return;
        }

        Create2Deployer.logSection("DEPLOYING SAFE SINGLETON FACTORY");

        // Get the deployer private key
        uint256 deployerPrivateKey = vm.envUint("SAFE_FACTORY_DEPLOYER_PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        // Final verification that deployer matches expected
        if (deployerAddress != _EXPECTED_DEPLOYER_ADDRESS) {
            Logger.logFail("ERROR: Deployer address mismatch!");
            Logger.logIndented("Expected:");
            Logger.logKeyAddress("  ", _EXPECTED_DEPLOYER_ADDRESS);
            Logger.logIndented("Got:");
            Logger.logKeyAddress("  ", deployerAddress);
            revert("Deployer address does not match expected address");
        }

        vm.startBroadcast(deployerPrivateKey);

        _deployFactory();

        vm.stopBroadcast();

        // Verify deployment
        if (!Create2Deployer.isContractDeployedAtAddress(_EXPECTED_FACTORY_ADDRESS)) {
            Logger.logFail("ERROR: Factory deployment failed!");
            revert("Factory deployment failed");
        }

        Create2Deployer.logFactoryDeploymentSuccess("Safe Singleton Factory", _EXPECTED_FACTORY_ADDRESS);
    }

    /// @notice Funds the Safe Singleton Factory deployer address with ETH
    /// @dev Can be called separately to fund the deployer before running the main script.
    ///      Requires PRIVATE_KEY environment variable to be set for the funding account.
    function fundDeployer() external {
        uint256 fundingPrivateKey = vm.envUint("PRIVATE_KEY");

        Logger.logEmptyLine();
        Logger.logIndented("Funding Safe Singleton Factory deployer...");
        Logger.logKeyAddress("Target", _EXPECTED_DEPLOYER_ADDRESS);
        Logger.logKeyUint("Amount (wei)", _REQUIRED_ETH_BALANCE);
        Logger.logEmptyLine();

        vm.startBroadcast(fundingPrivateKey);
        payable(_EXPECTED_DEPLOYER_ADDRESS).transfer(_REQUIRED_ETH_BALANCE);
        vm.stopBroadcast();

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

        require(deployedAtAddress != address(0), "Factory deployment failed");

        // The address should match due to CREATE from nonce 0
        if (deployedAtAddress != _EXPECTED_FACTORY_ADDRESS) {
            Logger.logKeyAddress("Deployed at", deployedAtAddress);
            Logger.logKeyAddress("Expected", _EXPECTED_FACTORY_ADDRESS);
            revert("Deployed address does not match expected factory address");
        }
    }

    /// @dev Runs all safety checks before deployment
    ///      Checks: Arachnid not present, factory not deployed, deployer key valid, nonce is 0, sufficient ETH
    /// @return passed True if all critical checks pass
    function _runSafetyChecks() internal view returns (bool passed) {
        Logger.logSafetyChecksStart();

        bool allPassed = true;

        // Check 0: Arachnid factory should NOT exist (prefer Arachnid over SafeSingleton)
        Logger.logCheckStart("0/4", "Checking if Arachnid factory exists...");
        if (Create2Deployer.isContractDeployedAtAddress(DeploymentConfig.ARACHNID_CREATE2_FACTORY_ADDRESS)) {
            Logger.logCheckFail("Arachnid factory already deployed");
            Logger.logCheckDetail("Use Arachnid factory instead of Safe Singleton Factory.");
            Logger.logCheckDetail("Set CREATE2_FACTORY_ADDRESS to the Arachnid factory address.");
            allPassed = false;
        } else {
            Logger.logCheckPass("Arachnid factory not present (Safe Singleton Factory needed)");
        }

        // Check 1: Safe Singleton Factory not already deployed
        if (Create2Deployer.checkFactoryNotDeployed(_EXPECTED_FACTORY_ADDRESS, "Safe Singleton Factory", "1/4")) {
            // Factory already deployed - not a failure, but deployment not needed
            // However for Safe, we treat this as a failure since the factory existing means nothing to do
            Logger.logCheckFail("Factory already deployed");
            allPassed = false;
        }

        // Check 2: Deployer private key provided and matches expected address
        Logger.logCheckStart("2/4", "Checking deployer private key...");
        try vm.envUint("SAFE_FACTORY_DEPLOYER_PRIVATE_KEY") returns (uint256 pk) {
            address deployerAddress = vm.addr(pk);
            if (deployerAddress == _EXPECTED_DEPLOYER_ADDRESS) {
                Logger.logCheckPass("Deployer key matches expected address");
            } else {
                Logger.logCheckFail("Deployer address mismatch");
                Logger.logCheckDetail("Expected: see _EXPECTED_DEPLOYER_ADDRESS constant");
                Logger.logCheckDetail("Got: different address from provided key");
                allPassed = false;
            }
        } catch {
            Logger.logCheckFail("SAFE_FACTORY_DEPLOYER_PRIVATE_KEY not set");
            allPassed = false;
        }

        // Check 3: Deployer nonce is 0
        Logger.logCheckStart("3/4", "Checking deployer nonce...");
        uint256 nonce = vm.getNonce(_EXPECTED_DEPLOYER_ADDRESS);
        if (nonce == 0) {
            Logger.logCheckPass("Deployer nonce is 0");
        } else {
            Logger.logCheckFail("Deployer nonce is not 0 (expected 0)");
            Logger.logCheckDetail("CRITICAL: Nonce has been burned! Cannot deploy factory.");
            allPassed = false;
        }

        // Check 4: Deployer has sufficient ETH (warning only, not a failure)
        Logger.logCheckStart("4/4", "Checking deployer ETH balance...");
        uint256 balance = _EXPECTED_DEPLOYER_ADDRESS.balance;
        if (balance >= _REQUIRED_ETH_BALANCE) {
            Logger.logCheckPass("Deployer has sufficient ETH");
        } else {
            Logger.logCheckWarn("Deployer may need more ETH");
            Logger.logCheckDetail("Current balance may be insufficient.");
            Logger.logCheckDetail("Recommended: fund deployer before proceeding.");
            // This is a warning, not a failure
        }

        return allPassed;
    }
}
