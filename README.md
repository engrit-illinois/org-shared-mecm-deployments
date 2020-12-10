# Summary
A few custom modules and some misc snippets related to maintaining the Engineering college's standardized MECM deployments and collections.

Org shared deployment model documentation home: https://wiki.illinois.edu/wiki/display/engritprivate/SCCM+-+Org+shared+collections+and+deployments  

# org-shared-deployments-misc.ps1

This doc just contains several snippets for doing various bulk or repetitive actions related to the shared deployments and collections.  
NOT intended to be run as a holistic script.  
Read and understand the code before using.  

# New-CMOrgModelDeploymentCollection.psm1

This is a module that takes a target application name, creates _standardized_ collections and deploys the target application to those collections.  
This is not official MECM terminology, but we call these "deployment collections" because the collection's sole purpose is to be the single point of deployment for a given app, and any collections which should receive this deployment should simply be added as in include rule in the collection's membership rules. As described on the wiki page above, this prevents the same application from being redundantly deployed to many, many scattered collections.  

### Behavior

- By default, the module creates two collections, one for an "Available" purpose deployment, and one for a "Required" purpose deployment. This behavior can be changed with the parameters documented below.  
- All collections will be created with a standard membership evaluation schedule of 1am daily.  
- All deployments will be configured to respect supersedence, if the app package has supersedence configured. If it doesn't, then you will see a benign warning that supersedence conditions were not met.  
  - Supersedence is preferred. If you must deploy without supersedence, please do so manually.  
- By default, the created collections will have a limiting collection of `UIUC-ENGR-All Systems`, unless the `-ISOnly` switch parameter is specified.  
- Created collections will have a standard name format of `UIUC-ENGR-Deploy <app> (<purpose>)`, unless the `-ISOnly` switch parameter is specified.  
- Created collections will show up in the root of `\Assets and Compliance\Overview\Device Collections` because the ConfigurationManager Powershell module is incapable of knowing about or manipulating folders. Please move them to the appropriate folder.  
  - For org-level collections, this is the appropriate subfolder of `\Assets and Compliance\Overview\Device Collections\UIUC-ENGR\Org shared collections\Deployments`.
  - For IS collections, this is `\Assets and Compliance\Overview\Device Collections\UIUC-ENGR\Instructional\Deployment Collections\Software\Installs`.

### Example usage

1. Download `New-CMOrgModelDeploymentCollection.psm1`
2. Import the file as a module: `Import-Module c:\path\to\New-CMOrgModelDeploymentCollection.psm1`
3. Run it, e.g.: `New-CMOrgModelDeploymentCollection -App "Slack - Latest"`
4. Take note of the output logged to the console.

### Parameters

#### -App
Required string.  
The exact name of the application package for which to create collections and which to deploy to those collections.  

#### -ISOnly
Optional switch.  
If specified, the behavior will change per the following:
- The created collections will have a name format of `UIUC-ENGR-IS Deploy <app> (<purpose>)` instead of `UIUC-ENGR-Deploy <app> (<purpose>)`.  
- The created collections will have a limiting collection of `UIUC-ENGR-Instructional`, instead of `UIUC-ENGR-All Systems`.

#### -SkipAvailable
Optional switch.  
If specified, creation of the "Available" deployment/collection will be skipped.  

#### -SkipRequired
Optional switch.  
If specified, creation of the "Required" deployment/collection will be skipped.  

#### -Uninstall
Optional switch.  
If specified, skips creation of "Available" and "Required" collections/deployments with "Install" action, and instead creates one "Required" collection/deployment with "Uninstall" action.  
Collection will be named like `UIUC-ENGR-IS Uninstall <app> (Required)`.  

#### -Prefix
Optional string.  
Specifies the prefix which the script assumes that all collections and apps have.  
Default value is `UIUC-ENGR-`.  
Script behavior is undefined if your unit's collections/deployments do not use a consistent prefix.  
This prefix methodology is probably somewhat unique to the mutli-tenant design of the UofI MECM infrastructure.  

#### - DeploymentDelaySec
Optional integer.  
The number of seconds to wait after creating a collection to deploy the app to that collection.  
Default is `10`.  
If you are getting errors with deployments, raise this value to e.g. `30` or so. It's possible MECM is being slow and not recognizing that the newly created collection exists before the script tries to deploy to it.  

#### -SiteCode
Optional string. Recommend leaving default.  
The site code of the MECM site to connect to.  
Default is `MP0`.  

#### -ProviderMachineName
Optional string. Recommend leaving default.  
The SMS provider machine name.  
Default is `sccmcas.ad.uillinois.edu`.  

#### -CMPSModulePath
Optional string. Recommend leaving default.  
The path to the ConfigurationManager Powershell module installed on the local machine (as part of the admin console).  
Default is `$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1`.  

# Get-CMCollsWhichIncludeColl.psm1

This is a module that takes a target collection name and returns all collections which include the target collection.  
Including the `-GetDeployments` parameter will also retrieve all deployments to the returned collections.  
Note: this will take ~3+ minutes to complete in our environment.  

This is useful because the GUI admin console does not provide a native way to see this data.  

### Example usage

1. Download `Get-CMCollsWhichIncludeColl.psm1`
2. Import the file as a module: `Import-Module c:\path\to\Get-CMCollsWhichIncludeColl.psm1`
3. Run it. Recommended to save the results to a variable.
  - e.g. `$collections = Get-CMCollsWhichIncludeColl "UIUC-ENGR-IS EWS" -GetDeployments`
4. Access returned data.
  - e.g. Get names of returned collections: `$collections.Name | Sort`
  - e.g. Get names of applications deployed to returned collections: `$collections._Deployments.ApplicationName | Sort`

### Parameters

#### -Loud
Optional switch.  
If specified, logs progress to the console.  
If omitted, module is silent.  

#### -GetDeployments
Optional switch.  
If specified, additionally retrieves deployments to returned collections.  

#### -SiteCode
Optional string. Recommend leaving default.  
The site code of the MECM site to query.  
Default is `MP0`.  

#### -ProviderMachineName
Optional string. Recommend leaving default.  
The SMS provider machine name.  
Default is `sccmcas.ad.uillinois.edu`.  

#### -CMPSModulePath
Optional string. Recommend leaving default.  
The path to the ConfigurationManager Powershell module installed on the local machine (as part of the admin console).  
Default is `$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1`.  

# Report-UnnecessaryDirectDeployments.psm1

This module looks through the org's standardized deployment collections, notes the deployments, and reports any extraneous collections/deployments which are found to deuplicate the standardized ones. The idea is to limit the number of one-off deployments of the same apps, to limit the overall number of deployments and thus limit time spent troubleshooting broken deployments.  

### Example usage

1. Download `Report-UnnecessaryDirectDeployments.psm1`
2. Import the file as a module: `Import-Module c:\path\to\Report-UnnecessaryDirectDeployments.psm1`
3. Run it.
  - e.g. `Report-UnnecessaryDirectDeployments`
4. Review the generated CSV.

### Parameters

#### -OutputPath
Optional string.  
The location where the log and generated CSV will be created.  
Default path is `c:\engrit\logs`.  
Output filenames are `Report-UnnecessaryDirectDeployments_<timestamp>.csv/log`.  

#### -SiteCode
Optional string. Recommend leaving default.  
The site code of the MECM site to query.  
Default is `MP0`.  

#### -ProviderMachineName
Optional string. Recommend leaving default.  
The SMS provider machine name.  
Default is `sccmcas.ad.uillinois.edu`.  

#### -CMPSModulePath
Optional string. Recommend leaving default.  
The path to the ConfigurationManager Powershell module installed on the local machine (as part of the admin console).  
Default is `$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1`.  

# Notes
- By mseng3