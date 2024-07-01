<#
.SYNOPSIS
  Get all VM tags from the vCenters.
.DESCRIPTION
  Useful when no access to PowerCLI.
.NOTES

    Output example: 

    Name       TagName    TagValue         
    ----       -------    --------         
    mssql-tst1 Backups    DBServer         
    mssql-tst1 project_id PR-000017        

    References:
    https://vdc-download.vmware.com/vmwb-repository/dcr-public/c2c7244e-817b-40d8-98f3-6c2ad5db56d6/af6d8ff7-1c38-4571-b72a-614ac319a62b/index.html#PKG_com.vmware.cis.tagging
    https://vdc-download.vmware.com/vmwb-repository/dcr-public/c2c7244e-817b-40d8-98f3-6c2ad5db56d6/af6d8ff7-1c38-4571-b72a-614ac319a62b/index.html#PKG_com.vmware.vcenter.tagging
    https://developer.broadcom.com/xapis/vsphere-automation-api/latest/cis/tagging/

#>

$Credential = $cred_userId
$vCenterList = @("vc01.corp.local", "vc02.corp.local")


#region --- Initial Setups and functions --------------------------------------

#create a vCenter connections array.
$auth = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Credential.UserName+':'+$Credential.GetNetworkCredential().Password))
$head = @{
  'Authorization' = "Basic $auth"
}


$vCenterConnections = foreach($vCenterName in $vCenterList) {

    try {
        $RestApi = Invoke-WebRequest -Uri "https://$($vCenterName)/rest/com/vmware/cis/session" -Method Post -Headers $head
        $token = (ConvertFrom-Json $RestApi.Content).value
        $session = @{'vmware-api-session-id' = $token}
    } catch {
        Write-Output "Error Exception Code: $($_.exception.gettype().fullname)"
        Write-Output "Error Message:        $($_.ErrorDetails.Message)"
        Write-Output "Exception:            $($_.Exception)"
        Write-Output "StatusCode:           $($_.Exception.Response.StatusCode.value__)"
        Continue
    }

    $hash = [ordered]@{}
    $hash.Name = $vCenterName
    $hash.Session = $session
    $object = New-Object PSObject -Property $hash
    $object
}
#$vCenterConnections

#endregion --------------------------------------------------------------------


function Get-VMTags-REST ($vCenterConnections) {

    foreach($vcenter in $vCenterConnections) {
        Write-Verbose "$(Get-Date) Get VMs from: $($vcenter.Name)" -Verbose

        $response = $null
        try {
            $response = Invoke-WebRequest -Uri "https://$($vcenter.Name)/rest/vcenter/vm" -Method Get -Headers $vcenter.Session
        } catch {
            Write-Warning "Error Exception Code: $($_.exception.gettype().fullname)"
            Write-Warning "Error Message:        $($_.ErrorDetails.Message)"
            Write-Warning "Exception:            $($_.Exception)"
            Write-Warning "StatusCode:           $($_.Exception.Response.StatusCode.value__)"
            Continue
        }

        if($response.Content) {
            $thisVMList = (ConvertFrom-Json $response.Content).value

            if($thisVMList) {
                $vmlist = foreach($thisVM in $thisVMList) {
                    
                    $response = $null

                    try {
                        $response = Invoke-WebRequest -Uri "https://$($vcenter.Name)/rest/vcenter/vm/$($thisVM.vm)" -Method Get -Headers $vcenter.Session
                        if($response.Content) {
                            $vm = ($response.Content | ConvertFrom-Json).value

                            if(-not [bool]($vm.PSObject.Properties.Name -match "moref")) {
                                $vm | Add-Member -MemberType NoteProperty -Name "moref" -Value $thisVM.vm
                            } else {
                                $vm.moref = $thisVM.vm
                            }

                            if(-not [bool]($vm.PSObject.Properties.Name -match "vcenter")) {
                                $vm | Add-Member -MemberType NoteProperty -Name "vcenter" -Value $vcenter.Name
                            } else {
                                $vm.vcenter = $vcenter.Name
                            }

                            #helps if you actually return the object :)
                            $vm
                            
                        }


                    } catch {
                        Write-Warning "Error Exception Code: $($_.exception.gettype().fullname)"
                        Write-Warning "Error Message:        $($_.ErrorDetails.Message)"
                        Write-Warning "Exception:            $($_.Exception)"
                        Write-Warning "StatusCode:           $($_.Exception.Response.StatusCode.value__)"
                        Continue
                    }

                }

            }

        }

        #Get all tag assocations
        $response = $null
        $method = "Get"
        try {
            $response = Invoke-RestMethod -Uri "https://$($vcenter.Name)/api/vcenter/tagging/associations" -Method $method -Headers $vcenter.Session
        } catch {
            Write-Warning "Error Exception Code: $($_.exception.gettype().fullname)"
            Write-Warning "Error Message:        $($_.ErrorDetails.Message)"
            Write-Warning "Exception:            $($_.Exception)"
            Write-Warning "StatusCode:           $($_.Exception.Response.StatusCode.value__)"
            Continue
        }
            
        if($response.associations) {
            $tagAssociations = $response.associations

            #get all the unique tag ids for VMs only
            $tagIdList = $tagAssociations | ? { $_.object.type -eq "VirtualMachine" } | Select -ExpandProperty tag -Unique

            #now get each of the unique tags
            $tagList = foreach($tagId in $tagIdList) {
                $response = $null
                $method = "Get"
                try {
                    $response = Invoke-RestMethod -Uri "https://$($vcenter.Name)/rest/com/vmware/cis/tagging/tag/id:$($tagId)" -Method $method -Headers $vcenter.Session
                    Start-Sleep -Milliseconds 10
                } catch {
                    Write-Warning "Error Exception Code: $($_.exception.gettype().fullname)"
                    Write-Warning "Error Message:        $($_.ErrorDetails.Message)"
                    Write-Warning "Exception:            $($_.Exception)"
                    Write-Warning "StatusCode:           $($_.Exception.Response.StatusCode.value__)"
                    Continue
                }
                if($response.value) {
                    $response.value
                }
            }

            #get all the unique category ids
            $catList = foreach($catId in $taglist | Select -ExpandProperty category_id -Unique) {
                $response = $null
                $method = "Get"
                try {
                    $response = Invoke-RestMethod -Uri "https://$($vcenter.Name)/rest/com/vmware/cis/tagging/category/id:$($catId)" -Method $method -Headers $vcenter.Session
                } catch {
                    Write-Warning "Error Exception Code: $($_.exception.gettype().fullname)"
                    Write-Warning "Error Message:        $($_.ErrorDetails.Message)"
                    Write-Warning "Exception:            $($_.Exception)"
                    Write-Warning "StatusCode:           $($_.Exception.Response.StatusCode.value__)"
                    Continue
                }
                if($response.value) {
                    $response.value
                }

            }
                
        }

        #now create a new object
        foreach($vm in $vmlist) {
            
            foreach($tagId in $tagAssociations | ? { $_.object.id -eq $vm.moref } | Select -ExpandProperty tag) {
                $tagValue = $taglist | ? { $_.id -eq $tagId } | Select -ExpandProperty name
                $catId = $taglist | ? { $_.id -eq $tagId } | Select -ExpandProperty category_id
                $category = $catList | ? { $_.id -eq $catId }

                $hash = [ordered]@{}
                $hash.Name = $vm.name
                $hash.TagName = $category.name
                $hash.TagValue = $tagValue
                $object = New-Object PSObject -Property $hash
                $object

            }
            

        }

    }

}
$vmTagList = Get-VMTags-REST $vCenterConnections
