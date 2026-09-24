#!/usr/bin/env perl
# with-timeout.pl SECONDS COMMAND...   run COMMAND in its own process group; after
# SECONDS kill the whole group (servers and children included) and exit 142.
# macOS has no timeout(1). Otherwise exits with COMMAND's status.
use strict; use warnings;
my $t = shift @ARGV;
defined(my $pid = fork) or die "with-timeout: fork failed: $!\n";
if ($pid == 0) { setpgrp(0, 0); exec @ARGV or die "with-timeout: cannot run @ARGV: $!\n"; }
local $SIG{ALRM} = sub { kill 'KILL', -$pid; waitpid($pid, 0); exit 142 };
alarm $t;
waitpid($pid, 0);
alarm 0;
exit($? & 127 ? 128 + ($? & 127) : $? >> 8);
