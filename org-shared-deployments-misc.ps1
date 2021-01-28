# Script and script documentation home: https://github.com/engrit-illinois/org-shared-mecm-deployments
# Org shared deployment model documentation home: https://wiki.illinois.edu/wiki/display/engritprivate/SCCM+-+Org+shared+collections+and+deployments
# By mseng3

# Note these snippets are not a holistic script.
# Read and understand before using.

# -----------------------------------------------------------------------------

# To prevent anyone from running this as a script blindly:
Exit

# -----------------------------------------------------------------------------

# Rename a collection
Get-CMDeviceCollection -Name $coll | Set-CMDeviceCollection -NewName $newname

# -----------------------------------------------------------------------------

# Get all relevant collections so they can be used in a foreach loop with the below commands
# Be very careful to check that you're actually getting ONLY the collections you want with this, before relying on the list of returned collections to make changes. It would have made it easier to rely on this if I had designed these collections to have a standard prefix, but I wanted to keep the UIUC-ENGR-App Name format to make it crystal clear that these are to be used as the primary org collections/deployments for these apps. Unfortunately the ConfigurationManager powershell module doesn't have any support for working with folders (known as container nodes).
$collsAvailable = (Get-CMCollection -Name "Deploy * - Latest (Available)" | Select Name).Name
$collsRequired = (Get-CMCollection -Name "Deploy * - Latest (Required)" | Select Name).Name

# To do actions on all at once
$colls = $collsAvailable + $collsRequired

# -----------------------------------------------------------------------------

# Define a refresh schedule of daily at 1am
# https://docs.microsoft.com/en-us/powershell/module/configurationmanager/set-cmcollection
# https://docs.microsoft.com/en-us/powershell/module/configurationmanager/new-cmschedule
# https://www.danielengberg.com/sccm-powershell-script-update-collection-schedule/
# https://gallery.technet.microsoft.com/Powershell-script-to-set-5d1c52f1
# https://stackoverflow.com/questions/10487011/creating-a-datetime-object-with-a-specific-utc-datetime-in-powershell/44196630
# https://hinchley.net/articles/create-a-collection-in-sccm-with-a-weekly-refresh-cycle/
$sched = New-CMSchedule -Start "2020-07-27 01:00" -RecurInterval "Days" -RecurCount 1

foreach($coll in $colls) {
	# Set the refresh schedule
	Set-CMCollection -Name $coll -RefreshType "Periodic" -RefreshSchedule $sched
}

# -----------------------------------------------------------------------------

# Adding and removing membership rules

# https://docs.microsoft.com/en-us/powershell/module/configurationmanager/add-cmdevicecollectionincludemembershiprule
Get-CMCollection -Name "UIUC-ENGR-Deploy <app> (<purpose>)" | Add-CMDeviceCollectionIncludeMembershipRule -IncludeCollectionName "UIUC-ENGR-Collection to include"

# https://docs.microsoft.com/en-us/powershell/module/configurationmanager/remove-cmdevicecollectionincludemembershiprule
Get-CMCollection -Name "UIUC-ENGR-Deploy <app> (<purpose>)" | Remove-CMDeviceCollectionIncludeMembershipRule -IncludeCollectionName "UIUC-ENGR-Collection to remove" -Force

# -----------------------------------------------------------------------------

# Get a list of all membership rules for a given collection

function Get-CMDeviceCollectionMembershipRuleCounts($coll) {
    $object = [PSCustomObject]@{
        includes = (Get-CMDeviceCollectionIncludeMembershipRule -CollectionName $coll)
        excludes = (Get-CMDeviceCollectionExcludeMembershipRule -CollectionName $coll)
        directs = (Get-CMDeviceCollectionDirectMembershipRule -CollectionName $coll)
        queries = (Get-CMDeviceCollectionQueryMembershipRule -CollectionName $coll)
    }
    Write-Host "`nInclude rules: $(@($object.includes).count)"
    Write-Host "`"$($object.includes.RuleName -join '", "')`""
    Write-Host "`nExclude rules: $(@($object.excludes).count)"
    Write-Host "`"$($object.excludes.RuleName -join '", "')`""
    Write-Host "`nDirect rules: $(@($object.directs).count)"
    Write-Host "`"$($object.directs.RuleName -join '", "')`""
    Write-Host "`nQuery rules: $(@($object.queries).count)"
    Write-Host "`"$($object.queries.RuleName -join '", "')`""
    Write-Host "`n"
    $object
}

$rules = Get-CMDeviceCollectionMembershipRuleCounts "UIUC-ENGR-Deploy 7-Zip x64 - Latest (Available)"

# -----------------------------------------------------------------------------

# Adding a new properly-configured collection for each of "available" and "required"
$app = "App x64 - Latest"
$purposes = @("Available","Required")
foreach($purpose in $purposes) {
    # Make new collection
    $coll = "UIUC-ENGR-Deploy $app ($purpose)"
    $sched = New-CMSchedule -Start "2020-07-27 01:00" -RecurInterval "Days" -RecurCount 1
    New-CMDeviceCollection -Name $coll -LimitingCollectionName "UIUC-ENGR-All Systems" -RefreshType "Periodic" -RefreshSchedule $sched
    
    # Comment this out if this isn't going to be a "common" app
    #Get-CMCollection -Name $coll | Add-CMDeviceCollectionIncludeMembershipRule -IncludeCollectionName "UIUC-ENGR-Deploy ^ All Common Apps - Latest ($purpose)"

    # Deploying the app
    # https://docs.microsoft.com/en-us/powershell/module/configurationmanager/new-cmapplicationdeployment
    # https://www.reddit.com/r/SCCM/comments/9bknh0/newcmapplicationdeployment_help/
    Start-Sleep -Seconds 10 # If performing immediate after creating the collection
    New-CMApplicationDeployment -Name $app -CollectionName $coll -DeployAction "Install" -DeployPurpose $purpose -UpdateSupersedence $true
}

# Note: new collections created via Powershell will end up in the root of "Device Collections" and will need to be manually moved to the appropriate folder
# Currently there is no support for management of the folder hierarchy in the ConfigurationManager Powershell module.

# -----------------------------------------------------------------------------

# Adding a collection as a member of a roll up collection
Get-CMCollection -Name "UIUC-ENGR-Deploy ^ All Common Apps - Latest (<purpose>)" | Add-CMDeviceCollectionIncludeMembershipRule -IncludeCollectionName "UIUC-ENGR-Collection to add"

# -----------------------------------------------------------------------------

# Find all collections which have an "include" membership rule that includes a target collection:
# https://configurationmanager.uservoice.com/forums/300492-ideas/suggestions/15827071-collection-deployment

$targetColl = "UIUC-ENGR-Target Collection"
$targetCollId = (Get-CMCollection -Name $targetColl).CollectionId

$collsWhichIncludeTargetColl = @()
Get-CMCollection -CollectionType Device | Foreach-Object {
    $thisColl = $_
    Get-CMCollectionIncludeMembershipRule -InputObject $thisColl | Where-Object { $_.IncludeCollectionId -eq $targetCollId } | Foreach-Object { $collsWhichIncludeTargetColl += $thisColl.Name }
}
$collsWhichIncludeTargetColl | Sort-Object | Format-Table -Autosize -Wrap

# -----------------------------------------------------------------------------

# Find all deployments to a target collection (including deployments that are "inherited" by virtue of the target collection being included in other collections):
# https://configurationmanager.uservoice.com/forums/300492-ideas/suggestions/15827071-collection-deployment

$targetColl = "UIUC-ENGR-Target Collection"
$targetCollId = (Get-CMCollection -Name $targetColl).CollectionId

$collsWhichIncludeTargetColl = @()
Get-CMCollection -CollectionType Device | Foreach-Object {
    $thisColl = $_
    Get-CMCollectionIncludeMembershipRule -InputObject $thisColl | Where-Object { $_.IncludeCollectionId -eq $targetCollId } | Foreach-Object { $collsWhichIncludeTargetColl += $thisColl.Name }
}

$depsToCollsWhichIncludeTargetColl = @()
#TODO

$depsToCollsWhichIncludeTargetColl | Sort-Object | Format-Table -Autosize -Wrap

# -----------------------------------------------------------------------------

# Find out whether deployments to a collection have supersedence enabled
$apps = Get-CMApplicationDeployment -CollectionName "UIUC-ENGR-Deploy All Adobe CC 2020 Apps - SDL (Available)"
$apps | Select ApplicationName,UpdateSupersedence

# -----------------------------------------------------------------------------

# More handy, consolidated function for creating standarized org-shared-model deployment collections
# This has been turned into a proper Powershell module. Please see the "New-CMOrgModelDeploymentCollection" section in the README here: 

# https://gitlab.engr.illinois.edu/engrit-epm/org-shared-deployments/-/tree/master

# -----------------------------------------------------------------------------

# Get all MECM device collections named like "UIUC-ENGR-CollectionName*" and set their refresh schedule to daily at 3am, starting 2020-08-28
$sched = New-CMSchedule -Start "2020-08-28 03:00" -RecurInterval "Days" -RecurCount 1
Get-CMDeviceCollection | Where { $_.Name -like "UIUC-ENGR-CollectionName*" } | Set-CMCollection -RefreshSchedule $sched

# -----------------------------------------------------------------------------

