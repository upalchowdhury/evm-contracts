pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;

import "./GovernorBravoInterfaces.sol";

contract GovernorBravoDelegate is
  GovernorBravoDelegateStorageV1,
  GovernorBravoEvents
{
  string public constant name = "Protocol Governance";

  uint256 public constant MIN_PROPOSAL_THRESHOLD = 10_000; // 10,000 app token

  uint256 public constant MAX_PROPOSAL_THRESHOLD = 100_000; // 100,000 app token

  uint256 public constant MIN_VOTING_PERIOD = 11520; // 48 hours

  uint256 public constant MAX_VOTING_PERIOD = 80640; // About 2 weeks

  uint256 public constant MIN_VOTING_DELAY = 1;

  uint256 public constant MAX_VOTING_DELAY = 40320; // About 1 week

  uint256 public constant noOfVotes = 100_000_000e18; // 1% of app token

  uint256 public constant proposalMaxOperations = 20; // 20 actions

  bytes32 public constant DOMAIN_TYPEHASH =
    keccak256(
      "EIP712Domain(string name,uint256 chainId,address verifyingContract)"
    );

  bytes32 public constant BALLOT_TYPEHASH =
    keccak256("Ballot(uint256 proposalId,uint8 support)");

  function initialize(
    address timelock_,
    address ondo_,
    uint256 votingPeriod_,
    uint256 votingDelay_,
    uint256 proposalThreshold_
  ) public {
    require(
      address(timelock) == address(0),
      "initialize: can only initialize once"
    );
    require(msg.sender == admin, "initialize: admin only");
    require(
      timelock_ != address(0),
      "initialize: invalid timelock address"
    );
    require(
      ondo_ != address(0),
      "invalid address"
    );
    require(
      votingPeriod_ >= MIN_VOTING_PERIOD && votingPeriod_ <= MAX_VOTING_PERIOD,
      "invalid voting period"
    );
    require(
      votingDelay_ >= MIN_VOTING_DELAY && votingDelay_ <= MAX_VOTING_DELAY,
      "invalid voting delay"
    );
    require(
      proposalThreshold_ >= MIN_PROPOSAL_THRESHOLD &&
        proposalThreshold_ <= MAX_PROPOSAL_THRESHOLD,
      "invalid proposal threshold"
    );

    timelock = TimelockInterface(timelock_);
    ondo = OndoInterface(ondo_);
    votingPeriod = votingPeriod_;
    votingDelay = votingDelay_;
    proposalThreshold = proposalThreshold_;
  }


  function propose(
    address[] memory targets,
    uint256[] memory values,
    string[] memory signatures,
    bytes[] memory calldatas,
    string memory description
  ) public returns (uint256) {
    require(
      ondo.getPriorVotes(msg.sender, sub256(block.number, 1)) >
        proposalThreshold,
      "below proposal threshold"
    );
    require(
      targets.length == values.length &&
        targets.length == signatures.length &&
        targets.length == calldatas.length,
      "mismatch"
    );
    require(
      targets.length != 0,
      "must provide actions"
    );
    require(
      targets.length <= proposalMaxOperations,
      "too many actions"
    );

    uint256 latestProposalId = latestProposalIds[msg.sender];
    if (latestProposalId != 0) {
      ProposalState proposersLatestProposalState = state(latestProposalId);
      require(
        proposersLatestProposalState != ProposalState.Active,
        "already active proposal"
      );
      require(
        proposersLatestProposalState != ProposalState.Pending,
        "already pending proposal"
      );
    }

    uint256 startBlock = add256(block.number, votingDelay);
    uint256 endBlock = add256(startBlock, votingPeriod);

    proposalCount++;
    Proposal memory newProposal =
      Proposal({
        id: proposalCount,
        proposer: msg.sender,
        eta: 0,
        targets: targets,
        values: values,
        signatures: signatures,
        calldatas: calldatas,
        startBlock: startBlock,
        endBlock: endBlock,
        forVotes: 0,
        againstVotes: 0,
        abstainVotes: 0,
        canceled: false,
        executed: false
      });

    proposals[newProposal.id] = newProposal;
    latestProposalIds[newProposal.proposer] = newProposal.id;

    emit ProposalCreated(
      newProposal.id,
      msg.sender,
      targets,
      values,
      signatures,
      calldatas,
      startBlock,
      endBlock,
      description
    );
    return newProposal.id;
  }


  function queue(uint256 proposalId) external {
    require(
      state(proposalId) == ProposalState.Succeeded,
      "proposal can only be queued if it is succeeded"
    );
    Proposal storage proposal = proposals[proposalId];
    uint256 eta = add256(block.timestamp, timelock.delay());
    for (uint256 i = 0; i < proposal.targets.length; i++) {
      queueOrRevertInternal(
        proposal.targets[i],
        proposal.values[i],
        proposal.signatures[i],
        proposal.calldatas[i],
        eta
      );
    }
    proposal.eta = eta;
    emit ProposalQueued(proposalId, eta);
  }

  function queueOrRevertInternal(
    address target,
    uint256 value,
    string memory signature,
    bytes memory data,
    uint256 eta
  ) internal {
    require(
      !timelock.queuedTransactions(
        keccak256(abi.encode(target, value, signature, data, eta))
      ),
      "identical proposal action already queued at eta"
    );
    timelock.queueTransaction(target, value, signature, data, eta);
  }


  function execute(uint256 proposalId) external payable {
    require(
      state(proposalId) == ProposalState.Queued,
      "proposal can only be executed if it is queued"
    );
    Proposal storage proposal = proposals[proposalId];
    proposal.executed = true;
    for (uint256 i = 0; i < proposal.targets.length; i++) {
      timelock.executeTransaction.value(proposal.values[i])(
        proposal.targets[i],
        proposal.values[i],
        proposal.signatures[i],
        proposal.calldatas[i],
        proposal.eta
      );
    }
    emit ProposalExecuted(proposalId);
  }


  function cancel(uint256 proposalId) external {
    require(
      state(proposalId) != ProposalState.Executed,
      "GovernorBravo::cancel: cannot cancel executed proposal"
    );

    Proposal storage proposal = proposals[proposalId];
    require(
      msg.sender == proposal.proposer ||
        ondo.getPriorVotes(proposal.proposer, sub256(block.number, 1)) <
        proposalThreshold,
      "proposer above threshold"
    );

    proposal.canceled = true;
    for (uint256 i = 0; i < proposal.targets.length; i++) {
      timelock.cancelTransaction(
        proposal.targets[i],
        proposal.values[i],
        proposal.signatures[i],
        proposal.calldatas[i],
        proposal.eta
      );
    }

    emit ProposalCanceled(proposalId);
  }

  function getActions(uint256 proposalId)
    external
    view
    returns (
      address[] memory targets,
      uint256[] memory values,
      string[] memory signatures,
      bytes[] memory calldatas
    )
  {
    Proposal storage p = proposals[proposalId];
    return (p.targets, p.values, p.signatures, p.calldatas);
  }

  function getReceipt(uint256 proposalId, address voter)
    external
    view
    returns (Receipt memory)
  {
    return proposals[proposalId].receipts[voter];
  }

  function state(uint256 proposalId) public view returns (ProposalState) {
    require(
      proposalCount >= proposalId && proposalId > initialProposalId,
      "invalid proposal id"
    );
    Proposal storage proposal = proposals[proposalId];
    if (proposal.canceled) {
      return ProposalState.Canceled;
    } else if (block.number <= proposal.startBlock) {
      return ProposalState.Pending;
    } else if (block.number <= proposal.endBlock) {
      return ProposalState.Active;
    } else if (
      proposal.forVotes <= proposal.againstVotes ||
      proposal.forVotes < quorumVotes
    ) {
      return ProposalState.Defeated;
    } else if (proposal.eta == 0) {
      return ProposalState.Succeeded;
    } else if (proposal.executed) {
      return ProposalState.Executed;
    } else if (
      block.timestamp >= add256(proposal.eta, timelock.gracePeriod())
    ) {
      return ProposalState.Expired;
    } else {
      return ProposalState.Queued;
    }
  }


  function castVote(uint256 proposalId, uint8 support) external {
    emit VoteCast(
      msg.sender,
      proposalId,
      support,
      castVoteInternal(msg.sender, proposalId, support),
      ""
    );
  }

  function castVoteWithReason(
    uint256 proposalId,
    uint8 support,
    string calldata reason
  ) external {
    emit VoteCast(
      msg.sender,
      proposalId,
      support,
      castVoteInternal(msg.sender, proposalId, support),
      reason
    );
  }


  function castVoteBySig(
    uint256 proposalId,
    uint8 support,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external {
    bytes32 domainSeparator =
      keccak256(
        abi.encode(
          DOMAIN_TYPEHASH,
          keccak256(bytes(name)),
          getChainIdInternal(),
          address(this)
        )
      );
    bytes32 structHash =
      keccak256(abi.encode(BALLOT_TYPEHASH, proposalId, support));
    bytes32 digest =
      keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    address signatory = ecrecover(digest, v, r, s);
    require(
      signatory != address(0),
      "invalid signature"
    );
    emit VoteCast(
      signatory,
      proposalId,
      support,
      castVoteInternal(signatory, proposalId, support),
      ""
    );
  }

  function castVoteInternal(
    address voter,
    uint256 proposalId,
    uint8 support
  ) internal returns (uint96) {
    require(
      state(proposalId) == ProposalState.Active,
      "voting is closed"
    );
    require(support <= 2, "invalid vote type");
    Proposal storage proposal = proposals[proposalId];
    Receipt storage receipt = proposal.receipts[voter];
    require(
      receipt.hasVoted == false,
      "voter already voted"
    );
    uint96 votes = ondo.getPriorVotes(voter, proposal.startBlock);

    if (support == 0) {
      proposal.againstVotes = add256(proposal.againstVotes, votes);
    } else if (support == 1) {
      proposal.forVotes = add256(proposal.forVotes, votes);
    } else if (support == 2) {
      proposal.abstainVotes = add256(proposal.abstainVotes, votes);
    }

    receipt.hasVoted = true;
    receipt.support = support;
    receipt.votes = votes;

    return votes;
  }

  function _setVotingDelay(uint256 newVotingDelay) external {
    require(msg.sender == admin, "GovernorBravo::_setVotingDelay: admin only");
    require(
      newVotingDelay >= MIN_VOTING_DELAY && newVotingDelay <= MAX_VOTING_DELAY,
      "invalid voting delay"
    );
    uint256 oldVotingDelay = votingDelay;
    votingDelay = newVotingDelay;

    emit VotingDelaySet(oldVotingDelay, votingDelay);
  }


  function _setVotingPeriod(uint256 newVotingPeriod) external {
    require(msg.sender == admin, "GovernorBravo::_setVotingPeriod: admin only");
    require(
      newVotingPeriod >= MIN_VOTING_PERIOD &&
        newVotingPeriod <= MAX_VOTING_PERIOD,
      "invalid voting period"
    );
    uint256 oldVotingPeriod = votingPeriod;
    votingPeriod = newVotingPeriod;

    emit VotingPeriodSet(oldVotingPeriod, votingPeriod);
  }

  function _setProposalThreshold(uint256 newProposalThreshold) external {
    require(
      msg.sender == admin,
      "GovernorBravo::_setProposalThreshold: admin only"
    );
    require(
      newProposalThreshold >= MIN_PROPOSAL_THRESHOLD &&
        newProposalThreshold <= MAX_PROPOSAL_THRESHOLD,
      "invalid proposal threshold"
    );
    uint256 oldProposalThreshold = proposalThreshold;
    proposalThreshold = newProposalThreshold;

    emit ProposalThresholdSet(oldProposalThreshold, proposalThreshold);
  }

  function _initiate() external {
    require(msg.sender == admin, "admin only");
    require(
      initialProposalId == 0,
      "can only initiate once"
    );
    timelock.acceptAdmin();
  }


  function _setPendingAdmin(address newPendingAdmin) external {
    // Check caller = admin
    require(msg.sender == admin, "admin only");

    // Save current value, if any, for inclusion in log
    address oldPendingAdmin = pendingAdmin;

    // Store pendingAdmin with value newPendingAdmin
    pendingAdmin = newPendingAdmin;

    // Emit NewPendingAdmin(oldPendingAdmin, newPendingAdmin)
    emit NewPendingAdmin(oldPendingAdmin, newPendingAdmin);
  }

  function _acceptAdmin() external {
    // Check caller is pendingAdmin and pendingAdmin ≠ address(0)
    require(
      msg.sender == pendingAdmin && msg.sender != address(0),
      "pending admin only"
    );

    // Save current values for inclusion in log
    address oldAdmin = admin;
    address oldPendingAdmin = pendingAdmin;

    // Store admin with value pendingAdmin
    admin = pendingAdmin;

    // Clear the pending value
    pendingAdmin = address(0);

    emit NewAdmin(oldAdmin, admin);
    emit NewPendingAdmin(oldPendingAdmin, pendingAdmin);
  }

  function add256(uint256 a, uint256 b) internal pure returns (uint256) {
    uint256 c = a + b;
    require(c >= a, "addition overflow");
    return c;
  }

  function sub256(uint256 a, uint256 b) internal pure returns (uint256) {
    require(b <= a, "subtraction underflow");
    return a - b;
  }

  function getChainIdInternal() internal pure returns (uint256) {
    uint256 chainId;
    assembly {
      chainId := chainid()
    }
    return chainId;
  }
}