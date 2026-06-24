// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "./MOERewards.sol";

abstract contract MOELiquidity is MOERewards {
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

    function swapAndAddLiquidity(uint256 amount) internal returns (uint256 liquidity) {
        address[] memory path = new address[](2);
        path[0] = WBNB;
        path[1] = address(this);

        _uniswapV2Router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: amount}(
            0, path, address(pool), block.timestamp
        );

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
        if (amount < 1e18) return;

        _approve(address(this), address(_uniswapV2Router), amount);
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = WBNB;

        _uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            amount, 0, path, address(this), block.timestamp
        );

        MOEUtils.safeTransferETH(feeAddress, (address(this).balance * fundRewardTotal) / amount);
        MOEUtils.safeTransferETH(nft, address(this).balance);

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
                lpAmount = MOEUtils.min(
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
        uint256 rootK = MOEUtils.sqrt(reservesWBNB * reservesToken);
        uint256 rootKLast = MOEUtils.sqrt(IUniswapV2Pair(_uniswapPair).kLast());
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

    function processStaticReward(address user) internal {
        User memory _user = users[user];
        require(_user.isBuy, "User has not bought");
        require(_user.staticDrawStatus, "Static reward not available");
        require(block.timestamp >= _user.staticDrawAt, "Reward not matured");

        uint256 staticReward = calculateStaticReward(user);
        require(staticReward > 0, "No static reward available");

        (, uint256 dynamicRate, uint256 nftRate, uint256 projectRate) = calculateRewardRates();

        uint256 bnbTotal = _user.bnbTotal;
        uint256 dynamicReward = (bnbTotal * dynamicRate) / 100000;
        uint256 nftReward = (bnbTotal * nftRate) / 100000;
        uint256 projectReward = (bnbTotal * projectRate) / 100000;

        uint256 rewardTotal = staticReward + dynamicReward + nftReward + projectReward;
        uint256 tokenTotal = getBNBForTokenAmount(rewardTotal);

        uint256[6] memory lpAmounts;
        lpAmounts[0] = distributeLPReward(tokenTotal);
        lpAmounts[1] = (lpAmounts[0] * staticReward) / rewardTotal;
        IERC20(_uniswapPair).transfer(user, lpAmounts[1]);

        lpAmounts[2] = calculateDynamicReward(user, lpAmounts[1]);

        lpAmounts[3] = (lpAmounts[0] * nftReward) / rewardTotal;
        IERC20(_uniswapPair).transfer(nft, lpAmounts[3]);
        try INFT(nft).process() {} catch {}

        lpAmounts[4] = (lpAmounts[0] * projectReward) / rewardTotal;
        IERC20(_uniswapPair).transfer(fundAddress, lpAmounts[4]);

        lpAmounts[5] = lpAmounts[0] - lpAmounts[1] - lpAmounts[2] - lpAmounts[3] - lpAmounts[4];
        if (lpAmounts[5] > 0) {
            IERC20(_uniswapPair).transfer(fundAddress, lpAmounts[5]);
        }
    }
}