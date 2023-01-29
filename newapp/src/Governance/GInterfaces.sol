pragma solidity 0.8.13;


contract GEvents {
  /// @notice An event emitted when a new proposal is created
  event ProposalCreated(
    uint256 id,
    address proposer,
    address[] targets,
    uint256[] values,
    string[] signatures,
    bytes[] calldatas,
    uint256 startBlock,
    uint256 endBlock,
    string description
  );

 
  /// @param voter The address which casted a vote
  event VoteCast(
    address indexed voter,
    uint256 proposalId,
    uint8 support,
    uint256 votes,
    string reason
  );


  event ProposalCanceled(uint256 id);

  event ProposalQueued(uint256 id, uint256 eta);

  event ProposalExecuted(uint256 id);

  event VotingDelaySet(uint256 oldVotingDelay, uint256 newVotingDelay);

  event VotingPeriodSet(uint256 oldVotingPeriod, uint256 newVotingPeriod);

  event NewImplementation(address oldImplementation, address newImplementation);

  event ProposalThresholdSet(
    uint256 oldProposalThreshold,
    uint256 newProposalThreshold
  );

  event NewPendingAdmin(address oldPendingAdmin, address newPendingAdmin);

  event NewAdmin(address oldAdmin, address newAdmin);
}

contract GDelegator {
  address public admin;
  address public pendingAdmin;
  address public implementation;
}

contract GDStorage is GDelegator {
  uint256 public votingDelay;

  uint256 public votingPeriod;

  uint256 public proposalThreshold;

  uint256 public initialProposalId;

  uint256 public proposalCount;

  TimelockInterface public timelock;

  AInterface public app;

  mapping(uint256 => Proposal) public proposals;

  mapping(address => uint256) public latestProposalIds;

  struct Proposal {
    uint256 id;
    address proposer;
    uint256 eta;
    address[] targets;
    uint256[] values;
    string[] signatures;
    bytes[] calldatas;
    uint256 startBlock;
    uint256 endBlock;
    uint256 forVotes;
    uint256 againstVotes;
    uint256 abstainVotes;
    bool canceled;
    bool executed;
    mapping(address => Receipt) receipts;
  }

  struct Receipt {
    bool hasVoted;
    uint8 support;
    uint96 votes;
  }

  enum ProposalState {
    Pending,
    Active,
    Canceled,
    Defeated,
    Succeeded,
    Queued,
    Expired,
    Executed
  }
}

interface TimelockInterface {
  function delay() external view returns (uint256);

  function gracePeriod() external view returns (uint256);

  function acceptAdmin() external;

  function queuedTransactions(bytes32 hash) external view returns (bool);

  function queueTransaction(
    address target,
    uint256 value,
    string calldata signature,
    bytes calldata data,
    uint256 eta
  ) external returns (bytes32);

  function cancelTransaction(
    address target,
    uint256 value,
    string calldata signature,
    bytes calldata data,
    uint256 eta
  ) external;

  function executeTransaction(
    address target,
    uint256 value,
    string calldata signature,
    bytes calldata data,
    uint256 eta
  ) external payable returns (bytes memory);
}

interface AInterface {
  function getPriorVotes(address account, uint256 blockNumber)
    external
    view
    returns (uint96);
}