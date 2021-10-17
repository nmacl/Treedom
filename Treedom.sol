// SPDX-License-Identifier: GPL-3.0
pragma solidity >= 0.7 .0 < 0.9 .0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBase.sol";

contract Treedom is ERC721Enumerable, Ownable, ReentrancyGuard, VRFConsumerBase {
    using Strings for uint256;

    string private _baseTokenURI = "ipfs://QmfSfjKnHnC7inzGX7jzjA3XLtBbnrfBrMPJtYQNh8Jkf1/";
    string private _contractURI = "ipfs://QmbNwjd1smagNBhpgX3tqUCUcqYEMWrku18ZBYND1chc4c";

    //toggle the sale
    bool public isSaleActive = false;

    //no more than 6k
    uint256 public constant totalTokenToMint = 6000;

    uint256 public tokenIndex = 0;
    uint256 public price = 50000000000000000; //0.05 eth

    //freezer address
    address public freezeAcc = address(0);

	//health mapping
    mapping(uint256 => uint256) public health;

    bytes32 internal keyHash;
    uint256 internal fee;

    uint256 public randomResult;

    constructor() ERC721("Treedom", "Tree") {}

	/*
	* START 
	* CHAINLINK KEEPER SOLUTION *
	*/

    //Damage each tree - Chainlink Keeper?
    function tick() external onlyOwner {
        uint256 tokenTree;
        for (tokenTree = 1; tokenTree <= totalSupply(); tokenTree++) {
            if (!_exists(tokenTree)) continue;
            if (ownerOf(tokenTree) == freezeAcc) continue;
            health[tokenTree] = health[tokenTree] - 1;
            if (health[tokenTree] <= 0) {
                burn(tokenTree);
            }
        }
    }

    //Add Health - Chainlink Keeper?
    function addHealth(uint256[] calldata tree, uint256 amt) external onlyOwner {
        uint256 i;
        for (i = 0; i < tree.length; i++) {
            require(health[tree[i]] + amt < 10, "over max health amt");
            require(health[tree[i]] != 0, "no tree in mapping or burned");
            health[tree[i]] = health[tree[i]] + amt;
        }
    }

    //Remove Health - Chainlink Keeper?
    function removeHealth(uint256[] calldata tree, uint256 amt) external onlyOwner {
        uint256 i;
        for (i = 0; i < tree.length; i++) {
            if (!_exists(i)) continue;
            require(health[tree[i]] != 0, "no tree in mapping or burned");
            if (health[tree[i]] - amt <= 0) {
                // delete from tree array?
                burn(tree[i]);
            }
            health[tree[i]] = health[tree[i]] - amt;
        }
    }

    //Get Health...
    function getHealth(uint256 tree) public view returns(uint256) {
        return health[tree];
    }

	/*
	* END
	* CHAINLINK KEEPER SOLUTION *
	*/

    /*
	*	Freezer
	*/

    function setFreeze(address addr) external onlyOwner {
        freezeAcc = addr;
    }

    function freeze(uint256 tree) public {
        require(freezeAcc != address(0), "no freeze address");
        safeTransferFrom(_msgSender(), freezeAcc, tree);
    }
    /*
     *	Burn Lottery
     */

    function getRandomNumber() public returns(bytes32 requestId) {
        require(LINK.balanceOf(address(this)) >= fee, "Not enough LINK - fill contract with faucet");
        return requestRandomness(keyHash, fee);
    }

    /*
     * Callback function used by VRF Coordinator
     */
    function fulfillRandomness(bytes32 requestId, uint256 randomness) internal override {
        randomResult = (randomness % totalSupply());
    }

    //Can get burned by randomResult value,
    //If freeze acc, skip. Get ran
    function burnLottery() public onlyOwner {
        uint256 burned = randomResult;
        address tokenOwner = ownerOf(tokenByIndex(burned));
        if (tokenOwner == freezeAcc) return;
        burn(tokenByIndex(burned));
        payable(tokenOwner).transfer(0.1 ether);
    }

    /*
     * This is how you get one, or more...
     */
    function acquire(uint256 amount) public payable nonReentrant {
        require(amount > 0, "minimum 1 token");
        require(amount <= totalTokenToMint - tokenIndex, "greater than max supply");
        require(isSaleActive, "sale is not active");
        require(amount <= 10, "max 10 tokens at once");
        require(getPricePerToken() * amount == msg.value, "exact value in ETH needed");
        for (uint256 i = 0; i < amount; i++) {
            _mintToken(_msgSender());
        }
    }

    //in case tokens are not sold, admin can mint them for giveaways, airdrops etc
    function adminMint(uint256 amount) public onlyOwner {
        require(amount > 0, "minimum 1 token");
        require(amount <= totalTokenToMint - tokenIndex, "amount is greater than the token available");
        for (uint256 i = 0; i < amount; i++) {
            _mintToken(_msgSender());
        }
    }

    /*
     * Internal mint function
     */
    function _mintToken(address destinationAddress) private {
        tokenIndex++;
        require(!_exists(tokenIndex), "Token already exist.");
        health[tokenIndex] = 5;
        _safeMint(destinationAddress, tokenIndex);
    }

    /*
     * Calculate price for the immediate next NFT minted
     */
    function getPricePerToken() public view returns(uint256) {
        require(totalSupply() < totalTokenToMint, "we're at max supply");
        return price;
    }

    /*
     * Helper function
     */
    function tokensOfOwner(address _owner) external view returns(uint256[] memory) {
        uint256 tokenCount = balanceOf(_owner);
        if (tokenCount == 0) {
            // Return an empty array
            return new uint256[](0);
        } else {
            uint256[] memory result = new uint256[](tokenCount);
            uint256 index;
            for (index = 0; index < tokenCount; index++) {
                result[index] = tokenOfOwnerByIndex(_owner, index);
            }
            return result;
        }
    }

    /*
     * Burn... Exception for owner (Burn lottery, Health mechanism)
     */

    function burn(uint256 tokenId) public virtual {
        require(_isApprovedOrOwner(_msgSender(), tokenId) || msg.sender == owner(), "caller is not contract owner, owner nor approved");
        _burn(tokenId);
    }

    function exists(uint256 _tokenId) external view returns(bool) {
        return _exists(_tokenId);
    }

    function isApprovedOrOwner(address _spender, uint256 _tokenId) external view returns(bool) {
        return _isApprovedOrOwner(_spender, _tokenId);
    }

    function stopSale() external onlyOwner {
        isSaleActive = false;
    }

    function startSale() external onlyOwner {
        isSaleActive = true;
    }

    function tokenURI(uint256 _tokenId) public view override returns(string memory) {
        require(_exists(_tokenId), "ERC721Metadata: URI query for nonexistent token");
        return string(abi.encodePacked(_baseTokenURI, _tokenId.toString()));
    }

    function setBaseURI(string memory newBaseURI) public onlyOwner {
        _baseTokenURI = newBaseURI;
    }

    function setContractURI(string memory newuri) public onlyOwner {
        _contractURI = newuri;
    }

    function contractURI() public view returns(string memory) {
        return _contractURI;
    }

    function withdrawEarnings() public onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }

    //give ether for burn lottery
    function deposit() external payable {}

    function reclaimERC20(IERC20 erc20Token) public onlyOwner {
        erc20Token.transfer(msg.sender, erc20Token.balanceOf(address(this)));
    }
}