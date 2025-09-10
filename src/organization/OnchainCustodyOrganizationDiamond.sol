// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../diamond/Diamond.sol";
import "../diamond/interfaces/IDiamondCut.sol";
import "./OrganizationStorage.sol";

/**
 * @title Onchain Custody Organization Diamond
 * @notice Diamond proxy for the OnchainCustodyOrganization contract with guardian protection
 * @author Den Technologies Inc
 */
contract OnchainCustodyOrganizationDiamond is Diamond {
    constructor(IDiamondCut.FacetCut[] memory _diamondCut, address _deployerAddress) payable Diamond(_diamondCut) {
        // Set the deployer address
        OrganizationStorage.layout().deployerAddress = _deployerAddress;
    }
}
