// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {BaseDeployScript} from "script/base/BaseDeployScript.sol";
import {Create2Utils} from "script/libraries/Create2Utils.sol";
import {Logger} from "script/libraries/Logger.sol";
import {StringUtils} from "script/libraries/StringUtils.sol";

/// @notice Minimal interface for Safe v1.4.1 functions needed by this script
/// @dev We define this locally rather than importing from the Safe library to avoid
///      compiler version mismatch (Safe uses Solidity 0.7.6, this script uses 0.8.33).
interface ISafe {
    function isModuleEnabled(address module) external view returns (bool);
    function enableModule(address module) external;
    function disableModule(address prevModule, address module) external;
    function getThreshold() external view returns (uint256);
    function getOwners() external view returns (address[] memory);
    function approvedHashes(address owner, bytes32 hash) external view returns (uint256);
    function approveHash(bytes32 hashToApprove) external;
    function nonce() external view returns (uint256);
    function getModulesPaginated(address start, uint256 pageSize)
        external
        view
        returns (address[] memory array, address next);
    function execTransaction(
        address to,
        uint256 value,
        bytes calldata data,
        uint8 operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address payable refundReceiver,
        bytes memory signatures
    ) external payable returns (bool success);
    function getTransactionHash(
        address to,
        uint256 value,
        bytes calldata data,
        uint8 operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address refundReceiver,
        uint256 _nonce
    ) external view returns (bytes32);
}

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
        bytes32 txHash = _getTransactionHash(safeAddress, txData);

        // Get approval info
        uint256 threshold = ISafe(safeAddress).getThreshold();
        address[] memory owners = ISafe(safeAddress).getOwners();
        uint256 approvalCount = _countApprovals(safeAddress, txHash, owners);

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

        // Get the transaction hash
        bytes32 txHash = _getTransactionHash(safeAddress, txData);

        // Get threshold and current approvals
        uint256 threshold = ISafe(safeAddress).getThreshold();
        address[] memory owners = ISafe(safeAddress).getOwners();

        // Log header
        Logger.logBoxHeader(string(abi.encodePacked("Guardian Safe Module Transaction - ", action)));
        Logger.logKeyValue("Guardian Safe", safeAddress);
        Logger.logKeyValue("Module", moduleAddress);
        Logger.logKeyValue("Threshold", threshold);
        Logger.logEmptyLine();

        // Check if sender is an owner
        bool isOwner = false;
        for (uint256 i = 0; i < owners.length; i++) {
            if (owners[i] == msg.sender) {
                isOwner = true;
                break;
            }
        }
        require(isOwner, "Sender is not a Guardian Safe owner");

        // Check if sender has already approved
        bool alreadyApproved = ISafe(safeAddress).approvedHashes(msg.sender, txHash) == 1;

        vm.startBroadcast();

        // Approve if not already done
        if (!alreadyApproved) {
            Logger.logIndented("Submitting approval...");
            ISafe(safeAddress).approveHash(txHash);
            Logger.logIndented("Approval submitted successfully");
        } else {
            Logger.logIndented("Already approved by this owner");
        }

        // Count approvals after our approval (includes the one we just submitted)
        uint256 approvalCount = _countApprovals(safeAddress, txHash, owners);

        Logger.logKeyValue("Approvals after this", approvalCount);

        // Execute if ready and requested
        if (executeIfReady && approvalCount >= threshold) {
            Logger.logEmptyLine();
            Logger.logIndented("Threshold met - executing transaction...");

            // Build signatures from approved hashes
            bytes memory signatures = _buildApprovedSignatures(safeAddress, txHash, owners, threshold);

            // Execute the transaction
            bool success = ISafe(safeAddress)
                .execTransaction(
                    safeAddress, // to (call the Safe itself)
                    0, // value
                    txData, // data
                    0, // operation (0 = Call)
                    0, // safeTxGas
                    0, // baseGas
                    0, // gasPrice
                    address(0), // gasToken
                    payable(address(0)), // refundReceiver
                    signatures // signatures
                );

            require(success, "Transaction execution failed");
            Logger.logIndented("Transaction executed successfully!");
        } else if (approvalCount < threshold) {
            Logger.logEmptyLine();
            Logger.logIndented(
                string(
                    abi.encodePacked(
                        "Need ", StringUtils.toString(threshold - approvalCount), " more approval(s) to execute"
                    )
                )
            );
        }

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

    /// @dev Get the Safe transaction hash
    function _getTransactionHash(address safeAddress, bytes memory txData) internal view returns (bytes32) {
        uint256 safeNonce = ISafe(safeAddress).nonce();
        return ISafe(safeAddress)
            .getTransactionHash(
                safeAddress, // to (call the Safe itself for module management)
                0, // value
                txData, // data
                0, // operation (0 = Call)
                0, // safeTxGas
                0, // baseGas
                0, // gasPrice
                address(0), // gasToken
                address(0), // refundReceiver
                safeNonce // _nonce
            );
    }

    /// @dev Count the number of owners who have approved the hash
    function _countApprovals(address safeAddress, bytes32 txHash, address[] memory owners)
        internal
        view
        returns (uint256 count)
    {
        for (uint256 i = 0; i < owners.length; i++) {
            // slither-disable-next-line calls-loop
            if (ISafe(safeAddress).approvedHashes(owners[i], txHash) == 1) {
                count++;
            }
        }
    }

    /// @dev Build signatures from approved hashes (sorted by owner address)
    function _buildApprovedSignatures(address safeAddress, bytes32 txHash, address[] memory owners, uint256 threshold)
        internal
        view
        returns (bytes memory signatures)
    {
        // Collect approving owners
        address[] memory approvers = new address[](threshold);
        uint256 approverCount = 0;

        for (uint256 i = 0; i < owners.length && approverCount < threshold; i++) {
            // slither-disable-next-line calls-loop
            if (ISafe(safeAddress).approvedHashes(owners[i], txHash) == 1) {
                approvers[approverCount] = owners[i];
                approverCount++;
            }
        }

        require(approverCount >= threshold, "Not enough approvals");

        // Sort approvers by address (ascending) - Safe requires sorted signatures
        for (uint256 i = 0; i < threshold - 1; i++) {
            for (uint256 j = i + 1; j < threshold; j++) {
                if (approvers[i] > approvers[j]) {
                    address temp = approvers[i];
                    approvers[i] = approvers[j];
                    approvers[j] = temp;
                }
            }
        }

        // Build signatures using approved hash signature type
        // For pre-approved hashes: r = owner address, s = 0, v = 1
        signatures = new bytes(threshold * 65);
        for (uint256 i = 0; i < threshold; i++) {
            // r = padded owner address (32 bytes)
            // s = 0 (32 bytes)
            // v = 1 (1 byte) - indicates approved hash
            bytes32 r = bytes32(uint256(uint160(approvers[i])));
            bytes32 s = bytes32(0);
            uint8 v = 1;

            // slither-disable-next-line assembly
            assembly {
                let sigPos := add(signatures, add(32, mul(i, 65)))
                mstore(sigPos, r)
                mstore(add(sigPos, 32), s)
                mstore8(add(sigPos, 64), v)
            }
        }
    }
}
