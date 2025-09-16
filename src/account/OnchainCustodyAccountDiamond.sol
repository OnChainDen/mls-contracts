// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../diamond/Diamond.sol";
import "../diamond/interfaces/IDiamondCut.sol";
import { AccountOrganizationAddressStorage } from "./facets/AccountOrganizationAddressStorage.sol";
import "./interfaces/INativeTokenReceivedEventEmitter.sol";

/**
 * @title Onchain Custody Account Diamond
 * @notice Diamond proxy for the OnchainCustodyAccount contract with guardian protection
 * @author Den Technologies Inc
 */
contract OnchainCustodyAccountDiamond is Diamond, INativeTokenReceivedEventEmitter {
    constructor(IDiamondCut.FacetCut[] memory _diamondCut, address _organizationAddress) payable Diamond(_diamondCut) {
        AccountOrganizationAddressStorage.layout().organizationAddress = _organizationAddress;
    }

    /**
     * @inheritdoc INativeTokenReceivedEventEmitter
     */
    receive() external payable override(Diamond, INativeTokenReceivedEventEmitter) {
        emit OnchainCustodyAccountNativeTokenReceived(msg.sender, msg.value);
    }
}
