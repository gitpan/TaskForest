# -*- perl -*-

my $SLEEP_TIME = 2;
use Test::More tests => 7;

use strict;
use warnings;
use Data::Dumper;
use Cwd;
use File::Copy;
use TaskForest::Test;

BEGIN {
    use_ok( 'TaskForest'  );
}

my $cwd = getcwd();
my $src_dir = "$cwd/t/family_archive";
my $dest_dir = "$cwd/t/families";
mkdir $dest_dir unless -d $dest_dir;

&TaskForest::Test::cleanup_files($dest_dir);
copy("$src_dir/MULTITOKENS", $dest_dir);


$ENV{TF_RUN_WRAPPER} = "$cwd/blib/script/run";
$ENV{TF_LOG_DIR} = "$cwd/t/logs";
$ENV{TF_JOB_DIR} = "$cwd/t/jobs";
$ENV{TF_FAMILY_DIR} = "$cwd/t/families";
$ENV{TF_CONFIG_FILE} = "$cwd/taskforest.test.cfg";
$ENV{TF_ONCE_ONLY} = 1;

#exit; 

my $log_dir = &TaskForest::LogDir::getLogDir($ENV{TF_LOG_DIR});
&TaskForest::Test::cleanup_files($log_dir);

my $tf = TaskForest->new();
isa_ok($tf,  'TaskForest',  'TaskForest created successfully');

$tf->{options}->{once_only} = 1;

my $options = &TaskForest::Options::getOptions();

print Dumper($options);
#exit 0;

print "Running ready jobs\n";
$tf->runMainLoop();
$tf->{options}->{once_only} = 1;
sleep (2);
ok(-e "$log_dir/MULTITOKENS.J1.0", "  After first cycle, J1 ran successfully");
ok(-e "$log_dir/MULTITOKENS.J2.0", "  After first cycle, J2 ran successfully");
ok(-e "$log_dir/MULTITOKENS.J4.0", "  After first cycle, J4 ran successfully");
ok(-e "$log_dir/MULTITOKENS.J5.0", "  After first cycle, J5 ran successfully");

print "Running ready jobs\n";
$tf->runMainLoop();
$tf->{options}->{once_only} = 1;
sleep (2);
ok(-e "$log_dir/MULTITOKENS.J3.0", "  After first cycle, J3 ran successfully");