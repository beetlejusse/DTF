// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

contract SimpleDTFFactory is Ownable, ReentrancyGuard {
    
    // ========== EVENTS ==========
    event DTFCreated(
        address indexed dtfAddress,
        address indexed creator,
        uint256 indexed dtfId,
        string name,
        string symbol,
        address[] tokens,
        uint256[] weights
    );
    
    // ========== STATE VARIABLES ==========
    mapping(uint256 => address) public dtfs;           // DTF ID -> DTF address
    mapping(address => bool) public isValidDTF;        // Quick lookup for valid DTFs
    mapping(address => uint256[]) public creatorToDTFs; // Creator -> array of DTF IDs
    uint256 public totalDTFs;                          // Total DTFs created
    
    // Configuration
    uint256 public constant MIN_TOKENS = 2;
    uint256 public constant MAX_TOKENS = 10;
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public maxDTFsPerCreator = 5;
    
    // DTF metadata
    struct DTFInfo {
        address dtfAddress;
        address creator;
        string name;
        string symbol;
        uint256 createdAt;
        bool active;
    }
    mapping(uint256 => DTFInfo) public dtfInfo;
    
    constructor() {}

    function createDTF(
        string memory name,
        string memory symbol,
        address[] memory tokens,
        uint256[] memory weights
    ) external nonReentrant returns (address dtfAddress) {
        
        // Validate creation limits
        require(
            creatorToDTFs[msg.sender].length < maxDTFsPerCreator,
            "Creator DTF limit exceeded"
        );
        
        // Validate parameters
        _validateDTFParams(name, symbol, tokens, weights);
        
        // Deploy new DTF contract
        SimpleDTF newDTF = new SimpleDTF(
            name,
            symbol,
            tokens,
            weights,
            msg.sender  // Creator becomes owner
        );
        
        dtfAddress = address(newDTF);
        
        // Register the DTF
        uint256 dtfId = totalDTFs;
        dtfs[dtfId] = dtfAddress;
        isValidDTF[dtfAddress] = true;
        
        // Store metadata
        dtfInfo[dtfId] = DTFInfo({
            dtfAddress: dtfAddress,
            creator: msg.sender,
            name: name,
            symbol: symbol,
            createdAt: block.timestamp,
            active: true
        });
        
        // Update creator tracking
        creatorToDTFs[msg.sender].push(dtfId);
        totalDTFs++;
        
        emit DTFCreated(dtfAddress, msg.sender, dtfId, name, symbol, tokens, weights);
        
        return dtfAddress;
    }
    
    /**
     * @notice Validate DTF parameters
     */
    function _validateDTFParams(
        string memory name,
        string memory symbol,
        address[] memory tokens,
        uint256[] memory weights
    ) internal pure {
        // String validation
        require(bytes(name).length > 0 && bytes(name).length <= 50, "Invalid name");
        require(bytes(symbol).length > 0 && bytes(symbol).length <= 10, "Invalid symbol");
        
        // Array validation
        require(tokens.length == weights.length, "Array length mismatch");
        require(tokens.length >= MIN_TOKENS, "Too few tokens");
        require(tokens.length <= MAX_TOKENS, "Too many tokens");
        
        // Weight validation
        uint256 totalWeight = 0;
        for (uint256 i = 0; i < weights.length; i++) {
            require(tokens[i] != address(0), "Invalid token address");
            require(weights[i] > 0, "Weight must be positive");
            totalWeight += weights[i];
        }
        require(totalWeight == BASIS_POINTS, "Weights must sum to 10000");
        
        // Check for duplicates
        for (uint256 i = 0; i < tokens.length; i++) {
            for (uint256 j = i + 1; j < tokens.length; j++) {
                require(tokens[i] != tokens[j], "Duplicate tokens");
            }
        }
    }
    
    // ========== VIEW FUNCTIONS ==========
    
    function getDTFById(uint256 dtfId) external view returns (address) {
        require(dtfId < totalDTFs, "DTF does not exist");
        return dtfs[dtfId];
    }
    
    function getDTFInfo(uint256 dtfId) external view returns (DTFInfo memory) {
        require(dtfId < totalDTFs, "DTF does not exist");
        return dtfInfo[dtfId];
    }
    
    function getCreatorDTFs(address creator) external view returns (uint256[] memory) {
        return creatorToDTFs[creator];
    }
    
    // ========== ADMIN FUNCTIONS ==========
    
    function setMaxDTFsPerCreator(uint256 newMax) external onlyOwner {
        require(newMax > 0 && newMax <= 20, "Invalid max");
        maxDTFsPerCreator = newMax;
    }
}
