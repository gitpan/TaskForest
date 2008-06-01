################################################################################
#
# $Id: TaskForest.pm 39 2008-06-01 22:36:48Z aijaz $
#
# This is the primary class of this application.  Version infromation
# is taken from this file.
#
################################################################################

package TaskForest;
use strict;
use warnings;
use POSIX ":sys_wait_h";
use Data::Dumper;
use TaskForest::Family;
use TaskForest::Options;
use TaskForest::Logs qw /$log/;


BEGIN {
    use vars qw($VERSION);
    $VERSION     = '1.12';
}



################################################################################
#
# Name      : The constructor
# Usage     : my $tf = TaskForest->new();
# Purpose   : Gets required and optional parameters from command line, or the
#             environment, if required parameters are missing from the command
#             line.   
# Returns   : Self
# Argument  : If you pass a hash of parameters and values, they are inserted
#             into the environment (as if they were always in %ENV)
# Throws    : 
#
################################################################################
#
sub new {
    my ($class, %parameters) = @_;

    my $self = bless ({}, ref ($class) || $class);

    if (%parameters) {
        foreach my $p (keys %parameters) {
            next unless $p =~ /^TF_([A-Z_]+)$/;
            # untaint
            $parameters{$p} =~ s/[^a-z0-9_\/:\.]//ig;
            $ENV{$p} = $parameters{$p};
        }
    }

    # Get Options
    $self->{options} = &TaskForest::Options::getOptions();

    return $self;
}




################################################################################
#
# Name      : runMainLoop
# Usage     : $tf->runMainLoop();
# Purpose   : This function loops until end_time (23:55) by default.  In each 
#             loop it examines all the Family files and sees if there are any
#             jobs that need to be run.  Because of this, any changes
#             made to any of the family files  will take effect on the
#             iteration of the loop.  By default the system sleeps 60
#             seconds at the end of each loop.  
# Returns   : Nothing
# Argument  : 
# Throws    : 
#
################################################################################
#
sub runMainLoop {
    my $self = shift;
    # We don't want to have to process zombie child processes
    #
    $SIG{CHLD} = 'IGNORE';


    my $end_time = $self->{options}->{end_time};
    my $wait_time = $self->{options}->{wait_time};

    my $rerun = 0;
    my $RELOAD = 1;

    $self->{options} = &TaskForest::Options::getOptions($rerun);  $rerun = 1;
    &TaskForest::LogDir::getLogDir($self->{options}->{log_dir}, $RELOAD);
    &TaskForest::Logs::init("New Loop");
   
    while (1) {
        
        my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);

        # get a fresh list of all family files
        #
        my $glob_string = "$self->{options}->{family_dir}/*";
        my @families = glob($glob_string);

        
        foreach my $family_name (@families) {
            # create a new family object. It is possible that this
            # family will never need to be run today.  That is yet to
            # be determined.
            #
            my ($name) = $family_name =~ /$self->{options}->{family_dir}\/(.*)/;
            my $family = TaskForest::Family->new(name => $name);

            if (!defined $family) {
                # there was a syntax error
                
            }

            # If there aren't any jobs in the family, we really don't
            # need to try.
            #
            next unless $family->{jobs}; # no jobs to run today

            print Dumper($family) if $self->{options}->{verbose};

            # The cycle method gets the current status and runs any
            # jobs that are ready to be run.
            #
            $family->cycle();
        }

        # The once_only option is good when testing.
        #
        if ($self->{options}->{once_only}) {
            last;
        }
        
        my $now = sprintf("%02d%02d", $hour, $min);
        print "It is $now, the time to end is $end_time\n" if $self->{options}->{verbose};
        if (($now + $wait_time) >= $end_time) {
            $log->info("In $wait_time seconds it will be past $end_time.  Exiting loop.");
            last;
        }
        $log->info("Sleeping $wait_time");
        sleep $wait_time;                         # by default: 60s

        &TaskForest::Logs::resetLogs();
        $self->{options} = &TaskForest::Options::getOptions($rerun); 
        &TaskForest::LogDir::getLogDir($self->{options}->{log_dir}, $RELOAD);
        &TaskForest::Logs::init("New Loop");
        
    }
    
}


################################################################################
#
# Name      : status
# Usage     : $tf->status();
# Purpose   : This function prints the status of all families in the
#             system, including ones that don't need to run today.  If
#             a family has no jobs in it, it is skipped
# Returns   : Nothing
# Argument  : 
# Throws    : 
#
################################################################################
#
sub status {
    my $self = shift;

    # get a fresh list of all family files
    #
    my $glob_string = "$self->{options}->{family_dir}/*";
    my @families = glob($glob_string);
    
    foreach my $family_name (@families) {
        # create a new Family object
        #
        my ($name) = $family_name =~ /$self->{options}->{family_dir}\/(.*)/;
        my $family = TaskForest::Family->new(name => $name);
        
        next unless $family->{jobs}; # no jobs to run today

        # get the status of any jobs that may have already run (or
        # failed) today.
        #
        $family->getCurrent();

        # display the family
        #
        $family->display();
    }
}



#################### main pod documentation begin ###################

=head1 NAME

TaskForest - Simple, powerful task scheduler

=head1 SYNOPSIS

  # Run the main program, checking for jobs to run.
  # By default, this will run until 23:55
  #
  use TaskForest;
  my $task_forest = TaskForest->new();
  $task_forest->runMainLoop();

  OR

  # Display the current status of all jobs scheduled to run today
  #
  use TaskForest;
  my $task_forest = TaskForest->new();
  $task_forest->status();

  # Rerun job J_RESOLVE in family F_DNS
  use TaskForest::Rerun;
  rerun("F_DNS", "J_RESOLVE", $log_dir);

  # Rerun job J_RESOLVE in family F_DNS
  use TaskForest::Rerun;
  &TaskForest::Rerun::rerun(
    "F_DNS",            # family name
    "J_RESOLVE",        # job name
    $log_dir,           # log directory
    $cascade,           # optional - apply to all dependent jobs as well
    $dependents_only,   # optional - apply to dependent jobs only
    $family_dir         # family directory
    );


  # Mark job J_RESOLVE in family F_DNS as Success
  use TaskForest::Mark;
  &TaskForest::Mark::mark(
    "F_DNS",            # family name
    "J_RESOLVE",        # job name
    $log_dir,           # log directory
    "Success",          # status
    $cascade,           # optional - apply to all dependent jobs as well
    $dependents_only,   # optional - apply to dependent jobs only
    $family_dir         # family directory
    );

=head1 DESCRIPTION

The TaskForest Job Scheduler (TF) is a simple but expressive job
scheduling system.  A job is defined as any executable program that
resides on the file system.  Jobs can depend on each other.  Jobs can
also have start times before which a job may not by run.  Jobs can be
grouped together into "Families."  A family has a start time
associated with it before which none of its jobs may run.  A family
also has a list of days-of-the-week associated with it.  Jobs within a
family may only run on these days of the week.

Jobs and families are given simple names.  A family is described in a
family file whose name is the family name.  Each family file is a text
file that contains 1 or more job names.  The layout of the job names
within a family file determine the dependencies between the jobs (if
any).

Family names and job names should contain only the characters shown below:
ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_

Let's see a few examples.  In these examples the dashes (-), pipes (|) and
line numbers are not parts of the files.  They're only there for
illustration purposes.  The main script expects environment variables or
command line options that specify the locations of the directory that
contain family files, the directory that contains job files, and the
directory where the logs will be written.  The directory that contains
family files should contain only family files.  

=head2 EXAMPLE 1 - Family file named F_ADMIN

    +---------------------------------------------------------------------
 01 |start => '02:00', tz => 'America/Chicago', days => 'Mon,Wed,Fri'
 02 |
 03 | J_ROTATE_LOGS()
 04 |
    +---------------------------------------------------------------------

The first line in any family file always contains 3 bits of information
about the family: the start time, the time zone, and the days on which
this jobs in this family are run.

In this case, this family starts at 2:00 a.m. Chicago time.  The time is
adjusted for daylight savings time.  This family 'runs' on Monday,
Wednesday and Friday only.  Pay attention to the format: it's important.

Valid days are 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'.  Days must
be separated by commas.

All start times (for families and jobs) are in 24-hour format. '00:00' is
midnight, '12:00' is noon, '13:00' is 1:00 p.m. and '23:59' is one minute
before midnight.

There is only one job in this family - J_ROTATE_LOGS.  This family will
start at 2:00 a.m., at which time J_ROTATE_LOGS will immediately be run.
Note the empty parentheses [()].  These are required. 

What does it mean to say that J_ROTATE_LOGS will be run?  It means that
the system will look for a file called J_ROTATE_LOGS in the directory that
contains job files.  That file should be executable.  The system will
execute that file (run that job) and keep track of whether it succeeded or
failed.  The J_ROTATE_LOGS script can be any executable file: a shell
script, a perl script, a C program etc.

To run the program, the system actually runs a wrapper script that invokes
the job script.  The location of the wrapper script is specified on the
command line or in an environment variable.

Now, let's look at a slightly more complicated example:

=head2 EXAMPLE 2 - Job Dependencies

This family file is named WEB_ADMIN

    +---------------------------------------------------------------------
 01 |start => '02:00', tz => 'America/Chicago', days => 'Mon,Wed,Fri'
 02 |
 03 |               J_ROTATE_LOGS()
 04 |
 05 | J_RESOLVE_DNS()               Delete_Logs_Older_Than_A_Year()
 06 |
 07 |               J_WEB_REPORTS()      
 08 |
 09 |            J_EMAIL_WEB_RPT_DONE()  # send me a notification
 10 |
    +---------------------------------------------------------------------

A few things to point out here:
- Blank lines are ignored.
- A hash (#) and anything after it, until the end of the line is treated
  as a comment and ignored
- Job and family names do not have to start with J_ or be in upper case.

Now then, all jobs on a single line are started AT THE SAME TIME.  All
jobs on a line are started only when all jobs on the previous line are
executed successfully.  If there are no jobs on a previous line (as in the
case of line 3 above), all jobs on that line are started when the family
starts (2:00 a.m. above).  There is an exception to this rule that we'll
see in the next example.

So the above family can be interpreted in English as follows:
"All WEB_ADMIN jobs are eligible to run after 2:00 a.m Chicago time on
Mondays, Wedesdays and Fridays.  The first job to be run is
J_ROTATE_LOGS.  If that succeeds, then J_RESOLVE_DNS and
Delete_Logs_Older_Than_A_Year are started at the same time.  If both these
jobs succeed, then J_WEB_REPORTS is run.  If that job succeeds, the
J_EMAIL_WEB_RPT_done is run."

=head2 EXAMPLE 3 - TIME DEPENDENCIES

Let's say tha twe don't want J_RESOLVE_DNS to start before 9:00 a.m. because
it's very IO-intensive and we want to wait until the relatively quiet
time of 9:00 a.m.  In that case, we can put a time dependency of the job.
This adds a restriction to the job, saying that it may not run before the
time specified.  We would do this as follows:

    +---------------------------------------------------------------------
 01 |start => '02:00', tz => 'America/Chicago', days => 'Mon,Wed,Fri'
 02 |
 03 |               J_ROTATE_LOGS()
 04 |
 05 | J_RESOLVE_DNS(start => '09:00')    Delete_Logs_Older_Than_A_Year()
 06 |
 07 |               J_WEB_REPORTS()      
 08 |
 09 |            J_EMAIL_WEB_RPT_DONE()  # send me a notification
 10 |
    +---------------------------------------------------------------------

J_ROTATE_LOGS will still start at 2:00, as always.  As soon as it
succeeds, Delete_Logs_Older_Than_A_Year is started.  If J_ROTATE_LOGS
succeeds before 09:00, the system will wait until 09:00 before starting
J_RESOLVE_DNS.  It is possible that Delete_Logs_Older_Than_A_Year would
have started and complete by then.  J_WEB_REPORTS would not have started
in that case, because it is dependent on two jobs, and both of them have
to run successfully before it can run.

For completeness, you may also specify a timezone for a job's time
dependency as follows:

 05 | J_RESOLVE_DNS(start=>'10:00', tz=>'America/New_York')  Delete_Logs_Older_Than_A_Year()

=head2 EXAMPLE 4 - JOB FORESTS

You can see in the example above that line 03 is the start of a group of
dependent job.  No job on any other line can start unless the job on line
03 succeeds.  What if you wanted two or more groups of jobs in the same
family that start at the same time (barring any time dependencies) and
proceed independently of each other?

To do this you would separate the groups with a line containing one or
more dashes (only).  Consider the following family:

    +---------------------------------------------------------------------
 01 |start => '02:00', tz => 'America/Chicago', days => 'Mon,Wed,Fri'
 02 |
 03 |               J_ROTATE_LOGS()
 04 |
 05 | J_RESOLVE_DNS(start => '09:00')    Delete_Logs_Older_Than_A_Year()
 06 |
 07 |               J_WEB_REPORTS()      
 08 |
 09 |            J_EMAIL_WEB_RPT_DONE()  # send me a notification
 10 |
 11 |----------------------------------------------------------------------
 12 |
 13 | J_UPDATE_ACCOUNTS_RECEIVABLE()
 14 |
 15 | J_ATTEMPT_CREDIT_CARD_PAYMENTS()
 16 |
 17 |----------------------------------------------------------------------
 18 |
 19 | J_SEND_EXPIRING_CARDS_EMAIL()
 20 |
    +---------------------------------------------------------------------

Because of the lines of dashes on lines 11 and 17, the jobs on lines
03, 13 and 19 will all start at 02:00.  These jobs are independent of
each other.  J_ATTEMPT_CREDIT_CARD_PAYMENT will not run if
J_UPDATE_ACCOUNTS_RECEIVABLE fails.  That failure, however will not
prevent J_SEND_EXPIRING_CARDS_EMAIL from running.

Finally, you can specify a job to run repeatedly every 'n' minutes,
as follows:

    +---------------------------------------------------------------------
 01 |start => '02:00', tz => 'America/Chicago', days => 'Mon,Wed,Fri'
 02 |
 03 | J_CHECK_DISK_USAGE(every=>'30', until=>'23:00')
 04 |
    +---------------------------------------------------------------------

This means that J_CHECK_DISK_USAGE will be called every 30 minutes and
will not run on or after 23:00.  By default, the 'until' time is
23:59.  If the job starts at 02:00 and takes 25 minutes to run to
completion, the next occurance will still start at 02:30, and not at
02:55.  By default, every repeat occurrance will only have one
dependency - the time - and will not depend on earlier occurances
running successfully or even running at all.  If line 03 were:

 03 | J_CHECK_DISK_USAGE(every=>'30', until=>'23:00', chained=>1)

...then each repeat job will be dependent on the previous occurance.

=head1 USAGE

There are a few simple scripts in the bin directory that simplify
usage.  To run the program you must let it know where it can find
the necessary files and directories. This can be done by environment
variables, or via the command line:

  export TF_JOB_DIR=/foo/jobs
  export TF_LOG_DIR=/foo/logs
  export TF_FAMILY_DIR=/foo/families
  export TF_RUN_WRAPPER=/foo/bin/run
  taskforest

  OR

  taskforest -run_wrapper=/foo/bin/run \
    --log_dir=/foo/logs \
    --job_dir=/foo/jobs \
    --family_dir=/foo/families

All jobs will run as the user who invoked taskforest.

You can rerun jobs or mark jobs as Success or Failure using the
'rerun' and 'mark' commands as shown below. 

=head1 OPTIONS

The following command line options are required.  If they are not
specified on the command line, the environment will be searched for
corresponding environment variables.

 --run_wrapper=/a/b/r  [or environment variable TF_RUN_WRAPPER]

   This is the location of the run wrapper that is used to execute the
   job files.  The run wrapper is also responsible for creating the
   semaphore files that denote whether a job ran successfully or not.
   You can use the provided run wrapper (bin/run).  If you need more
   functionality, like logging status to a database, you can create
   your own run wrapper, as long as it preserves the functionality of
   the default run_wrapper.   

 --log_dir=/a/b/l  [or environment variable TF_LOG_DIR]

   This is called the root log directory.  Every day a dated directory
   named in the form YYYYMMDD will be created and the semaphore files
   will be created in that directory.

 --job_dir=/a/b/j  [or environment variable TF_JOB_DIR]

   This is the location of all the job files.  Each job file should be
   an executable file (e.g.: a binary file, a shell script, a perl or
   python script).  The file names are used as job names in the family
   configuration files.  Job names may only contain the characters
   a-z, A-Z, 0-9 and _.  You may create aliases to jobs within this
   directory.

   If a job J1 is present in a family config file, any other
   occurrance of J1 in that family refers TO THAT SAME JOB INSTANCE.
   It does not mean that the job will be run twice.

   If you want the same job running twice, you will have to put it in
   different families, or make soft links to it and have the soft
   link(s) in the family file along with the actual file name.

   If a job is to run repeatedly every x minutes, you could specify
   that using the 'repeat/every' syntax shown above.

 --family_dir=/a/b/f  [or environment variable TF_FAMILY_DIR]

   This is the location of all the family files.  As is the case with
   jobs, family names are the file names.  Family names may only
   contain the characters a-z, A-Z, 0-9 and _.

The following command line options are optional

 --once_only

   If this option is set, the system will check each family once, run
   any jobs in the Ready state and then exit.  This is useful for
   testing, or if you want to invoke the program via cron or some
   similar system, or if you just want the program to run on demand,
   and not run and sleep all day.

 --end_time=HH:MM

   If once_only is not set, this option determines when the main
   program loop should end.  This refers to the local time in 24-hour
   format.  By default it is set to 23:55.  This is the recommended
   maximum.

 --wait_time

   This is the amount of seconds to sleep at the end of every
   loop. The default value is 60.

 --verbose

   Print a lot of debugging information

 --help

   Display help text

 --log

   Log stdout and stderr to files

 --log_threshold=t

   Log messages at level t and above only will be printed to the
   stdout log file.  The default value is "warn".

 --log_file=o

   Messages printed to stdout are saved to file o in the log_directory
   (if --log is set).  The default value is "stdout".

 --err_file=e

   Messages printed to stderr are saved to file e in the log_directory
   (if --log is set).  The default value is "stderr".

 --config_file=f

   Read configuration settings from config file f.

 --chained

   If this is set, all recurring jobs will have the chained attribute
   set to 1 unless specified explicitly in the family file. 

 --collapse

   If this option is set then the status command will behave as if the
   --collapse options was specified on the command line.

=head1 DISPLAY STATUS

To get the status of all currently running and recently run jobs,
enter the following command:

  status

  OR

  status --log_dir=/foo/logs --family_dir=/foo/families

  OR

  status --log_dir=/foo/logs --family_dir=/foo/families --collapse

If the --collapse option is used then pending repeat jobs will not be
displayed.

=head1 RERUN A JOB

To rerun a job, enter the following command:

 rerun --log_dir=l_d --job=Ff::Jj 

where l_d is the log directory and Ff is the family name and Jj is the
job name.

If you run the command like this:

 rerun --log_dir=l_d --job=Ff::Jj --cascade --family_dir=f_d

then all the jobs that are directly or indirectly dependent on job Jj
in family Ff will also be rerun. 

If you run the command like this:

 rerun --log_dir=l_d --job=Ff::Jj --dependents_only --family_dir=f_d

then only those jobs that are directly or indirectly dependent on job Jj
in family Ff will be rerun.  Job Jj will be unaffected. 

=head1 MARK A JOB SUCCESS OR FAILURE

To mark a previously-run job as success or failure, enter the
following command:

 mark --log_dir=l_d --job=Ff::Jj --status=s

where l_d is the log directory and Ff is the family name, Jj is the
job name, and s is 'Success' or 'Failure'.

If you run the command like this:

 mark --log_dir=l_d --job=Ff::Jj --status=s --cascade --family_dir=f_d

then all the jobs that are directly or indirectly dependent on job Jj
in family Ff will also be marked. 

If you run the command like this:

 mark --log_dir=l_d --job=Ff::Jj --status=s --dependents_only --family_dir=f_d

then only those jobs that are directly or indirectly dependent on job Jj
in family Ff will be marked.  Job Jj will be unaffected.

=head1 READING OPTIONS FROM A CONFIG FILE

The 'taskforest' and 'status' commands now accept a "--config_file=f"
option.  You can now specify commonly used options in the config file,
so you do not have to include them on the command line.  The config file
should contain one option per command line.  The following sample
config file shows the list of all supported options, and documents
their usage.

 # ########################################
 # SAMPLE CONFIG FILE
 # ########################################
 # These are the four required command line arguments to taskforest
 log_dir         = "t/logs"
 family_dir      = "/usr/local/taskforest/families"
 job_dir         = "/usr/local/taskforest/jobs"
 run_wrapper     = "/usr/local/bin/run"

 # wait this many seconds between iterations of the main loop
 wait_time       = 60

 # stop taskforest at this time of day
 end_time        = 2355

 # if set to 1, run taskforest once only and exit immediately after that
 once_only       = 0

 # print out extra logs - may be redundant, due to log_threshold, below
 # THIS OPTION WILL BE DEPRECATED SOON.
 verbose         = 0

 # by default assume that the --collapse option was given to the status command
 collapse        = 1  # change from previously default behavior

 # by default assume that all repeating jobs have the --chained=>1 attribute set
 chained         = 1  # change from previously default behavior

 # log stdout and stderr to files
 log             = 1

 # by default, log stdout messages with status >= this vale.
 # This only effects stdout
 # The sequence of thresholds (smallest to largest) is:
 # debug, info, warn, error, fatal
 log_threshold   = "warn"

 # The log_file and err_file names should NOT end with '.0' or '.1' 
 # because then they will be mistaken for job log files
 log_file        = "stdout"  
 err_file        = "stderr"  

 # currently unused
 log_status      = 0

=head1 PRECEDENCE OF DIFFERENT OPTIONS SOURCES

All settings (required and optional) may be specified in a variety of
ways: command line, environment variable and config file.  The order
of preferences is this: Most options have default values.  Settings
specified in the config file override those defaults.  Settings
specified in environment variables take override those specified in
the config file and the default values.  Setting specified on the
command line override those specified in envrionment variables, and
those specified in the config files and the default values.

The names of the environment variable are the same as the names of the
settings on the command line (or in the config file), but they should
be in UPPER CASE, with "TF_" prepended.  For example, the environment
variable name for the 'run_wrapper' setting is 'TF_RUN_WRAPPER'.

=head1 LOGGING STDOUT AND STDERR

If the --log option is set, then anything printed to stdout and stderr
will be saved to log files. Before the logging start, the program will
print onto stdout the names of the log file and error file.  The
program logs incidents at different levels ("debug", "info",
"warning", "error" and "fatal").  The "log_threshold" option sets the
level at which logs are written to the stdout file.  If the value of
log_threshold is "info", then only those log messages with a level of
"info" or above ("warning", "error" or "fatal") will be written to the
stdout log file.  The stderr log file always has logs printed at level
"error" or above, as well as anything printed explicitly to STDERR.

The log file and error file will be saved in the log_directory.  

=head1 BUGS

For an up-to-date bug listing and to submit a bug report, please
visit our website at http://sourceforge.net/projects/taskforest/

=head1 SUPPORT

For support, please visit our website at
http://sourceforge.net/projects/taskforest/

=head1 AUTHOR

Aijaz A. Ansari
http://sourceforge.net/projects/taskforest/

If you're using this program, I would love to hear from you.  Please
visit our project website and let me know what you think of it.

=head1 ACKNOWLEDGEMENTS

Many thanks to the following for their help and support:

 . SourceForge
 . Rosco Rouse

=head1 COPYRIGHT

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself - specifically, the Artistic
License. 

The full text of the license can be found in the
LICENSE file included with this module.

=head1 SEE ALSO

perl(1).

=cut

#################### main pod documentation end ###################


1;
# The preceding line will help the module return a true value

