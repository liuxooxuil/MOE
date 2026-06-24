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

// 基本版本
contract ROMANToken1 is ERC20, Ownable {
    IUniswapV2Router02 public immutable _uniswapV2Router;
    address public _uniswapPair;
    using EnumerableSet for EnumerableSet.AddressSet;

    mapping(address => mapping(address => bool)) public preUps;
    mapping(address => EnumerableSet.AddressSet) private upsChildList;
    mapping(address => uint256) public usersBuyTime;
    mapping(address => User) public users;
    address public WBNB;
    address public nft; // For backward, will be subNFT or main in future
    address public mainNFT;
    address public subNFT;
    address[] public nodes;
    address public dividendDistributor;                    // 分红分发器地址
    Pool public pool;

    bool public fused;
    uint256 public FUSE_THRESHOLD = 100_000_000e18; // Updated for rate control reference
    uint256 public nftRewardTotal;
    uint256 public fundRewardTotal;
    uint256 public MIN_AMOUNT = 0.002 ether; // Updated per spec
    uint256 constant BIND_AMOUNT = 2 ether;
    uint256 constant BACK_AMOUNT = 1 ether;
    uint256 constant START_AMOUNT = 1 ether;
    uint256 constant CLAIM_AMOUNT = 1 ether;
    uint256 constant WITHDRAW_AMOUNT = 10 ether;
    uint256 public startTime;
    uint256 public tradingOpenTime; // startTime + 30 days for NFT分配 rules
    address private inviteAddress = 0xE6a45D5F3E5D38103f9b1358672deD68FDf6835f;
    // address private inviteAddress = 0x5B6453Ea3f0e6f975f7440884257037F72a7c33b;
    address public fundAddress;
    address public feeAddress;
    bool inSwap;
    bool firstAdd = true;

    // USDT for NFT dividends (BSC mainnet)
    address public constant USDT = 0x55d398326f99059fF775485246999027B3197955;

    // Anti-dump tracking
    uint256 public lastPriceUpdateDay;
    uint256 public lastPrice; // WBNB per ROMAN * 1e18
    bool public antiDumpMode;

    // Hash game
    mapping(address => bool) public whitelist;
    uint256 public constant HASH_GAME_MIN = 100 * 1e18;
    uint256 public constant HASH_GAME_MAX = 100_000 * 1e18;
    uint256 public constant GAME_STOP_THRESHOLD = 10_000 * 1e18;
    bool public gameStopped;
    uint256 public hashGameRewardTotal; // Optional tracking

    struct User {
        address up;
        uint256 bnbTotal;
        uint256 lpTotal;
        uint256 staticDrawAt;
        uint256 lastClaimTime; // For cumulative interest (upgrade)
        uint256 directTotal;
        uint256 directBuyTotal;
        uint256 validTotal;
        uint256 totalStaticClaimed; // For 3x cap tracking (value in BNB)
        bool staticDrawStatus;
        bool isBuy;
    }

    error NodeAlreadyExist();
    error InvalidTransfer();
    error GameStopped();
    error InvalidGameAmount();

    event BindEvent(address indexed up, address indexed down);
    event InvestEvent(address indexed invite, uint256 amount);
    event HashGamePlayed(address indexed player, uint256 amount, bool indexed win, uint256 payout);
    event AntiDumpTriggered(uint256 day, uint256 priceDrop);

    constructor(address user_, address fund_, address fee_) ERC20("ROMAN", "ROMAN") Ownable(msg.sender) {
        _uniswapV2Router = IUniswapV2Router02(
            0xD99D1c33F9fC3444f8101754aBC46c52416550D1 // PancakeSwap V2 Router BSC
        );
        WBNB = _uniswapV2Router.WETH();
        _uniswapPair = IUniswapV2Factory(_uniswapV2Router.factory()).createPair(
            address(this),
            WBNB
        );
        fundAddress = fund_;
        feeAddress = fee_;
        pool = new Pool();
        startTime = 1772796447; // 2026-03-06 or set via setStartTime
        tradingOpenTime = startTime + 30 days; // For NFT 7:3 / 3:7 allocation start
        _mint(user_, 1_000_000_000 * 10 ** decimals()); // ROMAN fixed 1B supply
    }

    receive() external payable {
        address up = users[msg.sender].up;
        uint256 value = msg.value;
        if (msg.sender == tx.origin) {
            if (
                value >= MIN_AMOUNT &&
                (up != address(0) || msg.sender == inviteAddress)
            ) {
                if (!users[msg.sender].isBuy) {
                    users[msg.sender].isBuy = true;
                    if (up != address(0)) {
                        users[up].validTotal += 1;
                    }
                    usersBuyTime[msg.sender] = block.timestamp;
                }
                // Allow叠加 (add more position)
                uint256 liquidity = swapAndAddLiquidity(value / 2);
                users[msg.sender].bnbTotal += value;
                users[msg.sender].lpTotal += liquidity;
                emit InvestEvent(msg.sender, value);
                return;
            }
            revert NodeAlreadyExist();
        }
    }

    function _update(
        address from,
        address to,
        uint256 value
    ) internal virtual override {
        // Binding logic (unchanged, matches spec V)
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

        // Hash Game logic (new per spec VII) - before other to==this logic
        if (to == address(this) && msg.sender == tx.origin) {
            if (
                !whitelist[from] &&
                value >= HASH_GAME_MIN &&
                value <= HASH_GAME_MAX &&
                !gameStopped &&
                balanceOf(address(this)) >= GAME_STOP_THRESHOLD
            ) {
                _playHashGame(from, value);
                return; // Bet processed, do not trigger static/withdraw
            }
        }

        User memory _user = users[from];
        if (
            msg.sender == tx.origin &&
            _user.isBuy &&
            _user.lpTotal > 0 &&
            to == address(this)
        ) {
            if (value == START_AMOUNT) {
                if (fused) {
                    revert InvalidTransfer();
                }
                if (!_user.staticDrawStatus) {
                    users[from].staticDrawStatus = true;
                    users[from].staticDrawAt = block.timestamp + 1 days;
                    users[from].lastClaimTime = block.timestamp;
                } else if (
                    _user.staticDrawStatus &&
                    block.timestamp >= _user.staticDrawAt
                ) {
                    processStaticReward(from);
                    users[from].staticDrawAt = block.timestamp + 1 days;
                    users[from].lastClaimTime = block.timestamp;
                    super._update(from, to, value);
                    return super._update(address(this), from, 1e18);
                } else {
                    revert InvalidTransfer();
                }
            }
            if (value == WITHDRAW_AMOUNT) {
                require(startTime < block.timestamp, "startTime"); // Per spec: cannot withdraw pool before trading open

                uint256 lpToReturn = _user.lpTotal;

                // ==================== 撤池子惩罚逻辑（根据底池代币数量） ====================
                if (_user.lpTotal > 0) {
                    uint256 penaltyRate = getWithdrawPenaltyRate(); // 返回 50 或 20

                    if (penaltyRate > 0) {
                        uint256 penaltyAmount = (_user.lpTotal * penaltyRate) / 100;
                        lpToReturn = _user.lpTotal - penaltyAmount;
                        // 扣除的手续费 LP 留在合约地址
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
                // Return the 10 tokens key (spec: 把上次10个代币返回)
                super._update(from, to, value); // Move 10 to this first (already in flow)
                super._update(address(this), from, value); // Return 10 to user
                return;
            }
            return super._update(from, to, value);
        }

        if (
            from == address(this) ||
            to == address(this) ||
            from == address(pool) ||
            to == address(pool)
        ) {
            return super._update(from, to, value);
        }

        // Buy from pair (from == _uniswapPair)
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
                _updateAntiDumpMode(); // Check price drop
                uint256 feeRate = antiDumpMode ? 2900 : 300; // 29% or 3%
                uint256 fee = (value * feeRate) / 10000;
                uint256 baseFee = (value * 300) / 10000;
                uint256 extraFee = 0;
                if (antiDumpMode && fee > baseFee) {
                    extraFee = fee - baseFee;
                    uint256 halfExtra = extraFee / 2;
                    // Half to contract address (hold or later use/burn)
                    super._update(from, address(this), halfExtra);
                    // Half to NFT (will be swapped to USDT in sellFee or separate)
                    nftRewardTotal += (extraFee - halfExtra);
                    fee = baseFee; // Base fee split normal
                }
                uint256 nftAmount = (fee * 7) / 10; // 70% of base fee to NFT (USDT path)
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

        // Sell to pair (to == _uniswapPair)
        if (to == _uniswapPair) {
            if (firstAdd) {
                IUniswapV2Pair p = IUniswapV2Pair(_uniswapPair);
                (uint112 reserve0, uint112 reserve1, ) = p.getReserves();
                if (reserve0 == 0 && reserve1 == 0 && firstAdd) {
                    firstAdd = false;
                    return super._update(from, to, value);
                }
            }
            require(
                usersBuyTime[tx.origin] < block.timestamp - 10,
                "cd"
            );
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
                sellFee(); // Swap to BNB/USDT
            }
        }

        fusing();
        super._update(from, to, value);
    }

    // New: Hash game implementation (spec VII)
    function _playHashGame(address player, uint256 amount) internal {
        // Bet choice by amount last digit (even/odd) per spec description
        uint256 lastDigit = amount % 10;
        bool betEven = (lastDigit % 2 == 0);

        // Get hash last digit (from blockhash, fallback to previous)
        bytes32 hash = blockhash(block.number - 1);
        if (hash == bytes32(0)) {
            hash = blockhash(block.number - 2);
        }
        uint8 lastByte = uint8(hash[31]);
        uint8 hashDigit = lastByte % 10;
        bool hashEven = (hashDigit % 2 == 0);

        bool win = (betEven == hashEven);
        uint256 payout = amount * 2; // 2x total return (net +amount profit)

        super._update(player, address(this), amount); // Confirm bet to contract

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
            // Bet stays in contract (lose)
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

    // New: Update anti-dump mode based on daily price drop >8%
    function _updateAntiDumpMode() internal {
        IUniswapV2Pair p = IUniswapV2Pair(_uniswapPair);
        (uint112 reserve0, uint112 reserve1, ) = p.getReserves();
        if (reserve0 == 0 || reserve1 == 0) return;

        address token0 = p.token0();
        uint256 tokenReserve = token0 == address(this) ? reserve0 : reserve1;
        uint256 wbnbReserve = token0 == address(this) ? reserve1 : reserve0;
        if (wbnbReserve == 0) return;

        // Price in WBNB per ROMAN (scaled 1e18)
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

    function getUpsChildList(
        address account
    ) public view returns (address[] memory) {
        return upsChildList[account].values();
    }

    function safeTransferETH(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
    }

    function getBNBForTokenAmount(
        uint256 bnbAmount
    ) internal view returns (uint256 totalWbnb) {
        address[] memory path = new address[](2);
        path[0] = WBNB;
        path[1] = address(this);
        uint256[] memory amounts = _uniswapV2Router.getAmountsOut(
            bnbAmount,
            path
        );
        totalWbnb = amounts[1];
    }

    function distributeLPReward(
        uint256 reward
    ) internal returns (uint256 lpAmount) {
        uint half = reward / 2;
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = WBNB;
        super._update(_uniswapPair, address(this), reward);
        IUniswapV2Pair(_uniswapPair).sync();
        _approve(address(this), address(_uniswapV2Router), reward);
        _uniswapV2Router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            half,
            0,
            path,
            address(pool),
            block.timestamp
        );
        uint256 wbnbAmount = IERC20(WBNB).balanceOf(address(pool));
        pool.claimToken(WBNB, address(this), wbnbAmount);
        IERC20(WBNB).approve(address(_uniswapV2Router), wbnbAmount);
        (, , lpAmount) = _uniswapV2Router.addLiquidity(
            WBNB,
            address(this),
            wbnbAmount,
            half,
            0,
            0,
            address(this),
            block.timestamp
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

    // Updated rates per spec IV (1.6% / 1% based on 1亿 pool)
    function calculateRewardRates()
        public
        view
        returns (
            uint256 staticRate,
            uint256 dynamicRate,
            uint256 nftRate,
            uint256 projectRate
        )
    {
        uint256 poolTokenAmount = getPoolTokenAmount();
        if (poolTokenAmount > 100_000_000e18) {
            return (1600, 0, 300, 60); // 1.6% static, dynamic % of static handled in getDynamicRewardRate
        } else {
            return (1000, 0, 300, 60); // 1.0% static
        }
    }


    function setDividendDistributor(address _distributor) external onlyOwner {
        dividendDistributor = _distributor;
    }

    function calculateStaticReward(address user) public view returns (uint256) {
        User memory _user = users[user];
        if (
            !_user.isBuy ||
            !_user.staticDrawStatus
        ) {
            return 0;
        }
        // Time limit: 125 days 1.6%, up to 200 days 1% (pool rate still applies)
        uint256 investTime = usersBuyTime[user];
        if (investTime == 0) return 0;
        uint256 daysSinceInvest = (block.timestamp - investTime) / 86400;
        if (daysSinceInvest > 200) {
            return 0; // No static after 200 days
        }
        (uint256 staticRate, , , ) = calculateRewardRates();
        // If >125 days, force lower rate (even if pool high)
        if (daysSinceInvest > 125) {
            staticRate = 1000;
        }
        uint256 bnbTotal = _user.bnbTotal;
        uint256 dailyReward = (bnbTotal * staticRate) / 100000;

        // Cumulative days since last claim (upgrade for "不需要24小时操作一次")
        uint256 last = _user.lastClaimTime > 0 ? _user.lastClaimTime : investTime;
        uint256 daysPassed = (block.timestamp - last) / 86400;
        if (daysPassed == 0) return 0;

        uint256 pending = dailyReward * daysPassed;

        // 3x out cap (simple version, tracks BNB value)
        uint256 maxTotal = bnbTotal * 3;
        if (_user.totalStaticClaimed + pending > maxTotal) {
            if (_user.totalStaticClaimed >= maxTotal) return 0;
            pending = maxTotal - _user.totalStaticClaimed;
        }
        return pending;
    }


// ==================== Helper for DividendDistributor ====================
function getUserStatus(address user) external view returns (
    uint256 bnbTotal,
    bool isBuy,
    bool staticDrawStatus
) {
    User memory u = users[user];
    return (u.bnbTotal, u.isBuy, u.staticDrawStatus);
}

    function getDynamicRewardRate(
        uint256 generation
    ) public pure returns (uint256) {
        if (generation == 1) return 10; // 10%
        if (generation == 2) return 5; // 5%
        if (generation == 3) return 3; // 3%
        if (generation >= 4 && generation <= 17) return 1; // 1%
        if (generation == 18) return 3; // 3%
        if (generation == 19) return 5; // 5%
        if (generation == 20) return 10; // 10%
        return 0;
    }

    function calculateDynamicReward(
        address user,
        uint256 staticReward
    ) internal returns (uint256 sendTotal) {
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

    // processStaticReward kept similar, with time/3x notes. Distribution is LP heavy (original design)
    // To better match "一半币一半LP", further modification to split token vs LP would be needed in distributeLPReward and payout.
    function processStaticReward(address user) internal {
        User memory _user = users[user];
        require(_user.isBuy, "User has not bought");
        require(_user.staticDrawStatus, "Static reward not available");

        uint256 staticRewardValue = calculateStaticReward(user); // Now supports multi-day + 3x cap
        require(staticRewardValue > 0, "No static reward available or cap reached or time expired");

        (
            ,
            uint256 dynamicRate,
            uint256 nftRate,
            uint256 projectRate
        ) = calculateRewardRates();
        uint256 bnbTotal = _user.bnbTotal;
        uint256 dynamicRewardValue = (bnbTotal * dynamicRate) / 100000;
        uint256 nftRewardValue = (bnbTotal * nftRate) / 100000;
        uint256 projectRewardValue = (bnbTotal * projectRate) / 100000;
        uint256 rewardTotalValue = staticRewardValue +
            dynamicRewardValue +
            nftRewardValue +
            projectRewardValue;

        uint256 tokenTotal = getBNBForTokenAmount(rewardTotalValue);
        uint256[6] memory lpAmounts;
        lpAmounts[0] = distributeLPReward(tokenTotal);
        lpAmounts[1] = (lpAmounts[0] * staticRewardValue) / rewardTotalValue;
        IERC20(_uniswapPair).transfer(user, lpAmounts[1]);

        lpAmounts[2] = calculateDynamicReward(user, lpAmounts[1]);
        lpAmounts[3] = (lpAmounts[0] * nftRewardValue) / rewardTotalValue;

        // Split NFT share to main/sub per time-based rule (spec I)
        if (mainNFT != address(0) && subNFT != address(0)) {
            uint256 mainShare = lpAmounts[3] * 7 / 10;
            uint256 subShare = lpAmounts[3] - mainShare;
            if (block.timestamp < tradingOpenTime) {
                IERC20(_uniswapPair).transfer(subNFT, lpAmounts[3]); // Early: 100% sub per spec
            } else if (block.timestamp < tradingOpenTime + 30 days) {
                IERC20(_uniswapPair).transfer(subNFT, lpAmounts[3]);
            } else {
                IERC20(_uniswapPair).transfer(mainNFT, mainShare);
                IERC20(_uniswapPair).transfer(subNFT, subShare);
            }
        } else {
            IERC20(_uniswapPair).transfer(nft, lpAmounts[3]);
        }

        try INFT(nft).process() {
        } catch {
        }

        lpAmounts[4] = (lpAmounts[0] * projectRewardValue) / rewardTotalValue;
        IERC20(_uniswapPair).transfer(fundAddress, lpAmounts[4]);
        lpAmounts[5] =
            lpAmounts[0] -
            lpAmounts[1] -
            lpAmounts[2] -
            lpAmounts[3] -
            lpAmounts[4];
        if (lpAmounts[5] > 0) {
            IERC20(_uniswapPair).transfer(fundAddress, lpAmounts[5]);
        }

        // Update claimed for 3x cap (approximate value)
        users[user].totalStaticClaimed += staticRewardValue;
        users[user].lastClaimTime = block.timestamp;
    }

    function swapAndAddLiquidity(
        uint256 amount
    ) internal returns (uint256 liquidity) {
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
            address(this),
            _swapTotal,
            0,
            0,
            address(this),
            block.timestamp
        );
    }

    function swapTokenAndAddLiquidity(
        uint256 amount
    ) internal returns (uint256 liquidity) {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = WBNB;
        _uniswapV2Router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amount,
            0,
            path,
            address(pool),
            block.timestamp
        );
        uint256 _swapTotal = balanceOf(address(pool));
        super._update(address(pool), address(this), _swapTotal);
        (, , liquidity) = _uniswapV2Router.addLiquidityETH{value: amount}(
            address(this),
            _swapTotal,
            0,
            0,
            address(0xdead),
            block.timestamp
        );
    }

    // Updated sellFee to support USDT path for NFT (70% fee split)
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
            amount,
            0,
            path,
            address(this),
            block.timestamp
        );

        uint256 totalSwapped = address(this).balance;
        uint256 fundPart = (totalSwapped * fundRewardTotal) / amount;
        safeTransferETH(feeAddress, fundPart);

        uint256 nftPart = totalSwapped - fundPart;
        // For NFT: swap BNB to USDT and send to nft (or main/sub)
        if (nftPart > 0 && nft != address(0)) {
            address[] memory usdtPath = new address[](2);
            usdtPath[0] = WBNB;
            usdtPath[1] = USDT;
            try _uniswapV2Router.swapExactETHForTokensSupportingFeeOnTransferTokens{
                value: nftPart
            }(0, usdtPath, nft, block.timestamp) {
                // Success, USDT sent to nft contract for dividend
            } catch {
                // Fallback: send BNB to nft if USDT swap fails
                safeTransferETH(nft, nftPart);
            }
        } else if (nftPart > 0) {
            safeTransferETH(nft, nftPart);
        }

        nftRewardTotal = 0;
        fundRewardTotal = 0;
    }

    function isAddLiquidity(
        uint256 amount
    ) internal view returns (uint256 lpAmount) {
        if (msg.sender == address(_uniswapV2Router)) {
            (uint256 reservesWBNB, uint256 reservesToken, ) = IUniswapV2Pair(
                _uniswapPair
            ).getReserves();
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

    function getFeeLP(
        uint256 t,
        uint256 reservesWBNB,
        uint256 reservesToken
    ) internal view returns (uint256 amount) {
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

    // Withdraw pool penalty rules (spec III) - example, actual withdraw is via 10 token send
    // This can be extended or used in frontend/offchain check
    function getWithdrawPenaltyRate() public view returns (uint256) {
        uint256 poolToken = getPoolTokenAmount();
        if (poolToken > 100_000_000e18) {
            return 50; // 50% fee
        } else {
            return 20; // 20% fee
        }
    }
}