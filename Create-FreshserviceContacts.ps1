# Author: Scott Willett
# Version: 11:53 AM 28/01/2016
#
# Description: Gets a list of users from an OU in AD, then creates fresh service accounts for them using the fresh service API (doco here: http://api.freshservice.com/#introduction)

$base_uri = "https://ccmschools.freshservice.com"         # Your FreshService URI

# Alter these according to your environment
$users_ou = ""                  # OU of users you want to import into FreshService
$freshservice_apikey = ""       # API key of the user account you're authenticating with. See api.freshservice.com
$user_type = ""                 # User type the user will be identified as (Staff, Student, Carer). Note that this is a custom field created in fresh service.
$time_zone = ""                 # Time zone the user exists in (Brisbane, Adelaide, Canberra)
$department_id = ""             # Links the user to a department (or rather, a company). See commented code below to get the id for your department.

# Use this request below to get the department id
# (Invoke-WebRequest -Uri "$($base_uri)//itil/departments.json" -Header $headers).content | ConvertFrom-JSON

# API Key is converted and placed in a hash to be passed as a header with our API calls
$bytes = [System.Text.Encoding]::ASCII.GetBytes($freshservice_apikey)
$base64 = [System.Convert]::ToBase64String($bytes)
$headers = @{"Authorization" = "Basic $base64"}

# Place your users from AD into this array
$ad_users = Get-ADUser -Filter * -SearchBase $users_ou -Properties telephoneNumber, mobile, title

$has_content = $true	# Boolean to indicate if a response has content
$page_number = 1	# Need to paginate through assets. Start at page one.

$freshservice_users = @()		# Will hold all users returned from content

# Agents are retrieved differently (aren't a contact)
$freshservice_agents = Invoke-WebRequest -Uri "$($base_uri)/agents.json" -Header $headers
$freshservice_agents = ($freshservice_agents.Content | convertfrom-json).agent.user

# While the response has content
while ($has_content)
{
	# Get the response
	$response = Invoke-WebRequest -Uri "$($base_uri)/itil/requesters.json?page=$($page_number)&state=all" -Header $headers

	# Check the content. Convert the content to objects and add them to the assets list if content exists and prepare to check the next asset page, else break the loop.
	if ($response.Content -ne "[]")
	{
		$freshservice_users += ($response.Content | ConvertFrom-JSON).user
		$page_number += 1
	}
	else
	{
		$has_content = $false
	}
}

# Go through each AD user
foreach ($ad_user in $ad_users)
{
  # Check if the user is an agent. Skip if they are.
  if (-not ($freshservice_agents | where { $_.email.ToLower().EndsWith($ad_user.UserPrincipalName.ToLower()) } ))
  {
      # Check if the user exists in fresh service. If not create. If they do, ignore (potentially update in the future)
      if (-not ($freshservice_users | where { $_.email.ToLower().EndsWith($ad_user.UserPrincipalName.ToLower()) } ))
      {
        Write-Host "Account not in freshservice $($ad_user)" -foregroundcolor Red
        $post_data = ""
        
        # Build up a hash. Will be passed as JSON to freshservice
        # You may need to delete the "custom_field" lines
        $post_data = @{ user= @{
                          name=$ad_user.Name; 
                          email=$ad_user.UserPrincipalName;
                          job_title=$ad_user.Title;
                          phone=$ad_user.telephoneNumber;
                          mobile=$ad_user.mobile;
                          time_zone=$time_zone;
                          active="true";
                          department_users_attributes = @{
                            department_id=$department_id;
                          }
                          custom_field=@{
                            cf_contact_type=$user_type;
                          }
                        }
                      }
                      
        Write-Host ($post_data | ConvertTo-JSON)
        
        # Post the account creation request
        $response = Invoke-WebRequest -Uri "$($base_uri)/itil/requesters.json" -Header $headers -Method Post -Body ($post_data | ConvertTo-JSON) -ContentType "application/json"
        
        Write-Host $response
      }
      else
      {
        Write-Host "Account in freshservice: $($ad_user)" -foregroundcolor Green
      }
  }
  else
  {
    Write-Host "User an agent, skipping: $($ad_user)" -ForegroundColor Yellow
  }
}