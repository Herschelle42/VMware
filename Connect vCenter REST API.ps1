$Credential = Get-Credential
$vCenter1 = "vcenter01.corp.local"
$vCenter2 = "vcenter02.corp.local"

$auth = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Credential.UserName+':'+$Credential.GetNetworkCredential().Password))
$head = @{
  'Authorization' = "Basic $auth"
}


$RestApi1 = Invoke-WebRequest -Uri https://$vCenter1/rest/com/vmware/cis/session -Method Post -Headers $head
$token1 = (ConvertFrom-Json $RestApi1.Content).value
$session1 = @{'vmware-api-session-id' = $token1}

 
$response1 = Invoke-WebRequest -Uri https://$vCenter1/rest/vcenter/vm -Method Get -Headers $session1
$vmlist1 = (ConvertFrom-Json $response1.Content).value


$RestApi2 = Invoke-WebRequest -Uri https://$vCenter2/rest/com/vmware/cis/session -Method Post -Headers $head
$token2 = (ConvertFrom-Json $RestApi2.Content).value
$session2 = @{'vmware-api-session-id' = $token2}

 
$response2 = Invoke-WebRequest -Uri https://$vCenter2/rest/vcenter/vm -Method Get -Headers $session2
$vmlist2 = (ConvertFrom-Json $response2.Content).value

$vmlist = $vmlist1 + $vmlist2
$vmlist.Count

