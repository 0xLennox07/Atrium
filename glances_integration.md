CPU Stats:
```bash
curl -s http://<SERVER_IP>:<GLANCES_PORT>/api/4/percpu | jq 'map({core: .cpu_number, usage: .total})' && curl -s http://<SERVER_IP>:<GLANCES_PORT/api/4/cpu | jq '{cpuCores: .cpucore, cpuOverallUsage: .total}'

Output:
[
  {
    "core": 0,
    "usage": 43.3
  },
  {
    "core": 1,
    "usage": 46.0
  },
  {
    "core": 2,
    "usage": 44.0
  },
  {
    "core": 3,
    "usage": 44.6
  }
]
{
  "cpuCores": 4,
  "cpuOverallUsage": 44.4
}
```

getCores (to get both physical and logical cores):
```bash
curl http://<SERVER_IP>:<GLANCES_PORT/api/4/core | jq

Output:
{
  "phys": 2,
  "log": 4
}
```

getSensors:
```bash
curl -s http://<SERVER_IP>:<GLANCES_PORT/api/4/sensors | jq 'map({sensor: .label, unit: .unit, temp: .value, warning: .warning, critical: .critical})'
[
  {
    "sensor": "Core 0",
    "unit": "C",
    "temp": 43,
    "warning": 84,
    "critical": 100
  },
  {
    "sensor": "Core 1",
    "unit": "C",
    "temp": 44,
    "warning": 84,
    "critical": 100
  },
  {
    "sensor": "Package id 0",
    "unit": "C",
    "temp": 45,
    "warning": 84,
    "critical": 100
  }
]
```

getMemory:
```bash
curl -s http://<SERVER_IP>:<GLANCES_PORT/api/4/mem | jq '{
  percent: .percent,
  total: (((.total / 1024 / 1024 / 1024) * 100 | round) / 100),
  available: (((.available / 1024 / 1024 / 1024) * 100 | round) / 100),
  used: (((.used / 1024 / 1024 / 1024) * 100 | round) / 100)
}'

Output:

```

getSwapMemory:
```bash
curl -s http://<SERVER_IP>:<GLANCES_PORT/api/4/memswap | jq '{
  percent: .percent,
  total_GB: (((.total / 1024 / 1024 / 1024) * 100 | round) / 100),
  used_GB: (((.used / 1024 / 1024 / 1024) * 100 | round) / 100),
  free_GB: (((.free / 1024 / 1024 / 1024) * 100 | round) / 100),
  swap_in_MB: (((.sin / 1024 / 1024) * 100 | round) / 100),
  swap_out_MB: (((.sout / 1024 / 1024) * 100 | round) / 100)
}'

Output:
{
  "percent": 5.7,
  "total_GB": 8,
  "used_GB": 0.46,
  "free_GB": 7.54,
  "swap_in_MB": 19.36,
  "swap_out_MB": 500.57
}
```

getNetwork:
```bash
curl -s http://<SERVER_IP>:<GLANCES_PORT/api/4/network | jq 'map({
  interface: .interface_name,
  download_KBps: (((.bytes_recv_rate_per_sec / 1024) * 100 | round) / 100),
  upload_KBps: (((.bytes_sent_rate_per_sec / 1024) * 100 | round) / 100)
})'

Output:
[
  {
    "interface": "lo",
    "download_KBps": 0.02,
    "upload_KBps": 0.02
  },
  {
    "interface": "eth0",
    "download_KBps": 0.09,
    "upload_KBps": 1.01
  }
]
```

getDisks:
```bash
curl -s http://<SERVER_IP>:<GLANCES_PORT/api/4/fs | jq 'map({
  device: .device_name,
  mount: .mnt_point,
  type: .fs_type,
  percent: .percent,
  total_GB: (((.size / 1024 / 1024 / 1024) * 100 | round) / 100),
  used_GB: (((.used / 1024 / 1024 / 1024) * 100 | round) / 100),
  free_GB: (((.free / 1024 / 1024 / 1024) * 100 | round) / 100)
})'

Output:
[
  {
    "device": "/dev/sda2",
    "mount": "/etc/resolv.conf",
    "type": "ext4",
    "percent": 73.5,
    "total_GB": 467.35,
    "used_GB": 325.97,
    "free_GB": 117.57
  },
  {
    "device": "/dev/sda2",
    "mount": "/etc/hostname",
    "type": "ext4",
    "percent": 73.5,
    "total_GB": 467.35,
    "used_GB": 325.97,
    "free_GB": 117.57
  },
  {
    "device": "/dev/sda2",
    "mount": "/etc/hosts",
    "type": "ext4",
    "percent": 73.5,
    "total_GB": 467.35,
    "used_GB": 325.97,
    "free_GB": 117.57
  }
]
```

getUptime:
```bash
curl -s http://<SERVER_IP>:<GLANCES_PORT>/api/4/uptime | jq '
  capture("(?:(?<days>[0-9]+) days?, )?(?<hours>[0-9]+):(?<minutes>[0-9]+):(?<seconds>[0-9]+)")
  | {
      days: (.days // "0" | tonumber),
      hours: (.hours | tonumber),
      minutes: (.minutes | tonumber),
      seconds: (.seconds | tonumber)
    }
  | . + { total_seconds: ((.days * 86400) + (.hours * 3600) + (.minutes * 60) + .seconds) }
'

Output:
{
  "days": 2,
  "hours": 0,
  "minutes": 48,
  "seconds": 58,
  "total_seconds": 175738
}
```