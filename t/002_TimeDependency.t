# -*- perl -*-

# make sure TimeDependency works
use Test::More tests => 10;
use strict;
use warnings;

BEGIN {
    use_ok( 'TaskForest::TimeDependency',     "Can use TimeDependency" );
}

my $td = TaskForest::TimeDependency->new(
    start => '01:00',
    tz => 'UTC',
    );


isa_ok ($td, 'TaskForest::TimeDependency',         'TaskForest::TimeDependency object created properly');

is ($td->{start},     '01:00',      '   start is ok');
is ($td->{tz},        'UTC',        '   tz is ok');
is ($td->{rc},        '',           '   rc is ok');
is ($td->{status},    'Waiting',    '   status is waiting');

my $now = time;
$td->{ep} = $now + 3600;
$td->check();

is($td->{status},    'Waiting',     '   still waiting');

$td->{ep} = time;
$td->check();
is($td->{status},    'Success',     '   success');

$td->{ep} += 10;
$td->check();
is($td->{status},    'Success',     '   still success');

$td->{ep} -= 10;
$td->check();
is($td->{status},    'Success',     '   still success');
