// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../diamond/Diamond.sol";
import "../diamond/interfaces/IDiamondCut.sol";
import "../diamond/interfaces/IFacetCutsWhitelist.sol";
import "../diamond/libraries/LibDiamond.sol";
import { AccountOrganizationAddressStorage } from "./facets/AccountOrganizationAddressStorage.sol";
import "./interfaces/INativeTokenReceivedEventEmitter.sol";

/**
 * @title Onchain Custody Account Diamond
 * @notice Diamond proxy for the OnchainCustodyAccount contract with guardian protection
 * @author Den Technologies Inc
 */
contract OnchainCustodyAccountDiamond is Diamond, INativeTokenReceivedEventEmitter {
    constructor(
        IDiamondCut.FacetCut[] memory _diamondCut,
        address _organizationAddress,
        address _facetWhitelistAddress,
        uint256 whitelistSetId
    )
        payable
        Diamond(_diamondCut, whitelistSetId)
    {
        AccountOrganizationAddressStorage.layout().organizationAddress = _organizationAddress;

        // Set the facet whitelist address
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        ds.facetWhitelistAddress = _facetWhitelistAddress;
        ds.contractType = IFacetCutsWhitelist.ContractType.Account;
    }

    /**
     * @inheritdoc INativeTokenReceivedEventEmitter
     */
    receive() external payable override(Diamond, INativeTokenReceivedEventEmitter) {
        emit OnchainCustodyAccountNativeTokenReceived(msg.sender, msg.value);
    }
}
