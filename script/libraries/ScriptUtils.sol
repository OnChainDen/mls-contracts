// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Vm, VmSafe} from "forge-std/Vm.sol";

import {DeploymentConfig} from "script/config/DeploymentConfig.sol";
import {Logger} from "script/libraries/Logger.sol";

/**
 * @title ScriptUtils
 * @dev Helpers for Foundry deployment scripts.
 *
 *      NOTE: Foundry's console.log output is buffered and only displayed after script execution,
 *      but vm.prompt displays immediately. Therefore, any context that needs to be visible
 *      before user confirmation MUST be embedded in the prompt message itself.
 */
library ScriptUtils {
    /**
     * @dev Prompts the user for confirmation with context and reverts if they don't type "yes".
     * @param vm The Foundry Vm cheatcode instance
     * @param context Context message to display before the prompt (will be shown immediately)
     */
    function promptForConfirmationOrRevert(Vm vm, string memory context) internal {
        // Build prompt with context embedded so it displays immediately
        // NOTE: console.log output is buffered, but vm.prompt displays immediately
        string memory promptMessage = string.concat(context, "\nType 'yes' to continue: ");
        string memory response = vm.prompt(promptMessage);
        string memory trimmedResponse = vm.trim(response);
        require(Strings.equal(trimmedResponse, "yes"), "Confirmation not received");
    }

    /**
     * @dev Logs the execution mode (broadcast or dry run) and prompts the user for confirmation
     *      when broadcasting.
     * @param vm The Foundry Vm cheatcode instance
     * @param scriptName Human-readable script name for logging
     */
    function confirmBroadcastOrDryRun(Vm vm, string memory scriptName) internal {
        // Case: the script is being run with the --broadcast flag
        // Log the broadcast mode and prompt for confirmation
        if (vm.isContext(VmSafe.ForgeContext.ScriptBroadcast)) {
            // Build the context message with all info embedded
            // solhint-disable-next-line func-named-parameters
            string memory context = string.concat(
                "\n",
                "  !! BROADCAST MODE DETECTED !!\n",
                "  Script: ",
                scriptName,
                "\n",
                "  Transactions WILL be sent to the network."
            );

            promptForConfirmationOrRevert(vm, context);
            Logger.logEmptyLine();
        } else {
            // Case: the script is being run with the --dry-run flag
            // Log that we're in dry run mode
            Logger.logInfo("DRY RUN MODE - No transactions will be broadcast");
            Logger.logEmptyLine();
        }
    }

    /**
     * @dev Logs whether a production chain is detected and prompts for confirmation if so.
     * @param vm The Foundry Vm cheatcode instance
     * @param scriptName Human-readable script name for logging
     */
    function warnAndConfirmIfProductionChain(Vm vm, string memory scriptName) internal {
        // Determine if the chain is a production chain
        bool isProductionChain = DeploymentConfig.isProductionChain(block.chainid);

        // Case: the chain is a production chain
        // Prompt for confirmation with embedded context
        if (isProductionChain) {
            // Build the context message with all info embedded
            // solhint-disable-next-line func-named-parameters
            string memory context = string.concat(
                "\n",
                "  !! PRODUCTION CHAIN DETECTED !!\n",
                "  Script: ",
                scriptName,
                "\n",
                "  Chain ID: ",
                Strings.toString(block.chainid)
            );

            promptForConfirmationOrRevert(vm, context);
            Logger.logEmptyLine();
        } else {
            // Case: the chain is a non-production chain
            // Log that we're on a non-production chain (no confirmation needed)
            Logger.logInfo("NON-PRODUCTION CHAIN DETECTED");
            Logger.logKeyValue("Script", scriptName);
            Logger.logKeyValue("Chain ID", block.chainid);
            Logger.logEmptyLine();
        }
    }
}
