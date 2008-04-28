# -*- perl -*-

my $SLEEP_TIME = 2;
use Test::More tests => 7;

use strict;
use warnings;
use Data::Dumper;
use Cwd;
use File::Copy;

BEGIN {
    use_ok( 'TaskForest'  );
}


my $cwd = getcwd();
my $src_dir = "$cwd/t/family_archive";
my $dest_dir = "$cwd/t/families";
mkdir $dest_dir unless -d $dest_dir;

cleanup_files($dest_dir);
copy("$src_dir/SIMPLE", $dest_dir);


$ENV{TF_RUN_WRAPPER} = "$cwd/blib/script/run";
$ENV{TF_LOG_DIR} = "$cwd/t/logs";
$ENV{TF_JOB_DIR} = "$cwd/t/jobs";
$ENV{TF_FAMILY_DIR} = "$cwd/t/families";

my $log_dir = &TaskForest::LogDir::getLogDir($ENV{TF_LOG_DIR});
cleanup_files($log_dir);


my $tf = TaskForest->new();
isa_ok($tf,  'TaskForest',  'TaskForest created successfully');

$tf->{options}->{once_only} = 1;

print "Running ready jobs\n";
$tf->runMainLoop();

print "Waiting $SLEEP_TIME seconds for job to finish\n";

my $num_tries = 30;
for (my $n = 1; $n <= $num_tries; $n++) { 
    sleep $SLEEP_TIME;
    last if -e "$log_dir/SIMPLE.J2.0";
    diag("Haven't found job log files on try $n of $num_tries.  Sleeping another $SLEEP_TIME seconds");
}

    
    

my $diag = "Try to increase the value of \$SLEEP_TIME in t/007_TaskForest.t";

ok(-e "$log_dir/SIMPLE.J2.0", "  After first cycle, J2 ran successfully") || diag ($diag) ;
ok(-e "$log_dir/SIMPLE.J3.0", "  After first cycle, J3 ran successfully") || diag ($diag) ;
ok(-e "$log_dir/SIMPLE.J6.0", "  After first cycle, J6 ran successfully") || diag ($diag) ;
ok(-e "$log_dir/SIMPLE.J7.0", "  After first cycle, J7 ran successfully") || diag ($diag) ;
ok(-e "$log_dir/SIMPLE.J9.0", "  After first cycle, J9 ran successfully") || diag ($diag) ;




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
