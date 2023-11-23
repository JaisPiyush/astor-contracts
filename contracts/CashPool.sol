// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;


import { UD60x18, ud } from "@prb/math/src/UD60x18.sol";
import "./WeightMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./IIndexToken.sol";
import "./IRouter.sol";

contract CashPool is Ownable {

    event StartSettlement(uint256 indexed nonce);
    event Exchanged(uint256 indexed nonce, bool indexed finished, address[] tokens, uint256 baseTokenLeft);
    event FinishSettlement(uint256 indexed nonce);


    IERC20 public baseToken;
    IIndexToken public indexToken;

    uint256 public currentTxnNonce = 0;
    address public automationOracle;

    struct UserDetail {
        address addr;
        UD60x18 baseTokenAmount;
        bool isCreated;
        bool isPaid;
    }

    mapping(uint256 => bool) public txnNonceRecord;

    // Base token pooled in each txn
    mapping(uint256 => UD60x18) public pooledBaseTokenAmountPerNonce;
    // Amount of token exchanged in each txn
    mapping(uint256 => UD60x18) public exchnagedIndexTokenPerNonce;
    // Amount of index token which are unclaimed in each nonce
    mapping(uint256 => UD60x18) public unclaimedIndexTokenPerNonce;
    // Amount of base token unclaimed per nonce
    mapping(uint256 => UD60x18) public unclaimedBaseTokenPerNonce;
    // Nonce of each address which are yet no claimed
    mapping(address => uint256[]) public userUnclaimedNonce;
    mapping(uint256 => mapping(address => UserDetail)) public userContributionPerNonce;
    mapping(uint256 => uint256) public assetsExchangedPerNonce;
    // Routers for swap
    address[] public approvedRouters;
    


    modifier validTxnNonce(uint256 nonce) {
        require(txnNonceRecord[nonce], "invalid txn Nonce");
        _;
    }

    modifier validAndSettledNonce(uint256 nonce) {
        require(txnNonceRecord[nonce], "invalid txn Nonce");
        require(nonce < currentTxnNonce, "nonce not settled yet");
        _;
    }

    modifier onlyAutomationOracle {
        require(msg.sender == automationOracle, "Uauthorized");
        _;
    }



    constructor(address owner, address _baseToken, address _indexToken)
    Ownable(owner)
    {
        baseToken = IERC20(_baseToken);
        indexToken = IIndexToken(_indexToken);
        txnNonceRecord[currentTxnNonce] = true;
        automationOracle = owner;
    }

    function setAutomationOracel(address oracle) external onlyOwner {
        automationOracle = oracle;
    }


    function getUserBalanceInCurrentNonce(address user) external  view returns(UD60x18) {
        return userContributionPerNonce[currentTxnNonce][user].baseTokenAmount;
    }

    function _getCollectableIndexTokenOfUserForNonce(address user, uint256 nonce) internal view returns(UD60x18) {
        UserDetail memory detail = userContributionPerNonce[nonce][user];
        if (detail.isPaid) {
            return ud(0);
        }
        UD60x18 pooledBaseToken = pooledBaseTokenAmountPerNonce[nonce];
        UD60x18 indexTokenPerNonce = exchnagedIndexTokenPerNonce[nonce];
        UD60x18 indexTokenShare = detail.baseTokenAmount.mul(indexTokenPerNonce.div(pooledBaseToken));
        return indexTokenShare;
    }

    function getCollectableIndexTokenOfUserForNonce(address user, uint256 nonce) external view returns(UD60x18) {
        return _getCollectableIndexTokenOfUserForNonce(user, nonce);
    }

    function getCollectableIndexTokenOfUser(address user) external view returns(UD60x18) {
        if (currentTxnNonce == 0) {
            return ud(0);
        }
        return _getCollectableIndexTokenOfUserForNonce(user, currentTxnNonce);
    }

    function addRouter(address router) external onlyOwner {
        address[] memory tokens = indexToken.getTokens();
        for(uint256 i = 0; i < tokens.length; i++) {
            IERC20(tokens[i]).approve(router, type(uint256).max);
        }
        approvedRouters.push(router);
    }

    function depositFrom(address from, address to, uint256 amount) public {
        baseToken.transferFrom(from, to, amount);
        UserDetail memory detail = userContributionPerNonce[currentTxnNonce][to];
        if (!detail.isCreated) {
            detail.addr = to;
            detail.baseTokenAmount = ud(0);
            detail.isCreated = true;
        }
        UD60x18 _amount = ud(amount);
        detail.baseTokenAmount = detail.baseTokenAmount + _amount;
        userContributionPerNonce[currentTxnNonce][to] = detail;
        pooledBaseTokenAmountPerNonce[currentTxnNonce] = pooledBaseTokenAmountPerNonce[currentTxnNonce] + _amount;
        userUnclaimedNonce[to].push(currentTxnNonce);

    }

    function withdraw(address to, uint256 amount) external {
        UserDetail memory detail = userContributionPerNonce[currentTxnNonce][msg.sender];
        if (!detail.isCreated) {
            return;
        }
        UD60x18 _amount = ud(amount);
        require(detail.baseTokenAmount < _amount, "Amount overflow");
        detail.baseTokenAmount = detail.baseTokenAmount - _amount;
        if (detail.baseTokenAmount == ud(0)) {
            detail.isCreated = false;
            _removeTxnNonceFromUserInnerTxn(msg.sender, currentTxnNonce);
        }
        userContributionPerNonce[currentTxnNonce][msg.sender] = detail;
        pooledBaseTokenAmountPerNonce[currentTxnNonce] = pooledBaseTokenAmountPerNonce[currentTxnNonce] - _amount;
        baseToken.transfer(to, amount);
        

    }

    function deposit(address to, uint256 amount) external {
        depositFrom(msg.sender, to, amount);
    }

    function _collect(uint256 txnNonce, address from, address to) internal validAndSettledNonce(txnNonce) {
        UserDetail memory detail = userContributionPerNonce[txnNonce][from];
        if(!detail.isCreated){
            require(false, "No settlement");
        } else if(detail.isPaid) {
            require(false, "Already paid the settlement");
        }
        UD60x18 indexTokens = exchnagedIndexTokenPerNonce[txnNonce];
        UD60x18 unclaimedIndexTokens = unclaimedIndexTokenPerNonce[txnNonce];
        UD60x18 unclaimedBaseTokens = unclaimedBaseTokenPerNonce[txnNonce];
        UD60x18 pooledBaseTokens = pooledBaseTokenAmountPerNonce[txnNonce];
        UD60x18 userContributionRatio = detail.baseTokenAmount.div(pooledBaseTokens);
        UD60x18 userIndexTokenShare = indexTokens.mul(userContributionRatio);
        UD60x18 userBaseTokenShare = unclaimedBaseTokens.mul(userContributionRatio);
        unclaimedIndexTokenPerNonce[txnNonce] = unclaimedIndexTokens - userIndexTokenShare;
        unclaimedBaseTokenPerNonce[txnNonce] = unclaimedBaseTokens - userBaseTokenShare;
        detail.isPaid = true;
        userContributionPerNonce[txnNonce][from] = detail;
        indexToken.transfer(to, userIndexTokenShare.unwrap());
        baseToken.transfer(to, userBaseTokenShare.unwrap());
        _removeTxnNonceFromUserInnerTxn(from, txnNonce);

    }

    function _removeTxnNonceFromUserInnerTxn(address accnt, uint256 txnNonce) internal {
        uint256[] memory _userUnclaimedNonce = userUnclaimedNonce[accnt];
        if (_userUnclaimedNonce.length == 0 ||_userUnclaimedNonce.length > 10 ){
            return;
        }
        if (_userUnclaimedNonce[0] == txnNonce) {
            uint256 lastNonce =  _userUnclaimedNonce[_userUnclaimedNonce.length - 1];
            userUnclaimedNonce[accnt][_userUnclaimedNonce.length - 1] = txnNonce;
            userUnclaimedNonce[accnt][0] = lastNonce;
            userUnclaimedNonce[accnt].pop();
        } else if(_userUnclaimedNonce[_userUnclaimedNonce.length - 1] == txnNonce) {
            userUnclaimedNonce[accnt].pop();
        } else {
            for(uint256 i = 0; i < _userUnclaimedNonce.length; i++) {
                if (_userUnclaimedNonce[i] == txnNonce) {
                    uint256 lastNonce =  _userUnclaimedNonce[_userUnclaimedNonce.length - 1];
                    userUnclaimedNonce[accnt][_userUnclaimedNonce.length - 1] = txnNonce;
                    userUnclaimedNonce[accnt][i] = lastNonce;
                    userUnclaimedNonce[accnt].pop();
                    break;
                }
            }
        }
    }



    // function collectFrom(uint256 txnNonce, address from, address to) external {
    //     _collect(txnNonce, from, to);
    // }

    function collect(uint256 txnNonce, address to) external  {
        _collect(txnNonce, msg.sender, to);
    }

    function startSettlement() external onlyAutomationOracle {
        uint256 nonce = currentTxnNonce;
        currentTxnNonce += 1;
        txnNonceRecord[currentTxnNonce] = true;
        emit StartSettlement(nonce);
    }

    function finishSettlement(uint256[] calldata amounts) external onlyAutomationOracle {
        uint256 nonce = currentTxnNonce - 1;
        indexToken.mint(address(this), amounts);
        unclaimedBaseTokenPerNonce[nonce] = ud(baseToken.balanceOf(address(this)));
        UD60x18 balance = ud(indexToken.balanceOf(address(this)));
        exchnagedIndexTokenPerNonce[nonce] = balance;
        unclaimedIndexTokenPerNonce[nonce] = balance;
        emit FinishSettlement(nonce);

    }

    function _exchange(
        address[] calldata tokens, 
        address[] calldata exchangeRouters, 
        uint256[] calldata amountsOut
        ) internal onlyAutomationOracle {
        
        for (uint256 i = 0; i < tokens.length; i++) {
            IRouter router = IRouter(exchangeRouters[i]);
            router.swapForExactOutput(tokens[i], amountsOut[i]);
            assetsExchangedPerNonce[currentTxnNonce - 1] += 1;
        }
        emit Exchanged(currentTxnNonce - 1, indexToken.tokensLength() == tokens.length, tokens, baseToken.balanceOf(address(this)));

    }

}