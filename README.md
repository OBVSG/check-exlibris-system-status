# Check Ex Libris System Status

## Description

This program returns Ex Libris system status information via API, the
the information is also available at https://status.exlibrisgroup.com.

Nagios compliant status code & message will be generated. 

## Installation

Install dependencies (see cpanfile) and copy check_exlibris_system_status.pl
to a location where your Nagios compatible monitoring can find it and make it executable.

## Usage

```
$ ./check_exlibris_system_status.pl --help
Usage: ./check_exlibris_system_status.pl [-H <host>] [-u <username>] [-p <password>] [-S <service>] [-t <timeout>] [-d] [-v] [-V]

Check Ex Libris system status https://status.exlibrisgroup.com via API

  -H (--hostname)  = API hostname (exlprod.service-now.com or exldev.service-now.com)
  -u (--username)  = API username (default APIUser)
  -p (--password)  = API password
  -S (--service)   = internal service name (contact Exlibris.Status@exlibrisgroup.com if unknown)
  -t (--timeout)   = timeout in seconds (default 20)
  -d (--details)   = multiline output including service details
  -v (--verbose)   = debugging output
  -V (--version)
  -h (--help)
```

## License

See [LICENSE](./LICENSE)

## Contributing

Anyone can freely contribute to this project.
