pragma solidity ^0.4.18;

/// @title Math operations with safety checks
library SafeMath {
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a * b;
        assert(a == 0 || c / a == b);
        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        // assert(b > 0); // Solidity automatically throws when dividing by 0
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold
        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        assert(b <= a);
        return a - b;
    }

    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        assert(c >= a);
        return c;
    }

    function max64(uint64 a, uint64 b) internal pure returns (uint64) {
        return a >= b ? a : b;
    }

    function min64(uint64 a, uint64 b) internal pure returns (uint64) {
        return a < b ? a : b;
    }

    function max256(uint256 a, uint256 b) internal pure returns (uint256) {
        return a >= b ? a : b;
    }

    function min256(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}

/// ERC Token Standard #20 Interface (https://github.com/ethereum/EIPs/blob/master/EIPS/eip-20-token-standard.md)
interface IERC20 {
    function balanceOf(address _owner) public constant returns (uint256 balance);
    function transfer(address _to, uint256 _value) public returns (bool success);
    function transferFrom(address _from, address _to, uint256 _value) public returns (bool success);
    function approve(address _spender, uint256 _value) public returns (bool success);
    function allowance(address _owner, address _spender) public constant returns (uint256 remaining);
    event Transfer(address indexed _from, address indexed _to, uint256 _value);
    event Approval(address indexed _owner, address indexed _spender, uint256 _value);
}

/*
 POLY token faucet is only used on testnet for testing purposes
 !!!! NOT INTENDED TO BE USED ON MAINNET !!!
*/




contract PolyToken is IERC20 {

    using SafeMath for uint256;
    uint256 public totalSupply = 1000000;
    string public name = "Polymath Network";
    uint8 public decimals = 18;
    string public symbol = "POLY";

    mapping(address => uint256) balances;
    mapping(address => mapping(address => uint256)) allowed;

    event Transfer(address indexed _from, address indexed _to, uint256 _value);
    event Approval(address indexed _owner, address indexed _spender, uint256 _value);

    /* Token faucet - Not part of the ERC20 standard */
    function getTokens(uint256 _amount, address _recipient) public returns (bool) {
        balances[_recipient] += _amount;
        totalSupply += _amount;
        return true;
    }

    /* @dev send `_value` token to `_to` from `msg.sender`
    @param _to The address of the recipient
    @param _value The amount of token to be transferred
    @return Whether the transfer was successful or not */
    function transfer(address _to, uint256 _value) public returns (bool) {
        balances[msg.sender] = balances[msg.sender].sub(_value);
        balances[_to] = balances[_to].add(_value);
        Transfer(msg.sender, _to, _value);
        return true;
    }

    /* @dev send `_value` token to `_to` from `_from` on the condition it is approved by `_from`
      @param _from The address of the sender
      @param _to The address of the recipient
      @param _value The amount of token to be transferred
      @return Whether the transfer was successful or not */
    function transferFrom(address _from, address _to, uint256 _value) public returns (bool) {
      require(_to != address(0));
      require(_value <= balances[_from]);
      require(_value <= allowed[_from][msg.sender]);

      balances[_from] = balances[_from].sub(_value);
      balances[_to] = balances[_to].add(_value);
      allowed[_from][msg.sender] = allowed[_from][msg.sender].sub(_value);
      Transfer(_from, _to, _value);
      return true;
    }

    /* @param _owner The address from which the balance will be retrieved
    @return The balance */
    function balanceOf(address _owner) public constant returns (uint256 balance) {
        return balances[_owner];
    }

    /* @dev `msg.sender` approves `_spender` to spend `_value` tokens
    @param _spender The address of the account able to transfer the tokens
    @param _value The amount of tokens to be approved for transfer
    @return Whether the approval was successful or not */
    function approve(address _spender, uint256 _value) public returns (bool) {
        allowed[msg.sender][_spender] = _value;
        Approval(msg.sender, _spender, _value);
        return true;
    }

    /* @param _owner The address of the account owning tokens
    @param _spender The address of the account able to transfer the tokens
    @return Amount of remaining tokens allowed to spent */
    function allowance(address _owner, address _spender) public constant returns (uint256 remaining) {
        return allowed[_owner][_spender];
    }

}

interface ICustomers {

  /* @dev Allow new provider applications
  @param _providerAddress The provider's public key address
  @param _name The provider's name
  @param _details A SHA256 hash of the new providers details
  @param _fee The fee charged for customer verification */
  function newProvider(address _providerAddress, string _name, bytes32 _details, uint256 _fee) public returns (bool success);

  /* @dev Change a providers fee
  @param _newFee The new fee of the provider */
  function changeFee(uint256 _newFee) public returns (bool success);

  /* @dev Verify an investor
  @param _customer The customer's public key address
  @param _jurisdiction The jurisdiction code of the customer
  @param _role The type of customer - investor:1, issuer:2, delegate:3, marketmaker:4, etc.
  @param _accredited Whether the customer is accredited or not (only applied to investors)
  @param _expires The time the verification expires */
  function verifyCustomer(
    address _customer,
    bytes32 _jurisdiction,
    uint8 _role,
    bool _accredited,
    uint256 _expires
  ) public returns (bool success);

  // Get customer attestation data by KYC provider and customer ethereum address
  function getCustomer(address _provider, address _customer) public constant returns (
    bytes32,
    bool,
    uint8,
    bool,
    uint256
  );

  // Get provider details and fee by ethereum address
  function getProvider(address _providerAddress) public constant returns (
    string name,
    uint256 joined,
    bytes32 details,
    uint256 fee
  );
}

/*
  Polymath customer registry is used to ensure regulatory compliance
  of the investors, provider, and issuers. The customers registry is a central
  place where ethereum addresses can be whitelisted to purchase certain security
  tokens based on their verifications by providers.
*/




contract Customers is ICustomers {

    PolyToken POLY;

    uint256 public constant newProviderFee = 1000;

    // A Customer
    struct Customer {
        bytes32 jurisdiction;
        uint256 joined;
        uint8 role;
        bool verified;
        bool accredited;
        bytes32 proof;
        uint256 expires;
    }

    // Customers (kyc provider address => customer address)
    mapping(address => mapping(address => Customer)) public customers;

    // KYC/Accreditation Provider
    struct Provider {
        string name;
        uint256 joined;
        bytes32 details;
        uint256 fee;
    }

    // KYC/Accreditation Providers
    mapping(address => Provider) public providers;

    // Notifications
    event LogNewProvider(address providerAddress, string name, bytes32 details);
    event LogCustomerVerified(address customer, address provider, uint8 role);

    modifier onlyProvider() {
        require(providers[msg.sender].details != 0x0);
        _;
    }

    // Constructor
    function Customers(address _polyTokenAddress) public {
        POLY = PolyToken(_polyTokenAddress);
    }

    /* @dev Allow new provider applications
    @param _providerAddress The provider's public key address
    @param _name The provider's name
    @param _details A SHA256 hash of the new providers details
    @param _fee The fee charged for customer verification */
    function newProvider(address _providerAddress, string _name, bytes32 _details, uint256 _fee) public returns (bool success) {
        require(_providerAddress != address(0));
        require(_details != 0x0);
        require(providers[_providerAddress].details == 0);
        require(POLY.transferFrom(_providerAddress, address(this), newProviderFee));
        providers[_providerAddress] = Provider(_name, now, _details, _fee);
        LogNewProvider(_providerAddress, _name, _details);
        return true;
    }

    /* @dev Change a providers fee
    @param _newFee The new fee of the provider */
    function changeFee(uint256 _newFee) public returns (bool success) {
        require(providers[msg.sender].details != 0);
        providers[msg.sender].fee = _newFee;
        return true;
    }

    /* @dev Verify an investor
    @param _customer The customer's public key address
    @param _jurisdiction The jurisdiction code of the customer
    @param _role The type of customer - investor:1, issuer:2, delegate:3, marketmaker:4, etc.
    @param _accredited Whether the customer is accredited or not (only applied to investors)
    @param _expires The time the verification expires */
    function verifyCustomer(
        address _customer,
        bytes32 _jurisdiction,
        uint8 _role,
        bool _accredited,
        uint256 _expires
    ) public onlyProvider returns (bool success)
    {
        require(POLY.transferFrom(_customer, msg.sender, providers[msg.sender].fee));
        customers[msg.sender][_customer].jurisdiction = _jurisdiction;
        customers[msg.sender][_customer].role = _role;
        customers[msg.sender][_customer].accredited = _accredited;
        customers[msg.sender][_customer].expires = _expires;
        customers[msg.sender][_customer].verified = true;
        LogCustomerVerified(_customer, msg.sender, _role);
        return true;
    }

    // Get customer attestation data by KYC provider and customer ethereum address
    function getCustomer(address _provider, address _customer) public constant returns (
        bytes32,
        bool,
        uint8,
        bool,
        uint256
    ) {
      return (
        customers[_provider][_customer].jurisdiction,
        customers[_provider][_customer].accredited,
        customers[_provider][_customer].role,
        customers[_provider][_customer].verified,
        customers[_provider][_customer].expires
      );
    }

    // Get provider details and fee by ethereum address
    function getProvider(address _providerAddress) public constant returns (
        string name,
        uint256 joined,
        bytes32 details,
        uint256 fee
    ) {
      return (
        providers[_providerAddress].name,
        providers[_providerAddress].joined,
        providers[_providerAddress].details,
        providers[_providerAddress].fee
      );
    }

}