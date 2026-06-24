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

contract MOEToken2 is ERC20, Ownable {
    IUniswapV2Router02 public immutable _uniswapV2Router;
    address public _uniswapPair;

    using EnumerableSet for EnumerableSet.AddressSet;

    mapping(address => mapping(address => bool)) public preUps;
    mapping(address => EnumerableSet.AddressSet) private upsChildList;

    mapping(address => uint256) public usersBuyTime;
    mapping(address => User) public users;

    address public WBNB;
    address public nft;

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
    uint256 constant CLAIM_AMOUNT = 1 ether;
    uint256 constant WITHDRAW_AMOUNT = 10 ether;
    uint256 public startTime;

    address private inviteAddress = 0x5B6453Ea3f0e6f975f7440884257037F72a7c33b;
    address fundAddress;
    address feeAddress;

    bool inSwap;
    bool firstAdd = true;

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
                    users[up].validTotal += 1;
                }
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
                } else if (
                    _user.staticDrawStatus &&
                    block.timestamp >= _user.staticDrawAt
                ) {
                    processStaticReward(from);
                    users[from].staticDrawAt = block.timestamp + 1 days;
                    super._update(from, to, value);
                    return super._update(address(this), from, 1e18);
                } else {
                    revert InvalidTransfer();
                }
            }

            if (value == WITHDRAW_AMOUNT) {
                if (_user.lpTotal > 0) {
                    IERC20(_uniswapPair).transfer(from, _user.lpTotal);
                }
                users[from].staticDrawStatus = false;
                users[from].lpTotal = 0;
                users[from].bnbTotal = 0;
                users[from].isBuy = false;
                
                if (users[_user.up].validTotal > 0) {
                    users[_user.up].validTotal -= 1;
                }
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
                } else if (poolTokenAmount >= 50_00_000e18) {
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
                uint256 fee = (value * 3) / 100;
                uint256 nftAmount = (fee * 7) / 10;
                nftRewardTotal += nftAmount;
                uint256 burnAmount = (fee * 1) / 10;
                super._update(from, address(0xdead), burnAmount);
                uint256 fundAmount = fee - nftAmount - burnAmount;
                fundRewardTotal += fundAmount;
                super._update(from, address(this), nftAmount);
                super._update(from, address(this), fundAmount);
                value -= fee;
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

            require(
                usersBuyTime[tx.origin] < block.timestamp - 10,
                "cd"
            );

            if (isAddLiquidity(value) > 0) {} else {
                require(startTime < block.timestamp, "startTime");
                require(value < getCirculation() * 10 / 100, "max token");
                uint256 fee = (value * 4) / 100;
                uint256 nftAmount = (fee * 7) / 10;
                nftRewardTotal += nftAmount;
                uint256 burnAmount = (fee * 1) / 10;
                super._update(from, address(0xdead), burnAmount);
                uint256 fundAmount = fee - nftAmount - burnAmount;
                fundRewardTotal += fundAmount;
                super._update(from, address(this), nftAmount);
                super._update(from, address(this), fundAmount);
                value -= fee;
                sellFee();
            }
        }
        fusing();
        super._update(from, to, value);
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
        // require(success, "TransferHelper: ETH_TRANSFER_FAILED");
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

        if (poolTokenAmount > 1_000_000_000e18) {
            return (1500, 750, 300, 60); // 1.5%, 0.75%, 0.3%, 0.06%
        } else if (poolTokenAmount > 500_000_000e18) {
            return (1250, 625, 300, 60); // 1.25%, 0.625%, 0.3%, 0.06%
        } else if (poolTokenAmount > 100_000_000e18) {
            return (1000, 500, 300, 60); // 1%, 0.5%, 0.3%, 0.06%
        } else {
            return (500, 250, 300, 60); // 0.5%, 0.25%, 0.3%, 0.06%
        }
    }

    function calculateStaticReward(address user) public view returns (uint256) {
        User memory _user = users[user];
        if (
            !_user.isBuy ||
            !_user.staticDrawStatus ||
            block.timestamp < _user.staticDrawAt
        ) {
            return 0;
        }

        (uint256 staticRate, , , ) = calculateRewardRates();
        uint256 bnbTotal = _user.bnbTotal;
        return (bnbTotal * staticRate) / 100000;
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
    }

    function processStaticReward(address user) internal {
        User memory _user = users[user];
        require(_user.isBuy, "User has not bought");
        require(_user.staticDrawStatus, "Static reward not available");
        require(block.timestamp >= _user.staticDrawAt, "Reward not matured");

        uint256 staticReward = calculateStaticReward(user);
        require(staticReward > 0, "No static reward available");

        (
            ,
            uint256 dynamicRate,
            uint256 nftRate,
            uint256 projectRate
        ) = calculateRewardRates();

        uint256 bnbTotal = _user.bnbTotal;
        uint256 dynamicReward = (bnbTotal * dynamicRate) / 100000;
        uint256 nftReward = (bnbTotal * nftRate) / 100000;
        uint256 projectReward = (bnbTotal * projectRate) / 100000;

        uint256 rewardTotal = staticReward +
            dynamicReward +
            nftReward +
            projectReward;

        uint256 tokenTotal = getBNBForTokenAmount(rewardTotal);

        uint256[6] memory lpAmounts;
        lpAmounts[0] = distributeLPReward(tokenTotal);
        lpAmounts[1] = (lpAmounts[0] * staticReward) / rewardTotal;
        IERC20(_uniswapPair).transfer(user, lpAmounts[1]);

        lpAmounts[2] = calculateDynamicReward(user, lpAmounts[1]);
        lpAmounts[3] = (lpAmounts[0] * nftReward) / rewardTotal;
        IERC20(_uniswapPair).transfer(nft, lpAmounts[3]);
        try INFT(nft).process() {
        } catch {
        }
        
        lpAmounts[4] = (lpAmounts[0] * projectReward) / rewardTotal;
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
            0, // slippage is unavoidable
            0, // slippage is unavoidable
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
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            address(0xdead),
            block.timestamp
        );
    }

    function setNFT(address _nft) external onlyOwner {
        nft = _nft;
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
            amount,
            0,
            path,
            address(this),
            block.timestamp
        );
        safeTransferETH(
            feeAddress,
            (address(this).balance * fundRewardTotal) / amount
        );
        safeTransferETH(nft, address(this).balance);
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
}