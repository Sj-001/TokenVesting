//SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";



contract NftyDToken is ERC20 {
    uint public startTimestamp;                             //birth time of the contract
    

    // address private founderAddress; 
    // address private teamAddress; 
    // address private operationsAddress; 
    // address private projectsAddress; 
    // address private renaissanceContractAddress; 
    // address private treasuryAddress; 
    
           

    constructor
                            ( 
                                string memory tokenName, 
                                string memory tokenSymbol,
                                address _founderAddress, 
                                address _teamAddress,
                                address _operationsAddress, 
                                address _projectsAddress, 
                                address _renaissanceContractAddress, 
                                address _treasuryAddress
                                
                                
                            ) ERC20(tokenName, tokenSymbol) 
                             
    {
        _mint(_founderAddress, 50000000);                                          
        _mint(_teamAddress, 100000000);
        _mint(_operationsAddress, 60000000);                               
        _mint(_projectsAddress, 90000000);         
        _mint(_renaissanceContractAddress, 200000000);                               
        _mint(_treasuryAddress,  500000000);            
    
        startTimestamp =  block.timestamp;                           

        // 1 billion distributed (minted)
    }   


    fallback() external{
        revert();
    }
}