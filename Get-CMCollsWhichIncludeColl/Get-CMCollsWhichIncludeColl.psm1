# Script and script documentation home: https://github.com/engrit-illinois/org-shared-mecm-deployments
# Org shared deployment model documentation home: https://wiki.illinois.edu/wiki/display/engritprivate/SCCM+-+Org+shared+collections+and+deployments
# By mseng3

function Get-CMCollsWhichIncludeColl {

	param(
		[Parameter(Position=0,Mandatory=$true)]
		[string]$CollectionName,
		
		[switch]$GetDeployments,
		
		[string]$SiteCode="MP0",
		
		[string]$Provider="sccmcas.ad.uillinois.edu",
		
		[string]$CMPSModulePath="$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1",
		
		[switch]$Loud
	)
	
	function log($msg) {
		if($Loud) {
			$ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss:ffff"
			Write-Host "[$ts] $msg"
		}
	}

	function Prep-SCCM {
		log "Preparing connection to SCCM..."
		$initParams = @{}
		if((Get-Module ConfigurationManager) -eq $null) {
			# The ConfigurationManager Powershell module switched filepaths at some point around CB 18##
			# So you may need to modify this to match your local environment
			Import-Module $CMPSModulePath @initParams -Scope Global
		}
		if((Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue) -eq $null) {
			New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $Provider @initParams
		}
		Set-Location "$($SiteCode):\" @initParams
		log "Done prepping connection to SCCM."
	}
	
	$myPWD = $pwd.path
	Prep-SCCM
	
	# Get Collection ID
	$id = (Get-CMDeviceCollection -Name $CollectionName).CollectionId

	# Make arrays to store matching collections
	$colls = @()
	
	# Get all collections
	log "Getting all collections..."
	$allColls = Get-CMDeviceCollection
	log "Found $(@($allColls).count) collections."
		
	# Looping through all collections would takes forever (~10min in our environment), because it has to retrieve rules for each individual collection.
	# The collections don't store membership rules directly, but they DO store the number of Include/Exclude membership rules they have.
	# So, to save time, filter out collections which have <1 include rule.
	# In our environment, that cuts it down from ~680 collections to ~180, and from ~10min to ~3min.
	log "Filtering out collections which have no include rules..."
	$allColls = $allColls | Where { $_.IncludeExcludeCollectionsCount -gt 0 }
	log "Found $(@($allColls).count) collections with include/exclude rules."
	
	log "Looping through collections..."
	$i = 1
	foreach($coll in $allColls) {
		log "    Processing collection #$i/$(@($allColls).count): `"$($coll.Name)`"..."
		
		log "        Getting membership rules..."
		$rules = Get-CMCollectionIncludeMembershipRule -CollectionName $coll.Name
		
		log "        Looping through membership rules..."
		$j = 1
		foreach($rule in $rules) {
			log "            Processing rule #$j/$(@($rules).count)..."
			if($rule.IncludeCollectionId -eq $id) {
				log "                Rule includes target collection."
				$colls += $coll
				
				if($GetDeployments) {
					log "                -GetDeployments was specified. Getting deployments to this collection..."
					$coll | Add-Member -NotePropertyName "_Deployments" -NotePropertyValue (Get-CMDeployment -CollectionName $coll.Name)
				}
				
				break
			}
			else {
				log "                Rule does not include target collection."
			}
			$j += 1
		}
		log "        Done looping through rules."
		
		$i += 1
	}
	log "Done looping through collections."
	
	Set-Location $myPWD
	
	log "EOF"
	
	$colls
}
