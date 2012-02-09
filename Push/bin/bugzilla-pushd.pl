#!/usr/bin/perl

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use strict;
use warnings;

BEGIN {
    use Cwd 'abs_path';
    use File::Basename;
    use lib abs_path(dirname(__FILE__) . '/../../..');
    use lib abs_path(dirname(__FILE__) . '/../../../lib');
    use lib abs_path(dirname(__FILE__) . '/../lib');
    use Bugzilla;
    Bugzilla->extensions;
}

use Bugzilla::Extension::Push::Daemon;
Bugzilla::Extension::Push::Daemon->start();

=head1 NAME

bugzilla-push.pl - Pushes changes queued by the Push extension to connectors.

=head1 SYNOPSIS

  bugzilla-push.pl [OPTIONS] COMMAND

    OPTIONS:
      -f        Run in the foreground (don't detach)
      -d        Output a lot of debugging information
      -p file   Specify the file where jobqueue.pl should store its current
                process id. Defaults to F<data/jobqueue.pl.pid>.
      -n name   What should this process call itself in the system log?
                Defaults to the full path you used to invoke the script.

    COMMANDS:
      start     Starts a new jobqueue daemon if there isn't one running already
      stop      Stops a running jobqueue daemon
      restart   Stops a running jobqueue if one is running, and then
                starts a new one.
      check     Report the current status of the daemon.
      install   On some *nix systems, this automatically installs and
                configures jobqueue.pl as a system service so that it will
                start every time the machine boots.
      uninstall Removes the system service for jobqueue.pl.
      help      Display this usage info


