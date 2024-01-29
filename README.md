# CPU Monitoring Script for Hypervisors

This CPU Monitoring Script is a practical tool designed to monitor and alert about the CPU usage abuse for virtual machines on Virtfusion **Debian** hypervisors. It uses Virsh to collect data and integrate with an SRE management platform like Squadcast to send notifications via outgoing webhooks.

***

## Table of Contents

* [Getting Started](#getting-started)
* [Dependencies](#dependencies)
* [Authors](#authors)
* [Roadmap / Ideas](#roadmap--ideas)
* [Contributing](#contributing)
* [Acknowledgements](#acknowledgements)

***

## Getting Started

To use this script:

1. Ensure that all dependencies are installed on your hypervisor.
2. Clone the repository onto your hypervisor in desired location. We recommend `/usr/local/bin/virtfusion_helpers`.
3. Add execute permissions to the script using `chmod +x /usr/local/bin/virtfusion_helpers/abuse-detector.sh`.
4. Schedule the script to run at regular intervals using CRON. Create a file in `/etc/cron.d/` named `virtfusion_abuse-detector` with the following content (adjust the path and frequency as needed):
```
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
* * * * * root /usr/local/bin/virtfusion_helpers/abuse-detector.sh >/dev/null 2>&1
```
5. Adjust the threshold values and notification endpoints as per your requirements at the beggining of the PHP file. 
6. Adjust the SRE management platform's deduplication rules to avoid duplicate notifications.
7. Adjust the webhook payload to your liking. Currently it's formatted for Squadcast's incoming webhook format.

***

## Dependencies

- Utilities: `curl`, `bc`, `awk` and `grep`, should be present on the system.
- SRE management platform such as Squadcast/OpsGenie, for sending notification POST requests. You can replace this with anything that accepts POST webhook requests to handle the notifications.

***

## Authors

* [Matic Bončina](https://github.com/maticboncina)

***

## Roadmap / Ideas

- [X] Make data collection more reliable by using Virsh.
- [X] Redo the CPU time calculation from scratch to be more accurate.
- [ ] Ability to run the script anywhere, not just on the hypervisor - (Requires Virtfusion API endpoint for data collection).
- [ ] Ability to automatically throttle VM CPU % - (Requires Virtfusion API endpoint). 

***

## Contributing

Contributions to this project are highly appreciated. If you have ideas for improvements or enhancements, please feel free to open a pull request or issue. All contributions will be credited appropriately.

***

## Acknowledgements

This script was developed out of a personal need and in response to the community's demand for a reliable CPU monitoring tool for Virtfusion Debian hypervisors without the need for external tools such as HetrixTools, Grafana/Prometheus, netdata etc... 

CRON code was adapted from [Virtfusion's official disaster backup automation guide](https://stackoverflow.com/a/4880290), to remain consistent with the rest of the Virtfusion ecosystem.

Special thanks to [Phill](https://github.com/vf-phill), the creator of Virtfusion, for providing the code segment that calculates CPU time. This ensures that the usage values are as closely aligned as possible with those used by Virtfusion (in statistic graphs), thereby offering a high degree of accuracy.
