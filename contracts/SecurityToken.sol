pragma solidity ^0.4.15;

import './SafeMath.sol';
import './interfaces/IERC20.sol';
import './PolyToken.sol';
import './Customers.sol';
import './Compliance.sol';

contract SecurityToken is IERC20 {

    using SafeMath for uint256;

    string public version = '0.1';

    // Compliance Template Proposal
    struct ComplianceTemplate {
      address creator;
      bytes32 securityType;
      bytes32 complianceProcess;
      bytes8 issuerJurisdiction;
      bytes8[] restrictedJurisdictions;
      uint256 templateValidUntil;
      uint256 proposalValidUntil;
      uint256 estimatedTimeToComplete;
      uint256 vestingPeriod;
      uint256 delegateFee;
    }

    // Mapping of Legal Delegate addresses to proposed ComplianceTemplates
    // One legal delegate proposes one compliance template per security token
    mapping(address => ComplianceTemplate) public complianceTemplateProposals;


    // Legal delegate
    address public delegate;

    // Witness of compliance process (merkle root hash)
    bytes32 public complianceWitness;

    // STO address
    address public STO;

    // KYC Provider
    address public KYC;

    // Security Token Whitelisted Investors
    mapping(address => bool) public investors;

    // Instance of the POLY token contract
    PolyToken public POLY;

    Customers PolyCustomers;

    Compliance public ComplianceInstance;

    // ERC20 Fields
    string public name;
    uint8 public decimals;
    string public symbol;
    address public owner;
    uint256 public totalSupply;
    mapping (address => mapping (address => uint256)) allowed;
    mapping (address => uint256) balances;

    // Notifications
    event LogDelegateSet(address indexed delegateAddress);
    event LogComplianceTemplateProposal(address indexed delegateAddress, bytes32 complianceTemplate);
    event LogSecurityTokenOffering(address indexed STOAddress);
    event LogNewComplianceWitness(bytes32 merkleRoot, bytes32 complianceWitnessHash);
    event LogSetKYC(address kycProvider);

    modifier onlyOwner() {
      require (msg.sender == owner);
      _;
    }

    modifier onlyDelegate() {
      require(delegate == msg.sender);
      _;
    }
    
    //Used to allow both to update root hash (complianceWitness state variable)
    modifier onlyDelegateAndOwner() {
      require(delegate == msg.sender || owner == msg.sender);
      _;
    }

    /// Set default security token parameters
    /// @param _name Name of the security token
    /// @param _ticker Ticker name of the security
    /// @param _decimals Divisibility of the token
    /// @param _totalSupply Total amount of tokens being created
    /// @param _owner Ethereum public key address of the security token owner
    function SecurityToken(string _name, string _ticker, uint8 _decimals, uint256 _totalSupply, address _owner, address _polyTokenAddress) {
      owner = _owner;
      name = _name;
      symbol = _ticker;
      decimals = _decimals;
      totalSupply = _totalSupply;
      balances[_owner] = _totalSupply;
      POLY = PolyToken(_polyTokenAddress);
    }

    /// Propose a new compliance template for the Security Token
    /// @param _delegate Legal Delegate public ethereum address
    /// @param _complianceTemplate Compliance Template being proposed
    /// @param _complianceContract The Address of the compliance contract where Templates are stored
    /// @return bool success
    function proposeComplianceTemplate(address _delegate, bytes32 _complianceTemplate, address _complianceContract) returns (bool success) {
      //TODO require(complianceTemplateProposals[_delegate] == address(0));
      // complianceTemplateProposals[_delegate] = _complianceTemplate;

      //Grab the compliance.sol file with contract address, find the template and check if its approved and not expired
      //NOTE.0.1 - not sure if these is exactly how it should be, confused that there is a struct ComplianceTemplate in this sol file, and a struct Template in Compliance.sol
      ComplianceInstance = Compliance(_complianceContract);
      require(ComplianceInstance.templates(_complianceTemplate).approved == true);
      require(ComplianceInstance.templates(_complianceTemplate).expires < now);

      LogComplianceTemplateProposal(_delegate, _complianceTemplate);
      return true;
    }

    /// Accept a Delegate's proposal
    /// @param _delegate Legal Delegates public ethereum address
    /// @return bool success
    function setDelegate(address _delegate) onlyOwner returns (bool success) {
      require(delegate == address(0));
      require(complianceTemplateProposals[_delegate].proposalValidUntil > now);
      require(complianceTemplateProposals[_delegate].templateValidUntil > now);
      require(POLY.balanceOf(this) >= complianceTemplateProposals[_delegate].delegateFee);
      delegate = _delegate;
      LogDelegateSet(_delegate);
      return true;
    }

    /// Update compliance Witness
    /// @param _newMerkleRoot New merkle root hash of the compliance Witnesss
    /// @param _complianceWitness Compliance Witness hash
    /// @return bool success
    function updateComplianceWitness(bytes32 _newMerkleRoot, bytes32 _complianceWitness) onlyDelegateAndOwner returns (bool success) {
      require(msg.sender == owner || msg.sender == delegate);
      complianceWitness = _newMerkleRoot;
      LogNewComplianceWitness(_newMerkleRoot, _complianceWitness);
      return true;
    }

    /// Set the STO contract address
    /// @param _securityTokenOfferingAddress Ethereum address of the STO contract
    /// @return bool success
    function setSTO(address _securityTokenOfferingAddress) onlyDelegate returns (bool success) {
      require(complianceWitness != 0);
      //TODO require(_securityTokenOfferingAddress = address(0));
      STO = _securityTokenOfferingAddress;
      LogSecurityTokenOffering(_securityTokenOfferingAddress);
      return true;
    }

    /// Set the KYC provider
    /// @param _kycProvider Address of KYC provider
    /// @return bool success
    function setKYC(address _kycProvider) onlyOwner returns (bool success) {
      require(_kycProvider != address(0));
      require(complianceWitness != 0);
      KYC = _kycProvider;
      LogSetKYC(_kycProvider);
      return true;
    }

    /// Trasfer tokens from one address to another
    /// @param _to Ethereum public address to transfer tokens to
    /// @param _value Amount of tokens to send
    /// @return bool success
    function transfer(address _to, uint256 _value) returns (bool success) {
      if (investors[_to] && balances[msg.sender] >= _value && _value > 0) {
        balances[msg.sender] = balances[msg.sender].sub(_value);
        balances[_to] = balances[_to].add(_value);
        Transfer(msg.sender, _to, _value);
        return true;
      } else {
        return false;
      }
    }

    /// Allows contracts to transfer tokens on behalf of token holders
    /// @param _from Address to transfer tokens from
    /// @param _to Address to send tokens to
    /// @param _value Number of tokens to transfer
    /// @return bool success
    /// TODO: eliminate msg.sender for 0x
    function transferFrom(address _from, address _to, uint256 _value) returns (bool success) {
      if (investors[_to] && investors[msg.sender] && balances[_from] >= _value && allowed[_from][msg.sender] >= _value && _value > 0) {
        uint256 _allowance = allowed[_from][msg.sender];
        balances[_from] = balances[_from].sub(_value);
        balances[_to] = balances[_to].add(_value);
        allowed[_from][msg.sender] = _allowance.sub(_value);
        Transfer(_from, _to, _value);
        return true;
      } else {
        return false;
      }
    }

    /// @param _owner The address from which the balance will be retrieved
    /// @return The balance
    function balanceOf(address _owner) constant returns (uint256 balance) {
      return balances[_owner];
    }

    /// Approve transfer of tokens manually
    /// @param _spender Address to approve transfer to
    /// @param _value Amount of tokens to approve for transfer
    /// @return bool success
    function approve(address _spender, uint256 _value) returns (bool success) {
      if (investors[_spender]) {
        if ((_value != 0) && (allowed[msg.sender][_spender] != 0)) {
          revert();
        }
        allowed[msg.sender][_spender] = _value;
        Approval(msg.sender, _spender, _value);
        return true;
      } else {
        return false;
      }
    }

    /// @param _owner The address of the account owning tokens
    /// @param _spender The address of the account able to transfer the tokens
    /// @return Amount of remaining tokens allowed to spent
    function allowance(address _owner, address _spender) constant returns (uint256 remaining) {
      return allowed[_owner][_spender];
    }
}
