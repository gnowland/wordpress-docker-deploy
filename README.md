# make-success
A makefile for scaffolding, pushing, pulling, syncing, databases and files local &amp; remote.

Currently in use on a [Dokku](http://dokku.viewdocs.io/dokku/)-powered ([Docker](https://docker.com)-ized [WordPress](https://wordpress.org) installation.

Minor modifications would be required to generalize it for use in any environment.

## Requirements

- A fresh installation of [Ubuntu 18.04 x64](https://www.ubuntu.com/download)
- The FQDN set
  - Run `sudo hostname -f` to check if the system has an FQDN set
- At least 1GB of system memory
- A domain name pointed at the host's IP (optional)

## Use

### Make

Commands sourced from `Makefile`.

`make build` clones repo from https://github.com/WordPress/WordPress using variables within `.env` and configuration files within `config` and deploys it to a ([Docker](https://docker.com) container running [heroku-buildpack-php](https://github.com/heroku/heroku-buildpack-php) using the a [gliderlabs/herokuish](https://github.com/gliderlabs/herokuish) build orchestration on `git push dokku master`.

| Command                     | Action                                                       |
| --------------------------- | ------------------------------------------------------------ |
| `make help`                 | Outputs all commands & instructions.                         |
| Command                     | Action                                                       |
| `make build`                | Scaffold or Update WP Container. After running this `cd [<appname>] && git push dokku master`      |
| `make instructions`         | Show initial application set-up instructions (db setup, filesystem setup, etc)                     |
| `make diff_prod`            | Compare local changes with what's on the dev/prod server (depending on what's set in `/etc/hosts`) |
| `make push [<local path>] [<remote hostname or USER@HOST>]:[<remote path>]`*  | Send files to specified `ENV` server (optionally takes a path relative to `src/`, prompts otherwise) |
| `make pull [<remote hostname or USER@HOST>]:[<remote path>] [<local path>]`*  | Get files from specified `ENV` server (optionally takes a path relative to `src/`, prompts otherwise) |
| `make sync [<from hostname or USER@HOST>] [<to hostname or USER@HOST>]` | Pull database, `wp-content` from _origin_ and push to _destination_ (prompts for each procedure) |
| `make plugit [<user/repo>] ENV=[<host or USER@]HOST>]` | Download a git repo to the specified `ENV` server's `wp-content/plugins` folder, set proper ownership & permissions |
| `make theme_build ENV=[<hostname or USER@]HOST>]` | Run the theme build (CSS/JS compile) scripts & push to specified `ENV` server.    |
| `make destroy`              | 🧨 Permanently destroys the database, app, & all stored files (fresh start) 🧨                          |
| `make dev`                  | "`vagrant up`" Power up (or create, if it doesn't already exist) the VM                                 |
| `make dev_down`             | "`vagrant halt`" Shut down the VM                                                                       |
| `make dev_reload`           | "`vagrant reload`" Restart the VM (loads any Vagrantfile changes)<br>Pass `--provision` to re-provision |
| `make dev_ssh`              | "`vagrant ssh`" SSH into the VM                                                                         |
| `make dev_ssh_info`         | "`vagrant ssh-config dokku`" Output the SSH info (for use in `~/.ssh/config`)                           |
| `make dev_destroy`          | "`vagrant destroy`" 🧨 Permanently destroys all remnants of the VM: the database, app, & all stored files (fresh start) 🧨 |

> \*Before `make push ...`, `make pull ...`, `make theme_build ...`, or `vscode-ext.sync-rsync` will work you must first modify the host `visudo` settings to allow unattended operations:

> 🌍 The following commands should be run on the server

```shell
which rsync # take note of the result!
sudo visudo
```

And add the following to the bottom of the file (lower instructions take precedence):

```shell
[<username>] ALL=NOPASSWD:[<path returned from which rsync>]
```

IMPORTANT TARGET PATH INFORMATION!
- Source
  - When using "/" at the end of source path, rsync will copy the *content* of the source folder to the destination, but not the folder itself.
  - When omitting "/" from the end of source path, rsync will copy *the folder and its content* to the destination.
- Destination
  - When using "/" at the end of the destination path, rsync will place the data *inside the last destination folder*.
  - When omitting "/" from the end of the destination path, rsync will *create a folder with the name of the last destination* and paste the data inside that folder.

### Shell

## Custom Server Commands

Commands sourced from `.profile`.

```shell
# local
scp .profile [<remote hostname or USER@HOST>]:~

# remote
source .profile
```

| Command                           | Action                                                  | Notes                                                  |
| --------------------------------- | ------------------------------------------------------- | ------------------------------------------------------ |
| `la [<(opt: dir)>]`               | Supercharged `ls` (list files)                          | Uses current `dir` if unspecified                      |
| `lap [<(opt: dir)>]`              | `la` with "octal permissions" (e.g. 755)                | ☝️                                                     |
| `bin [<appname>] [<(opt: sudo)>]` | Enter container as root                                 | Executes `docker exec -it [<appname>].web.1 /bin/bash;`<br> (assumes `docker ps` 'name')`<br> Shorthand: `sudo : -s` |
| `wgit [<user/repo>]`              | Download a git repo (e.g. plugin), extract, set ownership & permissions | Sets ownership to 32767 (container user)               |
| `uzp [<file.zip>]`                | Extract a `.zip` file, set ownership & permissions                      | ☝️, (also: be sure to verify unzipped directory name!) |
| `pfix`                            | Fix ownership & permissions of current directory & subdirectories       | Sets ownership to 32767 (container user)               |
| `av [<on/off>]`                   | Turn on/off Sophos AV                                                   | Shorthand: `on : -i`, `off : -o` |
| `clr`                             | Clear up RAM (PageCache, Swapfile)                                      | Not recommended to run often, or in live environments! |
| `db [<export/import>] [<(import.sql)>]` | Import or export a database dump                                  | Export: Database dumps to `~/.sql` with timestamped filename.<br>Import: requires passing a `dump.sql` file<br>Shorthand: `export: -e`, `import: -i` |
| `sync [<up/down>]`                | Sync `wp-content` files up or down from VAGRANT (dev) server            | Note: this only works between local & vagrant, this **will not work on remote (prod)**<br>Shorthand: `up: -u`, `down: -d` |


## Upgrading WordPress

To upgrade to a later version of WordPress just change the version number in the `.env` file and run `make build` again!

> ⚠️ Warning: A 'traditional' upgrade performed using the WordPress UI-based upgrade process will not survive a server app restart (due to the ephemeral nature of the underlying docker-based filesystem) and thus should not be attempted if you want to persist the upgrade.
