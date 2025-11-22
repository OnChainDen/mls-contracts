// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../diamond/Diamond.sol";
import "../diamond/interfaces/IDiamondCut.sol";
import "../diamond/interfaces/IFacetCutsWhitelist.sol";
import "../diamond/libraries/LibDiamond.sol";
import { OrganizationDeployerAddressStorage } from "./facets/OrganizationDeployerAddressStorage.sol";

/**
 * @title Onchain Custody Organization Diamond
 * @notice Diamond proxy for the OnchainCustodyOrganization contract with guardian protection
 * @author Den Technologies Inc
 */
contract OnchainCustodyOrganizationDiamond is Diamond {
    constructor(
        IDiamondCut.FacetCut[] memory _diamondCut,
        address _deployerAddress,
        address _facetWhitelistAddress,
        uint256 whitelistSetId
    )
        payable
        Diamond(_diamondCut, whitelistSetId)
    {
        // Set the deployer address
        OrganizationDeployerAddressStorage.layout().deployerAddress = _deployerAddress;

        // Set the facet whitelist address
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        ds.facetWhitelistAddress = _facetWhitelistAddress;
        ds.contractType = IFacetCutsWhitelist.ContractType.Organization;
    }
}