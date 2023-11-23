// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;


import { UD60x18, ud } from "@prb/math/src/UD60x18.sol";

library WeightMath {

    /// Returns wrapped uint256
    /// V = Sum(Bi**wi)
    function calcVariance(
        UD60x18[] memory amounts,
        UD60x18[] memory weights
    ) internal pure returns(UD60x18) {
        UD60x18 variance = ud(0);
        require(amounts.length == weights.length, "Mistmatch array length");
        for (uint256 i = 0; i < amounts.length; i++) {
            variance = variance + amounts[i].pow(weights[i]);
        }
        return variance;
    }

    function calcSingleDepositLiq(
        UD60x18 supply,
        UD60x18 amount,
        UD60x18 balance,
        UD60x18 weight
    ) internal pure returns(UD60x18) {
        UD60x18 base =  ud(1e18) + amount.div(balance);
        UD60x18 del =  base.pow(weight) - ud(1e18);
        return supply.mul(del);

    }


    function calcSingleWithdrawAsset(
        UD60x18 supply,
        UD60x18 amount,
        UD60x18 balance,
        UD60x18 weight
    ) internal pure returns(UD60x18) {
        UD60x18 base = ud(1e18) - amount.div(supply );
        UD60x18 del = ud(1e18) - base.pow(weight);
        return balance.mul(del);

    }

    //TODO: Deposit of all token
    function checkRationOfAllAsset(
        UD60x18[] memory deposits,
        UD60x18[] memory balances
    ) internal pure returns(UD60x18 ratio) {
        require(deposits.length == balances.length, "Mistmatch array length");
        for (uint256 i = 0; i < balances.length; i++) {
            UD60x18 _r = deposits[i].div(balances[i]);
            if (ratio == ud(0)) {
                ratio = _r;
            } else {
                require(ratio == _r, "Assets not in proportion");
            }
        }
    }


    function calcAllAssetSupplyLiq(
        UD60x18 supply,
        UD60x18[] memory deposits,
        UD60x18[] memory balances
        
    ) internal pure returns(UD60x18 mintable) {
        UD60x18 ration = checkRationOfAllAsset(deposits, balances);
        mintable = supply.mul(ration);
    }


}