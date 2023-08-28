// SPDX-License-Identifier: MIT

pragma solidity ^0.8.21;

import "./utils/Delegated.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/finance/PaymentSplitter.sol";
import "operator-filter-registry/src/DefaultOperatorFilterer.sol";

contract LazyButts is
    DefaultOperatorFilterer,
    Delegated,
    PaymentSplitter,
    ERC721
{
    using Strings for uint;

    uint256 public price = 0.02 ether;
    
    string private _tokenURIPrefix = "https://api.the3dkings.io/api/metadata/";
    string private _tokenURISuffix = ".json";

    bytes32 public merkleRoot;
    bool public isAllowListActive = true;
    bool public isMintActive = false;

    IERC721 private LazyLions =
        IERC721(0x8943C7bAC1914C9A7ABa750Bf2B6B09Fd21037E0);

    event Mint(address indexed to, uint indexed tokenId);
    
    mapping (address => bool) public allowListMinted;

    address[] private _payees = [
        0x7B850fEf1064680d2F9e86CD1a0B83C052a2620c, // Community Wallet
        0x4cbF16139474316F4Ab10ec251195f992Bbe8B12, // Operational Wallet
        0x9e25Ce06a0b5Df2C8D7A8893E83AfB89966BfC92, // Team Member Wallet
        0x4517b0f5d99115223904D5f56DF5352A88c9b711, // Team Member Wallet
        0xc8028BDA23BbCF532A1352Df138d4634aFc91B8c, // Team Member Wallet
        0x0F6FCd1C0cfdD60d1f21A4A4Aa0f47a2B21d5e82 // Team Member Wallet
    ];

    uint256[] private _shares = [5000, 1000, 1000, 1000, 1000, 1000];

    constructor()
        Delegated()
        ERC721("Lazy Butts", "BUTTS")
        PaymentSplitter(_payees, _shares)
    {}

    /**
     * @param tokenId Id of token to check
     * @dev Checks if token exists and returns metadata URI
     */
    function tokenURI(
        uint tokenId
    ) public view override returns (string memory) {
        require(_exists(tokenId), "Token does not exist");
        return
            string(
                abi.encodePacked(
                    _tokenURIPrefix,
                    tokenId.toString(),
                    _tokenURISuffix
                )
            );
    }

    /**
     * @dev Checks if sender is tx.origin
     */
    modifier onlySender {
        require(msg.sender == tx.origin, "Only sender allowed");
        _;
    }

    /**
     * @dev Checks if mint is active
     */
    modifier mintActive {
        require(isMintActive, "Mint is not active");
        _;
    }

    /**
     * @param lionId Id of token to mint
     * @dev Mints token to owner
     */
    function mintButt(uint lionId) external payable onlySender mintActive {
        require(!_exists(lionId), "Token already minted");
        require(msg.value == price, "Not enough ether sent");
        address lion = LazyLions.ownerOf(lionId);
        _mint(lion, lionId);
        emit Mint(lion, lionId);
    }

    /**
     * @param lionIds Array of tokenIds to mint
     * @dev Mints tokens to owners
     */
    function mintManyButts(uint[] calldata lionIds) external payable onlySender mintActive {
        require(lionIds.length > 0, "No tokens to mint");
        require(msg.value == price * lionIds.length, "Not enough ether sent");
        address[] memory owners = new address[](lionIds.length);
        owners = _getLionOwners(lionIds);
        _mintMany(owners, lionIds);
    }

    /**
     * @param tokenIds Array of tokenIds to mint
     * @dev Mints tokens to owners
     * @dev Only callable by delegates
     */
    function buttDrop(uint[] calldata tokenIds) public payable onlyDelegates {
        require(tokenIds.length > 0, "No tokens to mint");
        address[] memory owners = new address[](tokenIds.length);
        owners = _getLionOwners(tokenIds);
        _mintMany(owners, tokenIds);
    }

    /**
     * @param tokenIds Array of tokenIds to check
     * @dev Gets owners of tokens
     */
    function _getLionOwners(
        uint[] memory tokenIds
    ) internal view returns (address[] memory owners) {
        owners = new address[](tokenIds.length);
        for (uint i; i < tokenIds.length; ++i) {
            require(!_exists(tokenIds[i]), "Token already minted");
            address lion = LazyLions.ownerOf(tokenIds[i]);
            owners[i] = lion;
        }
        return owners;
    }

    /**
     * @param owners Array of addresses to mint tokens to
     * @param lionIds Array of tokenIds to mint
     * @dev Mints tokens to owners
     */
    function _mintMany(
        address[] memory owners,
        uint[] memory lionIds
    ) internal {
        for (uint i; i < lionIds.length; ++i) {
            _mint(owners[i], lionIds[i]);
            emit Mint(owners[i], lionIds[i]);
        }
    }

    /**
     * @param prefix New prefix to append to tokenURI
     * @dev Only callable by delegates
     */
    function setTokenURIPrefix(string calldata prefix) external onlyDelegates {
        require(
            keccak256(abi.encodePacked(prefix)) !=
                keccak256(abi.encodePacked(_tokenURIPrefix)),
            "Prefix already set"
        );
        _tokenURIPrefix = prefix;
    }

    /**
     * @param suffix New suffix to append to tokenURI
     * @dev Only callable by delegates
     */
    function setTokenURISuffix(string calldata suffix) external onlyDelegates {
        require(
            keccak256(abi.encodePacked(suffix)) !=
                keccak256(abi.encodePacked(_tokenURISuffix)),
            "Suffix already set"
        );
        _tokenURISuffix = suffix;
    }

    /**
     * @param lazyLions Address of Lazy Lions contract
     * @dev Only callable by delegates
     */
    function setLazyLions(address lazyLions) external onlyDelegates {
        require(lazyLions != address(LazyLions), "Lazy Lions already set");
        LazyLions = IERC721(lazyLions);
    }

    /**
     * @param newPrice New price in wei
     * @dev Only callable by delegates
     */
    function updatePrice(uint256 newPrice) external onlyDelegates {
        require(newPrice != price, "Price already set");
        price = newPrice;
    }

    // Access List Functions

    /**
     * @param address_ Address to check
     * @param proof_ Merkle proof
     * @dev Checks merkle proof to determine if address is allowlisted.
     * @dev Merkle proof is generated off-chain.
     */
    function isAllowListed(address address_, bytes32[] memory proof_) public view returns (bool) {
        bytes32 _leaf = keccak256(abi.encodePacked(address_));

        for (uint i = 0; i < proof_.length; i++) {
            _leaf = _leaf < proof_[i] ? keccak256(abi.encodePacked(_leaf, proof_[i])) : keccak256(abi.encodePacked(proof_[i], _leaf));
        }
        return _leaf == merkleRoot;
    }

    /**
     * @param proof_ Merkle proof
     * @param lionIds Array of tokenIds to mint
     * @dev Public mint function for allowlist. Follows same rules as public mint, but requires merkle proof.
     */
    function mintAllowList(bytes32[] memory proof_, uint[] calldata lionIds) external payable {
        address _minter = msg.sender;
        require(isAllowListActive, "Allowlist is not active!");
        require(isAllowListed(_minter, proof_), "Address is not allowlisted!");
        require(lionIds.length > 0, "No tokens to mint");
        uint256 _totalPrice = allowListMinted[_minter] ? price * lionIds.length : lionIds.length > 1 ? price / 2 + price * (lionIds.length - 1) : price / 2;
        require(msg.value == _totalPrice, "Not enough ether sent");
        if (!allowListMinted[_minter]) allowListMinted[_minter] = true;
        address[] memory owners = new address[](lionIds.length);
        owners = _getLionOwners(lionIds);
        _mintMany(owners, lionIds);
    }

    /**
     * @notice Sets the merkle root for the allowlist. Can only be called by delegates.
     */ 
    function setMerkleRoot(bytes32 merkleRoot_) external onlyDelegates {
        merkleRoot = merkleRoot_;
    }

    /**
     * @notice Toggle the allowlist active state. Can only be called by delegates.
     */
    function setAllowListActive(bool isAllowListActive_) external onlyDelegates {
        require(isAllowListActive != isAllowListActive_, "Allowlist already set");
        isAllowListActive = isAllowListActive_;
    }

    /**
     * @notice Toggle the mint active state. Can only be called by delegates.
     */
    function setMintActive(bool isMintActive_) external onlyDelegates {
        require(isMintActive != isMintActive_, "Mint already set");
        isMintActive = isMintActive_;
    }

    // ERC721 Overrides for OpenSea's Operator Filter 
    function setApprovalForAll(
        address operator,
        bool approved
    ) public override onlyAllowedOperatorApproval(operator) {
        super.setApprovalForAll(operator, approved);
    }

    function approve(
        address operator,
        uint256 tokenId
    ) public override onlyAllowedOperatorApproval(operator) {
        super.approve(operator, tokenId);
    }

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public override onlyAllowedOperator(from) {
        super.transferFrom(from, to, tokenId);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public override onlyAllowedOperator(from) {
        super.safeTransferFrom(from, to, tokenId);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) public override onlyAllowedOperator(from) {
        super.safeTransferFrom(from, to, tokenId, data);
    }
}
