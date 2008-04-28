# -*- perl -*-

# 
use Test::More tests => 12;
use strict;
use warnings;
use Cwd;
use File::Copy;

BEGIN {
    use_ok( 'TaskForest',     "Can use TaskForest" );
    use_ok( 'TaskForest::LogDir',     "Can use LogDir" );
    use_ok( 'TaskForest::StringHandle',     "Can use StringHandle" );
}

my $cwd = getcwd();
cleanup_files("$cwd/t/families");

my $src_dir = "$cwd/t/family_archive";
my $dest_dir = "$cwd/t/families";
mkdir $dest_dir unless -d $dest_dir;

copy("$src_dir/LONG_RUNNING", $dest_dir);


$ENV{TF_RUN_WRAPPER} = "$cwd/blib/script/run";
$ENV{TF_LOG_DIR} = "$cwd/t/logs";
$ENV{TF_JOB_DIR} = "$cwd/t/jobs";
$ENV{TF_FAMILY_DIR} = "$cwd/t/families";

my $log_dir = &TaskForest::LogDir::getLogDir($ENV{TF_LOG_DIR});
cleanup_files($log_dir);


my $tf = TaskForest->new();
isa_ok($tf,  'TaskForest',  'TaskForest created successfully');

$tf->{options}->{once_only} = 1;


my $sh = TaskForest::StringHandle->start(*STDOUT);
$tf->status();
my $stdout = $sh->stop();
my @lines = split("\n", $stdout);

my $line;
my $regex;

$line = shift(@lines); is($line, "                                       Return   Time              Sched   Actual  Stop ");
$line = shift(@lines); is($line, "Job                          Status      Code   Zone              Start   Start   Time ");
$line = shift(@lines); is($line, "");
$line = shift(@lines); is($line, "LONG_RUNNING::JLongRunning   Ready          -   America/Chicago   00:00   --:--   --:--");

print "Simulate running ready jobs\n";
open (OUT, ">$log_dir/LONG_RUNNING.JLongRunning.pid") || die "Couldn't open pid file\n";
print OUT "pid: 111\nactual_start: 111\n";
close OUT;

open (OUT, ">$log_dir/LONG_RUNNING.JLongRunning.started") || die "Couldn't open started file\n";
print OUT "00:00\n";
close OUT;


$sh = TaskForest::StringHandle->start(*STDOUT);
$tf->status();
$stdout = $sh->stop();
@lines = split("\n", $stdout);

$line = shift(@lines); is($line, "                                       Return   Time              Sched   Actual  Stop ");
$line = shift(@lines); is($line, "Job                          Status      Code   Zone              Start   Start   Time ");
$line = shift(@lines); is($line, "");
$line = shift(@lines); like($line, qr/LONG_RUNNING::JLongRunning   Running        -   America\/Chicago   00:00   \d{2}:\d{2}   --:--/);






sub cleanup {
    my $dir = shift;
	local *DIR;
    
	opendir DIR, $dir or die "opendir $dir: $!";
	my $found = 0;
	while ($_ = readdir DIR) {
        next if /^\.{1,2}$/;
        my $path = "$dir/$_";
		unlink $path if -f $path;
		cleanup($path) if -d $path;
	}
	closedir DIR;
	rmdir $dir or print "error - $!";
}

sub cleanup_files {
    my $dir = shift;
	local *DIR;
    
	opendir DIR, $dir or die "opendir $dir: $!";
	my $found = 0;
	while ($_ = readdir DIR) {
        next if /^\.{1,2}$/;
        my $path = "$dir/$_";
		unlink $path if -f $path;
	}
	closedir DIR;
}
