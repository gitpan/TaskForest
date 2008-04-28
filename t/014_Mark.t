# -*- perl -*-

# 
use Test::More tests => 13;
use strict;
use warnings;
use Data::Dumper;
use Cwd;
use File::Copy;
use TaskForest::Mark;

BEGIN {
    use_ok( 'TaskForest::Family',     "Can use Family" );
    use_ok( 'TaskForest::LogDir',     "Can use LogDir" );
    use_ok( 'TaskForest::StringHandle',     "Can use StringHandle" );
    use_ok( 'TaskForest::Rerun',     "Can use Rerun" );
}

my $cwd = getcwd();
cleanup_files("$cwd/t/families");

my $src_dir = "$cwd/t/family_archive";
my $dest_dir = "$cwd/t/families";
mkdir $dest_dir unless -d $dest_dir;

copy("$src_dir/COLLAPSE", $dest_dir);

$ENV{TF_RUN_WRAPPER} = "$cwd/bin/run";
$ENV{TF_LOG_DIR} = "$cwd/t/logs";
$ENV{TF_JOB_DIR} = "$cwd/t/jobs";
$ENV{TF_FAMILY_DIR} = "$cwd/t/families";

my $log_dir = &TaskForest::LogDir::getLogDir($ENV{TF_LOG_DIR});
cleanup_files($log_dir);

my $sf = TaskForest::Family->new(name=>'COLLAPSE');

isa_ok($sf,  'TaskForest::Family',  'Created COLLAPSE family');
is($sf->{name},  'COLLAPSE',   '  name');
is($sf->{start},  '00:00',   '  start');
is($sf->{tz},  'America/Chicago',   '  tz');

my $sh = TaskForest::StringHandle->start(*STDOUT);
$sf->{options}->{collapse} = 1;
$sf->getCurrent();
$sf->display();
my $stdout = $sh->stop();


my $expected = qq^                                       Return   Time              Sched   Actual  Stop 
Job                          Status      Code   Zone              Start   Start   Time 

COLLAPSE::J9                 Ready          -   America/Chicago   00:00   --:--   --:--
COLLAPSE::J10                Waiting        -   America/Chicago   00:00   --:--   --:--
^;

is ($stdout, $expected, "Got expected collapsed output 1");


# simulate a run
print "Simulate running ready jobs\n";
fakeRun($log_dir, "COLLAPSE", "J9", 0);

$sf = TaskForest::Family->new(name=>'COLLAPSE');
$sf->{options}->{collapse} = 1; 
$sh = TaskForest::StringHandle->start(*STDOUT);
$sf->getCurrent();
$sf->display();
$stdout = '';
$stdout = $sh->stop();

$expected = qq^                                       Return   Time              Sched   Actual  Stop 
Job                          Status      Code   Zone              Start   Start   Time 

COLLAPSE::J9                 Success        0   America/Chicago   00:00   23:20   23:20
COLLAPSE::J10                Ready          -   America/Chicago   00:00   --:--   --:--
^;
is ($stdout, $expected, "Got expected collapsed output 2");

# now mark J9 as failed
#my $log_dir      = &TaskForest::LogDir::getLogDir($log_dir_root);
&TaskForest::Mark::mark("COLLAPSE", "J9", $log_dir, 'failure');

$sf = TaskForest::Family->new(name=>'COLLAPSE');
$sf->{options}->{collapse} = 1; 
$sh = TaskForest::StringHandle->start(*STDOUT);
$sf->getCurrent();
$sf->display();
$stdout = $sh->stop();

$expected = qq^                                       Return   Time              Sched   Actual  Stop 
Job                          Status      Code   Zone              Start   Start   Time 

COLLAPSE::J9                 Failure        0   America/Chicago   00:00   23:20   23:20
COLLAPSE::J10                Waiting        -   America/Chicago   00:00   --:--   --:--
^;
is ($stdout, $expected, "Job J9 marked as failed");



&TaskForest::Rerun::rerun("COLLAPSE", "J9", $log_dir);
$sf = TaskForest::Family->new(name=>'COLLAPSE');
$sf->{options}->{collapse} = 1; 
$sh = TaskForest::StringHandle->start(*STDOUT);
$sf->getCurrent();
$sf->display();
$stdout = $sh->stop();

$expected = qq^                                       Return   Time              Sched   Actual  Stop 
Job                          Status      Code   Zone              Start   Start   Time 

COLLAPSE::J9--Orig_1--       Failure        0   America/Chicago   00:00   23:20   23:20
COLLAPSE::J9                 Ready          -   America/Chicago   00:00   --:--   --:--
COLLAPSE::J10                Waiting        -   America/Chicago   00:00   --:--   --:--
^;
is ($stdout, $expected, "Job J9 marked rerun");

fakeRun($log_dir, "COLLAPSE", "J9", 0);
$sf = TaskForest::Family->new(name=>'COLLAPSE');
$sf->{options}->{collapse} = 1; 
$sh = TaskForest::StringHandle->start(*STDOUT);
$sf->getCurrent();
$sf->display();
$stdout = $sh->stop();

$expected = qq^                                       Return   Time              Sched   Actual  Stop 
Job                          Status      Code   Zone              Start   Start   Time 

COLLAPSE::J9--Orig_1--       Failure        0   America/Chicago   00:00   23:20   23:20
COLLAPSE::J9                 Success        0   America/Chicago   00:00   23:20   23:20
COLLAPSE::J10                Ready          -   America/Chicago   00:00   --:--   --:--
^;
is ($stdout, $expected, "Job J9 marked rerun");



sub fakeRun {
    my ($log_dir, $family, $job, $status) = @_;
    
    open (OUT, ">$log_dir/$family.$job.pid") || die "Couldn't open pid file\n";
    print OUT "pid: 111\nactual_start: 1209270000\nstop: 1209270001\nrc: $status\n";
    close OUT;
    
    open (OUT, ">$log_dir/$family.$job.started") || die "Couldn't open started file\n";
    print OUT "00:00\n";
    close OUT;

    open (OUT, ">$log_dir/$family.$job.$status") || die "Couldn't open pid file\n";
    print OUT "$status\n";
    close OUT;
    
    
}

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
