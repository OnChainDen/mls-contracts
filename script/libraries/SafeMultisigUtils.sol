// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ISafe} from "@safe/interfaces/ISafe.sol";
import {SafeProxyFactory} from "@safe/proxies/SafeProxyFactory.sol";
import {Vm} from "forge-std/Vm.sol";

import {DeploymentConfig} from "script/config/DeploymentConfig.sol";
import {ArrayUtils} from "script/libraries/ArrayUtils.sol";
import {Create2Utils} from "script/libraries/Create2Utils.sol";
import {Logger} from "script/libraries/Logger.sol";
import {SafeInfrastructure} from "script/libraries/Types.sol";

/**
 * @title SafeMultisigUtils
 * @notice Helper library for Safe multisig deployment and configuration in deployment scripts
 * @dev Contains utilities for deploying and validating Safe multisig wallets
 * @author Den Technologies Inc
 */
library SafeMultisigUtils {
    /// @dev Deploys a Safe multisig wallet using SafeProxyFactory
    /// @param safeInfra Safe infrastructure addresses needed for Safe deployment
    /// @param ownerAddresses Array of owner addresses for the Safe
    /// @param threshold Required number of signatures for transactions
    /// @param salt Salt used for deterministic address computation
    /// @param name Human-readable name for logging purposes
    /// @return safeAddress Address of the deployed Safe proxy
    function deploySafeMultisig(
        SafeInfrastructure memory safeInfra,
        address[] memory ownerAddresses,
        uint256 threshold,
        bytes32 salt,
        string memory name
    ) internal returns (address safeAddress) {
        // Encode the initializer for Safe.setup()
        bytes memory initializer = abi.encodeCall(
            ISafe.setup,
            (
                // owners
                ownerAddresses,
                // threshold
                threshold,
                // to - no delegate call
                address(0),
                // data - no delegate call data
                "",
                // fallbackHandler
                safeInfra.fallbackHandlerAddress,
                // paymentToken - ETH
                address(0),
                // payment - no payment
                0,
                // paymentReceiver
                payable(address(0))
            )
        );

        // Compute the salt nonce
        uint256 saltNonce = uint256(salt);

        // Compute expected address using SafeProxyFactory's CREATE2 formula
        safeAddress = computeSafeProxyAddress(safeInfra, initializer, saltNonce);

        // Check if already deployed
        if (Create2Utils.isContractDeployedAtAddress(safeAddress)) {
            Logger.logDeploymentSkipped(name, safeAddress);
            return safeAddress;
        }

        // Deploy the Safe
        address deployedAtAddress = address(
            SafeProxyFactory(safeInfra.proxyFactoryAddress)
                .createProxyWithNonce(safeInfra.singletonAddress, initializer, saltNonce)
        );
        Logger.logDeployed(name, deployedAtAddress);

        // Verify deployment matches expected address
        require(deployedAtAddress == safeAddress, "Safe deployed at unexpected address");
    }

    /// @dev Validates Safe configurations and prompts for user confirmation
    /// @param vm The Forge VM instance for prompting
    /// @param guardianOwners Guardian Safe owners from env
    /// @param guardianThreshold Guardian Safe threshold from env
    /// @param deployerOwners Deployer Safe owners from env
    /// @param deployerThreshold Deployer Safe threshold from env
    function validateSafeConfigsAndConfirm(
        Vm vm,
        address[] memory guardianOwners,
        uint256 guardianThreshold,
        address[] memory deployerOwners,
        uint256 deployerThreshold
    ) internal {
        bool guardianIsProd = isProductionGuardianConfig(guardianOwners, guardianThreshold);
        bool deployerIsProd = isProductionDeployerConfig(deployerOwners, deployerThreshold);

        Logger.logWarn("Safe configuration confirmation required");
        if (guardianIsProd) {
            Logger.logIndented("Guardian Safe: PRODUCTION configuration");
        } else {
            Logger.logIndented("Guardian Safe: NON-PRODUCTION configuration");
        }

        if (deployerIsProd) {
            Logger.logIndented("Deployer Safe: PRODUCTION configuration");
        } else {
            Logger.logIndented("Deployer Safe: NON-PRODUCTION configuration");
        }
        Logger.logEmptyLine();

        string memory mode = guardianIsProd && deployerIsProd ? "PRODUCTION" : "NON-PRODUCTION";
        string memory prompt =
            string(abi.encodePacked("Type 'yes' to confirm you want to deploy with ", mode, " configuration: "));
        string memory response = vm.prompt(prompt);
        string memory trimmedResponse = vm.trim(response);
        if (!Strings.equal(trimmedResponse, "yes")) {
            revert("Deployment aborted: confirmation not received");
        }
    }

    /// @dev Computes the deterministic address of a Safe proxy before deployment
    /// @param safeInfra Safe infrastructure addresses needed for address computation
    /// @param initializer Encoded Safe.setup() call data
    /// @param saltNonce Nonce used for salt computation
    /// @return The predicted Safe proxy address
    function computeSafeProxyAddress(SafeInfrastructure memory safeInfra, bytes memory initializer, uint256 saltNonce)
        internal
        view
        returns (address)
    {
        // SafeProxyFactory computes salt as: keccak256(abi.encodePacked(keccak256(initializer), saltNonce))
        bytes32 salt = keccak256(abi.encodePacked(keccak256(initializer), saltNonce));

        // Get the init code hash from the factory (includes singleton address)
        bytes32 initCodeHash =
            SafeProxyFactory(safeInfra.proxyFactoryAddress).proxyCreationCodehash(safeInfra.singletonAddress);

        // Use OpenZeppelin's Create2 utility for address computation
        return Create2.computeAddress(salt, initCodeHash, safeInfra.proxyFactoryAddress);
    }

    /// @dev Retrieves Guardian Safe configuration from environment variables
    /// @param vm The Forge VM instance for reading environment variables
    /// @return ownerAddresses Array of owner addresses for the Guardian Safe
    /// @return threshold Required number of signatures
    function getGuardianSafeConfig(Vm vm) internal view returns (address[] memory ownerAddresses, uint256 threshold) {
        ownerAddresses = vm.envAddress("GUARDIAN_SAFE_OWNERS", ",");
        threshold = vm.envUint("GUARDIAN_SAFE_THRESHOLD");
    }

    /// @dev Retrieves Deployer Safe configuration from environment variables
    /// @param vm The Forge VM instance for reading environment variables
    /// @return ownerAddresses Array of owner addresses for the Deployer Safe
    /// @return threshold Required number of signatures
    function getDeployerSafeConfig(Vm vm) internal view returns (address[] memory ownerAddresses, uint256 threshold) {
        ownerAddresses = vm.envAddress("DEPLOYER_SAFE_OWNERS", ",");
        threshold = vm.envUint("DEPLOYER_SAFE_THRESHOLD");
    }

    /// @dev Checks if the provided Guardian Safe config matches production
    /// @param owners Guardian Safe owner addresses from environment
    /// @param threshold Guardian Safe threshold from environment
    /// @return True if owners and threshold match production configuration
    function isProductionGuardianConfig(address[] memory owners, uint256 threshold) internal pure returns (bool) {
        if (threshold != DeploymentConfig.PROD_GUARDIAN_SAFE_THRESHOLD) {
            return false;
        }

        address[] memory prodOwners = DeploymentConfig.getProdGuardianSafeOwners();
        return ArrayUtils.equal(owners, prodOwners);
    }

    /// @dev Checks if the provided Deployer Safe config matches production
    /// @param owners Deployer Safe owner addresses from environment
    /// @param threshold Deployer Safe threshold from environment
    /// @return True if owners and threshold match production configuration
    function isProductionDeployerConfig(address[] memory owners, uint256 threshold) internal pure returns (bool) {
        if (threshold != DeploymentConfig.PROD_DEPLOYER_SAFE_THRESHOLD) {
            return false;
        }

        address[] memory prodOwners = DeploymentConfig.getProdDeployerSafeOwners();
        return ArrayUtils.equal(owners, prodOwners);
    }
}
