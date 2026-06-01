// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {BaseDeployScript} from "script/base/BaseDeployScript.sol";
import {Create2Utils} from "script/libraries/Create2Utils.sol";
import {ISafe} from "script/libraries/ISafe.sol";
import {Logger} from "script/libraries/Logger.sol";
import {SafeTransactionUtils} from "script/libraries/SafeTransactionUtils.sol";
import {StringUtils} from "script/libraries/StringUtils.sol";

/**
 * @title ManageGuardianSafeModule
 * @notice Script for Guardian Safe owners to approve and execute module add/remove transactions
 * @dev Uses onchain approvals (approveHash) instead of offchain signatures.
 *
 *      For adding the module:
 *        forge script script/safe-module/ManageGuardianSafeModule.s.sol:ManageGuardianSafeModule \
 *          --sig "addModule(address,bool)" <FACTORY_ADDRESS> <EXECUTE_IF_READY> \
 *          --rpc-url $RPC_URL \
 *          --broadcast \
 *          -vvvv
 *
 *      For removing the module:
 *        forge script script/safe-module/ManageGuardianSafeModule.s.sol:ManageGuardianSafeModule \
 *          --sig "removeModule(address,bool)" <FACTORY_ADDRESS> <EXECUTE_IF_READY> \
 *          --rpc-url $RPC_URL \
 *          --broadcast \
 *          -vvvv
 *
 *      Where:
 *        - FACTORY_ADDRESS: The CREATE2 factory used for deployment (to lookup addresses)
 *        - EXECUTE_IF_READY: true to execute if threshold is met after approval
 *
 * @author Den Technologies Inc
 */
contract ManageGuardianSafeModule is BaseDeployScript {
    /**
     * @notice Approve and optionally execute adding the module to the Guardian Safe
     * @param factoryAddress The CREATE2 factory address (to lookup Guardian Safe/module addresses)
     * @param executeIfReady If true, execute the transaction if threshold is met after approval
     */
    function addModule(address factoryAddress, bool executeIfReady) external {
        // Initialize and validate the factory
        validateAndInitializeFactoryOrRevert(factoryAddress);

        // Get Guardian Safe and module addresses
        (address safeAddress, address moduleAddress) = _getAddresses();

        // Validate the Safe and module are deployed
        require(Create2Utils.isContractDeployedAtAddress(safeAddress), "Guardian Safe not deployed");
        require(Create2Utils.isContractDeployedAtAddress(moduleAddress), "Guardian Safe module not deployed");

        // Check module is not already enabled
        require(!ISafe(safeAddress).isModuleEnabled(moduleAddress), "Module already enabled");

        // Build the transaction data for enableModule
        bytes memory txData = abi.encodeWithSelector(ISafe.enableModule.selector, moduleAddress);

        // Process the transaction
        _processTransaction(safeAddress, moduleAddress, txData, "ADD", executeIfReady);
    }

    /**
     * @notice Approve and optionally execute removing the module from the Guardian Safe
     * @param factoryAddress The CREATE2 factory address (to lookup Guardian Safe/module addresses)
     * @param executeIfReady If true, execute the transaction if threshold is met after approval
     */
    function removeModule(address factoryAddress, bool executeIfReady) external {
        // Initialize and validate the factory
        validateAndInitializeFactoryOrRevert(factoryAddress);

        // Get Guardian Safe and module addresses
        (address safeAddress, address moduleAddress) = _getAddresses();

        // Validate the Safe is deployed
        require(Create2Utils.isContractDeployedAtAddress(safeAddress), "Guardian Safe not deployed");

        // Check module is currently enabled
        require(ISafe(safeAddress).isModuleEnabled(moduleAddress), "Module not enabled");

        // Find the previous module in the linked list
        address prevModule = _findPrevModule(safeAddress, moduleAddress);

        // Build the transaction data for disableModule
        bytes memory txData = abi.encodeWithSelector(ISafe.disableModule.selector, prevModule, moduleAddress);

        // Process the transaction
        _processTransaction(safeAddress, moduleAddress, txData, "REMOVE", executeIfReady);
    }

    /**
     * @notice Check the approval status for a module transaction on the Guardian Safe
     * @param factoryAddress The CREATE2 factory address
     * @param action "add" or "remove"
     */
    function checkStatus(address factoryAddress, string calldata action) external {
        // Initialize and validate the factory
        validateAndInitializeFactoryOrRevert(factoryAddress);

        // Get Guardian Safe and module addresses
        (address safeAddress, address moduleAddress) = _getAddresses();

        // Build the transaction data
        // slither-disable-next-line uninitialized-local
        bytes memory txData;
        if (keccak256(bytes(action)) == keccak256("add")) {
            txData = abi.encodeWithSelector(ISafe.enableModule.selector, moduleAddress);
        } else if (keccak256(bytes(action)) == keccak256("remove")) {
            address prevModule = _findPrevModule(safeAddress, moduleAddress);
            txData = abi.encodeWithSelector(ISafe.disableModule.selector, prevModule, moduleAddress);
        } else {
            revert("Invalid action - must be 'add' or 'remove'");
        }

        // Get the transaction hash
        bytes32 txHash = SafeTransactionUtils.getTransactionHash(ISafe(safeAddress), safeAddress, txData, 0);

        // Get approval info
        uint256 threshold = ISafe(safeAddress).getThreshold();
        address[] memory owners = ISafe(safeAddress).getOwners();
        uint256 approvalCount = SafeTransactionUtils.countApprovals(ISafe(safeAddress), txHash, owners);

        // Log status
        Logger.logBoxHeader("Guardian Safe Module Transaction Status");
        Logger.logKeyValue("Guardian Safe", safeAddress);
        Logger.logKeyValue("Module", moduleAddress);
        Logger.logKeyValue("Action", action);
        Logger.logKeyValue("Threshold", threshold);
        Logger.logKeyValue("Approvals", approvalCount);
        Logger.logEmptyLine();

        if (approvalCount >= threshold) {
            Logger.logIndented("Status: READY TO EXECUTE");
        } else {
            Logger.logIndented(
                string(
                    abi.encodePacked(
                        "Status: NEEDS ", StringUtils.toString(threshold - approvalCount), " MORE APPROVAL(S)"
                    )
                )
            );
        }

        Logger.logEmptyLine();
        Logger.logIndented("Owners who have approved:");
        for (uint256 i = 0; i < owners.length; i++) {
            // slither-disable-next-line calls-loop
            if (ISafe(safeAddress).approvedHashes(owners[i], txHash) == 1) {
                Logger.logKeyValue("  ", owners[i]);
            }
        }
        Logger.logBoxFooter();
    }

    /// @dev Process a module transaction (approve and optionally execute)
    function _processTransaction(
        address safeAddress,
        address moduleAddress,
        bytes memory txData,
        string memory action,
        bool executeIfReady
    ) internal {
        // Prompt for confirmation when running with --broadcast
        confirmBroadcastOrDryRun("ManageGuardianSafeModule");

        // Log header
        Logger.logBoxHeader(string(abi.encodePacked("Guardian Safe Module Transaction - ", action)));
        Logger.logKeyValue("Guardian Safe", safeAddress);
        Logger.logKeyValue("Module", moduleAddress);
        Logger.logKeyValue("Threshold", ISafe(safeAddress).getThreshold());
        Logger.logEmptyLine();

        // Approve (and optionally execute) the Safe transaction (module management targets the Safe itself, Call)
        vm.startBroadcast();
        SafeTransactionUtils.approveAndExecuteIfReady({
            safe: ISafe(safeAddress), to: safeAddress, data: txData, operation: 0, executeIfReady: executeIfReady
        });
        vm.stopBroadcast();

        Logger.logBoxFooter();
    }

    /// @dev Get Guardian Safe and module addresses from deployment.toml
    function _getAddresses() internal returns (address safeAddress, address moduleAddress) {
        safeAddress = getExpectedGuardianSafeAddress();
        moduleAddress = getExpectedGuardianSafeModuleAddress();
    }

    /// @dev Find the previous module in the linked list (needed for disableModule).
    ///      This function only checks the first page of 100 modules. The Guardian Safe
    ///      will never have more than a handful of modules, so pagination is unnecessary.
    function _findPrevModule(address safeAddress, address moduleAddress) internal view returns (address prevModule) {
        // SENTINEL_MODULES = address(0x1)
        address sentinel = address(0x1);
        (address[] memory modules,) = ISafe(safeAddress).getModulesPaginated(sentinel, 100);

        prevModule = sentinel;
        for (uint256 i = 0; i < modules.length; i++) {
            if (modules[i] == moduleAddress) {
                return prevModule;
            }
            prevModule = modules[i];
        }
        revert("Module not found in Guardian Safe");
    }
}
