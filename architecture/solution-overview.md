# Solution Overview

## Platform

`mss-solution` is the wrapper around the mobile solution. It provides planning, governance, architecture, and Copilot workspace setup.

## Code Repositories

```text
mss-app
 ├── maui-toolkit
 ├── net-client-api

maui-toolkit
 └── net-client-api

net-client-api
 └── no platform dependencies
```

## Dependency Direction

Allowed:

```text
mss-app -> maui-toolkit
mss-app -> net-client-api
maui-toolkit -> net-client-api
```

Not allowed:

```text
net-client-api -> maui-toolkit
net-client-api -> mss-app
maui-toolkit -> mss-app
```
