# Summary
Some miscellaneous snippets and a few custom modules related to maintaining the Engineering college's standardized MECM deployments and collections.

Org shared deployment model documentation home: https://wiki.illinois.edu/wiki/display/engritprivate/SCCM+-+Org+shared+collections+and+deployments  

# Requirements
- Currently these custom modules have only been written for and tested with Powershell 5.1. While modern versions of Configuration Manager [support Powershell 7](https://docs.microsoft.com/en-us/powershell/sccm/overview?view=sccm-ps#support-for-powershell-version-7), there are apparently some differences which these scripts do not account for, and there are known Powershell 7 compatibility issues with at least New-CMOrgModelDeploymentCollection.psm1, and possible others.  

# org-shared-deployments-misc.ps1

This doc just contains several snippets for doing various bulk or repetitive actions related to the shared deployments and collections.  
NOT intended to be run as a holistic script.  
Read and understand the code before using.  

# Other modules
These other useful modules have been moved to their own repos for easier maintenance.  

### Prep-MECM
Prepares a connection to MECM so cmdlets from the ConfigurationManager Powershell module can be used.  
https://github.com/engrit-illinois/Prep-MECM  

### New-CMOrgModelDeploymentCollection
A module for creating standardized deployment collections  
https://github.com/engrit-illinois/New-CMOrgModelDeploymentCollection  

### Get-CollsWhichIncludeColl
A module to return the list of collections in which a given collection is included  
https://github.com/engrit-illinois/Get-CMCollsWhichIncludeColl  

### Get-DeploymentReport
Polls SCCM for information about all deployments and exports to a CSV  
https://github.com/engrit-illinois/Get-DeploymentReport  

### Report-UnnecessaryDirectDeployments
A module to list all deployments which are technically duplicates of existing org-level deployments  
https://github.com/engrit-illinois/Report-UnnecessaryDirectDeployments  

### Get-AppSupersedence
Analyzes data from MECM to identify mis-configured application packages, which cause deployment issues  
https://github.com/engrit-illinois/Get-AppSupersedence  

### Compare-AssignmentRevisions
Collects MECM client data directly from mass endpoints for analysis to identify issues related to deployment bugs in MECM  
https://github.com/engrit-illinois/Compare-AssignmentRevisions  

### Get-CMAppFromContentId
Tries to find the name of the MECM application package associated with a given Content ID.  
https://github.com/engrit-illinois/Get-CMAppFromContentId  

### Get-CMCollectionMembersWithAdOus
Returns all MECM devices in matching collections along with their resource information, including their parent Active Directory OU.  
https://github.com/engrit-illinois/Get-CMCollectionMembersWithAdOus  

### Get-MecmCollegePrefixes
Retrieve all college computer name prefixes used by your "All Systems" collection to determine which newly imported computer objects to include  
https://github.com/engrit-illinois/Get-MecmCollegePrefixes  

### force-mecm-baseline-evaluation
Force a list of remote MECM client to re-evaluate their configuration baselines  
https://github.com/engrit-illinois/force-mecm-baseline-evaluation  

### force-software-center-assignment-evaluation
Force the local MECM client (or a list of remote MECM clients) to re-evaluate assignments. Credit goes to UIUC Endpoint Services (EPS) team.  
https://github.com/engrit-illinois/force-software-center-assignment-evaluation  

# Notes
- By mseng3. See my other projects here: https://github.com/mmseng/code-compendium.
