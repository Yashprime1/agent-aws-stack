# Shutdown hook is not executed in a login shell,
# and launchD has no default built-in mechanism for loading environments
# like systemD's environment generators, so we need to set the PATH
# environment variable (and any other variables we might expect) here.
ARCH=$(uname -m)
if [[ ${ARCH} =~ "arm" || ${ARCH} == "aarch64" ]]; then
  export PATH="/opt/homebrew/bin:/opt/homebrew/sbin${PATH+:$PATH}";
else
  export PATH=/usr/local/bin:$PATH
fi

token=$(curl -X PUT -H "X-aws-ec2-metadata-token-ttl-seconds: 60" --fail --silent --show-error --location "http://169.254.169.254/latest/api/token")
instance_id=$(curl -H "X-aws-ec2-metadata-token: $token" --fail --silent --show-error --location "http://169.254.169.254/latest/meta-data/instance-id")
region=$(curl -H "X-aws-ec2-metadata-token: $token" --fail --silent --show-error --location "http://169.254.169.254/latest/meta-data/placement/region")

# We unset all AWS related variables to make sure the instance profile is always used.
# Before, we were using a specific AWS CLI profile that activates the instance profile,
# but that didn't work if people messed up the ~/.aws/config file.
unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY
unset AWS_SESSION_TOKEN
rm -rf $HOME/.aws/credentials

if $(cat /tmp/semaphore_job_completed); then
  echo "Job completed, terminating instance."
else
  echo "Job not completed, sleeping for 1 hour and then terminating instance."
  slack_token=${SLACK_BOT_TOKEN:-$SLACK_TOKEN}
  slack_channel=${SLACK_CHANNEL_ID:-C0A9NBF8KQQ}
  if [[ -n "$slack_token" ]]; then
    curl -X POST \
      -H "Authorization: Bearer $slack_token" \
      -H "Content-Type: application/x-www-form-urlencoded" \
      --data-urlencode "channel=$slack_channel" \
      --data-urlencode "text=Semaphore agent on instance $instance_id has an incomplete job; will sleep 1h then terminate." \
      https://slack.com/api/chat.postMessage
  else
    echo "SLACK_BOT_TOKEN/SLACK_TOKEN not set; skipping Slack notification."
  fi
  sleep 3600
fi

if [[ $SEMAPHORE_AGENT_SHUTDOWN_REASON == "IDLE" ]]; then
  aws autoscaling terminate-instance-in-auto-scaling-group \
    --region "$region" \
    --instance-id "$instance_id" \
    --should-decrement-desired-capacity
else
  aws autoscaling terminate-instance-in-auto-scaling-group \
    --region "$region" \
    --instance-id "$instance_id" \
    --no-should-decrement-desired-capacity
fi
