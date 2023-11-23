// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { UD60x18} from "@prb/math/src/UD60x18.sol";

interface IIndexToken is IERC20 {
    function setup(uint256[] memory initAmounts, uint256 initialMintAmount) external;
    function updateWeightUpdater(address updater) external;
    function getTokens() external view returns(address[] memory _tokens);
    function weights(address token) external view returns(UD60x18);
    function updateWeights(uint256[] memory _weights) external;
    function tokensLength() external view returns(uint256);
    function mintAmount(
        address asset,
        uint256 amount
    ) external view returns(UD60x18 liq);
    function mintAmountAllAsset(
        address asset,
        uint256 amount
    ) external view returns(UD60x18 liq);
    function burnAmount(
        uint256 amount
    ) external view returns(UD60x18[] memory );
    function mint(
        address asset,
        address to,
        uint256 amount
    ) external;
    function mint(
        address to,
        uint256[] memory amounts
    ) external;
    function burn(
        address to,
        uint256 amount
    ) external;

}
