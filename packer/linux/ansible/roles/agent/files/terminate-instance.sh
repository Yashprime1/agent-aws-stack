token=$(curl -X PUT -H "X-aws-ec2-metadata-token-ttl-seconds: 60" --fail --silent --show-error --location "http://169.254.169.254/latest/api/token")
instance_id=$(curl -H "X-aws-ec2-metadata-token: $token" --fail --silent --show-error --location "http://169.254.169.254/latest/meta-data/instance-id")
region=$(curl -H "X-aws-ec2-metadata-token: $token" --fail --silent --show-error --location "http://169.254.169.254/latest/meta-data/placement/region")
idle_tag_key="SemaphoreAgentState"
idle_tag_value="IDLE"
asg_name=$(curl -s -H "X-aws-ec2-metadata-token: $token" "http://169.254.169.254/latest/meta-data/tags/instance/aws:autoscaling:groupName")
# We unset all AWS related variables to make sure the instance profile is always used.
# Before, we were using a specific AWS CLI profile that activates the instance profile,
# but that didn't work if people messed up the ~/.aws/config file.
unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY
unset AWS_SESSION_TOKEN
rm -rf $HOME/.aws/credentials

aws autoscaling set-instance-protection \
    --region "$region" \
    --auto-scaling-group-name "$asg_name" \
    --instance-ids "$instance_id" \
    --no-protected-from-scale-in
if [[ $SEMAPHORE_AGENT_SHUTDOWN_REASON == "IDLE" ]]; then
  aws ec2 create-tags \
    --region "$region" \
    --resources "$instance_id" \
    --tags "Key=${idle_tag_key},Value=${idle_tag_value}"

  echo "Instance ${instance_id} tagged ${idle_tag_key}=${idle_tag_value} and unprotected from scale-in. Lambda will terminate it."
fi
