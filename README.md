# Hosts File Manager

## Description
Alfred 5 workflow to see what your Mac's hosts file overrides, and why, and to change it in seconds.

## Installation

1. Download the .alfredworkflow file from the latest release and open it to install the workflow in Alfred (requires Powerpack)

## Usage

+ Use keyword "hosts" to list entries. Each one shows its IP, its comment, when it was added and its section (e.g. "Docker Desktop"). System entries are listed last
+ Keep typing to search hostnames, IPs, comments and sections
+ ENTER on an entry turns it off (comments it out) or back on
+ OPTION + ENTER on an entry removes it (a backup is kept at /etc/hosts.bak)
+ CMD + C copies the line
+ To add an entry, type a hostname that isn't in the file: "hosts mysite.test My local site" adds it for 127.0.0.1 with a comment, and "hosts example.com 10.0.0.5 New server test" points it at another IP (the IP can also come first). A pasted URL is reduced to its hostname
+ Changes ask for your administrator password and flush the DNS cache. System entries such as localhost can't be changed
+ The keyword can be changed under Configure Workflow in Alfred's preferences

## What it changes on your Mac

The workflow only reads and writes `/etc/hosts`, and only when you press ENTER or OPTION + ENTER on an entry. Every change asks for your administrator password through the standard macOS dialog, then flushes the DNS cache.

+ Adding appends one line, e.g. `127.0.0.1 mysite.test # My local site (added 09-11-2026)`. The date is how the list shows an entry's age
+ Turning an entry off puts a `#` in front of its line; turning it on removes it again
+ Turning off and removing keep the previous file at `/etc/hosts.bak`
+ Before changing a line, the workflow checks it hasn't changed since the list was shown (e.g. by Docker), and stops if it has
+ System entries such as `localhost` are never changed

### Upgrading from 2.x

The "hostadd" keyword is gone: type the new hostname after "hosts" instead. ENTER on an entry now turns it off instead of copying it; use CMD + C to copy.

## Development

The logic lives in `workflow/hosts.sh`. To try it on a copy of your hosts file:

```bash
cp /etc/hosts /tmp/hosts && HOSTS_FILE=/tmp/hosts workflow/hosts.sh list "docker"
```

Build the workflow file from the `workflow` folder:

```bash
(cd workflow && zip -r "../Hosts File Manager.alfredworkflow" . -x '.*')
```

## Author
[Jacob Overgaard](https://snebold.dk)
