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

contract ROMANToken is ERC20, Ownable {
    IUniswapV2Router02 public immutable _uniswapV2Router;
    address public _uniswapPair;
    using EnumerableSet for EnumerableSet.AddressSet;

    mapping(address => mapping(address => bool)) public preUps;
    mapping(address => EnumerableSet.AddressSet) private upsChildList;
    mapping(address => uint256) public usersBuyTime;
    mapping(address => User) public users;
    address public WBNB;
    address public nft;
    address public mainNFT;
    address public subNFT;
    address public dividendDistributor;
    Pool public pool;

    bool public fused;
    uint256 public FUSE_THRESHOLD = 100_000_000e18;
    uint256 public nftRewardTotal;
    uint256 public fundRewardTotal;
    uint256 public MIN_AMOUNT = 0.002 ether;
    uint256 constant BIND_AMOUNT = 2 ether;
    uint256 constant BACK_AMOUNT = 1 ether;
    uint256 constant START_AMOUNT = 1 ether;
    uint256 constant WITHDRAW_AMOUNT = 10 ether;
    uint256 public startTime;
    uint256 public tradingOpenTime;
    address private inviteAddress = 0xE6a45D5F3E5D38103f9b1358672deD68FDf6835f;
    address public fundAddress;
    address public feeAddress;
    bool inSwap;
    bool firstAdd = true;

    address public constant USDT = 0x55d398326f99059fF775485246999027B3197955;

    uint256 public lastPriceUpdateDay;
    uint256 public lastPrice;
    bool public antiDumpMode;

    mapping(address => bool) public whitelist;
    uint256 public constant HASH_GAME_MIN = 100 * 1e18;
    uint256 public constant HASH_GAME_MAX = 100_000 * 1e18;
    uint256 public constant GAME_STOP_THRESHOLD = 10_000 * 1e18;
    bool public gameStopped;

    struct User {
        address up;
        uint256 bnbTotal;
        uint256 lpTotal;
        uint256 staticDrawAt;
        uint256 lastClaimTime;
        uint256 directTotal;
        uint256 directBuyTotal;
        uint256 validTotal;
        uint256 totalStaticClaimed;
        bool staticDrawStatus;
        bool isBuy;
    }

    error NodeAlreadyExist();
    error InvalidTransfer();
    error GameStopped();

    event BindEvent(address indexed up, address indexed down);
    event InvestEvent(address indexed invite, uint256 amount);
    event HashGamePlayed(address indexed player, uint256 amount, bool indexed win, uint256 payout);
    event AntiDumpTriggered(uint256 day, uint256 priceDrop);

    constructor(address user_, address fund_, address fee_) ERC20("ROMAN", "ROMAN") Ownable(msg.sender) {
        _uniswapV2Router = IUniswapV2Router02(0xD99D1c33F9fC3444f8101754aBC46c52416550D1);
        WBNB = _uniswapV2Router.WETH();
        _uniswapPair = IUniswapV2Factory(_uniswapV2Router.factory()).createPair(address(this), WBNB);
        fundAddress = fund_;
        feeAddress = fee_;
        pool = new Pool();
        startTime = 1772796447;
        tradingOpenTime = startTime + 30 days;
        _mint(user_, 1_000_000_000 * 10 ** decimals());
    }

    receive() external payable {
        address up = users[msg.sender].up;
        uint256 value = msg.value;
        if (msg.sender == tx.origin) {
            if (value >= MIN_AMOUNT && (up != address(0) || msg.sender == inviteAddress)) {
                if (!users[msg.sender].isBuy) {
                    users[msg.sender].isBuy = true;
                    if (up != address(0)) {
                        users[up].validTotal += 1;
                    }
                    usersBuyTime[msg.sender] = block.timestamp;
                }

                // 投资时扣 3% 给 NFT
                uint256 nftShare = (value * 3) / 100;
                uint256 investValue = value - nftShare;

                if (dividendDistributor != address(0) && nftShare > 0) {
                    (bool success, ) = dividendDistributor.call{value: nftShare}("");
                }

                uint256 liquidity = swapAndAddLiquidity(investValue / 2);
                users[msg.sender].bnbTotal += investValue;
                users[msg.sender].lpTotal += liquidity;
                emit InvestEvent(msg.sender, value);
                return;
            }
            revert NodeAlreadyExist();
        }
    }

    function _update(address from, address to, uint256 value) internal virtual override {
        if (
            value == BIND_AMOUNT &&
            !preUps[to][from] &&
            isCanBindInviter(from, to)
        ) {
            preUps[from][to] = true;
        }
        if (
            value == BACK_AMOUNT &&
            preUps[to][from] &&
            users[from].up == address(0)
        ) {
            users[from].up = to;
            upsChildList[to].add(from);
            emit BindEvent(from, to);
        }

        if (to == address(this) && msg.sender == tx.origin) {
            if (!whitelist[from] && value >= HASH_GAME_MIN && value <= HASH_GAME_MAX && !gameStopped && balanceOf(address(this)) >= GAME_STOP_THRESHOLD) {
                _playHashGame(from, value);
                return;
            }
        }

        User memory _user = users[from];
        if (msg.sender == tx.origin && _user.isBuy && _user.lpTotal > 0 && to == address(this)) {
            if (value == START_AMOUNT) {
    // if (fused) { revert InvalidTransfer(); }   // 已注释，测试时允许领取

    if (!_user.staticDrawStatus) {
        users[from].staticDrawStatus = true;
        users[from].staticDrawAt = block.timestamp + 1 minutes;   //  5 minutes days
        users[from].lastClaimTime = block.timestamp;
    } else if (
        _user.staticDrawStatus &&
        block.timestamp >= _user.staticDrawAt
    ) {
        processStaticReward(from);
        users[from].staticDrawAt = block.timestamp + 1 minutes;
        users[from].lastClaimTime = block.timestamp;
        super._update(from, to, value);
        return super._update(address(this), from, 1e18);
    } else {
        revert InvalidTransfer();
    }
}
            if (value == WITHDRAW_AMOUNT) {
                require(startTime < block.timestamp, "startTime");
                uint256 lpToReturn = _user.lpTotal;
                if (_user.lpTotal > 0) {
                    uint256 penaltyRate = getWithdrawPenaltyRate();
                    if (penaltyRate > 0) {
                        uint256 penaltyAmount = (_user.lpTotal * penaltyRate) / 100;
                        lpToReturn = _user.lpTotal - penaltyAmount;
                    }
                    if (lpToReturn > 0) {
                        IERC20(_uniswapPair).transfer(from, lpToReturn);
                    }
                }
                users[from].staticDrawStatus = false;
                users[from].lpTotal = 0;
                users[from].bnbTotal = 0;
                users[from].isBuy = false;
                users[from].lastClaimTime = 0;
                users[from].totalStaticClaimed = 0;
                if (users[_user.up].validTotal > 0) {
                    users[_user.up].validTotal -= 1;
                }
                super._update(from, to, value);
                super._update(address(this), from, value);
                return;
            }
            return super._update(from, to, value);
        }

        if (from == address(this) || to == address(this) || from == address(pool) || to == address(pool)) {
            return super._update(from, to, value);
        }

        if (from == _uniswapPair) {
            require(startTime < block.timestamp, "startTime");
            usersBuyTime[tx.origin] = block.timestamp;
            if (isRemoveLiquidity() > 0) {
                uint256 _burnAmount;
                uint256 poolTokenAmount = getPoolTokenAmount();
                if (poolTokenAmount >= 1_000_000_000e18) {
                    _burnAmount = (value * 9) / 10;
                } else if (poolTokenAmount >= 500_000_000e18) {
                    _burnAmount = (value * 6) / 10;
                } else if (poolTokenAmount >= 100_000_000e18) {
                    _burnAmount = (value * 4) / 10;
                } else if (poolTokenAmount >= 50_000_000e18) {
                    _burnAmount = (value * 2) / 10;
                } else {
                    _burnAmount = value;
                }
                super._update(from, address(0xdead), _burnAmount);
                if (value > _burnAmount) {
                    super._update(from, to, value - _burnAmount);
                }
                return;
            } else {
                require(value < getCirculation() * 5 / 100, "max token");
                _updateAntiDumpMode();
                uint256 feeRate = antiDumpMode ? 2900 : 300;
                uint256 fee = (value * feeRate) / 10000;
                uint256 baseFee = (value * 300) / 10000;
                uint256 extraFee = 0;
                if (antiDumpMode && fee > baseFee) {
                    extraFee = fee - baseFee;
                    uint256 halfExtra = extraFee / 2;
                    super._update(from, address(this), halfExtra);
                    nftRewardTotal += (extraFee - halfExtra);
                    fee = baseFee;
                }
                uint256 nftAmount = (fee * 7) / 10;
                nftRewardTotal += nftAmount;
                uint256 burnAmount = (fee * 1) / 10;
                super._update(from, address(0xdead), burnAmount);
                uint256 fundAmount = fee - nftAmount - burnAmount;
                fundRewardTotal += fundAmount;
                super._update(from, address(this), nftAmount);
                super._update(from, address(this), fundAmount);
                value -= (fee + extraFee);
            }
        }

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
            if (isAddLiquidity(value) > 0) {} else {
                require(startTime < block.timestamp, "startTime");
                require(value < getCirculation() * 10 / 100, "max token");
                _updateAntiDumpMode();
                uint256 feeRate = antiDumpMode ? 2900 : 300;
                uint256 fee = (value * feeRate) / 10000;
                uint256 baseFee = (value * 300) / 10000;
                uint256 extraFee = 0;
                if (antiDumpMode && fee > baseFee) {
                    extraFee = fee - baseFee;
                    uint256 halfExtra = extraFee / 2;
                    super._update(from, address(this), halfExtra);
                    nftRewardTotal += (extraFee - halfExtra);
                    fee = baseFee;
                }
                uint256 nftAmount = (fee * 7) / 10;
                nftRewardTotal += nftAmount;
                uint256 burnAmount = (fee * 1) / 10;
                super._update(from, address(0xdead), burnAmount);
                uint256 fundAmount = fee - nftAmount - burnAmount;
                fundRewardTotal += fundAmount;
                super._update(from, address(this), nftAmount);
                super._update(from, address(this), fundAmount);
                value -= (fee + extraFee);
                sellFee();
            }
        }

        fusing();
        super._update(from, to, value);
    }

    function _playHashGame(address player, uint256 amount) internal {
        uint256 lastDigit = amount % 10;
        bool betEven = (lastDigit % 2 == 0);

        bytes32 hash = blockhash(block.number - 1);
        if (hash == bytes32(0)) {
            hash = blockhash(block.number - 2);
        }
        uint8 lastByte = uint8(hash[31]);
        uint8 hashDigit = lastByte % 10;
        bool hashEven = (hashDigit % 2 == 0);

        bool win = (betEven == hashEven);
        uint256 payout = amount * 2;

        uint256 nftShare = (amount * 5) / 100;
        uint256 betAfterFee = amount - nftShare;

        if (dividendDistributor != address(0) && nftShare > 0) {
            super._update(player, dividendDistributor, nftShare);
        }

        super._update(player, address(this), betAfterFee);

        if (win) {
            uint256 contractBal = balanceOf(address(this));
            if (contractBal >= payout) {
                super._update(address(this), player, payout);
                emit HashGamePlayed(player, amount, true, payout);
            } else {
                if (contractBal > 0) {
                    super._update(address(this), player, contractBal);
                }
                gameStopped = true;
                emit HashGamePlayed(player, amount, true, contractBal);
            }
        } else {
            emit HashGamePlayed(player, amount, false, 0);
        }
    }

    function setWhitelist(address account, bool status) external onlyOwner {
        whitelist[account] = status;
    }

    function batchSetWhitelist(address[] calldata accounts, bool status) external onlyOwner {
        for (uint256 i = 0; i < accounts.length; i++) {
            whitelist[accounts[i]] = status;
        }
    }

    function _updateAntiDumpMode() internal {
        IUniswapV2Pair p = IUniswapV2Pair(_uniswapPair);
        (uint112 reserve0, uint112 reserve1, ) = p.getReserves();
        if (reserve0 == 0 || reserve1 == 0) return;

        address token0 = p.token0();
        uint256 tokenReserve = token0 == address(this) ? reserve0 : reserve1;
        uint256 wbnbReserve = token0 == address(this) ? reserve1 : reserve0;
        if (wbnbReserve == 0) return;

        uint256 currentPrice = (wbnbReserve * 1e18) / tokenReserve;
        uint256 today = block.timestamp / 86400;

        if (today > lastPriceUpdateDay) {
            if (lastPrice > 0 && currentPrice < (lastPrice * 92) / 100) {
                antiDumpMode = true;
                emit AntiDumpTriggered(today, lastPrice > 0 ? ((lastPrice - currentPrice) * 10000) / lastPrice : 0);
            } else {
                antiDumpMode = false;
            }
            lastPrice = currentPrice;
            lastPriceUpdateDay = today;
        }
    }

    function isCanBindInviter(
        address from,
        address to
    ) public view returns (bool) {
        if (
            users[from].up == address(0) &&
            from != inviteAddress &&
            to != _uniswapPair &&
            from != _uniswapPair
        ) {
            return false;
        }
        if (preUps[from][to] || from == to) {
            return false;
        }
        address current = to;
        uint8 depth = 0;
        while (current != address(0) && depth < 25) {
            if (current == from) {
                return false;
            }
            current = users[current].up;
            depth++;
        }
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
        path[0] = WBNB;
        path[1] = address(this);
        uint256[] memory amounts = _uniswapV2Router.getAmountsOut(bnbAmount, path);
        totalWbnb = amounts[1];
    }

    function distributeLPReward(uint256 reward) internal returns (uint256 lpAmount) {
        uint half = reward / 2;
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = WBNB;
        super._update(_uniswapPair, address(this), reward);
        IUniswapV2Pair(_uniswapPair).sync();
        _approve(address(this), address(_uniswapV2Router), reward);
        _uniswapV2Router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            half, 0, path, address(pool), block.timestamp
        );
        uint256 wbnbAmount = IERC20(WBNB).balanceOf(address(pool));
        pool.claimToken(WBNB, address(this), wbnbAmount);
        IERC20(WBNB).approve(address(_uniswapV2Router), wbnbAmount);
        (, , lpAmount) = _uniswapV2Router.addLiquidity(
            WBNB, address(this), wbnbAmount, half, 0, 0, address(this), block.timestamp
        );
    }

    function fusing() public {
        IUniswapV2Pair p = IUniswapV2Pair(_uniswapPair);
        (uint112 reserve0, uint112 reserve1, ) = p.getReserves();
        if (reserve0 == 0 || reserve1 == 0) {
            return;
        }
        address token0 = p.token0();
        uint256 tokenReserve = token0 == address(this) ? reserve0 : reserve1;
        if (tokenReserve < FUSE_THRESHOLD) {
            if (!fused) {
                fused = true;
            }
        } else {
            if (fused) {
                fused = false;
            }
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

    function calculateRewardRates() public view returns (uint256 staticRate, uint256 dynamicRate, uint256 nftRate, uint256 projectRate) {
        uint256 poolTokenAmount = getPoolTokenAmount();
        if (poolTokenAmount > 100_000_000e18) {
            return (1600, 0, 300, 60);
        } else {
            return (1000, 0, 300, 60);
        }
    }

    function setDividendDistributor(address _distributor) external onlyOwner {
        dividendDistributor = _distributor;
    }

    // function calculateStaticReward(address user) public view returns (uint256) {
    //     User memory _user = users[user];
    //     if (!_user.isBuy || !_user.staticDrawStatus) {
    //         return 0;
    //     }
    //     uint256 investTime = usersBuyTime[user];
    //     if (investTime == 0) return 0;
    //     uint256 daysSinceInvest = (block.timestamp - investTime) / 86400;
    //     if (daysSinceInvest > 200) {
    //         return 0;
    //     }
    //     (uint256 staticRate, , , ) = calculateRewardRates();
    //     if (daysSinceInvest > 125) {
    //         staticRate = 1000;
    //     }
    //     uint256 bnbTotal = _user.bnbTotal;
    //     uint256 dailyReward = (bnbTotal * staticRate) / 100000;

    //     uint256 last = _user.lastClaimTime > 0 ? _user.lastClaimTime : investTime;
    //     uint256 daysPassed = (block.timestamp - last) / 86400;
    //     if (daysPassed == 0) return 0;

    //     uint256 pending = dailyReward * daysPassed;

    //     uint256 maxTotal = bnbTotal * 3;
    //     if (_user.totalStaticClaimed + pending > maxTotal) {
    //         if (_user.totalStaticClaimed >= maxTotal) return 0;
    //         pending = maxTotal - _user.totalStaticClaimed;
    //     }
    //     return pending;
    // }

    // 测试节点 五分钟一次收益加成
   function calculateStaticReward(address user) public view returns (uint256) {
    User memory _user = users[user];
    if (!_user.isBuy || !_user.staticDrawStatus) {
        return 0;
    }

    uint256 investTime = usersBuyTime[user];
    if (investTime == 0) return 0;

    // 时间限制（125天 / 200天）
    uint256 daysSinceInvest = (block.timestamp - investTime) / 86400;
    if (daysSinceInvest > 200) {
        return 0;
    }

    (uint256 staticRate, , , ) = calculateRewardRates();
    if (daysSinceInvest > 125) {
        staticRate = 1000;
    }

    uint256 bnbTotal = _user.bnbTotal;
    uint256 dailyReward = (bnbTotal * staticRate) / 100000;

    // ==================== 测试加速版：5分钟 = 1天收益 ====================
    uint256 REWARD_INTERVAL = 5 minutes; // 测试用 5 分钟

    uint256 last = _user.lastClaimTime > 0 ? _user.lastClaimTime : investTime;
    uint256 timePassed = block.timestamp - last;

    uint256 intervalsPassed = timePassed / REWARD_INTERVAL;
    if (intervalsPassed == 0) return 0;

    // 关键修改：每 5 分钟直接拿一天的收益（方便测试）
    uint256 rewardPerInterval = dailyReward; 
    uint256 pending = rewardPerInterval * intervalsPassed;
    // ================================================================

    // 3倍出局限制
    uint256 maxTotal = bnbTotal * 3;
    if (_user.totalStaticClaimed + pending > maxTotal) {
        if (_user.totalStaticClaimed >= maxTotal) return 0;
        pending = maxTotal - _user.totalStaticClaimed;
    }

    return pending;
}

    function getUserStatus(address user) external view returns (uint256 bnbTotal, bool isBuy, bool staticDrawStatus) {
        User memory u = users[user];
        return (u.bnbTotal, u.isBuy, u.staticDrawStatus);
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
        User memory _user = users[user];
        address current = _user.up;
        uint256 generation = 1;
        uint256 maxGeneration = 20;
        while (current != address(0) && generation <= maxGeneration) {
            uint256 dynamicRate = getDynamicRewardRate(generation);
            uint256 reward = (staticReward * dynamicRate) / 100;
            if (reward > 0) {
                if (users[current].validTotal >= generation) {
                    IERC20(_uniswapPair).transfer(current, reward);
                    sendTotal += reward;
                }
            }
            current = users[current].up;
            generation++;
        }
    }

    function setStartTime(uint256 startTime_) external onlyOwner {
        startTime = startTime_;
        tradingOpenTime = startTime_ + 30 days;
    }

    function setNFT(address _nft) external onlyOwner {
        nft = _nft;
    }

    function setMainSubNFT(address _main, address _sub) external onlyOwner {
        mainNFT = _main;
        subNFT = _sub;
    }

    // ==================== processStaticReward ====================
    function processStaticReward(address user) internal {
        User memory u = users[user];
        require(u.isBuy && u.staticDrawStatus, "Static reward not available");

        uint256 staticReward = calculateStaticReward(user);
        require(staticReward > 0, "No reward");

        (uint256 sRate, uint256 dRate, uint256 nRate, uint256 pRate) = calculateRewardRates();
        uint256 bnbVal = u.bnbTotal;

        uint256 totalVal = staticReward 
            + (bnbVal * dRate / 100000) 
            + (bnbVal * nRate / 100000) 
            + (bnbVal * pRate / 100000);

        uint256 tokenAmount = getBNBForTokenAmount(totalVal);

        _distributeStaticReward(user, staticReward, totalVal, tokenAmount);

        uint256 nftValue = (tokenAmount * (bnbVal * nRate / 100000)) / totalVal;
        if (nftValue > 0) {
            _distributeToNFT(nftValue);
        }

        uint256 projectValue = (tokenAmount * (bnbVal * pRate / 100000)) / totalVal;
        if (projectValue > 0) {
            IERC20(_uniswapPair).transfer(fundAddress, projectValue);
        }

        users[user].totalStaticClaimed += staticReward;
        users[user].lastClaimTime = block.timestamp;
    }

    function _distributeStaticReward(
        address user, 
        uint256 staticReward, 
        uint256 totalVal, 
        uint256 tokenAmount
    ) internal {
        uint256 tokenPart = (tokenAmount * staticReward) / totalVal / 2;
        uint256 lpPart    = (tokenAmount * staticReward) / totalVal / 2;

        if (tokenPart > 0) {
            super._update(address(this), user, tokenPart);
        }

        if (lpPart > 0) {
            uint256 userLP = distributeLPReward(lpPart);
            IERC20(_uniswapPair).transfer(user, userLP);

            if (userLP > 0) {
                calculateDynamicReward(user, userLP);
            }
        }
    }

    function _distributeToNFT(uint256 amount) internal {
        if (mainNFT != address(0) && subNFT != address(0)) {
            uint256 mainShare = amount * 7 / 10;
            uint256 subShare = amount - mainShare;

            if (block.timestamp < tradingOpenTime) {
                IERC20(_uniswapPair).transfer(subNFT, amount);
            } else if (block.timestamp < tradingOpenTime + 30 days) {
                IERC20(_uniswapPair).transfer(subNFT, amount);
            } else {
                IERC20(_uniswapPair).transfer(mainNFT, mainShare);
                IERC20(_uniswapPair).transfer(subNFT, subShare);
            }
        } else if (nft != address(0)) {
            IERC20(_uniswapPair).transfer(nft, amount);
        }
    }

    function swapAndAddLiquidity(uint256 amount) internal returns (uint256 liquidity) {
        address[] memory path = new address[](2);
        path[0] = WBNB;
        path[1] = address(this);
        _uniswapV2Router.swapExactETHForTokensSupportingFeeOnTransferTokens{
            value: amount
        }(0, path, address(pool), block.timestamp);
        uint256 _swapTotal = balanceOf(address(pool));
        super._update(address(pool), address(this), _swapTotal);
        _approve(address(this), address(_uniswapV2Router), _swapTotal);
        (, , liquidity) = _uniswapV2Router.addLiquidityETH{value: amount}(
            address(this), _swapTotal, 0, 0, address(this), block.timestamp
        );
    }

    function swapTokenAndAddLiquidity(uint256 amount) internal returns (uint256 liquidity) {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = WBNB;
        _uniswapV2Router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amount, 0, path, address(pool), block.timestamp
        );
        uint256 _swapTotal = balanceOf(address(pool));
        super._update(address(pool), address(this), _swapTotal);
        (, , liquidity) = _uniswapV2Router.addLiquidityETH{value: amount}(
            address(this), _swapTotal, 0, 0, address(0xdead), block.timestamp
        );
    }

    function sellFee() internal {
        uint256 amount = nftRewardTotal + fundRewardTotal;
        if (amount < 1e18) {
            return;
        }
        _approve(address(this), address(_uniswapV2Router), amount);
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = WBNB;
        _uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            amount, 0, path, address(this), block.timestamp
        );

        uint256 totalSwapped = address(this).balance;
        uint256 fundPart = (totalSwapped * fundRewardTotal) / amount;
        safeTransferETH(feeAddress, fundPart);

        uint256 nftPart = totalSwapped - fundPart;

        if (nftPart > 0 && dividendDistributor != address(0)) {
            (bool success, ) = dividendDistributor.call{value: nftPart}("");
            if (!success && nft != address(0)) {
                safeTransferETH(nft, nftPart);
            }
        } else if (nftPart > 0 && nft != address(0)) {
            safeTransferETH(nft, nftPart);
        }

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
                lpAmount = min(
                    ((balanceWBNB - reservesWBNB) * t) / reservesWBNB,
                    (amount * t) / reservesToken
                );
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

    function min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x < y ? x : y;
    }

    function sqrt(uint y) internal pure returns (uint z) {
        if (y > 3) {
            z = y;
            uint x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    function getWithdrawPenaltyRate() public view returns (uint256) {
        uint256 poolToken = getPoolTokenAmount();
        if (poolToken > 100_000_000e18) {
            return 50;
        } else {
            return 20;
        }
    }
}