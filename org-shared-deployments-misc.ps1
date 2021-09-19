# Script and script documentation home: https://github.com/engrit-illinois/org-shared-mecm-deployments
# Org shared deployment model documentation home: https://wiki.illinois.edu/wiki/display/engritprivate/SCCM+-+Org+shared+collections+and+deployments
# By mseng3

# Note these snippets are not a holistic script.
# Read and understand before using.

# -----------------------------------------------------------------------------

# To prevent anyone from running this as a script blindly:
Exit

# -----------------------------------------------------------------------------

# Prepare a connection to SCCM so you can directly use ConfigurationManager Powershell cmdlets without opening the admin console app
# This is posted as a module in its own repo here: https://github.com/engrit-illinois/Prep-MECM
function Prep-MECM {
	$SiteCode = "MP0" # Site code 
	$ProviderMachineName = "sccmcas.ad.uillinois.edu" # SMS Provider machine name

	# Customizations
	$initParams = @{}
	#$initParams.Add("Verbose", $true) # Uncomment this line to enable verbose logging
	#$initParams.Add("ErrorAction", "Stop") # Uncomment this line to stop the script on any errors

	# Import the ConfigurationManager.psd1 module 
	if((Get-Module ConfigurationManager) -eq $null) {
		Import-Module "$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1" @initParams 
	}

	# Connect to the site's drive if it is not already present
	if((Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue) -eq $null) {
		New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $ProviderMachineName @initParams
	}

	# Set the current location to be the site code.
	Set-Location "$($SiteCode):\" @initParams
}

# -----------------------------------------------------------------------------

# Use the above Prep-MECM function (which must change your working directory to MP0:\), perform some commands, and return to your previous working directory

$myPWD = $pwd.path
Prep-MECM

# Some commands, e.g.:
Get-CMDeviceCollection -Name "UIUC-ENGR-All Systems"

Set-Location $myPWD

# -----------------------------------------------------------------------------

# Find which MECM collections contain a given machine:
# Note: this will probably take a long time (15+ minutes) to run
Get-CMCollection | Where { (Get-CMCollectionMember -InputObject $_).Name -contains "machine-name" } | Select Name

# -----------------------------------------------------------------------------

# Force the MECM client to re-evaluate its assignments
# Useful if deployments just won't show up in Software Center
# https://github.com/engrit-illinois/force-software-center-assignment-evaluation
$Assignments = (Get-WmiObject -Namespace root\ccm\Policy\Machine -Query "Select * FROM CCM_ApplicationCIAssignment").AssignmentID
ForEach ($Assignment in $Assignments) {
    $Trigger = [wmiclass] "\root\ccm:SMS_Client"
    $Trigger.TriggerSchedule("$Assignment")
    Start-Sleep 1
}

# -----------------------------------------------------------------------------

# Find the difference between two MECM collections:
$one = (Get-CMCollectionMember -CollectionName "UIUC-ENGR-Collection 1" | Select Name).Name
$two = (Get-CMCollectionMember -CollectionName "UIUC-ENGR-Collection 2" | Select Name).Name
$diff = Compare-Object -ReferenceObject $one -DifferenceObject $two
$diff
@($diff).count

# -----------------------------------------------------------------------------

# Get the current/authoritative list of valid ENGR computer name prefixes directly from MECM:
$rule = (Get-CMDeviceCollectionQueryMembershipRule -Name "UIUC-ENGR-All Systems" -RuleName "UIUC-ENGR-Imported Computers").QueryExpression
$regex = [regex]'"([a-zA-Z]*)-%"'
$prefixesFound = $regex.Matches($rule)
# Make array of prefixes, removing extraneous characters from matches
$prefixesFinal = @()
foreach($prefix in $prefixesFound) {
	# e.g pull "CEE" out of "`"CEE-%`""
	$prefixClean = $prefix -replace '"',''
	$prefixClean = $prefixClean -replace '-%',''
	$prefixesFinal += @($prefixClean)
}
$prefixesFinal | Sort-Object

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

# Get the revision number of a local MECM assignment named like "*Siemens NX*":
# Compare the return value with the revision number of the app (as seen in the admin console).
# If it's not the latest revision , use the "Update machine policy" action in the Configuration Manager control panel applet, and then run this code again.
function Get-RevisionOfAssignment($name) {
    $assignments = Get-WmiObject -Namespace root\ccm\Policy\Machine -Query "Select * FROM CCM_ApplicationCIAssignment" | where { $_.assignmentname -like $name }
	foreach($assignment in $assignments) {
		$xmlString = @($assignment.AssignedCIs)[0]
		$xmlObject = New-Object -TypeName System.Xml.XmlDocument
		$xmlObject.LoadXml($xmlString)
		$rev = $xmlObject.CI.ID.Split("/")[2]
		$assignment | Add-Member -NotePropertyName "Revision" -NotePropertyValue $rev
	}
	$assignments | Select Revision,AssignmentName
}

Get-RevisionOfAssignment "*autocad*"


# -----------------------------------------------------------------------------

# Get the refresh schedules of all MECM device collections,
# limit them to those that refresh daily,
# sort by refresh time and then by collection name,
# and print them in a table.
# This will take a while to run.
# Useful for finding out if we are contributing to poor MECM performance by having a bunch of collections refreshing at the same time, and when those collections refresh.

$colls = Get-CMDeviceCollection
$collsPruned = $colls | Select `
	Name,
	@{Name="RecurStartDate";Expression={$_.RefreshSchedule.StartTime.ToString("yyyy-MM-dd")}},
	@{Name="RecurTime";Expression={$_.RefreshSchedule.StartTime.ToString("HH:mm:ss")}},
	@{Name="RecurIntervalDays";Expression={$_.RefreshSchedule.DaySpan}},
	@{Name="RecurIntervalHours";Expression={$_.RefreshSchedule.HourSpan}},
	@{Name="RecurIntervalMins";Expression={$_.RefreshSchedule.MinuteSpan}}
$collsWithDailySchedules = $collsPruned | Where { $_.RecurIntervalDays -eq 1 } | Sort RecurTime,Name
$collsWithDailySchedules | Format-Table

# -----------------------------------------------------------------------------

# Find collections which have "incremental updates" enabled
# https://www.danielengberg.com/sccm-powershell-script-update-collection-schedule/
$refreshTypes = @{
    1 = "Manual Update Only"
    2 = "Scheduled Updates Only"
    4 = "Incremental Updates Only"
    6 = "Incremental and Scheduled Updates"
}
$colls = Get-CMCollection | Where { ($_.RefreshType -eq 4) -or ($_.RefreshType -eq 6) }
$collsCustom = $colls | Select Name,RefreshType,@{
    Name = "RefreshTypeFriendly"
    Expression = {
        [int]$type = $_.RefreshType
        $refreshTypes.$type
    }
}
$collsCustom | Format-Table

# -----------------------------------------------------------------------------

# Get all MECM device collections named like "UIUC-ENGR-CollectionName*" and set their refresh schedule to daily at 3am, starting 2020-08-28
$sched = New-CMSchedule -Start "2020-08-28 03:00" -RecurInterval "Days" -RecurCount 1
Get-CMDeviceCollection | Where { $_.Name -like "UIUC-ENGR-CollectionName*" } | Set-CMCollection -RefreshSchedule $sched

# -----------------------------------------------------------------------------

# Get all MECM Collections and apps named like "UIUC-ENGR *" and rename them to "UIUC-ENGR-*"

$colls = Get-CMCollection | Where { $_.Name -like "UIUC-ENGR *" }
$colls | ForEach {
	$name = $_.Name
	$newname = $name -replace "UIUC-ENGR ","UIUC-ENGR-"
	Write-Host "Renaming collection `"$name`" to `"$newname`"..."
	Set-CMCollection -Name $name -NewName $newname
}

$apps = Get-CMApplication -Fast | Where { $_.LocalizedDisplayName -like "UIUC-ENGR *" }
$apps | ForEach {
	$name = $_.LocalizedDisplayName
	$newname = $name -replace "UIUC-ENGR ","UIUC-ENGR-"
	Write-Host "Renaming app `"$name`" to `"$newname`"..."
	Set-CMApplication -Name $name -NewName $newname
}

# -----------------------------------------------------------------------------

# Force Software Center to reset its policy
# Useful for when an application is stuck downloading/installing on a client, and you want to redeploy it
# https://docs.microsoft.com/en-us/answers/questions/123991/sccm-software-center-how-to-reset-or-cancel-an-app.html
# Should be followed up by running the download computer policy/app deployment eval cycles
WMIC /Namespace:\\root\ccm path SMS_Client CALL ResetPolicy 1 /NOINTERACTIVE

# -----------------------------------------------------------------------------

# Find the app/deployment type associated with the CI_UniqueId of an unknown deployment type:
$ciuid = "DeploymentType_fb0b749d-dba0-45c4-b30e-98497831b2d7"
$ciuid = $ciuid.Replace("DeploymentType_","")
$dt = Get-WmiObject -Namespace "root\sms\site_MP0" -ComputerName "sccmcas.ad.uillinois.edu" -Class "SMS_Deploymenttype" -Filter "CI_UniqueId like '%$ciuid%'"
Write-Host "Deployment type: `"$($dt.LocalizedDisplayName)`""
$app = Get-CMApplication -ModelName $dt.AppModelName
Write-Host "App: `"$($app.LocalizedDisplayName)`""

# -----------------------------------------------------------------------------

# Sum up the total FullEvaluationRunTime of all ENGR collections
# Quick and dirty version. See Get-CMCollectionsEvalRuntime function below.

$colls = Get-CMCollection
$sumMillisec = ($colls | Select FullEvaluationRunTime).FullEvaluationRunTime | Measure-Object -Sum | Select -ExpandProperty Sum
$avgMillisec = $sumMillisec / $colls.count
$sumSec = $sumMillisec / 1000
$sumMin = $sumSec / 60

# As of 2021-06-11
$colls.count # Returns 946 (but one is the "lost computers" root collection)
$sumMin # Returns 13.3277666666667
$avgMillisec # Returns 845.31289640592

# -----------------------------------------------------------------------------

# Return an object which reports a bunch of MECM collection evaluation runtime data

function Get-CMCollectionsEvalRuntime {
	
	param(
		# Specify a wildcard query to filter to only collections with matching names
		$NameQuery,
		
		# Optional input of pre-made collections objects, to prevent having to wait for them to be pulled again
		$Collections
	)
	
	# Functions
	function log($msg) {
		Write-Host $msg
	}
	
	function addm($property, $value, $object) {
		$object | Add-Member -NotePropertyName $property -NotePropertyValue $value -Force
		$object
	}
	
	function Sum-EvalRuntime($type, $colls) {
		$typeProperty = "$($type)EvaluationRunTime"
		$sumMillisec = ($colls | Select $typeProperty).$typeProperty | Measure-Object -Sum | Select -ExpandProperty Sum
		$sumMillisec
	}
	
	# Make an object to keep data
	$o = [PSCustomObject]@{
		Data = [PSCustomObject]@{}
	}
	
	# Get collections
	if($Collections) {
		log "Using collections specified with -Collections."
		$colls = $Collections
	}
	else {
		log "Collections were not specified with -Collections. Pulling collections from MECM..."
		$myPWD = $pwd.path
		Prep-MECM
		$colls = Get-CMCollection
		Set-Location $myPWD
	}
	$o.Data = addm "Collections" $colls $o.Data
	
	$count = $colls.count
	log "$count collections were specified or pulled from MECM."
	$o = addm "CollectionsCount" $colls.count $o
	
	# Filter collections
	log "Filtering collections..."
	if($NameQuery) {
		log "Filtering to collections matching specified -NameQuery..."
		$collsFiltered = $colls | Where { $_.Name -like $NameQuery }
	}
	else {
		log "-NameQuery not specified."
		$collsFiltered = $colls
	}
	$o.Data = addm "FilteredCollections" $collsFiltered $o.Data
	
	$countFiltered = $collsFiltered.count
	log "Filtered to $count collections."
	$o = addm "FilteredCollectionsCount" $collsFiltered.count $o
	
	# Do the math and populate an output object
	log "Doing the math..."
	
	$o = addm "FullSumMillisec" (Sum-EvalRuntime "Full" $collsFiltered) $o
	$o = addm "FullAvgMillisec" ($o.FullSumMillisec / $countFiltered) $o
	$o = addm "FullSumSec" ($o.FullSumMillisec / 1000) $o
	$o = addm "FullAvgSec" ($o.FullSumSec / $countFiltered) $o
	$o = addm "FullSumMin" ($o.FullSumSec / 60) $o
	$o = addm "FullAvgMin" ($o.FullSumMin / $countFiltered) $o
	
	$o = addm "IncSumMillisec" (Sum-EvalRuntime "Incremental" $collsFiltered) $o
	$o = addm "IncAvgMillisec" ($o.IncSumMillisec / $countFiltered) $o
	$o = addm "IncSumSec" ($o.IncSumMillisec / 1000) $o
	$o = addm "IncAvgSec" ($o.IncSumSec / $countFiltered) $o
	$o = addm "IncSumMin" ($o.IncSumSec / 60) $o
	$o = addm "IncAvgMin" ($o.IncSumMin / $countFiltered) $o
	
	# Output the object
	log "Outputting result object..."
	$o
}

# Example use:
Get-CMCollectionsEvalRuntime -NameQuery "UIUC-ENGR-*"

# Or:
$colls = Get-CMCollection
Get-CMCollectionsEvalRuntime -NameQuery "UIUC-ENGR-*" -Collections $colls

# -----------------------------------------------------------------------------

# Re-run a Required Task Sequence deployment
# This actually just deletes the information on a computer that tells MECM that the TS has already been run. It doesn't actually kick of the TS; that will just happen because the TS is Required.
# This requires the TS deployment to be configured to "Always re-run", and for the relevant machines to be given this deployment.
# To do this for an Available deployment see the next snippet.
# https://social.technet.microsoft.com/Forums/en-US/b6eff363-ad8c-4412-b10d-fb70f2ead7f2/how-to-rerun-a-required-deployment?forum=configmanagerosd
# https://msendpointmgr.com/2012/11/21/re-run-task-sequence-with-powershell/
# https://smsagent.blog/2014/01/23/re-running-a-task-sequence/

function Rerun-TS {
	param(
		[string]$TsPackageId,
		[string]$ComputerName
	)

	$scriptBlock = {
		param(
			[string]$TsPackageId
		)
		$schedule = Get-WmiObject -Namespace "root\ccm\scheduler" -Class ccm_scheduler_history | where {$_.ScheduleID -like "*$TsPackageId*"}
		if(!$schedule) { Write-Host "Did not find schedule for given Task Sequence!" }
		else {
			Write-Host "Found schedule for given Task Sequence."
			Write-Host "Schedule ID: `"$($schedule.ScheduleID)`"."
			Write-Host "Deleting schedule..."
			$schedule | Remove-WmiObject

			$newSchedule = Get-WmiObject -Namespace "root\ccm\scheduler" -Class ccm_scheduler_history | where {$_.ScheduleID -like "*$TsPackageId*"}
			if($newSchedule) { Write-Host "Failed to delete schedule for given Task Sequence!" }
			else {
				Write-Host "Successfully deleted schedule for given Task Sequence."
				Write-Host "Restarting CCMExec..."
				Get-Service | where {$_.Name -eq "CCMExec"} | Restart-Service
			}
		}
	}

	Write-Host "Starting PSSession to `"$ComputerName`"..."
	$session = New-PSSession -ComputerName $ComputerName
	Write-Host "Sending commands to session..."
	Invoke-Command -Session $session -ScriptBlock $scriptBlock -ArgumentList $TsPackageId
	Write-Host "Done sending commands to session."
	Write-Host "Ending session..."
	Remove-PSSession $session
	Write-Host "Done."
}

# Examples:

# You can get the PackageID of the Task Sequence from the MECM Console
$TsPackageId = "MP0028BE"

# Run on one computer
Rerun-TS -TsPackageId $TsPackageId -ComputerName "comp-name-01"

# Run on multiple sequential lab computers
foreach($int in @(1..10)) {
	$num = ([string]$int).PadLeft(2,"0")
	$name = "COMP-NAME-$($num)"
	Rerun-TS -TSPackageId $TsPackageId -ComputerName $name
}

# -----------------------------------------------------------------------------

# Trigger an available Task Sequence deployment immediately
# https://msendpointmgr.com/2019/02/14/how-to-rerun-a-task-sequence-in-configmgr-using-powershell/

function Invoke-TaskSequence {
	param(
		[Parameter(Mandatory=$true)]
		[string]$TsPackageId,
		
		[Parameter(Mandatory=$true)]
		[string]$TsDeploymentId,
		
		[Parameter(Mandatory=$true)]
		[string]$ComputerName
	)

	$scriptBlock = {
		param(
			[string]$TsPackageId,
			[string]$TsDeploymentId
		)
		
		Write-Host "        Retrieving local TS advertisements from WMI..."
		$tsAds = Get-CimInstance -Namespace "root\ccm\policy\machine\actualconfig" -Class "CCM_TaskSequence"
		
		if(-not $tsAds) { Write-Host "            Failed to retrieve local TS advertisements from WMI!" }
		else {
			Write-Host "        Getting local advertisement for deployment `"$($TsDeploymentId)`" of TS `"$($TsPackageId)`"..."
			$tsAd = $tsAds | Where-Object { ($_.PKG_PackageID -eq $TsPackageId) -and ($_.ADV_AdvertisementID -eq $TsDeploymentId) }
			
			if(-not $tsAd) { Write-Host "            Failed to get local advertisement!" }
			else {
				Write-Host "        Modifying local advertisement..."
				
				# Set the RepeatRunBehavior property of this local advertisement to trick the client into thinking it should always rerun, regardless of previous success/failure
				if($tsAd.ADV_RepeatRunBehavior -notlike "RerunAlways") {
					Write-Host "            Changing RepeatRunBehavior from `"$($tsAd.ADV_RepeatRunBehavior) to `"RerunAlways`"."
					$tsAd.ADV_RepeatRunBehavior = "RerunAlways"
					$tsAd.Put() | Out-Null
				}
				else { Write-Host "            RepeatRunBehavior is already `"RerunAlways`"." }
				
				# Set the MandatoryAssignments property of this local advertisement to trick the client into thinking it's a Required deployment, regardless of whether it actually is
				if($tsAd.ADV_MandatoryAssignments -ne $true) {
					Write-Host "            Changing MandatoryAssignments from `"$($tsAd.ADV_MandatoryAssignments) to `"$true`"."
					$tsAd.Get()
					$tsAd.ADV_MandatoryAssignments = $true
					$tsAd.Put() | Out-Null
				}
				else { Write-Host "            MandatoryAssignments is already `"$true`"." }
				
				# Get the schedule for the newly modified advertisement and trigger it to run
				Write-Host "        Triggering TS..."
				
				Write-Host "            Retrieving scheduler history from WMI..."
				$schedulerHistory = Get-CimInstance -Namespace "root\ccm\scheduler" -Class "CCM_Scheduler_History"
				
				if(-not $schedulerHistory) { Write-Host "                Failed to retrieve scheduler history from WMI!" }
				else {
					
					Write-Host "            Getting schedule for local TS advertisement..."
					# ScheduleIDs look like "<DeploymentID>-<PackageID>-<ScheduleID>"
					$scheduleId = $schedulerHistory | Where-Object { ($_.ScheduleID -like "*$($TsPackageId)*") -and ($_.ScheduleID -like "*$($TsDeploymentId)*") } | Select-Object -ExpandProperty ScheduleID
					
					if(-not $scheduleId) { Write-Host "                Failed to get schedule for local TS advertisement!" }
					else {
						Write-Host "            Triggering schedule for newly-modified local advertisement..."
						Invoke-WmiMethod -Namespace "root\ccm" -Class "SMS_Client" -Name "TriggerSchedule" -ArgumentList $scheduleID
					}
				}
			}
		}
	}

	Write-Host "Starting PSSession to `"$ComputerName`"..."
	$session = New-PSSession -ComputerName $ComputerName
	Write-Host "    Sending commands to session..."
	Invoke-Command -Session $session -ScriptBlock $scriptBlock -ArgumentList $TsPackageId,$TsDeploymentId
	Write-Host "    Done sending commands to session."
	Write-Host "    Ending session..."
	Remove-PSSession $session
	Write-Host "Done."
}

# Examples:

# Specify the PackageID of the desired TS. Get this from the MECM console.
$tsPackageId = "MP0028BE"
# Specify the DeploymentID of the desired deployment (in case there are multiple deployments of the same TS). Get this from the MECM console.
$tsDeploymentId = "MP021145"

# Run on one computer
Invoke-TaskSequence -ComputerName "comp-name-01" -TsPackageId $tsPackageId -TsDeploymentId $tsDeploymentId

# Run on multiple sequential lab computers
foreach($int in @(1..10)) {
	$num = ([string]$int).PadLeft(2,"0")
	$comp = "COMP-NAME-$($num)"
	Invoke-TaskSequence -ComputerName $comp -TsPackageId $tsPackageId -TsDeploymentId $tsDeploymentId
}

# -----------------------------------------------------------------------------

# MECM "Script" version of above Invoke-TaskSequence function

param(
	[Parameter(Mandatory=$true)]
	[string]$TsPackageId,
	
	[Parameter(Mandatory=$true)]
	[string]$TsDeploymentId
)

Write-Host "        Retrieving local TS advertisements from WMI..."
$tsAds = Get-WmiObject -Namespace "root\ccm\policy\machine\actualconfig" -Class "CCM_TaskSequence"

if(-not $tsAds) { Write-Host "            Failed to retrieve local TS advertisements from WMI!" }
else {
	Write-Host "        Getting local advertisement for deployment `"$($TsDeploymentId)`" of TS `"$($TsPackageId)`"..."
	$tsAd = $tsAds | Where-Object { ($_.PKG_PackageID -eq $TsPackageId) -and ($_.ADV_AdvertisementID -eq $TsDeploymentId) }
	
	if(-not $tsAd) { Write-Host "            Failed to get local advertisement!" }
	else {
		Write-Host "        Modifying local advertisement..."
		
		# Set the RepeatRunBehavior property of this local advertisement to trick the client into thinking it should always rerun, regardless of previous success/failure
		if($tsAd.ADV_RepeatRunBehavior -notlike "RerunAlways") {
			Write-Host "            Changing RepeatRunBehavior from `"$($tsAd.ADV_RepeatRunBehavior) to `"RerunAlways`"."
			$tsAd.ADV_RepeatRunBehavior = "RerunAlways"
			$tsAd.Put() | Out-Null
		}
		else { Write-Host "            RepeatRunBehavior is already `"RerunAlways`"." }
		
		# Set the MandatoryAssignments property of this local advertisement to trick the client into thinking it's a Required deployment, regardless of whether it actually is
		if($tsAd.ADV_MandatoryAssignments -ne $true) {
			Write-Host "            Changing MandatoryAssignments from `"$($tsAd.ADV_MandatoryAssignments) to `"$true`"."
			$tsAd.Get()
			$tsAd.ADV_MandatoryAssignments = $true
			$tsAd.Put() | Out-Null
		}
		else { Write-Host "            MandatoryAssignments is already `"$true`"." }
		
		# Get the schedule for the newly modified advertisement and trigger it to run
		Write-Host "        Triggering TS..."
		
		Write-Host "            Retrieving scheduler history from WMI..."
		$schedulerHistory = Get-WmiObject -Namespace "root\ccm\scheduler" -Class "CCM_Scheduler_History"
		
		if(-not $schedulerHistory) { Write-Host "                Failed to retrieve scheduler history from WMI!" }
		else {
			
			Write-Host "            Getting schedule for local TS advertisement..."
			# ScheduleIDs look like "<DeploymentID>-<PackageID>-<ScheduleID>"
			$scheduleId = $schedulerHistory | Where-Object { ($_.ScheduleID -like "*$($TsPackageId)*") -and ($_.ScheduleID -like "*$($TsDeploymentId)*") } | Select-Object -ExpandProperty ScheduleID
			
			if(-not $scheduleId) { Write-Host "                Failed to get schedule for local TS advertisement!" }
			else {
				Write-Host "            Triggering schedule for newly-modified local advertisement..."
				Invoke-WmiMethod -Namespace "root\ccm" -Class "SMS_Client" -Name "TriggerSchedule" -ArgumentList $scheduleID
			}
		}
	}
}

# -----------------------------------------------------------------------------

# Remove all logged historical runs of a Task Sequence on a client, so that subsequent Required deployments will run, even if they've run before and are not set to "Always rerun".
# https://msendpointmgr.com/2019/02/14/how-to-rerun-a-task-sequence-in-configmgr-using-powershell/
# https://www.reddit.com/r/SCCM/comments/iq5t1j/how_to_configure_a_required_task_sequence/
# https://techcommunity.microsoft.com/t5/core-infrastructure-and-security/sccm-forcing-a-task-sequence-to-rerun/ba-p/322253

function Remove-TaskSequenceHistory {
	param(
		[Parameter(Mandatory=$true)]
		[string]$TsPackageId,
		
		[Parameter(Mandatory=$true)]
		[string]$ComputerName
	)

	$scriptBlock = {
		param(
			[string]$TsPackageId
		)
		
		function Get-SchedulerHistory {
			Get-CimInstance -Namespace "root\ccm\scheduler" -Class "CCM_Scheduler_History"
		}
		
		function Get-TsScheduleHistory($history, $ts) {
			$history | Where-Object { ($_.ScheduleID -like "*$($ts)*") }
		}
		
		# Get the scheduler history for the newly modified advertisement and trigger it to run
		Write-Host "        Retrieving scheduler history from WMI..."
		$schedulerHistory = Get-SchedulerHistory
		
		if(-not $schedulerHistory) { Write-Host "            Failed to retrieve scheduler history from WMI!" }
		else {
			
			Write-Host "        Getting schedule history for given TS..."
			# ScheduleIDs look like "<DeploymentID>-<PackageID>-<ScheduleID>"
			# In this case we want ANY runs of this TS, regardless of which deployment it came from, so we only care about <PackageID> and not <DeploymentID>.
			# But keep in mind that if there are multiple deployments of this same TS to the client, this may return multiple results.
			$schedules = Get-TsScheduleHistory $schedulerHistory $TsPackageId
			
			if(-not $schedules) { Write-Host "            No schedule history was found for given TS." }
			else {
				Write-Host "            Found $(@($schedules).count) schedules in the scheduler history for given TS." 
				Write-Host "        Removing schedule history for given TS..."
				$schedules | Remove-CimInstance
				
				Write-Host "        Checking that schedule history has been removed for given TS..."
				$scheduleHistory2 = Get-SchedulerHistory
				$schedules2 = Get-TsScheduleHistory $schedulerHistory2 $TsPackageId
		
				if($schedules2) {
					Write-Host "    Schedule history still found $(@($schedules2).count) schedules in the scheduler history for given TS!"
				}
				else {
					Write-Host "    Successfully removed schedule history for given TS."
					Write-Host "Restarting CcmExec service..."
					Get-service -Name "CcmExec" | Restart-Service
					Write-Host "    Done restarting CcmExec service."
				}
			}
		}
	}

	Write-Host "Starting PSSession to `"$ComputerName`"..."
	$session = New-PSSession -ComputerName $ComputerName
	Write-Host "    Sending commands to session..."
	Invoke-Command -Session $session -ScriptBlock $scriptBlock -ArgumentList $TsPackageId,$TsDeploymentId
	Write-Host "    Done sending commands to session."
	Write-Host "    Ending session..."
	Remove-PSSession $session
	Write-Host "Done."
}

# Examples:

# Specify the PackageID of the desired TS. Get this from the MECM console.
$tsPackageId = "MP0028BE"

# Run on one computer
Remove-TaskSequenceHistory -ComputerName "comp-name-01" -TsPackageId $tsPackageId

# Run on multiple sequential lab computers
foreach($int in @(1..10)) {
	$num = ([string]$int).PadLeft(2,"0")
	$comp = "COMP-NAME-$($num)"
	Remove-TaskSequenceHistory -ComputerName $comp -TsPackageId $tsPackageId
}

# -----------------------------------------------------------------------------

# MECM "Script" version of above Remove-TaskSequenceHistory function

param(
	[Parameter(Mandatory=$true)]
	[string]$TsPackageId
)
	
function Get-SchedulerHistory {
	Get-CimInstance -Namespace "root\ccm\scheduler" -Class "CCM_Scheduler_History"
}

function Get-TsScheduleHistory($history, $ts) {
	$history | Where-Object { ($_.ScheduleID -like "*$($ts)*") }
}

# Get the scheduler history for the newly modified advertisement and trigger it to run
Write-Host "Retrieving scheduler history from WMI..."
$schedulerHistory = Get-SchedulerHistory

if(-not $schedulerHistory) { Write-Host "    Failed to retrieve scheduler history from WMI!" }
else {
	
	Write-Host "Getting schedule history for given TS..."
	# ScheduleIDs look like "<DeploymentID>-<PackageID>-<ScheduleID>"
	# In this case we want ANY runs of this TS, regardless of which deployment it came from, so we only care about <PackageID> and not <DeploymentID>.
	# But keep in mind that if there are multiple deployments of this same TS to the client, this may return multiple results.
	$schedules = Get-TsScheduleHistory $schedulerHistory $TsPackageId
	
	if(-not $schedules) { Write-Host "    No schedule history was found for given TS." }
	else {
		Write-Host "    Found $(@($schedules).count) schedules in the scheduler history for given TS." 
		Write-Host "Removing schedule history for given TS..."
		$schedules | Remove-CimInstance
		
		Write-Host "Checking that schedule history has been removed for given TS..."
		$scheduleHistory2 = Get-SchedulerHistory
		$schedules2 = Get-TsScheduleHistory $schedulerHistory2 $TsPackageId
		
		if($schedules2) {
			Write-Host "    Schedule history still found $(@($schedules2).count) schedules in the scheduler history for given TS!"
		}
		else {
			Write-Host "    Successfully removed schedule history for given TS."
			Write-Host "Restarting CcmExec service..."
			Get-service -Name "CcmExec" | Restart-Service
			Write-Host "    Done restarting CcmExec service."
		}
	}
}

# -----------------------------------------------------------------------------

