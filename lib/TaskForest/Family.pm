################################################################################
#
# File:    Family
# Date:    $Date: 2008-03-27 18:23:10 -0500 (Thu, 27 Mar 2008) $
# Version: $Revision: 86 $
#
# A family is a group of jobs that share the following
# characteristics: 
# - They all start on or after a common time known as the family start
#   time
# - They run only on the days specified in the family file
# - They can be dependent on each other.  These dependencies are
#   represented by the location of jobs with respenct to each other in
#   the family file.
#
################################################################################
package TaskForest::Family;

use strict;
use warnings;
use TaskForest::Job qw ();
use Data::Dumper;
use TaskForest::TimeDependency;
use TaskForest::Options;
use TaskForest::LogDir;
use English '-no_match_vars';


################################################################################
#
# Name      : The constructor
# Usage     : my $family = TaskForest::Family->new();
# Purpose   : The Family constructor is passed the family name.  It
#             uses this name along with the location of the family
#             directory to find the family configuration file and
#             reads the file.  The family object is configured with
#             the data read in from the file.
# Returns   : Self
# Argument  : A hash that has the properties of he family.  Of these,
#             the only required one is the 'name' property.
# Throws    : "No family name specified" if the name property is
#              blank.  
#
################################################################################
#
sub new {
    my $arg = shift;
    my $class = (ref $arg) || $arg;

    my $self = {
        name   => '',
        start  => '',
        tz     => 'America/Chicago',        # default America/Chicago
        days   => {},
    };

    my %args = @_;
    
    foreach my $key (keys %args) {
        $self->{$key} = $args{$key};
    }

    die "No family name specified" unless $self->{name};
    bless $self, $class;

    $self->{options} = &TaskForest::Options::getOptions();
    
    $self->readFromFile();

    return $self;
}


################################################################################
#
# Name      : display
# Usage     : $family->display()
# Purpose   : This method displays the status of all jobs in all
#             families that are scheduled to run today. 
# Returns   : Nothing
# Argument  : None
# Throws    : Nothing
#
################################################################################
#
sub display {
    my $self = shift;

    foreach my $job_name (sort (keys (%{$self->{jobs}}))) {
        my $job = $self->{jobs}->{$job_name};
        printf("%-40s  %1s   %s\n", "$self->{name}".'::'."$job->{name}",  $job->{rc}, $job->{status});
    }
}
    

################################################################################
#
# Name      : getCurrent
# Usage     : $family->getCurrent()
# Purpose   : This method reads all the semaphore files in the log
#             directory and gets the current status of the entire
#             family.  Each run job can have succeeded or failed.  As
#             a result of this, other jobs may be Ready to be run.  If
#             a job's dependencies have not yet been met, it is said
#             to be in the Waiting state.  Once a family is current,
#             the only thing that makes it 'uncurrent' is if any jobs
#             are run, or if its configuration file changes.
# Returns   : Nothing
# Argument  : None
# Throws    : Nothing
#
################################################################################
#
sub getCurrent {
    my $self = shift;

    if ($self->{current}) {
        # nothing to do, really
        return;
    }

    # Get the status of all jobs, depending on the presence of job
    # semaphore files
    # 
    $self->updateJobStatuses();

    # Check to see if any of the time dependencies in this family have
    # been met.  A time dependency has been met if 'now' >= the time
    # dependency.
    #
    $self->checkAllTimeDependencies();

    # Get a list of all jobs whose status is 'Waiting'
    #
    my $waiting_jobs = $self->getAllWaitingJobs();
    print "waiting: ", Dumper($waiting_jobs) if $self->{options}->{verbose};

    # Construct a list of all ready jobs - these are jobs for which
    # all dependencies have been met
    #
    $self->{ready_jobs} = {};
    foreach my $job (values %$waiting_jobs) {
        # dependencies for each job
        #
        my $dependencies = $self->{dependencies}->{$job->{name}};
        my $ready = 1;

        foreach my $dep (@$dependencies) {
            if ($dep->check() == 0) {
                $ready = 0;
                last;
            }
        }

        if ($ready) {
            # set the status of the job to be ready
            $self->{ready_jobs}->{$job->{name}} = $job;
            $job->{status} = 'Ready';
        }
    }

    $self->{current} = 1;
    print "ready: ", Dumper($self->{ready_jobs}) if $self->{options}->{verbose};
}


################################################################################
#
# Name      : cycle
# Usage     : $family->cycle()
# Purpose   : This is the main method that is invoked once in every
#             loop, to run any jobs that are in a Ready state.  It
#             gets the current status of the family, displays the
#             status of all the family, and then runs any jobs that
#             are in the Ready state.
# Returns   : Nothing
# Argument  : None
# Throws    : Nothing
#
################################################################################
#
sub cycle {
    my $self = shift;

    $self->getCurrent();
    $self->display();
    $self->runReadyJobs();
}



################################################################################
#
# Name      : updateJobStatuses
# Usage     : $family->updateJobStatuses()
# Purpose   : This method looks at all the semaphore files in the
#             current day's log directory and updates job statuses
#             based on those semaphore files. 
# Returns   : Nothing
# Argument  : None
# Throws    : Nothing
#
################################################################################
#
sub updateJobStatuses {
    my $self = shift;

    my $log_dir = &TaskForest::LogDir::getLogDir($self->{options}->{log_dir});

    # keep in mind that semaphore files are in the form F.J.[01] where
    # F is the family name, J is a job name and 0 means success, and 1
    # failure
    #
    my $glob_string = "$log_dir/$self->{name}.*.[01]";

    my @files = glob($glob_string);

    foreach my $file (sort @files) { # the sort ensures that 1 overrides 0
        my ($job_name, $status) = $file =~ /$log_dir\/$self->{name}\.([^\.]+)\.([01])/;

        # when a job is rerun the .[01] file is moved to .r[01] file
        if ($status == 1) {
            $self->{jobs}->{$job_name}->{status} = 'Failure';
        }
        else {
            $self->{jobs}->{$job_name}->{status} = 'Success';
        }

        # read the return code
        #
        open(F, $file) || die "cannot open $file to read rc";
        $_ = <F>;
        chomp;
        $self->{jobs}->{$job_name}->{rc} = $_;
        close F;
    }
}
        
        

################################################################################
#
# Name      : runReadyJobs
# Usage     : $family->runReadyJobs()
# Purpose   : This method uses the fork and exec model to run all jobs
#             currently in the Ready state.  The script that is
#             actually exec'ed is the run wrapper.  The wrapper takes
#             a whole bunch of arguments, some of which can be derived
#             by others.  The intent is to make it flexible and make
#             it easy for others to write custom wrappers.  The code
#             that's executed in the child process before the exec is
#             rather paranoid and is taken from perldoc perlsec.
# Returns   : Nothing
# Argument  : None
# Throws    : "Can't drop priveleges" if the userids cannot be
#             changed
#
################################################################################
#
sub runReadyJobs {
    my $self = shift;
    $self->{current} = 0; # no longer current.  A reread of log dirs is necessary
    my $wrapper = $self->{options}->{run_wrapper};
    my $log_dir = &TaskForest::LogDir::getLogDir($self->{options}->{log_dir});
    
    foreach my $job (values %{$self->{ready_jobs}}) { 
        my $pid;
        if ($pid = fork) {
            # parent
            print "Forked child process $job->{name} $pid\n";
            $job->{status} = 'Running';
        } else {
            #child - this code comes from perldoc perlsec
            die "cannot fork: $!" unless defined $pid;

            my @temp     = ($EUID, $EGID);
            my $orig_uid = $UID;
            my $orig_gid = $GID;
            $EUID = $UID;
            $EGID = $GID;
            
            # Drop privileges
            #
            $UID  = $orig_uid;
            $GID  = $orig_gid;
            
            # Make sure privs are really gone
            #
            ($EUID, $EGID) = @temp;
            die "Can't drop privileges" unless $UID == $EUID  && $GID eq $EGID;
            $ENV{PATH} = "/bin:/usr/bin"; # Minimal PATH.
            $ENV{CDPATH} = ""; # We don't need this.
            
            # Consider sanitizing the environment even more.
            
            my $job_file_name = $job->{name};
            $job_file_name =~ s/--Repeat.*//;
            
            exec("$wrapper",
                 "$self->{name}",
                 "$job->{name}",
                 "$job_file_name",
                 "$log_dir",
                 "$self->{options}->{job_dir}",
                 "$log_dir/$self->{name}.$job->{name}.pid",
                 "$log_dir/$self->{name}.$job->{name}.0",
                 "$log_dir/$self->{name}.$job->{name}.1",
                ) or die "Can't exec: $!\n";
        }
    }
        
}

    

################################################################################
#
# Name      : checkAllTimeDependencies
# Usage     : $family->checkAllTimeDependencies()
# Purpose   : Runs td->check() on all time dependencies, to see
#             whether they have been met or not
# Returns   : Nothing
# Argument  : None
# Throws    : Nothing
#
################################################################################
#
sub checkAllTimeDependencies {
    my $self = shift;

    foreach my $td (@{$self->{time_dependencies}}) {
        $td->check();
    }
}

################################################################################
#
# Name      : getAllWaitingJobs
# Usage     : $family->getAllWaitingJobs()
# Purpose   : This method gets a hash of all jobs that are currently
#             in the Waiting state
# Returns   : Nothing
# Argument  : None
# Throws    : Nothing
#
################################################################################
#
sub getAllWaitingJobs {
    my $self = shift;

    my %waiting = map { $_->{name} => $_ } grep {$_->{status} eq 'Waiting'} values(%{$self->{jobs}});

    return \%waiting;
}


################################################################################
#
# Name      : readFromFile
# Usage     : $family->readFromFile
# Purpose   : This is the most crucial method of the application.  It
#             reads the Family configuration file and constructs a
#             data structure that represents all the configuration
#             parameters of the family.
# Returns   : Nothing
# Argument  : None
# Throws    : "Can't read dir/file" if the config file cannot be read
#             "No start time specified for Family",
#             "No time zone specified for Family",
#             "No run days specified for Family",
#                if any of the 3 required headers are not present in
#                the file
#             Generic die if the data cannot be extracted after an
#             eval.
#
################################################################################
#
sub readFromFile {
    my $self = shift;

    # intialize data structures
    #
    $self->{dependencies} = {};
    $self->{jobs} = {};
    $self->{time_dependencies} = [];

    # once you reread a family's config file, it is no longer current
    #
    $self->{current} = 0;

    # get current time
    #
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time); $year += 1900; $mon ++;

    # retrieve file name and attempt to open the file
    #
    my $file = $self->{name};
    my $dir = $self->{options}->{family_dir};
    open(FILE, "$dir/$file") || die "cant read $dir/$file";
    while (<FILE>) {
        chomp;
        last if /\S/;  # get first non-blank line
    }

    # parse first line
    # untaint
    # start => '08:00', tz => 'America/Chicago', days => 'Mon,Tue,Wed,Thu,Fri,Sat,Sun'
    #
    s/\s//g;

    # make sure all the data we expect in the header is available
    #
    my $args = '';
    if (/(start=>['"]\d+:\d+['"])/)      { $args .= "$1,"; } else { die "No start time specified for Family $file"; }
    if (/(tz=>['"][a-zA-Z0-9\/]+['"])/)  { $args .= "$1,"; } else { die "No time zone specified for Family $file"; }
    if (/(days=>['"][a-zA-Z0-9,]+['"])/) { $args .= "$1,"; } else { die "No run days specified for Family $file"; }
    my %args = eval($args);
    die unless ($args{start} and $args{days});

    # set the start time and the days to run
    #
    $self->{start} = $args{start};
    my @days = split(/,/, $args{days});
    foreach my $day (@days) {
        $self->{days}->{$day} = 1; # create a hash of eligible days
    }

    # close the file and silently return if this family is not
    # scheduled to run today.  Coversely this means that you could
    # change the days in the header file in the middle of the day, and
    # add today to the list of valid days.  This would cause the
    # family to now become eligible to run today, when earlier in the
    # day it was not
    #
    if ($self->okToRunToday() == 0) {
        close FILE;
        return;
    }

    # create main dependency - every job has at least one dependency:
    # a time dependency on the start time of the family.   
    #
    my %td_args = ( start => $self->{start} );
    $td_args{tz} = $self->{tz} if ($self->{tz});
    my $family_time_dependency = TaskForest::TimeDependency->new(%td_args);
    push (@{$self->{time_dependencies}}, $family_time_dependency);
    

    # PARSE THE FILE HERE
    # get rid of comments
    # get rid of blank lines
    # convert to a string
    # split on line of dashes
    #
    my @sections = split(/^ *-+ *[\r\n]+/m, (join'', grep(/\S/, (map {s/\#.*//; $_; }  <FILE>))));
    
    close FILE;


    my $forest = [];
    my $last_dependency;
    my $current_dependency;
    my $this_jobs_dependency;
    
    foreach my $section (@sections) {
        my @lines = split(/[\r\n]/, $section);    # lines in the section
        

        # Create a one-element array of dependencies.  This is the
        # default dependency list for all jobs as they're first
        # encountered. 
        #
        $last_dependency = [ $family_time_dependency ];
        foreach my $line (@lines) {
            $current_dependency = [];
            $line =~ s/ //g;

            # a job is always specified with a set of parentheses
            # (that may not be empty)
            #
            my @jobs = $line =~ /([a-z0-9_]+\([^\)]*\))/ig;

            my $job_name;
            my %args;
            foreach my $job (@jobs) {
                $this_jobs_dependency = undef;
                if ($job =~ /^([a-z0-9_]+)(\([^\)]*\))/i) {  # THIS IS ALWAYS TRUE BECAUSE OF THE @jobs above.  REMOVE THIS RESTRICTION LATER
                    # got one more arguments within the parentheses -
                    # include the time restrictions in the
                    # last_restrictions.
                    #
                    $job_name = $1;
                    $args = $2;
                    
                    if ($args =~ /^\(\S/) {  # We have additional dependencies
                        %args = eval ($args);
                        $args{tz} = $self->{tz} unless $args{tz}; # time zone defaults to family time zone
                        if ($args{start}) { # time dependency
                            $this_jobs_dependency = TaskForest::TimeDependency->new(start => $args{start}, tz => $args{tz});
                            push(@{$self->{time_dependencies}}, $this_jobs_dependency);
                            # It is ok to have more than one time
                            # dependency for a job.  Every time
                            # dependency will need to be satisfied 
                        }
                        if ($args{every} and $args{every} !~ /\D/) {
                            # this is a recurring job that needs to
                            # run every $args{every} minutes until
                            # $args{until} or 23:59
                            #
                            # What the program does is create bunch of
                            # new jobs with a prefix of --Repeat_$n--
                            # where $n specifies which job this is. 
                            #
                            my $until = $args{until};
                            my ($until_mm, $until_hh);
                            if ($until =~ /^(\d\d):(\d\d)$/) {
                                $until_hh = $1;
                                $until_mm = $2;
                            }
                            else {
                                $until_hh = 23;
                                $until_mm = 59;
                            }

                            # get an epoch value for the the until
                            # time
                            #
                            my $until_dt = DateTime->new(year => $year, month => $mon, day => $mday, hour => $until_hh, minute => $until_mm, time_zone => $args{tz});
                            my $until_epoch = $until_dt->epoch();

                            # get a start time epoch value, defaulting
                            # to the family start time
                            #
                            my ($start_dt, $start_hh, $start_mm);
                            $args{start} = $self->{start} unless $args{start};
                            ($start_hh, $start_mm) = $args{start} =~ /(\d\d):(\d\d)/;
                            $start_dt = DateTime->new(year => $year,
                                                      month => $mon,
                                                      day => $mday,
                                                      hour =>
                                                      $start_hh,
                                                      minute =>
                                                      $start_mm,
                                                      time_zone =>
                                                      $args{tz});

                            # create a duration value that's added in
                            # every loop
                            #
                            my $every_duration = DateTime::Duration->new(minutes => $args{every});
                            my $next_dt = $start_dt + $every_duration;
                            my $next_epoch = $next_dt->epoch();
                            my $next_n = 0;
                            while ($next_epoch <= $until_epoch) {
                                # the newly created jobs are *not*
                                # dependent on each other.  They're
                                # only dependent on the start time
                                # 
                                $next_n++;
                                my $jn = "$job_name"."--Repeat_$next_n--";
                                my $repeat_job_object = TaskForest::Job->new(name => $jn);
                                $self->{jobs}->{$jn} = $repeat_job_object;
                                my $td = TaskForest::TimeDependency->new($next_dt);
                                $self->{dependencies}->{$jn} = [$td];

                                $next_dt = $next_dt + $every_duration;
                                $next_epoch = $next_dt->epoch();
                            }
                        }
                            
                    }
                }
                else {
                    $job_name = $job;
                }

                
                # Create the job if necessary
                #
                # What this implies is that if a job J1 is already
                # present in this family, any other occurrance of J1
                # in this family refers TO THAT SAME JOB INSTANCE.
                #
                # If you want the same job running twice, you will
                # have to put them in different families, or make
                # soft links to them and have the soft link(s) in the
                # family file
                #
                my $job_object;
                if ($self->{jobs}->{$job_name}) {
                    $job_object = $self->{jobs}->{$job_name};
                }
                else {
                    $job_object = TaskForest::Job->new(name => $job_name);
                    $self->{jobs}->{$job_name} = $job_object;
                }

                # Now set dependencies.  A dependency can be a time
                # dependency or another job
                #
                # As we cycle through jobs on this line we add them to
                # an array of dependencies (current_dependency) so
                # that the next line's jobs will have every job in
                # that array as a dependency.
                #
                $self->{dependencies}->{$job_name} = [] unless $self->{dependencies}->{$job_name};
                foreach my $dep (@$last_dependency) {
                    push (@{$self->{dependencies}->{$job_name}}, $dep);
                }

                # this condition refers to the time dependency - if a
                # start time was specified in the parentheses
                #
                if ($this_jobs_dependency) {
                    push (@{$self->{dependencies}->{$job_name}}, $this_jobs_dependency);
                }

                # push this job into the dependency array for the jobs
                # in the next line
                #
                push (@$current_dependency, $job_object)
            }

            # set the list of dependencies for the next iteration in
            # the loop
            #
            $last_dependency = $current_dependency;
        }
    }
}


################################################################################
#
# Name      : 
# Usage     : $family->okToRunToday
# Purpose   : This method checks whether today is in the list of days
#             of the week that this family is eligible to run
# Returns   : 1 if it is, 0 if it's not.
# Argument  : None
# Throws    : Nothing
#
################################################################################
#
sub okToRunToday {
    my $self = shift;

    my @days = qw (Sun Mon Tue Wed Thu Fri Sat);
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
    my $today = $days[$wday];

    if ($self->{days}->{$today}) {
        return 1;
    }
    else {
        return 0;
    }
}


################################################################################
#
# Name      : isTainted
# Usage     : isTainted($foo)
# Purpose   : This is a debug function that is used to examine the
#             taintedness of a variable.
# Returns   : 1 if the variable is tainted, 0 if it isn't.
# Argument  : None
# Throws    : 
#
################################################################################
#
sub isTainted {
    return ! eval { eval("#" . substr(join("", @_), 0, 0)); 1 };
}



1;
