pragma solidity ^0.4.18;

/*
  Polymath compliance protocol is intended to ensure regulatory compliance
  in the jurisdictions that security tokens are being offered in. The compliance
  protocol allows security tokens remain interoperable so that anyone can
  build on top of the Polymath platform and extend it's functionality.
*/

import './interfaces/ICompliance.sol';
import './Customers.sol';
import './Template.sol';
import './interfaces/ISecurityToken.sol';

contract Compliance is ICompliance {

    string public VERSION = "0.1";

    // A compliance template
    struct TemplateReputation {
        address owner;
        uint256 totalRaised;
        uint256 timesUsed;
        uint256 expires;
        address[] usedBy;
    }
    mapping(address => TemplateReputation) templates;

    // Template proposals for a specific security token
    mapping(address => address[]) public templateProposals;

    // Smart contract proposals for a specific security token offering
    struct Offering {
        address auditor;
        uint256 fee;
        uint256 vestingPeriod;
        uint8 quorum;
        address[] usedBy;
    }
    mapping(address => Offering) offerings;
    // Security token contract proposals for a specific security token
    mapping(address => address[]) public offeringProposals;

    // Instance of the Compliance contract
    Customers public PolyCustomers;

    // 100 Day minimum vesting period for POLY earned
    uint256 public constant minimumVestingPeriod = 60 * 60 * 24 * 100;

    // Notifications
    event LogTemplateCreated(address indexed creator, address _template, string _offeringType);
    event LogNewTemplateProposal(address indexed _securityToken, address _template, address _delegate);
    event LogNewContractProposal(address indexed _securityToken, address _offeringContract, address _delegate);
    
    /* @param _polyCustomersAddress The address of the Polymath Customers contract */
    function Compliance(address _polyCustomersAddress) public {
        PolyCustomers = Customers(_polyCustomersAddress);
    }

    /* @dev `createTemplate` is a simple function to create a new compliance template
    @param _offeringType The name of the security being issued
    @param _issuerJurisdiction The jurisdiction id of the issuer
    @param _accredited Accreditation status required for investors
    @param _KYC KYC provider used by the template
    @param _details Details of the offering requirements
    @param _expires Timestamp of when the template will expire
    @param _fee Amount of POLY to use the template (held in escrow until issuance)
    @param _quorum Minimum percent of shareholders which need to vote to freeze
    @param _vestingPeriod Length of time to vest funds */
    function createTemplate(
        string _offeringType,
        bytes32 _issuerJurisdiction,
        bool _accredited,
        address _KYC,
        bytes32 _details,
        uint256 _expires,
        uint256 _fee,
        uint8 _quorum,
        uint256 _vestingPeriod
    ) public
    {
        var (,, role, verified, expires) = PolyCustomers.getCustomer(_KYC, msg.sender);
        require(role == 2 && verified && expires > now);
        require(_quorum > 0 && _quorum < 100);
        require(_vestingPeriod >= minimumVestingPeriod);
        address _template = new Template(
            msg.sender,
            _offeringType,
            _issuerJurisdiction,
            _accredited,
            _KYC,
            _details,
            _expires,
            _fee,
            _quorum,
            _vestingPeriod
        );
        templates[_template] = TemplateReputation({
            owner: msg.sender,
            totalRaised: 0,
            timesUsed: 0,
            expires: _expires,
            usedBy: new address[](0)
        });
        LogTemplateCreated(msg.sender, _template, _offeringType);
    }

    /* @dev Propose a bid for a security token issuance
    @param _securityToken The security token being bid on
    @param _template The unique template address
    @return bool success */
    function proposeTemplate(
        address _securityToken,
        address _template
    ) public returns (bool success)
    {
        require(templates[_template].expires > now);
        require(templates[_template].owner == msg.sender);
        templateProposals[_securityToken].push(_template);
        LogNewTemplateProposal(_securityToken, _template, msg.sender);
        return true;
    }

    /* @dev Cancel a Template proposal if the bid hasn't been accepted
    @param _securityToken The security token being bid on
    @param _templateProposalIndex The template proposal array index
    @return bool success */
    function cancelTemplateProposal(
        address _securityToken,
        uint256 _templateProposalIndex
    ) public returns (bool success)
    {
        address proposedTemplate = templateProposals[_securityToken][_templateProposalIndex];
        require(templates[proposedTemplate].owner == msg.sender);
        var (chosenTemplate,,,,) = ISecurityToken(_securityToken).getTokenDetails();
        require(chosenTemplate != proposedTemplate);
        templateProposals[_securityToken][_templateProposalIndex] = address(0);
        return true;
    }

    /* @dev Set the STO contract by the issuer.
       @param _STOAddress address of the STO contract deployed over the network.
       @param _fee fee to be paid in poly to use that contract
       @param _vestingPeriod no. of days investor binded to hold the Security token
       @param _quorum Minimum percent of shareholders which need to vote to freeze*/
    function setSTO (
        address _STOAddress,
        uint256 _fee,
        uint256 _vestingPeriod,
        uint8 _quorum
        ) public returns (bool success)
    {
            require(_STOAddress != address(0));
            require(_quorum > 0 && _quorum < 100);
            require(_vestingPeriod >= minimumVestingPeriod);
            offerings[_STOAddress].auditor = msg.sender;
            offerings[_STOAddress].fee = _fee;
            offerings[_STOAddress].vestingPeriod = _vestingPeriod;
            offerings[_STOAddress].quorum = _quorum;
            return true;
    }

    /* @dev Propose a Security Token Offering Contract for an issuance
    @param _securityToken The security token being bid on
    @param _stoContract The security token offering contract address
    @return bool success */
    function proposeOfferingContract(
        address _securityToken,
        address _stoContract
    ) public returns (bool success)
    {
        var (,,,,KYC) = ISecurityToken(_securityToken).getTokenDetails();
        var (,,, verified, expires) = PolyCustomers.getCustomer(KYC, offerings[_stoContract].auditor);
        require(offerings[_stoContract].auditor == msg.sender);
        require(verified == true);
        require(expires > now);
        offeringProposals[_securityToken].push(_stoContract);
        LogNewContractProposal(_securityToken, _stoContract, msg.sender);
        return true;
    }

    /* @dev Cancel a STO contract proposal if the bid hasn't been accepted
    @param _securityToken The security token being bid on
    @param _offeringProposalIndex The offering proposal array index
    @return bool success */
    function cancelOfferingProposal(
        address _securityToken,
        uint256 _offeringProposalIndex
    ) public returns (bool success)
    {
        address proposedOffering = offeringProposals[_securityToken][_offeringProposalIndex];
        require(offerings[proposedOffering].auditor == msg.sender);
        var (,,,,chosenOffering) = ISecurityToken(_securityToken).getTokenDetails();
        require(chosenOffering != proposedOffering);
        offeringProposals[_securityToken][_offeringProposalIndex] = address(0);
        return true;
    }

    /* @dev `updateTemplateReputation` is a constant function that updates the
     history of a security token template usage to keep track of previous uses
    @param _template The unique template id
    @param _templateIndex The array index of the template proposal */
    function updateTemplateReputation (address _template, uint8 _templateIndex) external returns (bool success) {
        require(templateProposals[msg.sender][_templateIndex] == _template);
        templates[_template].usedBy.push(msg.sender);
        return true;
    }

    /* @dev `updateOfferingReputation` is a constant function that updates the
     history of a security token offering contract to keep track of previous uses
    @param _contractAddress The smart contract address of the STO contract
    @param _offeringProposalIndex The array index of the security token offering proposal */
    function updateOfferingReputation (address _stoContract, uint8 _offeringProposalIndex) external returns (bool success) {
        require(offeringProposals[msg.sender][_offeringProposalIndex] == _stoContract);
        offerings[_stoContract].usedBy.push(msg.sender);
        return true;
    }

    /* @dev Get template details by the proposal index
    @param _securityTokenAddress The security token ethereum address
    @param _templateIndex The array index of the template being checked
    @return Template struct */
    function getTemplateByProposal(address _securityTokenAddress, uint8 _templateIndex) view public returns (
        address template
    ){
        return templateProposals[_securityTokenAddress][_templateIndex];
    }

    /* @dev Get security token offering smart contract details by the proposal index
    @param _securityTokenAddress The security token ethereum address
    @param _offeringProposalIndex The array index of the STO contract being checked
    @return Contract struct */
    function getOfferingByProposal(address _securityTokenAddress, uint8 _offeringProposalIndex) view public returns (
        address stoContract,
        address auditor,
        uint256 vestingPeriod,
        uint8 quorum,
        uint256 fee
    ){
        address _stoContract = offeringProposals[_securityTokenAddress][_offeringProposalIndex];
        return (
            _stoContract,
            offerings[_stoContract].auditor,
            offerings[_stoContract].vestingPeriod,
            offerings[_stoContract].quorum,
            offerings[_stoContract].fee
        );
    }

}
