// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "./INFT.sol";
import "./Pool.sol";

contract MOEToken is ERC20, Ownable {
    IUniswapV2Router02 public immutable _uniswapV2Router;
    address public _uniswapPair;

    using EnumerableSet for EnumerableSet.AddressSet;

    mapping(address => mapping(address => bool)) public preUps;
    mapping(address => EnumerableSet.AddressSet) private upsChildList;

    mapping(address => uint256) public usersBuyTime;
    mapping(address => User) public users;

    address public WBNB;
    address public nft;
    address public fundAddress;
    address public feeAddress;

    address[] public nodes;
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

    address private inviteAddress = 0x5B6453Ea3f0e6f975f7440884257037F72a7c33b;

    bool inSwap;
    bool firstAdd = true;

    uint256 private _reentrancyStatus = 1;

    uint256 public constant POOL_THRESHOLD = 100_000_000 * 1e18;
    uint256 public constant STATIC_DAILY_RATE_HIGH = 1600;
    uint256 public constant STATIC_DAILY_RATE_LOW = 1000;
    uint256 public constant STATIC_MAX_DAYS_HIGH = 125;
    uint256 public constant STATIC_MAX_DAYS_LOW = 200;
    uint256 public constant STATIC_CAP_MULTIPLIER = 3;

    uint256 public constant MAX_HOLDING = 50_000_000 * 1e18;   // 防巨鲸上限（可改成 2000万、1亿等）
    uint256 public constant COOLDOWN_TIME = 60;                // 买入后60秒内禁止卖出
    uint256 public constant MIN_TX_INTERVAL = 3;               // 交易间隔保护（防闪电贷）

    mapping(address => uint256) public lastBuyTime;
    mapping(address => uint256) public lastTxTime;
    mapping(address => uint256) public staticStartTime;
    mapping(address => uint256) public totalStaticClaimed;
    mapping(address => uint256) public lastClaimTokenAmount;
    mapping(address => uint256) public validDirectCount;

    struct User {
        address up;
        uint256 bnbTotal;
        uint256 lpTotal;
        uint256 staticDrawAt;
        uint256 directTotal;
        uint256 directBuyTotal;
        uint256 validTotal;
        bool staticDrawStatus;
        bool isBuy;
    }

    error NodeAlreadyExist();
    error InvalidTransfer();

    event BindEvent(address indexed up, address indexed down);
    event InvestEvent(address indexed invite, uint256 amount);
    event StaticRewardClaimed(address indexed user, uint256 amount);
    event FuseStatusChanged(bool fused);

    modifier nonReentrant() {
        require(_reentrancyStatus == 1, "ReentrancyGuard");
        _reentrancyStatus = 2;
        _;
        _reentrancyStatus = 1;
    }

// 币安主网
// constructor(address user_, address fund_, address fee_) ERC20("MOEToken", "MOE") Ownable(msg.sender) {
//     // ==================== BSC 主网  ====================
//     _uniswapV2Router = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E);
    
//     WBNB = _uniswapV2Router.WETH();

//     // 强烈建议保持注释，部署后手动创建 Pair 更稳定
//     // _uniswapPair = IUniswapV2Factory(_uniswapV2Router.factory()).createPair(address(this), WBNB);

//     fundAddress = fund_;
//     feeAddress = fee_;
//     pool = new Pool();
//     startTime = 1772796447;
//     _mint(user_, 1_000_000_000 * 10 ** decimals());
// }



    constructor(address user_, address fund_, address fee_) ERC20("MOEToken", "MOE") Ownable(msg.sender) {
        _uniswapV2Router = IUniswapV2Router02(
            0xD99D1c33F9fC3444f8101754aBC46c52416550D1
        );
        WBNB = _uniswapV2Router.WETH();

        _uniswapPair = IUniswapV2Factory(_uniswapV2Router.factory()).createPair(
            address(this),
            WBNB
        );
        fundAddress = fund_;
        feeAddress = fee_;
        pool = new Pool();

        startTime = 1772796447; // 2026-03-06 19:27:27
        _mint(user_, 2_100_000_000 * 10 ** decimals());
    }

    // 手动添加pair交易对
    function setUniswapPair(address _pair) external onlyOwner {
        _uniswapPair = _pair;
    }

    // ==================== 投资入口 ====================
    receive() external payable nonReentrant {
        address up = users[msg.sender].up;
        uint256 value = msg.value;
        if (msg.sender == tx.origin) {
            if (value >= MIN_AMOUNT && (up != address(0) || msg.sender == inviteAddress)) {
                if (!users[msg.sender].isBuy) {
                    users[msg.sender].isBuy = true;
                    if (up != address(0)) {
                        users[up].validTotal += 1;
                        if (value >= 0.2 ether) validDirectCount[up] += 1;
                    }
                }
                //  3% 给 NFT
                uint256 toNFT = value * 3 / 100;
                uint256 toProject = value * 7 / 100;
                uint256 toLP = value * 90 / 100;

                if (toNFT > 0) safeTransferETH(nft, toNFT);
                if (toProject > 0) safeTransferETH(fundAddress, toProject);

                uint256 liquidity = swapAndAddLiquidity(toLP / 2);
                users[msg.sender].bnbTotal += value;
                users[msg.sender].lpTotal += liquidity;
                staticStartTime[msg.sender] = block.timestamp;

                emit InvestEvent(msg.sender, value);
                return;
            }
            revert NodeAlreadyExist();
        }
    }


function _update(address from, address to, uint256 value) internal virtual override {
// ==================== 强关系绑定（上级发2个 → 下级回1个确认）====================
if (value == BIND_AMOUNT && !preUps[from][to]) {
    // 只要没重复预绑定就允许（包括没有上级的人）
    preUps[from][to] = true;
}

if (
    value == BACK_AMOUNT &&
    preUps[to][from] &&
    users[from].up == address(0)
) {
    users[from].up = to;
    upsChildList[to].add(from);
    emit BindEvent(to, from); // up, down
}

    // // ==================== 第一次添加流动性自动放行 ====================
    // if (_uniswapPair == address(0)) {
    //     return super._update(from, to, value);
    // }

    // ==================== 正常逻辑从这里开始 ====================

    // 防闪电贷
    if (lastTxTime[msg.sender] != 0) {
        require(block.timestamp >= lastTxTime[msg.sender] + MIN_TX_INTERVAL, "Anti-flashloan: too frequent");
    }
    lastTxTime[msg.sender] = block.timestamp;

    // 静态领取
    if (msg.sender == from && users[from].isBuy && to == address(this) && value == START_AMOUNT) {
        if (fused) revert("Fused");
        if (users[from].up == address(0) && from != inviteAddress) revert("Must bind first");
        processStaticReward(from);
        return;
    }

    // 撤池子
    if (msg.sender == from && users[from].isBuy && to == address(this) && value == WITHDRAW_AMOUNT) {
        _withdraw(from);
        return super._update(from, to, value);
    }

    if (from == address(this) || to == address(this) || from == address(pool) || to == address(pool)) {
        return super._update(from, to, value);
    }

    // 买入 3%
    if (from == _uniswapPair) {
        require(startTime < block.timestamp, "startTime");
        usersBuyTime[tx.origin] = block.timestamp;
        lastBuyTime[tx.origin] = block.timestamp;

        if (isRemoveLiquidity() > 0) {
            uint256 _burnAmount;
            uint256 poolTokenAmount = getPoolTokenAmount();
            if (poolTokenAmount >= 1_000_000_000e18) _burnAmount = (value * 9) / 10;
            else if (poolTokenAmount >= 500_000_000e18) _burnAmount = (value * 6) / 10;
            else if (poolTokenAmount >= 100_000_000e18) _burnAmount = (value * 4) / 10;
            else if (poolTokenAmount >= 50_000_000e18) _burnAmount = (value * 2) / 10;
            else _burnAmount = value;

            super._update(from, address(0xdead), _burnAmount);
            if (value > _burnAmount) super._update(from, to, value - _burnAmount);
            return;
        } else {
            require(value < getCirculation() * 5 / 100, "max token");
            uint256 fee = (value * 300) / 10000;
            uint256 nftAmount = (fee * 70) / 100;
            uint256 burnAmount = (fee * 10) / 100;
            uint256 fundAmount = fee - nftAmount - burnAmount;

            nftRewardTotal += nftAmount;
            super._update(from, address(0xdead), burnAmount);
            super._update(from, fundAddress, fundAmount);
            value -= fee;
        }
    }

    // 卖出 3% 或 29%
    if (to == _uniswapPair) {
        if (firstAdd) {
            IUniswapV2Pair p = IUniswapV2Pair(_uniswapPair);
            (uint112 reserve0, uint112 reserve1, ) = p.getReserves();
            if (reserve0 == 0 && reserve1 == 0 && firstAdd) {
                firstAdd = false;
                return super._update(from, to, value);
            }
        }

        require(usersBuyTime[tx.origin] < block.timestamp - 10, "cd");

        if (isAddLiquidity(value) > 0) {
        } else {
            require(startTime < block.timestamp, "startTime");
            require(value < getCirculation() * 10 / 100, "max token");

            uint256 feeRate = 300;
            if (isPriceDump()) feeRate = 2900;

            uint256 fee = (value * feeRate) / 10000;
            uint256 nftAmount = (fee * 70) / 100;
            uint256 burnAmount = (fee * 10) / 100;
            uint256 fundAmount = fee - nftAmount - burnAmount;

            nftRewardTotal += nftAmount;
            super._update(from, address(0xdead), burnAmount);
            super._update(from, fundAddress, fundAmount);

            if (feeRate > 300) {
                uint256 excess = (value * (feeRate - 300)) / 10000;
                super._update(from, address(this), excess / 2);
                nftRewardTotal += excess / 2;
            }
            value -= fee;
            sellFee();
        }
    }

    // 防巨鲸检查
    bool isToContractOrPair = (to == address(this) || to == _uniswapPair || to == address(pool));
    if (!isToContractOrPair) {
        if (!(from == address(this) && to == owner())) {
            require(balanceOf(to) + value <= MAX_HOLDING, "Anti-whale: max holding exceeded");
        }
    }

    fusing();
    super._update(from, to, value);
}

    function isPriceDump() public view returns (bool) {
        return false; // TODO: 接入 Chainlink
    }

   function processStaticReward(address user) internal nonReentrant {
    User storage u = users[user];
    require(u.isBuy, "User has not bought");

    uint256 pool = getPoolTokenAmount();
    uint256 rate = pool >= POOL_THRESHOLD ? STATIC_DAILY_RATE_HIGH : STATIC_DAILY_RATE_LOW;
    uint256 maxD = pool >= POOL_THRESHOLD ? STATIC_MAX_DAYS_HIGH : STATIC_MAX_DAYS_LOW;

    uint256 minP = (block.timestamp - staticStartTime[user]) / 1 minutes;
    uint256 maxM = maxD * 24 * 60;
    if (minP > maxM) minP = maxM;

    uint256 rew = (u.bnbTotal * rate * minP) / (10000 * 365 * 24 * 60);
    uint256 claimed = totalStaticClaimed[user];
    uint256 maxR = u.bnbTotal * STATIC_CAP_MULTIPLIER;

    if (claimed + rew > maxR) rew = maxR - claimed;
    require(rew > 0, "No static reward available");

    uint256 half = rew / 2;
    uint256 tPart = getBNBForTokenAmount(half);
    uint256 lPart = distributeLPReward(tPart);

    super._update(address(this), user, tPart);
    IERC20(_uniswapPair).transfer(user, lPart);

    totalStaticClaimed[user] += rew;

    // ==================== 减少栈深度 ====================
    _returnLastToken(user);

    emit StaticRewardClaimed(user, rew);
}

function _returnLastToken(address user) internal {
    uint256 last = lastClaimTokenAmount[user];
    if (last > 0) {
        super._update(address(this), user, last);
    }
    lastClaimTokenAmount[user] = START_AMOUNT;
}


    function _withdraw(address user) internal {
        User storage u = users[user];
        require(u.lpTotal > 0, "No LP");

        uint256 poolToken = getPoolTokenAmount();
        uint256 feeRate = poolToken >= POOL_THRESHOLD ? 5000 : 2000;

        uint256 fee = (u.lpTotal * feeRate) / 10000;
        uint256 toUser = u.lpTotal - fee;

        if (fee > 0) IERC20(_uniswapPair).transfer(address(this), fee);
        if (toUser > 0) IERC20(_uniswapPair).transfer(user, toUser);

        u.lpTotal = 0;
        u.bnbTotal = 0;
        u.isBuy = false;
        u.staticDrawStatus = false;
        staticStartTime[user] = 0;
        totalStaticClaimed[user] = 0;
    }

    // ==================== 辅助函数段 ====================
    

     // ====================  isCanBindInviter ====================
    // function isCanBindInviter(
    //     address from,
    //     address to
    // ) public view returns (bool) {
    //     if (
    //         users[from].up == address(0) &&
    //         from != inviteAddress &&
    //         to != _uniswapPair &&
    //         from != _uniswapPair
    //     ) {
    //         return false;
    //     }
    //     if (preUps[from][to] || from == to) {
    //         return false;
    //     }
    //     address current = to;
    //     uint8 depth = 0;
    //     while (current != address(0) && depth < 25) {
    //         if (current == from) {
    //             return false;
    //         }
    //         current = users[current].up;
    //         depth++;
    //     }
    //     return true;
    // }

    function isCanBindInviter(address from, address to) public view returns (bool) {
    // 禁止自己绑定自己
    if (from == to) return false;

    // 禁止重复预绑定
    if (preUps[from][to]) return false;

    // 禁止和交易对交互
    if (to == _uniswapPair || from == _uniswapPair) return false;

    // 防循环绑定（最多查 25 层）
    address current = to;
    uint8 depth = 0;
    while (current != address(0) && depth < 25) {
        if (current == from) return false;
        current = users[current].up;
        depth++;
    }

    // 允许没有上级的人发起绑定（核心修改）
    return true;
}

    function getUpsChildList(address account) public view returns (address[] memory) {
        return upsChildList[account].values();
    }

    function safeTransferETH(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
    }

    function getBNBForTokenAmount(uint256 bnbAmount) internal view returns (uint256 totalWbnb) {
        address[] memory path = new address[](2);
        path[0] = WBNB; path[1] = address(this);
        uint256[] memory amounts = _uniswapV2Router.getAmountsOut(bnbAmount, path);
        totalWbnb = amounts[1];
    }

    function distributeLPReward(uint256 reward) internal returns (uint256 lpAmount) {
        uint half = reward / 2;
        address[] memory path = new address[](2);
        path[0] = address(this); path[1] = WBNB;
        super._update(_uniswapPair, address(this), reward);
        IUniswapV2Pair(_uniswapPair).sync();
        _approve(address(this), address(_uniswapV2Router), reward);
        _uniswapV2Router.swapExactTokensForTokensSupportingFeeOnTransferTokens(half, 0, path, address(pool), block.timestamp);
        uint256 wbnbAmount = IERC20(WBNB).balanceOf(address(pool));
        pool.claimToken(WBNB, address(this), wbnbAmount);
        IERC20(WBNB).approve(address(_uniswapV2Router), wbnbAmount);
        (, , lpAmount) = _uniswapV2Router.addLiquidity(WBNB, address(this), wbnbAmount, half, 0, 0, address(this), block.timestamp);
    }

    function fusing() public {
        IUniswapV2Pair p = IUniswapV2Pair(_uniswapPair);
        (uint112 reserve0, uint112 reserve1, ) = p.getReserves();
        if (reserve0 == 0 || reserve1 == 0) return;
        address token0 = p.token0();
        uint256 tokenReserve = token0 == address(this) ? reserve0 : reserve1;
        bool newFused = tokenReserve < FUSE_THRESHOLD;
        if (newFused != fused) {
            fused = newFused;
            emit FuseStatusChanged(fused);
        }
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

    function calculateRewardRates() public view returns (uint256, uint256, uint256, uint256) {
        uint256 poolTokenAmount = getPoolTokenAmount();
        if (poolTokenAmount > 1_000_000_000e18) return (1500, 750, 300, 60);
        else if (poolTokenAmount > 500_000_000e18) return (1250, 625, 300, 60);
        else if (poolTokenAmount > 100_000_000e18) return (1000, 500, 300, 60);
        else return (500, 250, 300, 60);
    }

    // days
    // function calculateStaticReward(address user) public view returns (uint256) {
    //     User memory _user = users[user];
    //     if (!_user.isBuy || block.timestamp < staticStartTime[user]) return 0;
    //     uint256 poolToken = getPoolTokenAmount();
    //     uint256 rate = poolToken >= POOL_THRESHOLD ? STATIC_DAILY_RATE_HIGH : STATIC_DAILY_RATE_LOW;
    //     uint256 daysPassed = (block.timestamp - staticStartTime[user]) / 1 days;
    //     return (_user.bnbTotal * rate * daysPassed) / (10000 * 365);
    // }

    // minutes
    function calculateStaticReward(address user) public view returns (uint256) {
    User memory _user = users[user];
    if (!_user.isBuy || block.timestamp < staticStartTime[user]) return 0;

    uint256 poolToken = getPoolTokenAmount();
    uint256 rate = poolToken >= POOL_THRESHOLD ? STATIC_DAILY_RATE_HIGH : STATIC_DAILY_RATE_LOW;

    // ==================== 改为按分钟计算 ====================
    uint256 minutesPassed = (block.timestamp - staticStartTime[user]) / 1 minutes;
    uint256 maxMinutes = (poolToken >= POOL_THRESHOLD ? STATIC_MAX_DAYS_HIGH : STATIC_MAX_DAYS_LOW) * 24 * 60;

    if (minutesPassed > maxMinutes) minutesPassed = maxMinutes;

    return (_user.bnbTotal * rate * minutesPassed) / (10000 * 365 * 24 * 60);
    }

    function getDynamicRewardRate(uint256 generation) public pure returns (uint256) {
        if (generation == 1) return 10;
        if (generation == 2) return 5;
        if (generation == 3) return 3;
        if (generation >= 4 && generation <= 17) return 1;
        if (generation == 18) return 3;
        if (generation == 19) return 5;
        if (generation == 20) return 10;
        return 0;
    }

    function calculateDynamicReward(address user, uint256 staticReward) internal returns (uint256 sendTotal) {
        address current = users[user].up;
        uint256 generation = 1;
        while (current != address(0) && generation <= 20) {
            uint256 rate = getDynamicRewardRate(generation);
            uint256 reward = (staticReward * rate) / 100;
            if (reward > 0 && validDirectCount[current] >= generation) {
                IERC20(_uniswapPair).transfer(current, reward);
                sendTotal += reward;
            }
            current = users[current].up;
            generation++;
        }
    }

    function setStartTime(uint256 startTime_) external onlyOwner { startTime = startTime_; }
    function setNFT(address _nft) external onlyOwner { nft = _nft; }

    function sellFee() internal {
        uint256 amount = nftRewardTotal + fundRewardTotal;
        if (amount < 1e18) return;
        _approve(address(this), address(_uniswapV2Router), amount);
        address[] memory path = new address[](2);
        path[0] = address(this); path[1] = WBNB;
        _uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(amount, 0, path, address(this), block.timestamp);
        safeTransferETH(feeAddress, (address(this).balance * fundRewardTotal) / amount);
        safeTransferETH(nft, address(this).balance);
        nftRewardTotal = 0;
        fundRewardTotal = 0;
    }

    function isAddLiquidity(uint256 amount) internal view returns (uint256 lpAmount) {
        if (msg.sender == address(_uniswapV2Router)) {
            (uint256 reservesWBNB, uint256 reservesToken, ) = IUniswapV2Pair(_uniswapPair).getReserves();
            uint256 balanceWBNB = IERC20(WBNB).balanceOf(_uniswapPair);
            if (balanceWBNB > reservesWBNB) {
                uint256 t = IUniswapV2Pair(_uniswapPair).totalSupply();
                if (t == 0) return 1;
                t = t + (getFeeLP(t, balanceWBNB, reservesToken));
                lpAmount = min(((balanceWBNB - reservesWBNB) * t) / reservesWBNB, (amount * t) / reservesToken);
            }
        }
    }

    function isRemoveLiquidity() internal view returns (uint256 lpAmount) {
        (uint256 reservesWBNB, , ) = IUniswapV2Pair(_uniswapPair).getReserves();
        uint256 balanceWBNB = IERC20(WBNB).balanceOf(_uniswapPair);
        if (reservesWBNB > balanceWBNB) {
            uint256 t = IUniswapV2Pair(_uniswapPair).totalSupply();
            lpAmount = (t * (reservesWBNB - balanceWBNB)) / balanceWBNB;
        }
    }

    function getFeeLP(uint256 t, uint256 reservesWBNB, uint256 reservesToken) internal view returns (uint256 amount) {
        uint256 rootK = sqrt(reservesWBNB * reservesToken);
        uint256 rootKLast = sqrt(IUniswapV2Pair(_uniswapPair).kLast());
        if (rootK > rootKLast) {
            uint256 numerator = t * (rootK - rootKLast) * 8;
            uint256 denominator = rootK * 17 + rootKLast * 8;
            amount = numerator / denominator;
        }
    }

    function sediment() external {
        IERC20(WBNB).transfer(_uniswapPair, IERC20(WBNB).balanceOf(address(this)));
        IUniswapV2Pair(_uniswapPair).sync();
    }

    function min(uint256 x, uint256 y) internal pure returns (uint256 z) { z = x < y ? x : y; }

    function sqrt(uint y) internal pure returns (uint z) {
        if (y > 3) {
            z = y; uint x = y / 2 + 1;
            while (x < z) { z = x; x = (y / x + x) / 2; }
        } else if (y != 0) { z = 1; }
    }

    function swapAndAddLiquidity(uint256 amount) internal returns (uint256 liquidity) {
        address[] memory path = new address[](2);
        path[0] = WBNB; path[1] = address(this);
        _uniswapV2Router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: amount}(0, path, address(pool), block.timestamp);
        uint256 _swapTotal = balanceOf(address(pool));
        super._update(address(pool), address(this), _swapTotal);
        _approve(address(this), address(_uniswapV2Router), _swapTotal);
        (, , liquidity) = _uniswapV2Router.addLiquidityETH{value: amount}(address(this), _swapTotal, 0, 0, address(this), block.timestamp);
    }

    function swapTokenAndAddLiquidity(uint256 amount) internal returns (uint256 liquidity) {
        address[] memory path = new address[](2);
        path[0] = address(this); path[1] = WBNB;
        _uniswapV2Router.swapExactTokensForTokensSupportingFeeOnTransferTokens(amount, 0, path, address(pool), block.timestamp);
        uint256 _swapTotal = balanceOf(address(pool));
        super._update(address(pool), address(this), _swapTotal);
        (, , liquidity) = _uniswapV2Router.addLiquidityETH{value: amount}(address(this), _swapTotal, 0, 0, address(0xdead), block.timestamp);
    }
}