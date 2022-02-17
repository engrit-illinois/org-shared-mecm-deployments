# Summary
A few custom modules and some misc snippets related to maintaining the Engineering college's standardized MECM deployments and collections.

Org shared deployment model documentation home: https://wiki.illinois.edu/wiki/display/engritprivate/SCCM+-+Org+shared+collections+and+deployments  

Table of contents:  
- [org-shared-deployments-misc.ps1](#org-shared-deployments-miscps1): handy snippets to perform various tasks relating to the org shared deployments
- [New-CMOrgModelDeploymentCollection.psm1](#new-cmorgmodeldeploymentcollectionpsm1): a module for creating standardized deployment collections
- [Get-CollsWhichIncludeColl.psm1](#get-cmcollswhichincludecollpsm1): a module to return the list of collections in which a given collection is included
- [Report-UnnecessaryDirectDeployments.psm1](#report-unnecessarydirectdeploymentspsm1): a module to list all deployments which are technically duplicates of existing org-level deployments, and thus could be assimilated

# Requirements
- Currently these custom modules have only been written for and tested with Powershell 5.1. While modern versions of Configuration Manager [support Powershell 7](https://docs.microsoft.com/en-us/powershell/sccm/overview?view=sccm-ps#support-for-powershell-version-7), there are apparently some differences which these scripts do not account for, and there are known Powershell 7 compatibility issues with at least New-CMOrgModelDeploymentCollection.psm1, and possible others.  

# org-shared-deployments-misc.ps1

This doc just contains several snippets for doing various bulk or repetitive actions related to the shared deployments and collections.  
NOT intended to be run as a holistic script.  
Read and understand the code before using.  

# New-CMOrgModelDeploymentCollection.psm1

This is a module that takes a target application name, creates _standardized_ collections and deploys the target application to those collections.  
This is not official MECM terminology, but we call these "deployment collections" because the collection's sole purpose is to be the single point of deployment for a given app, and any collections which should receive this deployment should simply be added as an include rule in the collection's membership rules. As described on the wiki page above, this prevents the same application from being redundantly deployed to many scattered collections.  

This module has been moved to its own repo here: https://github.com/engrit-illinois/New-CMOrgModelDeploymentCollection

# Get-CMCollsWhichIncludeColl.psm1

This is a module that takes a target collection name and returns all collections which include the target collection.  
Including the `-GetDeployments` parameter will also retrieve all deployments to the returned collections.  
Note: this will take ~3+ minutes to complete in our environment.  

This is useful because the GUI admin console does not provide a native way to see this data.  

This module has been moved to its own repo here: https://github.com/engrit-illinois/Get-CMCollsWhichIncludeColl

# Report-UnnecessaryDirectDeployments.psm1

This module looks through the org's standardized deployment collections, notes the deployments, and reports any deployments of the same apps which are directly deployed to other collections, and which collections. The idea is to limit the number of duplicated one-off deployments, to limit the overall number of deployments and thus limit time spent troubleshooting broken deployments.  

This module has been moved to its own repo here: https://github.com/engrit-illinois/Report-UnnecessaryDirectDeployments  

# Notes
- By mseng3. See my other projects here: https://github.com/mmseng/code-compendium.
