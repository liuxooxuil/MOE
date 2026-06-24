// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";

import "../Pool.sol";
import "../INFT.sol";
import "../MOEUtils.sol";

abstract contract MOEBase is ERC20, Ownable {
    using MOEUtils for *;

    IUniswapV2Router02 public immutable _uniswapV2Router;
    address public _uniswapPair;
    address public WBNB;
    address public nft;
    Pool public pool;

    bool public fused;
    uint256 public FUSE_THRESHOLD = 21_000_000e18;
    uint256 public nftRewardTotal;
    uint256 public fundRewardTotal;

    uint256 public MIN_AMOUNT = 0.1 ether;
    uint256 constant BIND_AMOUNT = 2 ether;
    uint256 constant BACK_AMOUNT = 1 ether;
    uint256 constant START_AMOUNT = 1 ether;
    uint256 constant WITHDRAW_AMOUNT = 10 ether;

    uint256 public startTime;
    address internal inviteAddress = 0x5B6453Ea3f0e6f975f7440884257037F72a7c33b;
    address public fundAddress;
    address public feeAddress;

    bool firstAdd = true;
    mapping(address => uint256) public usersBuyTime;

    error NodeAlreadyExist();
    error InvalidTransfer();

    event BindEvent(address indexed up, address indexed down);
    event InvestEvent(address indexed invite, uint256 amount);

    constructor(address user_, address fund_, address fee_) 
        ERC20("MOEToken", "MOE") Ownable(msg.sender) 
    {
        _uniswapV2Router = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E);
        WBNB = _uniswapV2Router.WETH();
        _uniswapPair = IUniswapV2Factory(_uniswapV2Router.factory()).createPair(address(this), WBNB);

        fundAddress = fund_;
        feeAddress = fee_;
        pool = new Pool();

        startTime = 1772796447;
        _mint(user_, 2_100_000_000 * 10 ** decimals());
    }

    function setNFT(address _nft) external onlyOwner { nft = _nft; }
    function setStartTime(uint256 startTime_) external onlyOwner { startTime = startTime_; }

    function fusing() public {
        IUniswapV2Pair p = IUniswapV2Pair(_uniswapPair);
        (uint112 reserve0, uint112 reserve1, ) = p.getReserves();
        if (reserve0 == 0 || reserve1 == 0) return;
        address token0 = p.token0();
        uint256 tokenReserve = token0 == address(this) ? reserve0 : reserve1;
        fused = tokenReserve < FUSE_THRESHOLD;
    }

    function getPoolTokenAmount() public view returns (uint256) {
        IUniswapV2Pair p = IUniswapV2Pair(_uniswapPair);
        (uint112 reserve0, uint112 reserve1, ) = p.getReserves();
        address token0 = p.token0();
        return token0 == address(this) ? reserve0 : reserve1;
    }

    function getCirculation() public view returns (uint256) {
        return totalSupply() - balanceOf(address(0xdead));
    }
}