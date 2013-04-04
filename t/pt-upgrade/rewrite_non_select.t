#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More;

use PerconaTest;
use Sandbox;
require "$trunk/bin/pt-upgrade";

# This runs immediately if the server is already running, else it starts it.
diag(`$trunk/sandbox/start-sandbox master 12348 >/dev/null`);

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh1 = $sb->get_dbh_for('master');
my $dbh2 = $sb->get_dbh_for('master1');

if ( !$dbh1 ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( !$dbh2 ) {
   plan skip_all => 'Cannot connect to second sandbox master';
}
else {
   plan tests => 5;
}

$sb->load_file('master1', 't/pt-upgrade/samples/001/tables.sql');
$sb->load_file('master',  't/pt-upgrade/samples/001/tables.sql');

# Issue 747: Make mk-upgrade rewrite non-SELECT

my $cmd = "$trunk/bin/pt-upgrade h=127.1,P=12345 P=12348 -u msandbox -p msandbox --compare results,warnings --zero-query-times --convert-to-select --fingerprints";

my $c1 = $dbh1->selectrow_arrayref('checksum table test.t')->[1];
my $c2 = $dbh2->selectrow_arrayref('checksum table test.t')->[1];

is(
   $c1,
   $c2,
   'Table checksums identical'
);

ok(
   no_diff(
      "$cmd $trunk/t/pt-upgrade/samples/001/non-selects.log",
      't/pt-upgrade/samples/001/non-selects-rewritten.txt'
   ),
   'Rewrite non-SELECT'
);

my $c1_after = $dbh1->selectrow_arrayref('checksum table test.t')->[1];
my $c2_after = $dbh2->selectrow_arrayref('checksum table test.t')->[1];

is(
   $c1_after,
   $c1,
   'Table on host1 not changed'
);

is(
   $c2_after,
   $c2,
   'Table on host2 not changed'
);

# #############################################################################
# Done.
# #############################################################################
diag(`$trunk/sandbox/stop-sandbox 12348 >/dev/null`);
$sb->wipe_clean($dbh1);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;