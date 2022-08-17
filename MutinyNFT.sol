// SPDX-License-Identifier: MIT

pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

/**
 * @dev Interface for the `CommunityProposals` contract.
 */
interface ICommunityProposals {
    function submitProposal(
        string calldata,
        address,
        string calldata
    ) external returns (uint256);

    function voteOnProposal(uint256, bool) external;

    function getProposalForExecution(uint256)
        external
        returns (address, string memory);

    function setProposalExecuted(uint256 proposalNumber_) external;
}

/**
 * @title Community Proposals
 *
 * @dev Contract allows holders of the NFT defined in `_nftContract` to submit
 * proposals that may be voted on by other holders. These proposals may specify
 * a fuction to run on a separate smart contract that will be executed via
 * `delegatecall` by the `nftContract`. This means that any approved community
 * proposals may alter any state variables of the `nftContract`, effectively
 * giving the community total control over the NFT.
 */
contract CommunityProposals {
    address private _deployer;
    IERC721 private _nftContract;

    // Current community proposal number
    uint256 proposalNumber = 1;
    // Proposal number => IPFS link of outline
    mapping(uint256 => string) public outlines;
    // Proposal number => contract address
    mapping(uint256 => address) public contractAddresses;
    // Proposal number => contract function signature
    mapping(uint256 => string) public functionSignatures;
    // Proposal number => total votes
    mapping(uint256 => uint256) public totalVotes;
    // Proposal number => total votes in favor
    mapping(uint256 => uint256) public votesInFavor;
    // Proposal number => approval status
    mapping(uint256 => bool) public approvals;
    // Proposal number => whether proposal has been executed
    mapping(uint256 => bool) public executed;
    // Proposal number => voting deadline
    mapping(uint256 => uint256) public deadlines;
    // Proposal number => (token ID => voted)
    mapping(uint256 => mapping(uint256 => bool)) public votesByTokenId;

    /**
     * @dev Constructor sets the `_deployer` address.
     *
     * Note that `_deployer` is used only to set the `_nftContract` address
     * then immediately overwritten to the 0 address.
     */
    constructor(address deployer) {
        _deployer = deployer;
    }

    /**
     * @dev Requires `msg.sender` is an NFT holder.
     */
    modifier msgSenderIsNftHolder() {
        uint256 nftBalanceOfMsgSender = _nftContract.balanceOf(msg.sender);
        require(
            nftBalanceOfMsgSender > 0,
            "CommunityProposals: Feature only available to NFT holders"
        );
        _;
    }

    /**
     * @dev Requires `proposalNumber_` is valid.
     */
    modifier proposalExists(uint256 proposalNumber_) {
        require(
            proposalNumber_ > 0 && proposalNumber_ < proposalNumber,
            "CommunityProposals: Invalid proposal number"
        );
        _;
    }

    /**
     * @dev Proposal `proposalNumber_` was created.
     */
    event ProposalCreated(
        uint256 proposalNumber_,
        string outline,
        address contractAddress,
        string functionSignature
    );

    /**
     * @dev Proposal `proposalNumber_` was approved.
     */
    event ProposalApproved(uint256 proposalNumber_);

    /**
     * @dev Proposal `proposalNumber_` was disapproved.
     */
    event ProposalDenied(uint256 proposalNumber_);

    /**
     * @dev Creates a new proposal and returns its proposal number.
     *
     * Note that `outline` is intended to be an IPFS link to the proposal's
     * details, but this is only a suggestion. The `contractAddress` may be the
     * 0 address and `functionSignature` may be an empty string if proposal
     * does not require code execution.
     */
    function submitProposal(
        string calldata outline,
        address contractAddress,
        string calldata functionSignature
    ) external msgSenderIsNftHolder returns (uint256) {
        require(
            contractAddress != address(this),
            "CommunityProposals: Contract address cannot be this contract"
        );
        require(
            contractAddress != address(_nftContract),
            "CommunityProposals: Contract address cannot be NFT contract"
        );

        // Create a new proposal
        outlines[proposalNumber] = outline;
        contractAddresses[proposalNumber] = contractAddress;
        functionSignatures[proposalNumber] = functionSignature;
        totalVotes[proposalNumber] = 0;
        votesInFavor[proposalNumber] = 0;
        executed[proposalNumber] = false;

        // @todo implement deadline here ... is this variable?
        deadlines[proposalNumber] = 0;

        emit ProposalCreated(
            proposalNumber,
            outline,
            contractAddress,
            functionSignature
        );

        // Increment current proposal number and return
        return proposalNumber += 1;
    }

    /**
     * @dev Logs vote of `msg.sender` on proposal `proposalNumber_`.
     *
     * Note that only votes in favor of the proposal need to be logged as votes
     * against may be calculated from: (total votes) -( votes in favor).
     */
    function voteOnProposal(
        uint256 proposalNumber_,
        uint256 tokenId,
        bool voteInFavor
    ) external proposalExists(proposalNumber_) msgSenderIsNftHolder {
        address ownerOfTokenId = _nftContract.ownerOf(msg.sender);

        require(
            msg.sender == ownerOfTokenId,
            "CommunityProposals: Feature only available to NFT holder"
        );

        totalVotes[proposalNumber_] += 1;
        votesByTokenId[proposalNumber_][tokenId] = true;

        if (voteInFavor) {
            votesInFavor[proposalNumber_] += 1;
        }
    }

    /**
     * @dev Approves `proposalNumber_` if approval conditions have been met.
     */
    function approveProposal(uint256 proposalNumber_) external {
        bool approvalConditionsMet = true;

        if (approvalConditionsMet) {
            approvals[proposalNumber_] = true;
        }
    }

    /**
     * @dev Returns proposal contract address and function signature for
     * execution by the NFT contract via `delegatecall`.
     */
    function getProposalForExecution(uint256 proposalNumber_)
        external
        proposalExists(proposalNumber_)
        returns (address, string memory)
    {
        require(
            contractAddresses[proposalNumber_] != address(0),
            "CommunityProposals: Proposal has no contract address"
        );
        require(
            functionSignatures[proposalNumber_] != "",
            "CommunityProposals: Proposal has no function signature"
        );
        require(
            approvals[proposalNumber_],
            "CommunityProposals: Proposal not approved"
        );

        return (
            contractAddresses[proposalNumber_],
            functionSignatures[proposalNumber_]
        );
    }

    /**
     * @dev Sets `executed` to true for `proposalNumber_`
     */
    function setProposalExecuted(uint256 proposalNumber_)
        external
        proposalExists(proposalNumber_)
    {
        require(
            msg.sender == address(_nftContract),
            "CommunityProposals: Feature only available to NFT contract"
        );

        executed[proposalNumber_] = true;
    }

    /**
     * @dev Sets `_nftContractAddress` then renounces contract ownership by
     * setting `_deployer` to 0 address.
     */
    function setNftContractAddress(address nftContractAddress) external {
        require(
            msg.sender == _deployer,
            "CommunityProposals: Feature only available to deployer"
        );

        // Set NFT contract address
        _nftContract = IERC721(nftContractAddress);
        // Renounce contract ownership!
        _deployer = address(0);
    }
}

/**
 * @title Mutiny NFT
 *
 * @dev An ERC721 token contract that allows community-generated proposals to
 * potentially make changes to any of the contract's state variables.
 */
contract MutinyNFT is ERC721 {
    address public owner;

    // PRICE, discordLink, website, etc.
    // bytes32 array for message?

    /**
     * @dev Constructor runs ERC721 constructor and sets `owner` to
     * `msg.sender`.
     */
    constructor(string calldata name, string calldata symbol)
        ERC721(name, symbol)
    {
        owner = msg.sender;
    }

    /**
     * @dev Executes `proposalNumber` proposal in the context of this contract.
     *
     * Note that the `CommunityProposals` contract is responsible for ensuring
     * the proposal can, in fact, be executed, and will revert otherwise.
     */
    function executeProposal(uint256 proposalNumber) external {
        // Note this address is hardcoded to prevent being overwritten by a community proposal
        address communityProposalsContractAddress = 0x00;

        // Get proposal's contract address and function signature
        (
            address contractAddress,
            string memory signature
        ) = ICommunityProposals(communityProposalsContractAddress)
                .getProposalForExecution(proposalNumber);

        // Execute proposal code
        (bool success, bytes memory data) = contractAddress.delegatecall(
            abi.encodeWithSignature(signature)
        );

        // If proposal successfully executed, update proposal to reflect that fact
        if (success) {
            ICommunityProposals(communityProposalsContractAddress)
                .setProposalExecuted(proposalNumber);
        }
    }

    // Note: maybe code creator royalties into actual tx functions
    // function transferCreatorRoyalties(uint256 amount) external {
    //     address creatorAddress = 0xE0f5206BBD039e7b0592d8918820024e2a7437b9;

    //     payable(creatorAddress).transfer(address(this).balance);
    // }
}
