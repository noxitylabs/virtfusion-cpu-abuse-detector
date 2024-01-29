#!/bin/bash

# Editable fields
webhook_url="" # Set your webhook URL here
cpu_usage_threshold=75 # Set your CPU usage threshold here in %. We recommend setting this to +5% of actual threshold you want to monitor, to account for usage discrepancies.
node_name="" # Set your node name here. Used in the webhook incident message
average_period_minutes=60 # Set your averaging period here (in minutes)

# Data file location
data_file="/tmp/final_cpu_usage_data.txt" # Specify the path to store data. You must create full path and the .txt file.

# Function to send a webhook
send_webhook() {
  local domain=$1
  local event_id=$domain # Using the domain of the VM (UUID) as the event ID

  curl -X POST "$webhook_url" \
    -H "Content-Type: application/json" \
    -d "{\"message\": \"VM CPU abuse was detected on $node_name\", \"description\": \"Verify average CPU usage on $domain and throttle the CPU to XX% if abuse is confirmed.\", \"status\": \"trigger\", \"event_id\": \"$event_id\"}"

    ## echo --> Verify average CPU usage on <uuid> and throttle the CPU to 50% if abuse is confirmed.
}

# Function to get CPU time and VCPU count for a domain, with debugging - Remove echos for w/o debugging.
get_cpu_time_and_vcpu_count() {
  local domain_uuid=$1
  local domain_stats=$(virsh domstats "$domain_uuid")
  local cpu_time=$(echo "$domain_stats" | grep 'cpu.time' | cut -d'=' -f2)
  local vcpu_count=$(echo "$domain_stats" | grep 'vcpu.current' | cut -d'=' -f2)

  echo "Domain: $domain_uuid, CPU Time: $cpu_time, VCPU Count: $vcpu_count" >&2
  echo "$cpu_time $vcpu_count"
}

# Function to calculate CPU usage, with debugging - Remove echos for w/o debugging.
calculate_cpu_usage() {
  local last_cpu_time=$1
  local current_cpu_time=$2
  local time_diff=$3
  local vcpu_count=$4

  if [ "$time_diff" -eq 0 ]; then
    echo "0"
  else
    local cpu_time_diff=$((current_cpu_time - last_cpu_time))
    local cpu_usage=$(echo "scale=1; (($cpu_time_diff * 100.0) / ($time_diff * 1000.0 * 1000.0 * 1000.0) / $vcpu_count)" | bc)
    echo "Calculated CPU Usage: $cpu_usage%, Time Diff: $time_diff, CPU Time Diff: $cpu_time_diff, VCPU Count: $vcpu_count" >&2
    echo "$cpu_usage"
  fi
}

# Function to update data file with new readings and clean up old entries
update_data_file() {
  local domain=$1
  local usage=$2
  local cpu_time=$3
  local vcpu_count=$4
  local current_time=$(date +%s)
  
  # Calculate period to keep data (average_period_minutes + 20%)
  local keep_duration=$((average_period_minutes * 60 * 120 / 100)) # 72 usage snapshots in seconds for a 60 minute period

  # Filter and keep the relevant entries
  awk -v domain="$domain" -v current_time="$current_time" -v period="$keep_duration" '
    $2 == domain && current_time - $1 <= period { print $0; }
    END { print current_time " " domain " " usage " " cpu_time " " vcpu_count; }
  ' "$data_file" > "/tmp/cpu_usage_data_updated.txt"

  # Replace old data file with the new one
  mv /tmp/cpu_usage_data_updated.txt "$data_file"
}

# Function to calculate average CPU usage from data file
calculate_average_from_data() {
  local domain=$1
  local current_time=$(date +%s)
  local period=$((average_period_minutes * 60)) # Only consider data within this period

  awk -v domain="$domain" -v current_time="$current_time" -v period="$period" '
    $2 == domain && current_time - $1 <= period { total += $3; count++ }
    END { if (count > 0) print total / count; else print 0; }
  ' "$data_file"
}

# Ensure data file exists
touch "$data_file"

# Get a list of all running domains
mapfile -t domains < <(virsh list --state-running | awk '{if(NR>2)print $2}')

# Collect data for each domain
for domain in "${domains[@]}"; do
  # Skip if domain is empty
  if [[ -z "$domain" ]]; then
    continue
  fi

  read -r current_cpu_time current_vcpu_count <<< $(get_cpu_time_and_vcpu_count "$domain")
  
  # Skip if any value is missing or not numeric
  if ! [[ "$current_cpu_time" =~ ^[0-9]+$ && "$current_vcpu_count" =~ ^[0-9]+$ ]]; then
    echo "Skipping $domain due to missing data."
    continue
  fi

  last_entry=$(awk -v domain="$domain" '$2 == domain {print $0}' "$data_file" | tail -n 1)
  last_cpu_time=$(echo "$last_entry" | cut -d' ' -f4)
  last_update=$(echo "$last_entry" | cut -d' ' -f1)

  # If it's the first run, we won't have last values
  if [[ -z "$last_cpu_time" || -z "$last_update" ]]; then
    last_cpu_time=$current_cpu_time
    last_update=$(date +%s)
  fi

  time_diff=$(( $(date +%s) - last_update ))

  # Calculate and store CPU usage
  cpu_usage=$(calculate_cpu_usage "$last_cpu_time" "$current_cpu_time" "$time_diff" "$current_vcpu_count")
  update_data_file "$domain" "$cpu_usage" "$current_cpu_time" "$current_vcpu_count"
done

# Calculate average and send webhook if needed
for domain in "${domains[@]}"; do
  # Calculate the average CPU usage over the specified period
  average=$(calculate_average_from_data "$domain")

  # Count the number of data points for the specified period
  data_points=$(grep "$domain" "$data_file" | wc -l)

  # Calculate the number of data points expected for the specified period
  expected_data_points=$((average_period_minutes))

  # Only send a notification if we have enough data points
  if [ "$data_points" -ge "$expected_data_points" ]; then
    echo "Average CPU Usage for $domain over the last $average_period_minutes minutes: $average%"

    # Check if average CPU usage exceeds threshold and send webhook
    if (( $(echo "$average > $cpu_usage_threshold" | bc -l) )); then
      send_webhook "$domain"
    fi
  else
    echo "Not enough data to calculate average for $domain. Data points: $data_points, Expected: $expected_data_points"
  fi
done
