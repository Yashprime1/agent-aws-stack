$Token = (Invoke-WebRequest -UseBasicParsing -Method Put -Headers @{'X-aws-ec2-metadata-token-ttl-seconds' = '60'} http://169.254.169.254/latest/api/token).content
$InstanceId = (Invoke-WebRequest -UseBasicParsing -Headers @{'X-aws-ec2-metadata-token' = $Token} http://169.254.169.254/latest/meta-data/instance-id).content
$Region = (Invoke-WebRequest -UseBasicParsing -Headers @{'X-aws-ec2-metadata-token' = $Token} http://169.254.169.254/latest/meta-data/placement/region).content
$IdleTagKey = "SemaphoreAgentState"
$IdleTagValue = "IDLE"
$AutoScalingGroupName = (Invoke-WebRequest -UseBasicParsing -Headers @{'X-aws-ec2-metadata-token' = $Token} http://169.254.169.254/latest/meta-data/tags/instance/aws:autoscaling:groupName).content

# We unset all AWS related variables to make sure the instance profile is always used.
# Before, we were using a specific AWS CLI profile that activates the instance profile,
# but that didn't work if people messed up the ~/.aws/config file.
$env:AWS_ACCESS_KEY_ID = ""
$env:AWS_SECRET_ACCESS_KEY = ""
$env:AWS_SESSION_TOKEN = ""

if (Test-Path "$HOME\.aws\credentials") {
  Remove-Item -Recurse -Force -Path "$HOME\.aws\credentials"
}

aws autoscaling set-instance-protection `
    --region "$Region" `
    --auto-scaling-group-name "$AutoScalingGroupName" `
    --instance-ids "$InstanceId" `
    --no-protected-from-scale-in 2> $null

if ($env:SEMAPHORE_AGENT_SHUTDOWN_REASON -eq "IDLE") {

  aws ec2 create-tags `
    --region "$Region" `
    --resources "$InstanceId" `
    --tags "Key=$IdleTagKey,Value=$IdleTagValue" 2> $null

  Write-Output "Instance $InstanceId tagged $IdleTagKey=$IdleTagValue and unprotected from scale-in. Lambda will terminate it."
}
