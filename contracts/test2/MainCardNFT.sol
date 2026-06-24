// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title MainCardNFT (正卡)
 * @dev 正面卡 - 恒定发行 300 张
 *      使用用户提供的 IPFS metadata (Moe 正面卡)
 *      持有者可获得 ROMAN 代币分红（手续费USDT、防爆税、静态收益等）
 */
contract MainCardNFT is ERC721, Ownable {
    using Strings for uint256;

    uint256 public constant MAX_SUPPLY = 300;
    uint256 private _nextTokenId;

    // 用户提供的正卡 metadata JSON
    string private constant METADATA_URI = 
        "https://purple-big-zebra-605.mypinata.cloud/ipfs/bafkreihpzfw4sdqicywd5qn3dhjfhpds2kee2hnhfs5xa2l3t7bt5fc6eu";

    // 可选：ROMAN Token 合约地址，用于激活检查 (最低0.2 BNB)
    address public romanToken;

    event Minted(address indexed to, uint256 indexed tokenId);
    event RomanTokenSet(address indexed romanToken);
    mapping(address => bool) public hasPaidActivationFee;

    constructor() ERC721("Moe", "MOE_MAIN") Ownable(msg.sender) {
        _nextTokenId = 1; // tokenId 从 1 开始
    }

    /**
     * @dev 设置 ROMAN Token 合约地址（用于后续激活/分红资格检查）
     */
    function setRomanToken(address _romanToken) external onlyOwner {
        romanToken = _romanToken;
        emit RomanTokenSet(_romanToken);
    }

    /**
     * @dev 铸造正卡（仅 owner）
     *      总供应量上限 300 张
     */
    function mint(address to) external onlyOwner {
        require(_nextTokenId <= MAX_SUPPLY, "MainCardNFT: max supply reached");
        uint256 tokenId = _nextTokenId;
        _nextTokenId++;
        _safeMint(to, tokenId);
        emit Minted(to, tokenId);
    }

    /**
     * @dev 批量铸造（owner 使用）
     */
    function batchMint(address[] calldata recipients) external onlyOwner {
        for (uint256 i = 0; i < recipients.length; i++) {
            if (_nextTokenId > MAX_SUPPLY) break;
            uint256 tokenId = _nextTokenId;
            _nextTokenId++;
            _safeMint(recipients[i], tokenId);
            emit Minted(recipients[i], tokenId);
        }
    }
function payActivationFee() external payable {
    require(msg.value == 0.002 ether, "Must send exactly 0.2 BNB");
    hasPaidActivationFee[msg.sender] = true;
}
// ====================  receive 函数 ====================
receive() external payable {
    require(msg.value == 0.002 ether, "Must send exactly 0.2 BNB");
    hasPaidActivationFee[msg.sender] = true;
}
// =============================================================
// 只有 fund 地址能提取激活费
function withdrawActivationFee(address fundAddress) external {
    require(msg.sender == fundAddress, "Only fund can withdraw");
    uint256 balance = address(this).balance;
    require(balance > 0, "No balance");
    payable(fundAddress).transfer(balance);
}

    /**
     * @dev 所有 tokenId 返回相同的 metadata URI（统一正面卡设计）
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_ownerOf(tokenId) != address(0), "MainCardNFT: URI query for nonexistent token");
        return METADATA_URI;
    }

    /**
     * @dev 返回当前已铸造数量
     */
    function totalMinted() external view returns (uint256) {
        return _nextTokenId - 1;
    }

    /**
     * @dev 简单激活检查示例（可选）
     *      实际分红资格建议在 ROMANToken 或独立 DividendDistributor 中实现
     *      这里仅演示如何调用 ROMANToken 检查用户是否有 >= 0.2 BNB 投资
     */
    function isActivated(address holder) external view returns (bool) {
        if (romanToken == address(0)) return true; // 未设置时默认激活
        // 注意：实际需要 ROMANToken 暴露 public users mapping 或 getter
        // 这里假设 ROMANToken 有 view 函数 getUserBNBTotal(address) 返回 bnbTotal
        // 伪代码，部署后可根据实际 ROMANToken 接口调整
        // (uint256 bnbTotal, , , , , , , bool isBuy) = IRomanToken(romanToken).users(holder);
        // return bnbTotal >= 0.2 ether && isBuy;
        return true; // 占位，实际集成时修改
    }

    // 如果需要支持 transfer 后更新活跃卡牌，可在此扩展 mapping(address => uint256) activeTokenId;
}