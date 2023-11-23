// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { UD60x18, ud } from "@prb/math/src/UD60x18.sol";
import "./WeightMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";



contract IndexToken is ERC20, Ownable {

    address[] public tokens;
    // Weights are wrapped i.e 1e10 decimal places
    mapping(address => UD60x18) public  weights;
    uint256 public lastWeightsUpdateTimestamp;

    address public weightUpdater;
    uint256 private PERMANENT_LIQUIDITY = 1000;


    constructor(
        address initialOwner, 
        string memory name, 
        string memory symbol,
        address[] memory _tokens,
        uint256[] memory _weights
        )
        ERC20(name,symbol)
        Ownable(initialOwner)
    {
        tokens = _tokens;
        for (uint256 i=0; i < _tokens.length; i++) {
            weights[_tokens[i]] = ud(_weights[i]);
        }
        lastWeightsUpdateTimestamp = block.timestamp;
    }

    modifier onlyWeightUpdater {
        require(msg.sender == weightUpdater, "Unauthorized updater");
        _;
    }

    fallback() external payable {
        require(false);
    }

    receive() external payable { 
        require(false);
    }


    function setup(uint256[] memory initAmounts, uint256 initialMintAmount) external onlyOwner {
        address[] memory _tokens = tokens;
        for (uint256 i=0; i < _tokens.length; i++) {
            IERC20(_tokens[i]).transferFrom(msg.sender, address(this), initAmounts[i]);
        }
        _mint(msg.sender, initialMintAmount - PERMANENT_LIQUIDITY);
    } 

    function updateWeightUpdater(address updater) external onlyOwner {
        weightUpdater = updater;
    }

    function getTokens() public view returns(address[] memory _tokens) {
        _tokens = tokens;
    }

    function updateWeights(uint256[] memory _weights) external onlyWeightUpdater  {
        address[] memory _tokens = tokens;
        for(uint256 i = 0; i < _tokens.length; i++) {
            weights[_tokens[i]] = ud(_weights[i]);
        }
        lastWeightsUpdateTimestamp = block.timestamp;
    }

    function tokensLength() external view returns(uint256) {
        return tokens.length;
    }


    function mintAmount(
        address asset,
        uint256 amount
    ) public view returns(UD60x18 liq) {
        UD60x18 weight = weights[asset];
        require(weight != ud(0) && amount > 0, "Asset not supported or zero amount");
        liq = WeightMath.calcSingleDepositLiq(
            ud(totalSupply()),
            ud(amount),
            ud(IERC20(asset).balanceOf(address(this))),
            weight
        );
    }

    function mintAmountAllAsset(
        address asset,
        uint256 amount
    )public view returns(UD60x18 liq) {
        UD60x18 weight = weights[asset];
        require(weight != ud(0) && amount > 0, "Asset not supported or zero amount");
        uint256 balance = IERC20(asset).balanceOf(address(this));
        UD60x18 ratio = ud(amount).div(ud(balance));
        liq = ud(totalSupply()).mul(ratio);
    }

    function burnAmount(
        uint256 amount
    ) public view returns(UD60x18[] memory ) {
        UD60x18[] memory amounts = new UD60x18[](tokens.length);
        UD60x18 ratio = ud(amount).div(ud(totalSupply()));
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20 token = IERC20(tokens[i]);
            UD60x18 assetAmount = ratio.mul(ud(token.balanceOf(address(this))));
            amounts[i] = assetAmount;
        }
        return amounts;
    }

    // Deposit single asset
    function mint(
        address asset,
        address to,
        uint256 amount
    ) external{
        UD60x18 weight = weights[asset];
        require(weight != ud(0) && amount > 0, "Asset not supported or zero amount");
        UD60x18 liq = WeightMath.calcSingleDepositLiq(
            ud(totalSupply()),
            ud(amount),
            ud(IERC20(asset).balanceOf(address(this))),
            weight
        );
        require(IERC20(asset).transferFrom(msg.sender, address(this), amount), "insuf. balance");
        _mint(to, liq.unwrap());
    }



    // Deposit all tokens
    function mint(
        address to,
        uint256[] memory amounts
    ) external{
        UD60x18 supply = ud(totalSupply());
        UD60x18 ration = ud(0);
        require(amounts.length == tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20 token = IERC20(tokens[i]);
            require(amounts[i] > 0, "Zero amount");
            UD60x18 balance = ud(token.balanceOf(address(this)));
            if (ration == ud(0)) {
                ration = ud(amounts[i]).div(balance);
            } else {
                require(ration == ud(amounts[i]).div(balance), "Assets not in proportion");
            }
            require(token.transferFrom(msg.sender, address(this), amounts[i]));
        }
        UD60x18 liq = supply.mul(ration);
        _mint(to, liq.unwrap());
    }



    function burn(
        address to,
        uint256 amount
    ) external  {
        UD60x18 ratio = ud(amount).div(ud(totalSupply()));
        _burn(msg.sender, amount);
        for (uint256 i =0; i < tokens.length; i++) {
            IERC20 token = IERC20(tokens[i]);
            UD60x18 assetAmount = ratio.mul(ud(token.balanceOf(address(this))));
            require(token.transfer(to, assetAmount.unwrap()), "insuf. balance");
        }
    }

}
