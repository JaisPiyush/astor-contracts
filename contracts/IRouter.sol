// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IRouter {
    function swapRouterAddress() external view returns(address);


    function swapForExactOutput(address tokenOut, uint256 amountOut) external;


}