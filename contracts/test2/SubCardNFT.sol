// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title SubCardNFT (副卡)
 * @dev 负面卡 - 恒定发行 2500 张
 *      使用用户提供的 IPFS metadata (Moe 负面卡)
 *      持有者可获得 ROMAN 代币分红（手续费USDT、防爆税、静态收益等）
 */
contract SubCardNFT is ERC721, Ownable {
    using Strings for uint256;

    uint256 public constant MAX_SUPPLY = 2500;
    uint256 private _nextTokenId;

    // 用户提供的副卡 metadata JSON
    string private constant METADATA_URI = 
        "https://purple-big-zebra-605.mypinata.cloud/ipfs/bafkreih5e7yp6bcm2dgah3ie3clkr5c637su7no3xxxvjpj5u3smldxlvu";

    // 可选：ROMAN Token 合约地址，用于激活检查 (最低0.2 BNB)
    address public romanToken;

    event Minted(address indexed to, uint256 indexed tokenId);
    event RomanTokenSet(address indexed romanToken);

    constructor() ERC721("Moe", "MOE_SUB") Ownable(msg.sender) {
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
     * @dev 铸造副卡（仅 owner）
     *      总供应量上限 2500 张
     */
    function mint(address to) external onlyOwner {
        require(_nextTokenId <= MAX_SUPPLY, "SubCardNFT: max supply reached");
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

    /**
     * @dev 所有 tokenId 返回相同的 metadata URI（统一负面卡设计）
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_ownerOf(tokenId) != address(0), "SubCardNFT: URI query for nonexistent token");
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
     */
    function isActivated(address holder) external view returns (bool) {
        if (romanToken == address(0)) return true;
        // 占位实现，实际需根据 ROMANToken 的 users mapping 调整接口
        return true;
    }
}