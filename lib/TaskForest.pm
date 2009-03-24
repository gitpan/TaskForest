################################################################################
#
# $Id: TaskForest.pm 164 2009-03-24 02:04:15Z aijaz $
#
# This is the primary class of this application.  Version infromation
# is taken from this file.
#
################################################################################

package TaskForest;
use strict;
use warnings;
use POSIX (":sys_wait_h", "strftime");
use Data::Dumper;
use TaskForest::Family;
use TaskForest::Options;
use TaskForest::Logs qw /$log/;
use File::Basename;
use Carp;

BEGIN {
    use vars qw($VERSION);
    $VERSION     = '1.23';
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


    my $end_time            = $self->{options}->{end_time};
    $end_time               =~ /(\d\d)(\d\d)/;
    my $end_time_in_seconds = $1 * 3600 + $2 * 60;
    my $wait_time           = $self->{options}->{wait_time};

    my $rerun = 0;
    my $RELOAD = 1;

    $self->{options} = &TaskForest::Options::getOptions($rerun);  $rerun = 1;
    &TaskForest::LogDir::getLogDir($self->{options}->{log_dir}, $RELOAD);
    &TaskForest::Logs::init("New Loop");
   
    while (1) {
        
        # get a fresh list of all family files
        #
        my @families = $self->globFamilyFiles($self->{options}->{family_dir});
        
        
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
        
        my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
        my $now = sprintf("%02d%02d", $hour, $min);
        print "It is $now, the time to end is $end_time\n" if $self->{options}->{verbose};
        my $now_plus_wait = $hour * 3600 + $min * 60 + $wait_time;
        if ( $now_plus_wait >= $end_time_in_seconds) {
            $log->info("In $wait_time seconds it will be past $end_time.  Exiting loop.");
            last;
        }
        $log->info("After $wait_time seconds, $now_plus_wait < $end_time_in_seconds.  Sleeping $wait_time");
        sleep $wait_time;                         # by default: 60s

        &TaskForest::Logs::resetLogs();
        $self->{options} = &TaskForest::Options::getOptions($rerun); 
        &TaskForest::LogDir::getLogDir($self->{options}->{log_dir}, $RELOAD);
        &TaskForest::Logs::init("New Loop");
        
    }
    
}


################################################################################
#
# Name      : globFamilyFiles
# usage     : $tf->globFamilyFiles();
# Purpose   : Find all family files given the rules of what's a valid file name
#             and what file names are to be ignored
# Returns   : An array of file names
# Argument  : The family directory to be searched
# Throws    : 
#
################################################################################
#
sub globFamilyFiles {
    my ($self, $dir) = @_;

    my $glob_string = "$dir/*";
    my @all_files = glob($glob_string);
    my @families = ();

    my @ignore_regexes = ();
    if (ref($self->{options}->{ignore_regex}) eq 'ARRAY') {
        @ignore_regexes = @{$self->{options}->{ignore_regex}};
    }
    elsif ($self->{options}->{ignore_regex}) {
        @ignore_regexes = ($self->{options}->{ignore_regex});
    }
    

    my @regexes = map { qr/$_/ } @ignore_regexes;
    
    foreach my $file (@all_files) {
        my $basename = basename($file);
        if ($basename =~ /[^a-zA-Z0-9_]/) {
            next;
        }
        my $ok = 1;
        foreach my $regex (@regexes) {
            if ($basename =~ /$regex/) {
                $ok = 0;
                last;
            }
        }
        if ($ok) {
            push (@families, $file);
        }
    }

    return @families;
}

################################################################################
#
# Name      : status
# usage     : $tf->status();
# Purpose   : This function determines the status of all jobs that have run
#             today, as well as the the status of jobs that have not
#             yet run (are in the "Waiting" or "Ready" state.  
#             If the --collapse option is given, pending repeat
#             jobs are not displayed.  
# Returns   : A data structure representing all the jobs
# Argument  : data-only - If this is true, then nothing is printed.
# Throws    : 
#
################################################################################
#
sub status {
    my ($self, $data_only) = @_;


    my $log_dir = &TaskForest::LogDir::getLogDir($self->{options}->{log_dir}, 'reload');
    
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time); $mon++; $year += 1900;
    my $log_date = sprintf("%4d%02d%02d", $year, $mon, $mday);
    
    # get a fresh list of all family files
    #
    my @families = $self->globFamilyFiles($self->{options}->{family_dir});

    my $display_hash = { all_jobs => [], Success  => [], Failure  => [], Ready  => [], Waiting  => [],  Running => []};

    foreach my $family_name (sort @families) {
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
        $family->display($display_hash);
    }

    foreach my $job (@{$display_hash->{Ready}}, @{$display_hash->{Waiting}}) {
        $job->{actual_start} = $job->{stop} = "--:--";
        $job->{rc} = '-';
        $job->{has_actual_start} = $job->{has_stop} = $job->{has_rc} = 0;
    }

    foreach my $job (@{$display_hash->{Success}}, @{$display_hash->{Failure}}, @{$display_hash->{Running}}) {
        my $dt = DateTime->from_epoch( epoch => $job->{actual_start} );
        $dt->set_time_zone($job->{tz});
        $job->{actual_start_epoch} = $job->{actual_start};
        $job->{actual_start} = sprintf("%02d:%02d", $dt->hour, $dt->minute);
        $job->{has_actual_start} = 1;
        $job->{has_rc} = 1;

        if (($job->{stop}) && ($job->{status} ne "Running")) {
            $dt = DateTime->from_epoch( epoch => $job->{stop} );
            $dt->set_time_zone($job->{tz});
            $job->{stop} = sprintf("%02d:%02d", $dt->hour, $dt->minute);
            $job->{has_stop} = 1;
            if ($job->{status} eq 'Success') {
                $job->{is_success} = 1;
            }
            else { 
                $job->{is_success} = 0;
            }
        }
        else {
            $job->{stop} = '--:--';
            $job->{rc} = '-';
            $job->{has_stop} = $job->{has_rc} = 0;
        }
    }

    $self->getUnaccountedForJobs($display_hash);

    map { ($_->{base_name}) = $_->{name} =~ /([^\-]+)/; } @{$display_hash->{all_jobs}};

    my @sorted = sort  {
        
                               $a->{family_name} cmp $b->{family_name}                 # family first
                                                  ||
                                 $a->{base_name} cmp $b->{base_name}                    # base name
                                                  ||
                          $b->{has_actual_start} <=> $a->{has_actual_start}            # REady and Waiting after Success or Failed 
                                                  ||

                        # after this point they're either both run or both not run
                                                      
  (($a->{has_actual_start}) ? ($a->{actual_start} cmp $b->{actual_start}) :             # Actual start if possible (if both have started ELSE BOTH HAVE FAILED, THEN:
                                    $a->{start} cmp $b->{start})                      # Waiting after Ready
                                                  ||
                                      $a->{name} cmp $b->{name}                        # Job Name
               

                              
        
    } @{$display_hash->{all_jobs}};

    my $oe = 'odd';
    foreach (@sorted) {
        $_->{oe} = $oe = (($oe eq 'odd') ? 'even' : 'odd');
        $_->{has_output_file} = 0;
        if ($_->{has_actual_start}) {
            $_->{output_file} = "$_->{family_name}.$_->{name}.$_->{pid}.$_->{actual_start_epoch}.stdout";
            if (-e "$log_dir/$_->{output_file}") {
                $_->{has_output_file} = 1;
                $_->{log_date} = $log_date;
            }
        }
        $_->{is_waiting} = ($_->{status} eq 'Waiting') ? 1 : 0;
    }

    
    $display_hash->{all_jobs} = \@sorted;

    return $display_hash if $data_only;

    ## ########################################
    
    my $max_len_name = 0;
    my $max_len_tz = 0;
    foreach my $job (@{$display_hash->{all_jobs}}) {
        my $l = length($job->{full_name} = "$job->{family_name}::$job->{name}");
        if ($l > $max_len_name) { $max_len_name = $l; }
        
        $l = length($job->{tz});
        if ($l > $max_len_tz)   { $max_len_tz   = $l; }

    }

    my $format = "%-${max_len_name}s   %-7s   %6s   %-${max_len_tz}s   %-5s   %-6s  %-5s\n";
    printf($format, '', '', 'Return', 'Time', 'Sched', 'Actual', 'Stop');
    printf($format, 'Job', 'Status', 'Code', 'Zone', 'Start', 'Start', 'Time');
    print "\n";
    
    my $collapse = $self->{options}->{collapse};
   
    foreach my $job (@{$display_hash->{all_jobs}}) {
        if ($collapse and
          $job->{name} =~ /--Repeat/ and
          $job->{status} eq 'Waiting') {
            next;  # don't print every waiting repeat job
        }
        printf($format,
               $job->{full_name},
               $job->{status},
               $job->{rc},
               $job->{tz},
               $job->{start},
               $job->{actual_start},
               $job->{stop});
    }
    
}



################################################################################
#
# Name      : hist_status
# usage     : $tf->status();
# Purpose   : This function determines the status of all jobs that have run
#             for a particular day.  If the --collapse option is given, 
#             pending repeat jobs are not displayed.  
# Returns   : A data structure representing all the jobs
# Argument  : data-only - If this is true, then nothing is printed.
# Throws    : 
#
################################################################################
#
sub hist_status {
    my ($self, $date, $data_only) = @_;
    my $log_dir = $self->{options}->{log_dir}."/$date";

    my $display_hash = { all_jobs => [], Success  => [], Failure  => [], Ready  => [], Waiting  => [],  };
    $self->getUnaccountedForJobs($display_hash, $date);

    map { ($_->{base_name}) = $_->{name} =~ /([^\-]+)/; } @{$display_hash->{all_jobs}};

    my @sorted = sort  {
                               $a->{family_name} cmp $b->{family_name}                 # family first
                                                  ||
                                 $a->{base_name} cmp $b->{base_name}                   # base name
                                                  ||
                              $a->{actual_start} cmp $b->{actual_start}                # start_time 
                                                  ||
                                      $a->{name} cmp $b->{name}                        # Job Name
    } @{$display_hash->{all_jobs}};
    
    my $oe = 'odd';
    foreach (@sorted) {
        $_->{oe} = $oe = (($oe eq 'odd') ? 'even' : 'odd');
        $_->{has_output_file} = 0;
        $_->{output_file} = "$_->{family_name}.$_->{name}.$_->{pid}.$_->{actual_start_epoch}.stdout";
        if (-e "$log_dir/$_->{output_file}") {
            $_->{has_output_file} = 1;
            $_->{log_date} = $date;
        }
        $_->{is_waiting} = ($_->{status} eq 'Waiting') ? 1 : 0;
    }

    $display_hash->{all_jobs} = \@sorted;

    return $display_hash if $data_only;

    my $max_len_name = 0;
    my $max_len_tz = 0;
    foreach my $job (@{$display_hash->{all_jobs}}) {
        my $l = length($job->{full_name} = "$job->{family_name}::$job->{name}");
        if ($l > $max_len_name) { $max_len_name = $l; }
        
        $l = length($job->{tz});
        if ($l > $max_len_tz)   { $max_len_tz   = $l; }

    }

    my $format = "%-${max_len_name}s   %-7s   %6s   %-${max_len_tz}s   %-5s   %-6s  %-5s\n";
    printf($format, '', '', 'Return', 'Time', 'Sched', 'Actual', 'Stop');
    printf($format, 'Job', 'Status', 'Code', 'Zone', 'Start', 'Start', 'Time');
    print "\n";
    
    my $collapse = $self->{options}->{collapse};
   
    foreach my $job (@{$display_hash->{all_jobs}}) {
        if ($collapse and
          $job->{name} =~ /--Repeat/ and
          $job->{status} eq 'Waiting') {
            next;  # don't print every waiting repeat job
        }
        printf($format,
               $job->{full_name},
               $job->{status},
               $job->{rc},
               $job->{tz},
               $job->{start},
               $job->{actual_start},
               $job->{stop});
        
    }
}
    

################################################################################
#
# Name      : getUnaccountedForJobs
# usage     : $tf->getUnaccountedForJobs($display_hash, "YYYYMMDD");
# Purpose   : This function browses a log directory for a particular date
#             and populates the input variable $display_hash with data
#             about each job that ran that day.
# Returns   : None
# Argument  : $display_hash - the hash that will contain the data for
#             all the jobs.
#             $date - the date for which you want job data
# Throws    : "Cannot open file"
#
################################################################################
#
sub getUnaccountedForJobs {
    my ($self, $display_hash, $date) = @_;
    my $log_dir;
    if ($date) {
        $log_dir = $self->{options}->{log_dir}."/$date";
    }
    else {
        $log_dir = &TaskForest::LogDir::getLogDir($self->{options}->{log_dir});  # TODO: should we RELOAD?
    }
    
    my $seen  = {};
    foreach my $job (@{$display_hash->{Success}}, @{$display_hash->{Failure}}) {
        $seen->{"$job->{family_name}.$job->{name}"} = 1;
    }
    
    # readdir
    my $glob_string = "$log_dir/*.[01]";
    my @files = glob($glob_string);

    my $new = [];
    my $file_name;
    my %valid_fields = ( actual_start => 1, pid => 1, stop => 1, rc => 1, );
    foreach my $file (@files) {
        my ($family_name, $job_name, $status) = $file =~ /$log_dir\/([^\.]+)\.([^\.]+)\.([01])/;
        my $full_name = "$family_name.$job_name";
        next if $seen->{$full_name};  # don't update $seen, because we want to show every job that ran.

        my $job = { family_name => $family_name,
                    name => $job_name,
                    full_name => $full_name,
                    start => '--:--',
                    status => ($status) ? 'Failure' : 'Success' };  # just a hash, not an object, since this is only used for display

        # read the pid file
        substr($file, -1, 1) = 'pid';
        open(F, $file) || croak "cannot open $file to read job data";
        while (<F>) { 
            chomp;
            my ($k, $v) = /([^:]+): (.*)/;
            $v =~ s/[^a-z0-9_ ,.\-]/_/ig;
            if ($valid_fields{$k}) {
                $job->{$k} = $v;
            }
        }
        close F;

        my $tz                   = $self->{options}->{default_time_zone};
        $job->{actual_start_epoch} = $job->{actual_start};
        my $dt                   = DateTime->from_epoch( epoch => $job->{actual_start} );
        $dt->set_time_zone($tz);
        $job->{actual_start}     = sprintf("%02d:%02d", $dt->hour, $dt->minute);
        $job->{actual_start_dt}  = sprintf("%d/%02d/%02d %02d:%02d", $dt->year, $dt->month, $dt->day, $dt->hour, $dt->minute); #sprintf("%02d:%02d", $dt->hour, $dt->minute);
        $dt                      = DateTime->from_epoch( epoch => $job->{stop} );
        $dt->set_time_zone($tz);
        $job->{stop}             = sprintf("%02d:%02d", $dt->hour, $dt->minute);
        $job->{stop_dt}          = sprintf("%d/%02d/%02d %02d:%02d", $dt->year, $dt->month, $dt->day, $dt->hour, $dt->minute);  #sprintf("%02d:%02d", $dt->hour, $dt->minute);
        $job->{has_actual_start} = $job->{has_stop} = $job->{has_rc} = 1;
        $job->{tz}               = $tz;

        $job->{is_success} = ($job->{status} eq 'Success') ? 1 : 0;
        

        push (@{$display_hash->{all_jobs}}, $job);
    }
}



#################### main pod documentation begin ###################

=head1 NAME

TaskForest - A simple but expressive job scheduler that allows you to chain jobs/tasks and create time dependencies. Uses text config files to specify task dependencies.

=head1 VERSION

This version is 1.23.

=head1 EXECUTIVE SUMMARY

With the TaskForest Job Scheduler you can:

=over 4

=item * 

schedule jobs run at predetermined times

=item *

have jobs be dependent on each other

=item *

rerun failed jobs

=item *

mark jobs as succeeded or failed

=item *

check the status of all jobs scheduled to run today

=item *

interact with the included web service using your own client code

=item *

interact with the included web server using your default browser

=item *

express the relationships between jobs using a simple text-based format (a big advantage if you like using 'grep')

=back

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

Let's see a few examples.  In these examples the dashes (-), pipes (|)
and line numbers are not parts of the files.  They're only there for
illustration purposes.  The main script expects environment variables
or command line options or configuration file settings that specify
the locations of the directory that contain family files, the
directory that contains job files, and the directory where the logs
will be written.  The directory that contains family files should
contain only family files.

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

=over 4

=item *

Blank lines are ignored.

=item *

A hash (#) and anything after it, until the end of the line is treated
as a comment and ignored

=item *

Job and family names do not have to start with J_ or be in upper case.

=back

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
variables, via the command line, or via the configuration file:

  export TF_JOB_DIR=/foo/jobs
  export TF_LOG_DIR=/foo/logs
  export TF_FAMILY_DIR=/foo/families
  export TF_RUN_WRAPPER=/foo/bin/run
  taskforest

  OR

  taskforest --run_wrapper=/foo/bin/run \
    --log_dir=/foo/logs \
    --job_dir=/foo/jobs \
    --family_dir=/foo/families

  OR

  taskforest --config_file=/foo/config/taskforest.cfg

All jobs will run as the user who invoked taskforest.

You can rerun jobs or mark jobs as Success or Failure using the
'rerun' and 'mark' commands as shown below. 

=head1 OPTIONS

The following command line options are required.  If they are not
specified on the command line, the environment will be searched for
corresponding environment variables or look for them in the
configuration file.

 --run_wrapper=/a/b/r  [or environment variable TF_RUN_WRAPPER]

   This is the location of the run wrapper that is used to execute the
   job files.  The run wrapper is also responsible for creating the
   semaphore files that denote whether a job ran successfully or not.
   The system comes with two run wrappers:
    bin/run
    and
    bin/run_with_log

   The first provides the most basic functionality, while the second
   also captures the stdout and stderr from the invoked job and saves
   it to a file in the log directory.  You may use either run wrapper.
   If you need additional functionality, you can create your own run
   wrapper, as long as it preserves the functionality of the default
   run_wrapper.

   You are encouraged to use run_with_log because of the extra
   functionality available to you.  If you also use the included web
   server to look at the status of today's job, or to browser the logs
   from earlier days, clicking on a the status of a job that's already
   run will bring up the log file associated with that job.  This is
   very convenient if you're trying to investigate a job failure.

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

 --ignore_regex=r

   If this option is set then the family files whose names match the
   perl regular expression r will be ignored.  You can specify this
   option more than once on the command line or in the configuration
   file, but if you use the environment to set this option, you can
   only set it to one value.  Look at the included configuration
   file taskforest.cfg for examples.

 --default_time_zone

   This is the time zone in which jobs that ran on days in the past will
   be displayed.  When looking at previous days' status, the system has no
   way of knowing what time zone the job was originally scheduled for.
   Therefore, the system will choose the time zone denoted by this
   option.  The default value for this option is "America/Chicago".

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

The "status" command also accepts a "--date" option, in which case it
displays all the jobs that ran for that date.  The date must be in the
"YYYYMMDD" format:

  status --log_dir=/foo/logs --family_dir=/foo/families --date 20090201

If the date specified is not the same as the current date, the
"--collapse" option doesn't make any sense, because there can't be any
pending jobs for a date in the past.

When displaying the status for days in the past, there is no way for the
system to know what time zone the jobs were scheduled for.  This is
because the corresponding family file could have changed between the time
that the job ran and the time that you're running the status command.  To
resolve this, the system will always display jobs in the time zone
specified by the 'default_time_zone' option.  If the default time zone is
not specified, its default value is "America/Chicago".

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

=head1 RELEASE ALL DEPENDENCIES FROM A JOB

When you release all dependencies from a job, you put that job in the
'Ready' state.  This causes TaskForest to run the job immediately,
regardless of what other jobs it is waiting on, or what its time
dependencies are.  To release all dependencies from a job, run the
following command:

 release --log_dir=l_d --job=Ff::Jj --family_dir=f_d

where l_d is the log directory and Ff is the family name and Jj is the
job name and f_d is the family_directory.  Dependencies on a job will
only be released if the job is in the 'Waiting' state.

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

 # by default, log stdout messages with status >= this value.
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

 # ignore family files whose names match these regexes
 ignore_regex    = "~$"
 ignore_regex    = ".bak$"
 ignore_regex    = '\$'

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

=head1 THE TASKFORESTD WEB SERVER

The TaskForest package includes a simple, low-footprint web server, called
taskforestd, written in perl.  The webserver uses the LWP library and its
sole purpose is to give you an web-based interface to TaskForest.  I chose
to write a perl-based web server because it is easy for users to download,
install and deploy.  Also, it may be too much to ask users to install and
mantain Apache, and configure mod_perl, just to get this web-based access.

Taskforestd's behavior is controlled with a configuration file,
taskforestd.cfg.  This configuration file B<must> be customized as
described below, before you can use the web server.  Once you have
customized the configuration file, you can start web server like this:

  taskforestd --config_file=taskforestd.cfg

You can stop the web server like this:

  taskforestd --config_file=taskforestd.cfg --stop

For example, if the configuration file specifies that the host on
which taskforestd runs is www.example.com, then the web server will be
available at http://www.example.com/ .

To use the webserver (or even the web service described below) you
must have a valid userid and password.  Taskforestd does not ship with
any default userid and password pairs.  A password is required to
authenticate the person making requests via the web browswer.  This
userid and password combination may be (and should be) different from
the userid and password of the account under which taskforestd is
running.

Which reminds me, as you would expect, taskforestd runs with the
privileges of the account that invoked the program.  If that account
does not have permissions to read and write the job and family files,
you will not be able to use the web server.

It is B<not> a good idea to run taskforestd as root, because even
though taskforestd is written with security in mind, running as root
opens a huge security hole.  And anyway, you shouldn't run as root any
program that you download off the 'net any more than you should give a
stranger the keys to your house.

The best method is to create a separate system user account for
taskforest and taskforestd, and run the web server and command line
requests as that user.

Coming back to the taskforestd userid and password: The userids and
passwords are specified in the configuration file using the same
format as Apache's .htpasswd files.  You can see commented-out
examples of this in the configuration file taskforestd.cfg.  For your
convenience, the TaskForest distribution includes a program called
gen_passwd that generates text that you can copy and paste into the
config file:

 gen_passwd foo bar

The above command will print out somthing that looks like the following;

 foo:4poVZGiAlO1BY

This text can then be copied and pasted into the configuration file.

Please see the included configuration file, C<taskforestd.cfg>, for a
list of each configuration option, and what it means.

B<Please keep in mind that the taskforestd server is not encrypted.  Your
userid and password will be transmitted in cleartext.  This is a huge
security hole.  Do not do this unless both the client and the server
behind a firewall, for example in a local intranet.  If someone sniffs
your unencrypted userid and password, they can change job files, family
files, or delete them too.>

If you wish to use an encrypted, SSL-enabled server, please use the
included taskforestdssl program instead of taskforestd.  The only
difference between the two is that the taskforestd uses HTTP::Daemon,
and taskforestdssl uses HTTP::Daemon::SSL.  To set up SSL, you will
need to set up a server key and a server certificate.  The locations
of these files may be specified in the taskforestd configuration file,
under server_key_file and server_cert_file, respctively.  You can find
more information in the documentation of HTTP::Daemon::SSL.

If you would like to self-sign a certificate, there are some instructions
in the HOWTO section later in this document.

If your system does not support SSL (for example, with openssl), and you
would like to use taskforestd across the Internet, my advice would be:
"Don't."  If you do, you would essentially be giving the world the
ability to run any command on your server.  If you still want to do it,
at least make sure that the system account that taskforestd runs under
does not have write access to any files, especially those in job_dir,
log_dir and family_dir.  This means that you would not be able to change
job or family files or schedule reruns using taskforestd, but neither
would the rest of the world be able to do that on your machine.

=head1 A SAMPLE TASKFORESTD CONFIGURATION FILE

 # This is a sample taskforestd configuration file

 # Please change all settings to values that make sense for you.

 # These are the four required command line arguments to taskforest
 log_dir         = "t/logs"
 family_dir      = "t/families"
 job_dir         = "t/jobs"

 # This is a file that ensures that only one child process can accept 
 # connections at any time
 lock_file       = "t/lock_file"

 # The HTTP server document_root
 document_root   = "htdocs"

 # The host on which the taskforest daemon will run
 host            = "127.0.0.1"

 # The port on which to listen for connections
 port            = 1111

 # The number of children that should be available at any time
 child_count     = 10

 # The number of requests each child process should serve before exiting.
 # (To protect from memory leaks, etc)
 requests_per_child = 40

 # Every time a child dies wait this much time (in seconds) before starting 
 # a new child. Do NOT set this value to less than 1, otherwise you may
 # encounter CPU thrashing.  Set it to something like 10 seconds if you're
 # testing.
 respawn_wait    = 1

 # my default, log stdout messages with status >= this.
 # This only effects stdout
 # The sequence of thresholds (smallest to largest is):
 # debug, info, warn, error, fatal
 log_threshold   = "info"

 # The log_file and err_file names should NOT end with '.0' or '.1' 
 # because then they will be mistaken for job log files
 #log_file        = "taskforestd.%Y%m%d.%H%M%S.stdout"  
 #err_file        = "taskforestd.%Y%m%d.%H%M%S.stderr"  
 log_file        = "taskforestd.stdout"  
 err_file        = "taskforestd.stderr"  
 pid_file        = "taskforestd.pid"

 # Run as a daemon (detach from terminal)
 run_as_daemon   = 1

 # 
 # In order for the web site to work, you must have at least one valid
 # user set up.  As the commented examples below show, you may have
 # more than one.  The value of each valid_user option is the login
 # followed by a colon (:) followed by a crypt hash of the password.
 # There are many ways to generate the crypt hash, including using the
 # crypt perl function.  You can also use the gen_password script
 # included with this release.
 #
 #valid_user = "test:e3MdYgHPUo.QY"
 #valid_user = "foo:jp8Xizm2S52yw"

 # The path to the server private key file
 server_key_file   = "certs/server-key.pem"

 # The path to the server certificate
 server_cert_file  = "certs/server-cert.pem"

=head1 THE TASKFORESTD RESTFUL WEB SERVICE

The TaskForest package includes a low-footprint web server written in
perl.  The webserver hosts one or more RESTful Web Services.  The web
service allows you to write, in any programming language, your own client
software that integrates with TaskForest.

For an introduction to RESTful web services, you can look at
Wikipedia: http://en.wikipedia.org/wiki/Representational_State_Transfer

=head2 A NOTE ABOUT URI NOTATION

For the purposes of this document we will denote variable parts of
URIs using braces.  For example, in the URI
C</foo/bar.html/{variable_name}> the value of the variable
C<variable_name> will replace the string C<{variable_name}>.

=head2 RESTFUL WEB SERVICE VERSION 1.0

All of the service's URIs for version 1.0 are in the /rest/1.0/
hierarchy.  If the service upgrades to a newer version, 1.0 will be
preserved, and the new service will be in, for example, the /rest/2.0/
hierarchy.  This way, backward compatability is preserved while
clients migrate to the new interface.

The documentation that follows describes the common 'header' and
'footer' XHTML.  This is followed by a list of all the URIs and
families of URIs supported by the web service, the HTTP methods that
each URI supports, and a description of the service for the client
software developer.

=head3 HEADERS AND FOOTERS

Every page with an HTTP Status code of 200-207 served by version 1.0
of the web service will start with the html shown below.

    +----------------------------------------------------------------------------------------------------
 01 | <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">
 02 | <html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en">
 03 |  <head>
 04 |   <title>$title</title>
 05 |  </head>
 06 |  <body>
 07 | 
 08 |    <div class="header_navigation">
 09 |      <a href="/rest/1.0/familyList.html">Family List</a>
 10 |      <a href="/rest/1.0/jobList.html">Job List</a>
 11 |      <a href="/rest/1.0/status.html">Status</a>
 12 |    </div>
 13 | 
 14 |    <form id="rerun" class="request" method="POST" action="/rest/1.0/request.html">
 15 |      <label for="rerun_family">Family</label><input id="rerun_family" name="family" /><br />
 16 |      <label for="rerun_job">Job</label><input id="rerun_job" name="job" /><br />
 17 |      <label for="rerun_log_date">Log Date</label><input id="rerun_log_date" name="log_date" /><br />
 18 |      <label for="rerun_options">Options</label><select id="rerun_options" name="options">
 19 |        <option value="">None</option>
 20 |        <option value="cascade">Cascade</option>
 21 |        <option value="dependents_only">Dependents Only</option>
 22 |      </select>
 23 |      <input type=submit name=submit  value="Rerun"/>
 24 |    </form>
 25 | 
 26 |    <form id="mark" class="request" method="POST" action="/rest/1.0/request.html">
 27 |      <label for="mark_family">Family</label><input id="mark_family" name="family" /><br />
 28 |      <label for="mark_job">Job</label><input id="mark_job" name="job" /><br />
 29 |      <label for="mark_log_date">Log Date</label><input id="mark_log_date" name="log_date" /><br />
 30 |      <label for="mark_options">Options</label><select id="mark_options" name="options">
 31 |        <option value="">None</option>
 32 |        <option value="cascade">Cascade</option>
 33 |        <option value="dependents_only">Dependents Only</option>
 34 |      </select>
 35 |      <label for="mark_status">Status</label><select id="mark_status" name="status">
 36 |        <option value="Success">Success</option>
 37 |        <option value="Failure">Failure</option>
 38 |      </select>
 39 |      <input type=submit name=submit  value="Mark"/>
 40 |    </form>
 41 | 
 42 |    <form id="logs" class="request" method="GET" action="/rest/1.0/logs.html">
 43 |      <label for="logs_date">Date</label><input id="logs_date" name="date" size=8 maxlength=8/><br />
 44 |      <input type=submit name=submit  value="View Logs"/>
 45 |    </form>
    +----------------------------------------------------------------------------------------------------

Lines 01-02 describe the file as an XHTML file.  I chose XHTML because
the output can be viewed by any web browser.  If you would like
another format, drop me an email.

Line 04 will display the value of the title for that page.  The C<$>
sign is an artifact of the web development framework I'm using.

Lines 08-12 are the main navigation hyperlinks.

Lines 14-24 and 26-40 are the two forms that show up on every page.
These forms allow you to rerun jobs, and mark jobs, respectively.
They're essentially interfaces to the 'rerun' and 'mark' commands.
The log_date form variable is a date formatted like YYYYMMDD and is
used to determine which day's job should be rerun.  If left blank, the
system uses today's date.

Every page with an HTTP Status code of 200-207 served by version 1.0
of the web service will end with the html shown below.

  </body>
 </html>

=head3 /rest/1.0/familyList.html

 HEAD
 ====
       This URI does not support this method.

 GET
 ===
       DESCRIPTION
       ...........
       Use this URI to retrieve a list of all Families.  These are all the
       files in the directory specified by the family_dir option in the
       taskforestd configuration file.

       REPRESENTATION SENT BY CLIENT TO SERVER
       .......................................
       The client should not send any content to this URI.

       REPRESENTATION SENT BY SERVER TO CLIENT
       .......................................
       In a typical case, the server will send the header and footer, and
       the 'real' content in between.  The content will look like this:

       01 | <ul class=family_list>
       02 |     <li class=family_name><a href="/rest/1.0/families.html/$file_name">$file_name</a></li>
       03 | </ul>

       Line 02 will appear 0 or more times, depending on how many Families
       are present. 

       HTTP STATUS CODES
       .................
       200 - Everything's OK
       304 - The resource has not been modified since the time
             specified in the request If-Modified-Since header,
             OR 
             The calculated Etag of the resource is the same as that
             specified in the request If-None-Match header.
       404 - The resource was not found

       HTTP RESPONSE HEADERS
       .....................
       o Date
       o Last-Modified
       o ETag
       o Content-Length
       o Content-Type

 PUT
 ===
       This URI does not support this method.

 POST
 ====
       This URI does not support this method.

 DELETE
 ======
       This URI does not support this method. 

=head3 /rest/1.0/families.html/{family_name}

 HEAD
 ====
       DESCRIPTION
       ...........
       Send this URI the HEAD method to see if the family specified within
       the URI has changed recently.

       REPRESENTATION SENT BY CLIENT TO SERVER
       .......................................
       The family name is represented by {family_name} and is part
       of the URI.

       REPRESENTATION SENT BY SERVER TO CLIENT
       .......................................
       The HTTP content is empty.

       HTTP STATUS CODES
       .................
       200 - Everything's OK
       304 - The resource has not been modified since the time
             specified in the request If-Modified-Since header,
             OR 
             The calculated Etag of the resource is the same as that
             specified in the request If-None-Match header.
       404 - The resource was not found

       HTTP RESPONSE HEADERS
       .....................
       o Date
       o Last-Modified
       o ETag
       o Content-Length
       o Content-Type

 GET
 ===
       DESCRIPTION
       ...........
       Send this URI the GET method to retrieve the contents of the family
       file whose name is specified within the URI. 

       REPRESENTATION SENT BY CLIENT TO SERVER
       .......................................
       The family name is represented by {family_name} and is part
       of the URI.

       REPRESENTATION SENT BY SERVER TO CLIENT
       .......................................
       In a typical case, the server will send the header and footer, and
       the 'real' content in between.  The content will look like this:

       01 | <div class="family_title">Viewing family $file_name</div>
       02 | <div id="family_contents_div" class="file_contents"><pre>$file_contents</pre></div>
       03 | <form name="family_form" action="/rest/1.0/families.html/$file_name" method="POST">
       04 |   <input type=hidden name="_method" value="PUT">
       05 |   <textarea name="file_contents" rows=20 cols=100>$file_contents</textarea>
       06 |   <br>
       07 |   <input type=submit value="Update Family" name=update />
       08 | </form>

       Line 01 displays the family name.  Line 02 displays the
       contents of the family file in its own div.  Line 03-08 are a
       form that can be used to update the family file.  Note here
       that the method is POST, but there is a form variable called
       "_method" whose value is "PUT".  This is a common idiom in
       RESTful service development because most web browsers only
       support GET and POST.  This is called overloaded POST.  

       With the taskforestd web service, whenever you need to use the
       HEAD, PUT or DELETE methods, you can use POST and define the
       'real' method with the _method form variable.  

       HTTP STATUS CODES
       .................
       200 - Everything's OK
       304 - The resource has not been modified since the time
             specified in the request If-Modified-Since header,
             OR 
             The calculated Etag of the resource is the same as that
             specified in the request If-None-Match header.
       404 - The resource was not found

       HTTP RESPONSE HEADERS
       .....................
       o Date
       o Last-Modified
       o ETag
       o Content-Length
       o Content-Type

 PUT
 ===
       DESCRIPTION
       ...........
       Send this URI the PUT method to create a new family file or to
       change the contents of an existing family file.   

       REPRESENTATION SENT BY CLIENT TO SERVER
       .......................................
       If your client is really using the PUT method, the contents of
       the family file should be sent in the contents of the HTTP
       request.

       If, however, your client is using overloaded POST, then the
       content that you would have sent with the PUT must be in the
       file_contents form variable.  Overloaded POST is explained in
       the description of the GET method, above.

       REPRESENTATION SENT BY SERVER TO CLIENT
       .......................................
       In the typical case, after creating the new family file, or
       changing the contents of the existing family file, the server will
       return the  same contents as in the case of the GET method.  

       HTTP STATUS CODES
       .................
       200 - OK
       400 - The file_contents form variable was missing, in the case of
             Overloaded POST
       500 - The file could not be written - likely a permission issue  

       HTTP RESPONSE HEADERS
       .....................
       o Date
       o Last-Modified
       o ETag
       o Content-Length
       o Content-Type

 POST
 ====
       This URI does not support this method. 

 DELETE
 ======
       DESCRIPTION
       ...........
       Send this URI the DELETE method to delete the family file named in
       the URI. 

       REPRESENTATION SENT BY CLIENT TO SERVER
       .......................................
       The family name is represented by {family_name} and is part
       of the URI.

       REPRESENTATION SENT BY SERVER TO CLIENT
       .......................................
       In the case of DELETE, the server will never return any content.  

       HTTP STATUS CODES
       .................
       204 - Delete was successful and the client should not expect any
             content
       500 - The file could not be deleted - likely a permission issue 

       HTTP RESPONSE HEADERS
       .....................
       o Date
       o Content-Length
       o Content-Type

=head3 /rest/1.0/jobList.html

 HEAD
 ====
       This URI does not support this method.

 GET
 ===
       DESCRIPTION
       ...........
       Use this URI to retrieve a list of all Jobs.  These are all the
       files in the directory specified by the job_dir option in the
       taskforestd configuration file.

       REPRESENTATION SENT BY CLIENT TO SERVER
       .......................................
       The client should not send any content to this URI.

       REPRESENTATION SENT BY SERVER TO CLIENT
       .......................................
       In a typical case, the server will send the header and footer, and
       the 'real' content in between.  The content will look like this:

       01 | <ul class=job_list>
       02 |     <li class=job_name><a href="/rest/1.0/jobs.html/$file_name">$file_name</a></li>
       03 | </ul>

       Line 02 will appear 0 or more times, depending on how many Jobs
       are present. 

       HTTP STATUS CODES
       .................
       200 - Everything's OK
       304 - The resource has not been modified since the time
             specified in the request If-Modified-Since header,
             OR 
             The calculated Etag of the resource is the same as that
             specified in the request If-None-Match header.
       404 - The resource was not found

       HTTP RESPONSE HEADERS
       .....................
       o Date
       o Last-Modified
       o ETag
       o Content-Length
       o Content-Type

 PUT
 ===
       This URI does not support this method.

 POST
 ====
       This URI does not support this method.

 DELETE
 ======
       This URI does not support this method. 

=head3 /rest/1.0/jobs.html/{job_name}

 HEAD
 ====
       DESCRIPTION
       ...........
       Send this URI the HEAD method to see if the job specified within
       the URI has changed recently.

       REPRESENTATION SENT BY CLIENT TO SERVER
       .......................................
       The job name is represented by {job_name} and is part
       of the URI.

       REPRESENTATION SENT BY SERVER TO CLIENT
       .......................................
       The HTTP content is empty.

       HTTP STATUS CODES
       .................
       200 - Everything's OK
       304 - The resource has not been modified since the time
             specified in the request If-Modified-Since header,
             OR 
             The calculated Etag of the resource is the same as that
             specified in the request If-None-Match header.
       404 - The resource was not found

       HTTP RESPONSE HEADERS
       .....................
       o Date
       o Last-Modified
       o ETag
       o Content-Length
       o Content-Type

 GET
 ===
       DESCRIPTION
       ...........
       Send this URI the GET method to retrieve the contents of the job
       file whose name is specified within the URI. 

       REPRESENTATION SENT BY CLIENT TO SERVER
       .......................................
       The job name is represented by {job_name} and is part
       of the URI.

       REPRESENTATION SENT BY SERVER TO CLIENT
       .......................................
       In a typical case, the server will send the header and footer, and
       the 'real' content in between.  The content will look like this:

       01 | <div class="job_title">Viewing job $file_name</div>
       02 | <div id="job_contents_div" class="file_contents"><pre>$file_contents</pre></div>
       03 | <form name="job_form" action="/rest/1.0/jobs.html/$file_name" method="POST">
       04 |   <input type=hidden name="_method" value="PUT">
       05 |   <textarea name="file_contents" rows=20 cols=100>$file_contents</textarea>
       06 |   <br>
       07 |   <input type=submit value="Update Job" name=update />
       08 | </form>

       Line 01 displays the job name.  Line 02 displays the contents of
       the job file in its own div.  Line 03-08 are a form that can be
       used to update the job file.  Note here that the method is POST,
       but there is a form variable called "_method" whose value is "PUT".
       This is a common idiom in RESTful service development because most
       web browsers only support GET and POST.  This is called overloaded
       POST.

       With the taskforestd web service, whenever you need to use the
       HEAD, PUT or DELETE methods, you can use POST and define the 'real'
       method with the _method form variable.

       HTTP STATUS CODES
       .................
       200 - Everything's OK
       304 - The resource has not been modified since the time
             specified in the request If-Modified-Since header,
             OR 
             The calculated Etag of the resource is the same as that
             specified in the request If-None-Match header.
       404 - The resource was not found

       HTTP RESPONSE HEADERS
       .....................
       o Date
       o Last-Modified
       o ETag
       o Content-Length
       o Content-Type

 PUT
 ===
       DESCRIPTION
       ...........
       Send this URI the PUT method to create a new job file or to
       change the contents of an existing job file.   

       REPRESENTATION SENT BY CLIENT TO SERVER
       .......................................
       If your client is really using the PUT method, the contents of the
       job file should be sent in the contents of the HTTP request.

       If, however, your client is using overloaded POST, then the content
       that you would have sent with the PUT must be in the file_contents
       form variable.  Overloaded POST is explained in the description of
       the GET method, above.

       REPRESENTATION SENT BY SERVER TO CLIENT
       .......................................
       In the typical case, after creating the new job file, or changing
       the contents of the existing job file, the server will return the
       same contents as in the case of the GET method.

       HTTP STATUS CODES
       .................
       200 - OK
       400 - The file_contents form variable was missing, in the case of
             Overloaded POST
       500 - The file could not be written - likely a permission issue  

       HTTP RESPONSE HEADERS
       .....................
       o Date
       o Last-Modified
       o ETag
       o Content-Length
       o Content-Type

 POST
 ====
       This URI does not support this method. 

 DELETE
 ======
       DESCRIPTION
       ...........
       Send this URI the DELETE method to delete the job file named in the
       URI.  

       REPRESENTATION SENT BY CLIENT TO SERVER
       .......................................
       The job name is represented by {job_name} and is part of the URI. 

       REPRESENTATION SENT BY SERVER TO CLIENT
       .......................................
       In the case of DELETE, the server will never return any content.  

       HTTP STATUS CODES
       .................
       204 - Delete was successful and the client should not expect any
             content
       500 - The file could not be deleted - likely a permission issue 

       HTTP RESPONSE HEADERS
       .....................
       o Date
       o Content-Length
       o Content-Type

=head3 /rest/1.0/status.html

 HEAD
 ====
       This URI does not support this method.

 GET
 ===
       DESCRIPTION
       ...........
       Send this URI the GET method to get the status of today's jobs.  

       REPRESENTATION SENT BY CLIENT TO SERVER
       .......................................
       None - no additional information is needed. 

       REPRESENTATION SENT BY SERVER TO CLIENT
       .......................................
       In a typical case, the server will send the header and footer, and
       the 'real' content in between.  The content will look like this:

       01 | <div class=status>
       02 |     <dl class=job>
       03 |       <dt>Family Name</dt>
       04 |       <dd><a href="/rest/1.0/families.html/$family_name">$family_name</a></dd>
       05 |       <dt>Job Name</dt>
       06 |       <dd><a href="/rest/1.0/jobs.html/$base_name">$name</a></dd>
       07 |       <dt>Status</dt>
       08 |       <dd>$status</dd>
       09 |       <dt>Return Code</dt>
       10 |       <dd>$rc</dd>
       11 |       <dt>Time Zone</dt>
       12 |       <dd>$tz</dd>
       13 |       <dt>Scheduled Start Time</dt>
       14 |       <dd>$start</dd>
       15 |       <dt>Actual Start Time</dt>
       16 |       <dd>$actual_start</dd>
       17 |       <dt>Stop Time</dt>
       18 |       <dd>$stop</dd>
       19 |     </dl>
       20 | </div>

       Lines 02-19 will appear 0 or more times, once for every job that
       appears in the output of the status command.  The --collapse option
       is implied in the web service; pending repeat jobs are not
       displayed.

       If the job has an associated log file (in other words: if the
       wrapper script that ran it was run_with_log, and the status is
       either Running, Success or Failure) then line 08 will look like
       this:

       08 |       <dd><a href="/logFile.html/$output_file">$status</a></dd>

       HTTP STATUS CODES
       .................
       200 - OK

       HTTP RESPONSE HEADERS
       .....................
       o Date
       o Content-Length
       o Content-Type

 PUT
 ===
       This URI does not support this method.

 POST
 ====
       This URI does not support this method.

 DELETE
 ======
       This URI does not support this method.

=head3 /rest/1.0/logs.html?date={date}

 HEAD
 ====
       This URI does not support this method.

 GET
 ===
       DESCRIPTION
       ...........
       Send this URI the GET method to browse the log directory for a
       particular date - to see which jobs ran on that day, and when, and
       what the exit codes were.

       REPRESENTATION SENT BY CLIENT TO SERVER
       .......................................
       The date is specified as a query parameter.  The date must be in
       the YYYYMMDD format.  If the date is omitted, then the date will
       default to the current date, and jobs with a status of 'Ready' or
       'Waiting' will also be displayed.           

       REPRESENTATION SENT BY SERVER TO CLIENT
       .......................................
       In a typical case, the server will send the header and footer, and
       the 'real' content in between.  The content will look like this:

       01 | <div class=status>
       02 |     <dl class=job>
       03 |       <dt>Family Name</dt>
       04 |       <dd><a href="/rest/1.0/families.html/$family_name">$family_name</a></dd>
       05 |       <dt>Job Name</dt>
       06 |       <dd><a href="/rest/1.0/jobs.html/$base_name">$name</a></dd>
       07 |       <dt>Status</dt>
       08 |       <dd>$status</dd>
       09 |       <dt>Return Code</dt>
       10 |       <dd>$rc</dd>
       11 |       <dt>Time Zone</dt>
       12 |       <dd>$tz</dd>
       13 |       <dt>Actual Start Time</dt>    
       14 |       <dd>$actual_start_dt</dd>     
       15 |       <dt>Stop Time</dt>            
       16 |       <dd>$stop_dt</dd>             
       17 |     </dl>              
       18 | </div>                  

       Lines 02-17 will appear 0 or more times, once for every job that
       appears in the output of the status command.  

       If the job has an associated log file (in other words: if the
       wrapper script that ran it was run_with_log, and the status is
       either Running, Success or Failure) then line 08 will look like
       this:

       08 |       <dd><a href="/logFile.html/$output_file">$status</a></dd>

       HTTP STATUS CODES
       .................
       200 - OK

       HTTP RESPONSE HEADERS
       .....................
       o Date
       o Content-Length
       o Content-Type

 PUT
 ===
       This URI does not support this method.

 POST
 ====
       This URI does not support this method.

 DELETE
 ======
       This URI does not support this method.

=head3 /rest/1.0/logFile.html/{file}

 HEAD
 ====
       DESCRIPTION
       ...........
       Send this URI the HEAD method to see if the log file specified
       within the URI has changed recently.

       REPRESENTATION SENT BY CLIENT TO SERVER
       .......................................
       The name of the log file is represented by {file} and is part
       of the URI. 

       REPRESENTATION SENT BY SERVER TO CLIENT
       .......................................
       The HTTP content is empty.

       HTTP STATUS CODES
       .................
       200 - Everything's OK
       304 - The resource has not been modified since the time
             specified in the request If-Modified-Since header,
             OR 
             The calculated Etag of the resource is the same as that
             specified in the request If-None-Match header.
       404 - The resource was not found

       HTTP RESPONSE HEADERS
       .....................
       o Date
       o Last-Modified
       o ETag
       o Content-Length
       o Content-Type

 GET
 ===
       DESCRIPTION
       ...........
       Send this URI the HEAD method to browse the log file specified
       within the URI. 

       Send this URI the GET method to browse the log directory for a
       particular date - to see which jobs ran on that day, and when, and
       what the exit codes were.

       REPRESENTATION SENT BY CLIENT TO SERVER
       .......................................
       The name of the log file is represented by {file} and is part
       of the URI. 

       REPRESENTATION SENT BY SERVER TO CLIENT
       .......................................
       In a typical case, the server will send the header and footer,
       and the 'real' content in between.  The content will look like
       this: 

       01 | <div class="title">Viewing log file $file_name</div>
       02 |
       03 | <div id="file_contents_div" class="file_contents"><pre>$file_contents</pre></div>

       HTTP STATUS CODES
       .................
       200 - Everything's OK
       304 - The resource has not been modified since the time
             specified in the request If-Modified-Since header,
             OR 
             The calculated Etag of the resource is the same as that
             specified in the request If-None-Match header.
       404 - The resource was not found

       HTTP RESPONSE HEADERS
       .....................
       o Date
       o Last-Modified
       o ETag
       o Content-Length
       o Content-Type

 PUT
 ===
       This URI does not support this method.

 POST
 ====
       This URI does not support this method.

 DELETE
 ======
       This URI does not support this method.

=head3 /rest/1.0/request.html

 HEAD
 ====
       This URI does not support this method.

 GET
 ===
       This URI does not support this method.

 PUT
 ===
       This URI does not support this method.

 POST
 ====
       DESCRIPTION
       ...........
       Send a POST to this URI to request a job be marked as success or
       failure, or be rerun.  

       REPRESENTATION SENT BY CLIENT TO SERVER
       .......................................
       There are three required form variables: "family", "job", and
       "submit".  The first is the name of the family, and the second is
       the name of the job.  If the value of the "submit" variable is
       "Rerun", then that job is rerun.  If the value is "Mark", then the
       job will be marked based on the value of the form variable
       "status", which can take a value of "Success" or "Failure".

       In either case, mark or rerun, the optional variable "options" is
       also permitted.  If it has a value, its value can be either
       "cascade" or "dependents_only".  These are treated the same way as
       the command line options to the 'rerun' and 'mark' commands. 

       REPRESENTATION SENT BY SERVER TO CLIENT
       .......................................
       In every case, the server will send the header and footer, and
       the 'real' content in between.  The content will look like this:

       01 | Request accepted.

       HTTP STATUS CODES
       .................
       200 - OK
       500 - The request could not be honored. 

       HTTP RESPONSE HEADERS
       .....................
       o Date
       o Content-Length
       o Content-Type

 DELETE
 ======
       This URI does not support this method.

=head1 HOWTO

=head2 Run taskforest all day with cron

This is the line I have in my crontab:

 02 00 * * * /usr/local/bin/taskforest --config_file=/foo/bar/taskforest.cfg

=head2 Allow a user to view the web site

Please make sure you read the section entitled "The Taskforestd Web
Server" for important security considerations.

Having said that, : The userids and passwords are specified in the
configuration file using the same format as Apache's .htpasswd files.
You can see commented-out examples of this in the configuration file
taskforestd.cfg.  For your convenience, the TaskForest distribution
includes a program called gen_passwd that generates text that you can
copy and paste into the config file:

 gen_passwd foo bar

The above command will print out somthing that looks like the following;

 foo:4poVZGiAlO1BY

This text can then be copied and pasted into the configuration file.

Make sure you stop the server and restart it after making any changes
to the configuration file.

=head2 Start the web server

To start the web server, run the taskforestd program with the
--config_file and --start options.  For example:

 taskforestd --config_file=taskforestd.cfg  --start

Or, in the case of the ssl version of the server:

 taskforestdssl --config_file=taskforestd.cfg  --start

=head2 Stop the web server

To stop the web server, run the taskforestd program with the
--config_file and --stop options.  For example:

 taskforestd --config_file=taskforestd.cfg  --stop

Or, in the case of the ssl version of the server:

 taskforestdssl --config_file=taskforestd.cfg  --stop

=head2 Create a self-signed certificate with openssl.

This is what works for me (instructions found at
http://www.modssl.org/docs/2.8/ssl_faq.html#ToC25 ).

 1) Create a server key

   openssl genrsa -des3 -out server.key.en 1024

 2) Make a decrypted version of it

   openssl rsa -in server.key.en -out server-key.pem

 3) Create a CSR (Certificate Signing Request)

   openssl req -new -key server-key.pem -out server.csr

 4) Create a CA Private Key

   openssl genrsa -des3 -out ca.key.en 1024

 5) Create a decrypted version of it

   openssl rsa -in ca.key.en -out ca.key

 6) Create a 10-yr self-signed CA cert with the CA key

   openssl req -new -x509 -days 3650 -key ca.key -out my-ca.pem

 7) Sign the CSR

    sign.sh server.csr

    The sign.sh program can be found in the pkg.contrib/ subdirectory
    of the mod_ssl distribution.  It is not clear whether or not I can
    include that script in this distribution, so for now at least,
    you'll have to use your own copy.  Make sure you specify the
    locations of the files in the taskforestd configuration file.

=head2 Force a Job to run NOW

Let's say you have a job J4 that depends on 3 other jobs - J1, J2 and
J3.  Normally, that setup is fine, but today you really want the job
to run now.  You don't care whether J1, J2 and J3 run successfully or
not, as far as J4 is concerned.  What you need to do is release all
the dependencies off J4.  You also don't want to make a permanent
change to the family file.

This means that regardless of what job dependencies or time
dependencies J4 has, when you release all its dependencies, it will
run the very next time TaskForest checks to see if there are any jobs
that need to be run (determined by wait_time).  It's as if those
dependencies never existed.

A release 'request' is only valid once - once J4 runs, the system has
no 'memory' of the fact that J4's dependencies were released.  It will
not change the behavior of the rest of the family.  If J5 depends on
J4, then J5 will be ready to run, even if J1, J2 and J3 haven't run
yet. To release all dependencies from a job, run the following
command:

 release --log_dir=l_d --job=Ff::Jj --family_dir=f_d

where C<l_d> is the log directory and C<Ff> is the
family name and C<Jj> is the job name and C<f_d>
is the family_directory.  Dependencies on a job will only be released
if the job is in the 'Waiting' state.

You can also use the "Release" button on the 'Status' or 'View Logs'
page on the web site to release all dependencies off a job.

Remember: no changes are made to the Family file.  So next time this
family runs, J4 will still depend on J1, J2 and J3, just like it
always did.

=head1 BUGS

For an up-to-date bug listing and to submit a bug report, please
send an email to the TaskForest Discussion Mailing List at
"taskforest-discuss at lists dot sourceforge dot net"

=head1 SUPPORT

For support, please visit our website at http://www.taskforest.com/ or
send an email to the TaskForest Discussion Mailing List at
"taskforest-discuss at lists dot sourceforge dot net"

=head1 AUTHOR

Aijaz A. Ansari
http://www.taskforest.com/

If you're using this program, I would love to hear from you.  Please
send an email to the TaskForest Discussion Mailing List at
"taskforest-discuss at lists dot sourceforge dot net" and let me know
what you think of it.

=head1 ACKNOWLEDGEMENTS

Many thanks to the following for their help and support:

=over 4

=item *

SourceForge

=item *

Rosco Rouse

=back

I would also like to thank Randal L. Schwartz for teaching the readers of
the Feb 1999 issue of Web Techniques how to write a pre-forking web
server, the code upon which the TaskForest Web server is built.

I would also like to thank the fine developers at Yahoo! for providing
yui to the open source community.

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

