// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2026 Den Technologies Inc. All rights reserved.
pragma solidity 0.8.33;

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {IBeacon} from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import {IOrganizationAccountSignature} from "interfaces/organization/IOrganizationAccountSignature.sol";

/**
 * @dev Beacon + organization-signature mock used by account implementation tests.
 */
contract AccountOrganizationBeaconMock is IBeacon, IOrganizationAccountSignature {
    address public beaconImplementation;
    bytes4 public signatureResult = IERC1271.isValidSignature.selector;

    bool public enforceExpectedCall;
    address public expectedAccount;
    bytes32 public expectedHash;
    bytes32 public expectedSignatureHash;

    error UnexpectedSignatureValidationCall();

    constructor(address initialImplementation) {
        beaconImplementation = initialImplementation;
    }

    function implementation() external view returns (address) {
        return beaconImplementation;
    }

    function setImplementation(address newImplementation) external {
        beaconImplementation = newImplementation;
    }

    function setSignatureResult(bytes4 newSignatureResult) external {
        signatureResult = newSignatureResult;
    }

    function setExpectedSignatureValidation(address account, bytes32 hash, bytes calldata signature) external {
        enforceExpectedCall = true;
        expectedAccount = account;
        expectedHash = hash;
        expectedSignatureHash = keccak256(signature);
    }

    function clearExpectedSignatureValidation() external {
        enforceExpectedCall = false;
        expectedAccount = address(0);
        expectedHash = bytes32(0);
        expectedSignatureHash = bytes32(0);
    }

    function isValidSignatureForAccount(address account, bytes32 hash, bytes calldata signature)
        external
        view
        returns (bytes4)
    {
        if (
            enforceExpectedCall
                && (account != expectedAccount || hash != expectedHash || keccak256(signature) != expectedSignatureHash)
        ) {
            revert UnexpectedSignatureValidationCall();
        }
        return signatureResult;
    }
}

/**
 * @dev Target used for call forwarding and gas/value/caller assertions.
 */
contract AccountCallRecorderTarget {
    uint256 public calls;
    uint256 public lastValue;
    address public lastCaller;
    bytes public lastPayload;
    uint256 public observedGas;
    uint256 public returnMarker;

    function record(bytes calldata payload, uint256 marker) external payable returns (bytes32) {
        calls++;
        lastValue = msg.value;
        lastCaller = msg.sender;
        lastPayload = payload;
        observedGas = gasleft();
        returnMarker = marker;
        return keccak256(abi.encodePacked(payload, marker));
    }

    function fail() external pure {
        revert("forced target revert");
    }
}

/**
 * @dev Receiver used by native-transfer tests.
 */
contract AccountNativeReceiver {
    uint256 public totalReceived;
    address public lastSender;

    receive() external payable {
        totalReceived += msg.value;
        lastSender = msg.sender;
    }
}
