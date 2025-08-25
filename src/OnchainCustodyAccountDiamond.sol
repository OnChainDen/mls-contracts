// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./diamond/Diamond.sol";
import "./diamond/interfaces/IDiamondCut.sol";

/**
 * @title Onchain Custody Account Diamond
 * @notice Diamond proxy for the OnchainCustodyAccount contract with guardian protection
 * @author Den Technologies Inc
 */
contract OnchainCustodyAccountDiamond is Diamond {
    constructor(
        IDiamondCut.FacetCut[] memory _diamondCut,
        Diamond.DiamondArgs memory _args
    )
        payable
        Diamond(_diamondCut, _args)
    { }
}
